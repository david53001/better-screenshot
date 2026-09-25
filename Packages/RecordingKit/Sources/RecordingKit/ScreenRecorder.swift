import AVFoundation
import ScreenCaptureKit

public enum RecorderError: Error {
    case writerFailed
    case noMicrophone
    case notRecording
}

/// SCStream → AVAssetWriter MP4 recording engine. Video + optional system-audio
/// track (SCK) + optional microphone track (MicCapturer). All sample appends run
/// on `sampleQueue`; start/stop are called from the main actor.
public final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    /// Audio-only stream supplying system audio for window recordings (see `start`).
    private var audioStream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var micCapturer: MicCapturer?
    private let sampleQueue = DispatchQueue(label: "betterscreenshot.recorder.samples")
    private let discardFrames = DiscardFrames()
    private var sessionStarted = false
    private var sessionStartPTS: CMTime?
    private var outputURL: URL?
    // Pause/resume: flags are flipped on `sampleQueue` so they serialize with
    // appends. While `paused`, all samples are dropped. `pendingResume` means a
    // resume was requested but the first post-resume video frame hasn't set the
    // new offset yet (audio is held back until it does — a ≤1-buffer seam nick).
    private var paused = false
    private var pendingResume = false
    private var lastVideoPTS: CMTime?
    /// End of the newest audio buffer appended (either track), and when `pause()`
    /// ran — the resume anchor (see `clearPendingResume`).
    private var lastAudioEnd: CMTime?
    private var pausedAt: CMTime?
    private var frameDuration = CMTime(value: 1, timescale: 60)
    private var timeline = PauseTimeline()
    // Live mute: also flipped on `sampleQueue`. A muted source keeps appending,
    // but silent copies (SilenceFill), so its track stays continuous and in sync.
    // Deliberately NOT reset by start()/stop(): they're the session's live toggles
    // (a Restart keeps them); the caller clears them for a new session.
    private var micMuted = false
    private var systemAudioMuted = false
    /// The newest complete frame that arrived while paused. Static content (e.g.
    /// a window just switched to during the pause) never sends another frame, so
    /// `resume()` opens the resumed span with this one.
    private var heldFrame: CMSampleBuffer?
    /// The configuration the stream started with, kept so `retarget` changes only
    /// where the content comes from and where it lands in the frame.
    private var streamConfig: SCStreamConfiguration?

    /// Stream died underneath us (display unplugged, etc.). Fired on sampleQueue.
    public var onStreamError: ((Error) -> Void)?

    public override init() { super.init() }

    private static let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 128_000,
    ]

    /// Begin recording `filter` at `pixelSize` to `outputURL`.
    /// `sourceRect` (display-relative, top-left-origin, points) crops the display.
    /// `systemAudioFilter`, when set, supplies system audio from a separate audio-only
    /// stream instead of `filter`: a single-window filter only hears that window's own
    /// process (not even its helpers — a browser's tab audio is silent), so window
    /// recordings pass a display filter here to hear all apps.
    public func start(filter: SCContentFilter, pixelSize: CGSize, sourceRect: CGRect?,
                      config: RecordingConfig, outputURL: URL,
                      systemAudioFilter: SCContentFilter? = nil) async throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let pure = config.videoSettings(width: Int(pixelSize.width), height: Int(pixelSize.height))
        // Map the pure-model dictionary onto the real AVFoundation constants.
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pure[AVKey.width] as? Int ?? Int(pixelSize.width),
            AVVideoHeightKey: pure[AVKey.height] as? Int ?? Int(pixelSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:
                    (pure[AVKey.compression] as? [String: Any])?[AVKey.bitRate] as? Int ?? 8_000_000,
                AVVideoMaxKeyFrameIntervalDurationKey: RecordingConfig.keyFrameInterval,
            ],
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(vInput) else { throw RecorderError.writerFailed }
        writer.add(vInput)

        var sysInput: AVAssetWriterInput?
        if config.systemAudio {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
            a.expectsMediaDataInRealTime = true
            if writer.canAdd(a) { writer.add(a); sysInput = a }
        }
        var micInput: AVAssetWriterInput?
        if config.microphone {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
            a.expectsMediaDataInRealTime = true
            if writer.canAdd(a) { writer.add(a); micInput = a }
        }

        let sc = SCStreamConfiguration()
        sc.width = Int(pixelSize.width)
        sc.height = Int(pixelSize.height)
        if let sourceRect { sc.sourceRect = sourceRect }
        sc.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        sc.showsCursor = config.showsCursor
        let audioOnMainStream = config.systemAudio && systemAudioFilter == nil
        sc.capturesAudio = audioOnMainStream
        sc.excludesCurrentProcessAudio = config.systemAudioMode.excludesOwnAudio
        sc.pixelFormat = kCVPixelFormatType_32BGRA
        sc.queueDepth = 6

        let stream = SCStream(filter: filter, configuration: sc, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if audioOnMainStream {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }
        var audioStream: SCStream?
        if config.systemAudio, let systemAudioFilter {
            let ac = SCStreamConfiguration()
            ac.width = 2; ac.height = 2   // its video is discarded
            ac.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            ac.capturesAudio = true
            ac.excludesCurrentProcessAudio = sc.excludesCurrentProcessAudio
            let s = SCStream(filter: systemAudioFilter, configuration: ac, delegate: self)
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            try s.addStreamOutput(discardFrames, type: .screen, sampleHandlerQueue: sampleQueue)
            audioStream = s
        }

        guard writer.startWriting() else { throw writer.error ?? RecorderError.writerFailed }

        self.writer = writer
        self.videoInput = vInput
        self.systemAudioInput = sysInput
        self.micInput = micInput
        self.outputURL = outputURL
        self.sessionStarted = false
        self.frameDuration = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        self.paused = false
        self.pendingResume = false
        self.lastVideoPTS = nil
        self.timeline = PauseTimeline()
        self.stream = stream
        self.audioStream = audioStream
        self.streamConfig = sc

        if config.microphone, micInput != nil {
            let capturer = MicCapturer()
            self.micCapturer = capturer
            try? capturer.start(deviceID: config.microphoneDeviceID, queue: sampleQueue) { [weak self] buffer in
                self?.appendMic(buffer)
            }
        }

        do {
            try await stream.startCapture()
            if let audioStream {
                do { try await audioStream.startCapture() } catch {
                    try? await stream.stopCapture()
                    throw error
                }
            }
        } catch {
            // Don't leak a running mic session / half-configured writer.
            micCapturer?.stop()
            writer.cancelWriting()
            reset()
            throw error
        }
    }

    /// Stop and finalize; returns the finished file URL.
    public func stop() async throws -> URL {
        guard let writer, let outputURL else { throw RecorderError.notRecording }
        if let stream { try? await stream.stopCapture() }
        if let audioStream { try? await audioStream.stopCapture() }
        micCapturer?.stop()
        // Finish on the sample queue so an in-flight append can't land after
        // markAsFinished (AVAssetWriterInput.append traps post-finish).
        sampleQueue.sync {
            videoInput?.markAsFinished()
            systemAudioInput?.markAsFinished()
            micInput?.markAsFinished()
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        defer { reset() }
        if writer.status == .failed { throw writer.error ?? RecorderError.writerFailed }
        return outputURL
    }

    /// Pause: drop all samples until `resume()`. Serialized on the sample queue.
    public func pause() {
        sampleQueue.sync { paused = true; heldFrame = nil; pausedAt = CMClockGetTime(CMClockGetHostTimeClock()) }
    }

    /// Resume: the next video frame re-establishes the gap-free offset; samples
    /// flow again retimed by the accumulated pause offset. A frame held from the
    /// pause is restamped to now and becomes that first frame.
    public func resume() {
        sampleQueue.sync {
            paused = false; pendingResume = true
            if let held = heldFrame, let now = Self.restamped(held, to: CMClockGetTime(CMClockGetHostTimeClock())) {
                appendVideo(now)
            }
            heldFrame = nil
        }
    }

    /// Mute/unmute the microphone track (silence, not a gap). Serialized on the
    /// sample queue, so the next mic buffer honours it. No-op without a mic track.
    public func setMicMuted(_ muted: Bool) {
        sampleQueue.sync { micMuted = muted }
    }

    /// Mute/unmute the system-audio track, like `setMicMuted`.
    public func setSystemAudioMuted(_ muted: Bool) {
        sampleQueue.sync { systemAudioMuted = muted }
    }

    /// Whether the current recording has a microphone / system-audio track —
    /// muting only affects tracks that exist (they're fixed at start).
    public var recordsMicrophone: Bool { micInput != nil }
    public var recordsSystemAudio: Bool { systemAudioInput != nil }
    /// The file being written (nil when idle) — lets a discard delete it even if
    /// finalizing fails.
    public var currentOutputURL: URL? { outputURL }

    /// Points the running stream at new content — another window, or another
    /// display area (`sourceRect`: display-relative, top-left origin, points) —
    /// without stopping. The output pixel size stays as configured at start, so
    /// content of another shape is scaled to fit and centred with black bars
    /// (`LetterboxFit`; window streams would otherwise pin it top-left).
    public func retarget(filter: SCContentFilter, sourceRect: CGRect?) async throws {
        guard let stream, let streamConfig else { throw RecorderError.notRecording }
        let output = CGSize(width: streamConfig.width, height: streamConfig.height)
        streamConfig.sourceRect = sourceRect ?? .null
        streamConfig.destinationRect = LetterboxFit.rect(
            content: sourceRect?.size ?? filter.contentRect.size, output: output)
        streamConfig.scalesToFit = true         // window streams: scale small windows up too
        streamConfig.preservesAspectRatio = true
        try await stream.updateContentFilter(filter)
        try await stream.updateConfiguration(streamConfig)
    }

    /// Swaps the running stream's filter for the same content with a different set of left-out
    /// windows (e.g. a tour tag that just appeared). Nothing else about the stream changes.
    public func updateFilter(_ filter: SCContentFilter) async throws {
        guard let stream else { throw RecorderError.notRecording }
        try await stream.updateContentFilter(filter)
    }

    private func reset() {
        stream = nil; audioStream = nil; writer = nil; videoInput = nil
        systemAudioInput = nil; micInput = nil; micCapturer = nil
        outputURL = nil; sessionStarted = false; sessionStartPTS = nil; streamConfig = nil
        paused = false; pendingResume = false; lastVideoPTS = nil; heldFrame = nil
        lastAudioEnd = nil; pausedAt = nil
        timeline = PauseTimeline()
    }

    /// On the first sample after resume, fold the silent gap into the timeline
    /// and let samples flow again. Audio and video share the host-time clock, so
    /// whichever sample arrives first may clear the resume — this avoids dropping
    /// audio when the captured content is static (no new video frames) after resume.
    /// The gap is anchored on where the recording actually stopped: the end of the
    /// last audio appended (AVAssetWriter packs audio back to back, so video must
    /// resume there to stay in sync), or the pause moment without audio — never on
    /// the last video frame alone, which with static content can be seconds before
    /// the pause (that anchor put post-resume video ~0.9 s ahead of its audio).
    private func clearPendingResume(firstPTS pts: CMTime) {
        let anchors = [lastVideoPTS, lastAudioEnd ?? pausedAt].compactMap { $0 }
        if let last = anchors.max() {
            timeline.resume(lastPTSBeforePause: last, firstPTSAfterResume: pts,
                            frameDuration: frameDuration)
        }
        pendingResume = false
    }

    /// Append `sampleBuffer` retimed by the current pause offset. Subtracts the
    /// offset from every timing entry (handles multi-sample audio buffers). Fast
    /// path: with a zero offset (no pause yet) the original buffer is appended.
    private func appendRetimed(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput) {
        let offset = timeline.currentOffset
        if offset == .zero { input.append(sampleBuffer); return }
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0,
                                               arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { input.append(sampleBuffer); return }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count,
                                               arrayToFill: &timings, entriesNeededOut: &count)
        for i in 0..<count {
            if timings[i].presentationTimeStamp.isValid {
                timings[i].presentationTimeStamp = timings[i].presentationTimeStamp - offset
            }
            if timings[i].decodeTimeStamp.isValid {
                timings[i].decodeTimeStamp = timings[i].decodeTimeStamp - offset
            }
        }
        var out: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: count, sampleTimingArray: &timings, sampleBufferOut: &out)
        if status == noErr, let out { input.append(out) } else { input.append(sampleBuffer) }
    }

    // MARK: - SCStreamOutput (called on sampleQueue)

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                       of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            // Only complete frames carry image data.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
                      sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: statusRaw) == .complete else { return }
            let pts = sampleBuffer.presentationTimeStamp
            if !sessionStarted {
                writer?.startSession(atSourceTime: pts)
                sessionStartPTS = pts
                sessionStarted = true
                lastVideoPTS = pts
            }
            if paused { heldFrame = sampleBuffer; return }
            appendVideo(sampleBuffer)
        case .audio:
            guard sessionStarted, !paused,
                  let systemAudioInput, systemAudioInput.isReadyForMoreMediaData else { return }
            if pendingResume { clearPendingResume(firstPTS: sampleBuffer.presentationTimeStamp) }
            guard let buffer = Self.audible(sampleBuffer, muted: systemAudioMuted) else { return }
            appendRetimed(buffer, to: systemAudioInput)
            noteAudioEnd(sampleBuffer)
        default:
            break
        }
    }

    /// Appends a complete video frame (on sampleQueue, not paused).
    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        let pts = sampleBuffer.presentationTimeStamp
        if pendingResume { clearPendingResume(firstPTS: pts) }
        if let videoInput, videoInput.isReadyForMoreMediaData {
            appendRetimed(sampleBuffer, to: videoInput)
        }
        lastVideoPTS = pts
    }

    /// A copy of a video frame presented at `pts` (SCK stamps frames on the host clock).
    private static func restamped(_ frame: CMSampleBuffer, to pts: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: frame,
                                              sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                              sampleBufferOut: &out)
        return out
    }

    private func appendMic(_ buffer: CMSampleBuffer) {
        guard sessionStarted, !paused, let sessionStartPTS,
              buffer.presentationTimeStamp >= sessionStartPTS,
              let micInput, micInput.isReadyForMoreMediaData else { return }
        if pendingResume { clearPendingResume(firstPTS: buffer.presentationTimeStamp) }
        guard let buffer = Self.audible(buffer, muted: micMuted) else { return }
        appendRetimed(buffer, to: micInput)
        noteAudioEnd(buffer)
    }

    private func noteAudioEnd(_ buffer: CMSampleBuffer) {
        let duration = buffer.duration
        let end = buffer.presentationTimeStamp + (duration.isValid ? duration : .zero)
        lastAudioEnd = max(lastAudioEnd ?? end, end)
    }

    /// `buffer` itself, or a silent copy while its source is muted. Nil (drop the
    /// buffer) if no silent copy can be made — a muted source must never leak sound.
    private static func audible(_ buffer: CMSampleBuffer, muted: Bool) -> CMSampleBuffer? {
        muted ? SilenceFill.silentCopy(of: buffer) : buffer
    }

    // MARK: - SCStreamDelegate

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamError?(error)
    }
}

/// Swallows the audio-only stream's 2×2 frames (without a screen output SCK logs
/// "stream output NOT found" for every frame).
private final class DiscardFrames: NSObject, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {}
}
