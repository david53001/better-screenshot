import AVFoundation

/// Microphone capture on macOS 14 (SCK mic capture is macOS 15+): a tiny
/// AVCaptureSession forwarding audio sample buffers to the recording writer.
public final class MicCapturer: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    /// startRunning/stopRunning are serialized here so a quick start→stop (the record
    /// strip's meter as you switch mics) can't leave an orphaned session running.
    private let sessionQueue = DispatchQueue(label: "betterscreenshot.mic.session")
    private var onBuffer: ((CMSampleBuffer) -> Void)?
    /// Loudest channel's average power (dBFS) per buffer, on the capture queue —
    /// drives the record strip's level meter (`MicLevel`). Set before `start`.
    public var onLevel: ((Float) -> Void)?

    /// Requests mic permission if needed; false when denied.
    public static func ensurePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Starts delivering mic buffers on `queue` from `deviceID` (`uniqueID`), or the
    /// default mic when that one isn't connected. Throws when no mic is available.
    public func start(deviceID: String? = nil, queue: DispatchQueue,
                      onBuffer: @escaping (CMSampleBuffer) -> Void) throws {
        guard let device = AVCaptureDevice.connected(deviceID, else: .audio) else {
            throw RecorderError.noMicrophone
        }
        self.onBuffer = onBuffer
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw RecorderError.noMicrophone
        }
        session.addInput(input)
        session.addOutput(output)
        sessionQueue.async { [session] in
            session.startRunning()
        }
    }

    public func stop() {
        sessionQueue.sync { session.stopRunning() }
        onBuffer = nil
    }

    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        onBuffer?(sampleBuffer)
        if let onLevel, let db = connection.audioChannels.map(\.averagePowerLevel).max() {
            onLevel(db)
        }
    }
}
