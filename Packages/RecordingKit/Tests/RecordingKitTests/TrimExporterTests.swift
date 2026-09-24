import TestKit
import AVFoundation
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
/// ScreenCaptureKit): `seconds` long, 10 fps, 1 s keyframe interval, silent audio.
private func makeFixtureMP4(at url: URL, seconds: Double = 3) throws {
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
        do {
            try makeFixtureMP4(at: src)
            let a = try blocking { try await TrimExporter.exportCopy(source: src, range: TrimRange(start: 0, end: 1), muted: false) }
            let b = try blocking { try await TrimExporter.exportCopy(source: src, range: TrimRange(start: 0, end: 1), muted: false) }
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
            try blocking { try await TrimExporter.replaceOriginal(source: src, range: TrimRange(start: 1, end: 2), muted: true) }
            let i = try info(src)
            t.approxEqual(i.duration, 1, tol: 0.15)
            t.equal(i.audio, 0)
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            t.equal(leftovers, ["Recording.mp4"], "no temp files left next to the original")
        } catch { t.fail("replace: \(error)") }
    },
    TestCase("failedReplaceLeavesOriginalUntouched") { t in
        let dir = freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("Recording.mp4")
        let junk = Data("not a movie".utf8)
        try? junk.write(to: src)
        let threw = (try? blocking { try await TrimExporter.replaceOriginal(source: src, range: nil, muted: false) }) == nil
        t.isTrue(threw, "export of a non-movie must fail")
        t.equal(try? Data(contentsOf: src), junk, "original bytes unchanged")
    },
]
