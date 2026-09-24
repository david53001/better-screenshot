import TestKit
import AVFoundation
import ImageIO
@testable import RecordingKit

/// Runs async work from the synchronous TestKit runner (main thread) — the work
/// itself never touches the main actor, so blocking here can't deadlock.
private func blocking<T>(_ body: @escaping () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    var result: Result<T, Error>?
    Task.detached {
        do { result = .success(try await body()) } catch { result = .failure(error) }
        sem.signal()
    }
    sem.wait()
    return try result!.get()
}

/// Writes a small H.264 + AAC MP4 (like ScreenRecorder's output, minus
/// ScreenCaptureKit): `seconds` long, 10 fps, 1 s keyframe interval. Frame i is a flat
/// grey of level i·8, so a decoded frame tells which source frame it came from. Audio
/// is silent, or a 440 Hz tone with `tone`.
private func makeFixtureMP4(at url: URL, seconds: Double = 3, tone: Bool = false) throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240,
        AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 10],
    ])
    let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000,
    ])
    video.expectsMediaDataInRealTime = false
    audio.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
    writer.add(video); writer.add(audio)
    guard writer.startWriting() else { throw writer.error ?? TrimExporter.ExportError.cannotExport }
    writer.startSession(atSourceTime: .zero)

    var asbd = AudioStreamBasicDescription(
        mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2,
        mBitsPerChannel: 16, mReserved: 0)
    var audioFormat: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                   magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                   formatDescriptionOut: &audioFormat)

    let frames = Int(seconds * 10)
    func appendVideo(_ i: Int) {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 320, 240, kCVPixelFormatType_32BGRA, nil, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        memset(CVPixelBufferGetBaseAddress(pb!), Int32(i * 8 % 255), CVPixelBufferGetDataSize(pb!))
        CVPixelBufferUnlockBaseAddress(pb!, [])
        adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 10))
    }
    func appendAudio(_ i: Int) {
        // 0.1 s of silence per step.
        let count = 4_800, bytes = count * 4
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes,
                                           blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                           dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag,
                                           blockBufferOut: &block)
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes)
        if tone {
            var pcm = [Int16](repeating: 0, count: count * 2)
            for k in 0..<count {
                let v = Int16(0.3 * 32_767 * sin(2 * Double.pi * 440 * Double(i * count + k) / 48_000))
                pcm[2 * k] = v; pcm[2 * k + 1] = v
            }
            CMBlockBufferReplaceDataBytes(with: pcm, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes)
        }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block!, formatDescription: audioFormat!, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(i * count), timescale: 48_000),
            packetDescriptions: nil, sampleBufferOut: &sample)
        audio.append(sample!)
    }
    // Feed whichever input is ready: the writer interleaves tracks and stalls one
    // input until the other catches up, so strict alternation can deadlock.
    var v = 0, a = 0
    let deadline = Date().addingTimeInterval(20)
    while (v < frames || a < frames) && Date() < deadline {
        var progressed = false
        if v < frames, video.isReadyForMoreMediaData { appendVideo(v); v += 1; progressed = true }
        if a < frames, audio.isReadyForMoreMediaData { appendAudio(a); a += 1; progressed = true }
        if !progressed { usleep(1_000) }
    }
    video.markAsFinished(); audio.markAsFinished()
    let sem = DispatchSemaphore(value: 0)
    writer.finishWriting { sem.signal() }
    sem.wait()
    guard writer.status == .completed else { throw writer.error ?? TrimExporter.ExportError.cannotExport }
}

private func info(_ url: URL) throws -> (duration: Double, video: Int, audio: Int) {
    try blocking {
        let asset = AVURLAsset(url: url)
        let d = try await asset.load(.duration).seconds
        let v = try await asset.loadTracks(withMediaType: .video).count
        let a = try await asset.loadTracks(withMediaType: .audio).count
        return (d, v, a)
    }
}

/// Grey level (0…255) of the frame shown at `seconds`, decoded frame-exactly.
private func grey(_ url: URL, at seconds: Double) throws -> Int {
    try blocking {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Int(px[0])
    }
}

/// RMS (0…1) of the first audio track between `from` and `to` seconds.
private func audioRMS(_ url: URL, from: Double, to: Double) throws -> Double {
    try blocking {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return 0 }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600),
                                       end: CMTime(seconds: to, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        reader.startReading()
        var sum = 0.0, n = 0
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Int16](repeating: 0, count: length / 2)
            _ = samples.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            for s in samples { sum += Double(s) * Double(s) }
            n += samples.count
        }
        return n > 0 ? sqrt(sum / Double(n)) / 32_768 : 0
    }
}

/// Collects progress callbacks from the export's background task.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() }
    var last: Double? { lock.lock(); defer { lock.unlock() }; return values.last }
}

/// [0,1] · (cut) · [1.5,2] · (cut) · [2.5,3] of the 3 s fixture — 2 s kept.
private func threeSegments() -> CutList {
    var cuts = CutList(duration: 3)
    for t in [1, 1.5, 2, 2.5] { _ = cuts.split(atSource: t) }
    _ = cuts.remove(at: 3); _ = cuts.remove(at: 1)
    return cuts
}

private func freshDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("TrimExporterTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

let trimExporterTests: [TestCase] = [
    TestCase("fixtureIsARealRecording") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        do {
            try makeFixtureMP4(at: src)
            let i = try info(src)
            t.approxEqual(i.duration, 3, tol: 0.15)
            t.equal(i.video, 1); t.equal(i.audio, 1)
        } catch { t.fail("fixture: \(error)") }
    },
    TestCase("trimKeepsTheRangeAndAudio") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        let out = dir.appendingPathComponent("out.mp4")
        do {
            try makeFixtureMP4(at: src)
            try blocking { try await TrimExporter.export(source: src, range: TrimRange(start: 0.5, end: 2.0),
                                                         muted: false, to: out) }
            let i = try info(out)
            t.approxEqual(i.duration, 1.5, tol: 0.15)
            t.equal(i.video, 1); t.equal(i.audio, 1)
        } catch { t.fail("export: \(error)") }
    },
    TestCase("muteDropsAudioAndStillTrims") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        let out = dir.appendingPathComponent("out.mp4")
        do {
            try makeFixtureMP4(at: src)
            try blocking { try await TrimExporter.export(source: src, range: TrimRange(start: 1.0, end: 2.5),
                                                         muted: true, to: out) }
            let i = try info(out)
            t.approxEqual(i.duration, 1.5, tol: 0.15)
            t.equal(i.video, 1); t.equal(i.audio, 0)
        } catch { t.fail("mute export: \(error)") }
    },
    TestCase("wholeRangeExportKeepsDuration") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        let out = dir.appendingPathComponent("out.mp4")
        do {
            try makeFixtureMP4(at: src)
            try blocking { try await TrimExporter.export(source: src, range: nil, muted: false, to: out) }
            t.approxEqual(try info(out).duration, 3, tol: 0.15)
        } catch { t.fail("export: \(error)") }
    },
    TestCase("saveAsCopyNamesUniquelyAndKeepsOriginal") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        let cuts = CutList(range: TrimRange(start: 0, end: 1), duration: 3)
        do {
            try makeFixtureMP4(at: src)
            let a = try blocking { try await TrimExporter.exportCopy(source: src, cuts: cuts, muted: false) }
            let b = try blocking { try await TrimExporter.exportCopy(source: src, cuts: cuts, muted: false) }
            t.equal(a.lastPathComponent, "Recording (trimmed).mp4")
            t.equal(b.lastPathComponent, "Recording (trimmed) 2.mp4")
            t.approxEqual(try info(a).duration, 1, tol: 0.15)
            t.approxEqual(try info(src).duration, 3, tol: 0.15)
        } catch { t.fail("copy: \(error)") }
    },
    TestCase("replaceOriginalSwapsInPlace") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        do {
            try makeFixtureMP4(at: src)
            let cuts = CutList(range: TrimRange(start: 1, end: 2), duration: 3)
            try blocking { try await TrimExporter.replaceOriginal(source: src, cuts: cuts, muted: true) }
            let i = try info(src)
            t.approxEqual(i.duration, 1, tol: 0.15)
            t.equal(i.audio, 0)
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            t.equal(leftovers, ["Recording.mp4"], "no temp files left next to the original")
        } catch { t.fail("replace: \(error)") }
    },
    TestCase("replaceOriginalWithCutsReencodesInPlace") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        do {
            try makeFixtureMP4(at: src)
            try blocking { try await TrimExporter.replaceOriginal(source: src, cuts: threeSegments(), muted: false) }
            t.approxEqual(try info(src).duration, 2, tol: 0.1)
            t.equal(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["Recording.mp4"])
        } catch { t.fail("replace: \(error)") }
    },
    TestCase("failedReplaceLeavesOriginalUntouched") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        let junk = Data("not a movie".utf8)
        try? junk.write(to: src)
        for cuts in [CutList(duration: 3), threeSegments()] {
            let threw = (try? blocking { try await TrimExporter.replaceOriginal(source: src, cuts: cuts, muted: false) }) == nil
            t.isTrue(threw, "export of a non-movie must fail")
            t.equal(try? Data(contentsOf: src), junk, "original bytes unchanged")
        }
    },
    TestCase("threeSegmentCutLandsOnTheChosenFrames") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        let out = dir.appendingPathComponent("out.mp4")
        do {
            try makeFixtureMP4(at: src)
            let cuts = threeSegments()
            t.isTrue(TrimExporter.needsReencode(cuts))
            let reported = ProgressLog()
            try blocking {
                try await TrimExporter.export(source: src, cuts: cuts, muted: false, to: out) { p in
                    reported.add(p)
                }
            }
            let i = try info(out)
            t.approxEqual(i.duration, cuts.keptDuration, tol: 0.1)    // 2 s = 1 + 0.5 + 0.5
            t.equal(i.video, 1); t.equal(i.audio, 1)
            t.equal(reported.last, 1, "progress ends at 100%")
            // Output 0.55 / 1.25 / 1.55 / 1.75 show source 0.55 / 1.75 / 2.55 / 2.75 —
            // frame-exact, though 1.5 and 2.5 aren't keyframes (the fixture has one per second).
            for (o, s) in [(0.55, 0.55), (1.25, 1.75), (1.55, 2.55), (1.75, 2.75)] {
                let got = try grey(out, at: o), want = try grey(src, at: s)
                t.isTrue(abs(got - want) <= 3, "output \(o)s shows source \(s)s (grey \(got) vs \(want))")
            }
        } catch { t.fail("cut export: \(error)") }
    },
    TestCase("doubleSpeedHalvesItsSegment") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        let out = dir.appendingPathComponent("out.mp4")
        do {
            try makeFixtureMP4(at: src)
            var cuts = CutList(duration: 3)
            _ = cuts.split(atSource: 2)
            _ = cuts.setSpeed(2, of: 0)                     // [0,2] at 2× = 1 s, then [2,3] = 1 s
            try blocking { try await TrimExporter.export(source: src, cuts: cuts, muted: false, to: out) }
            let i = try info(out)
            t.approxEqual(i.duration, 2, tol: 0.1)
            t.equal(i.audio, 1, "the 1× segment keeps its audio")
            for (o, s) in [(0.575, 1.15), (0.975, 1.95), (1.45, 2.45)] {
                let got = try grey(out, at: o), want = try grey(src, at: s)
                t.isTrue(abs(got - want) <= 3, "output \(o)s shows source \(s)s (grey \(got) vs \(want))")
            }
        } catch { t.fail("speed export: \(error)") }
    },
    TestCase("mutedSegmentIsSilentAndTheRestIsNot") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        let out = dir.appendingPathComponent("out.mp4")
        do {
            try makeFixtureMP4(at: src, tone: true)
            var cuts = CutList(duration: 3)
            _ = cuts.split(atSource: 1.5)
            _ = cuts.setMuted(true, of: 0)
            t.isTrue(TrimExporter.needsReencode(cuts))
            try blocking { try await TrimExporter.export(source: src, cuts: cuts, muted: false, to: out) }
            t.approxEqual(try info(out).duration, 3, tol: 0.1)
            t.isTrue(try audioRMS(src, from: 0.2, to: 1.2) > 0.1, "the fixture's tone is audible")
            t.isTrue(try audioRMS(out, from: 0.2, to: 1.2) < 0.01, "muted segment is silent")
            t.isTrue(try audioRMS(out, from: 1.8, to: 2.8) > 0.1, "unmuted segment keeps its sound")
        } catch { t.fail("mute export: \(error)") }
    },
    TestCase("plainTrimThroughTheCutListStaysPassthrough") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        let out = dir.appendingPathComponent("out.mp4")
        do {
            try makeFixtureMP4(at: src)
            var cuts = CutList(duration: 3)
            _ = cuts.setStart(0.5, of: 0); _ = cuts.setEnd(2, of: 0); _ = cuts.split(atSource: 1.2)
            t.isFalse(TrimExporter.needsReencode(cuts))
            try blocking { try await TrimExporter.export(source: src, cuts: cuts, muted: false, to: out) }
            let i = try info(out)
            t.approxEqual(i.duration, 1.5, tol: 0.15)
            t.equal(i.audio, 1)
        } catch { t.fail("passthrough export: \(error)") }
    },
    TestCase("gifExportOfTheEdit") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        do {
            try makeFixtureMP4(at: src)
            let a = try blocking { try await TrimExporter.exportGIF(source: src, cuts: threeSegments()) }
            let b = try blocking { try await TrimExporter.exportGIF(source: src, cuts: CutList(duration: 3)) }
            t.equal(a.lastPathComponent, "Recording (edited).gif")
            t.equal(b.lastPathComponent, "Recording (edited) 2.gif")
            let frames = CGImageSourceCreateWithURL(a as CFURL, nil).map(CGImageSourceGetCount) ?? 0
            t.isTrue(abs(frames - 20) <= 1, "2 s at 10 fps ≈ 20 frames (got \(frames))")
            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
            t.equal(names, ["Recording (edited) 2.gif", "Recording (edited).gif", "Recording.mp4"],
                    "no temp MP4 left next to the original")
        } catch { t.fail("gif export: \(error)") }
    },
    TestCase("avKeysMatchAVFoundation") { t in
        t.equal(AVKey.bitRate, AVVideoAverageBitRateKey)
        t.equal(AVKey.maxKeyFrameIntervalDuration, AVVideoMaxKeyFrameIntervalDurationKey)
    },
]
