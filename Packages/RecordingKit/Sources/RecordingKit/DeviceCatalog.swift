import AVFoundation

/// Connected microphones (built-in, AirPods, USB, Continuity). Listing devices
/// never triggers the microphone permission prompt.
public struct AudioInputCatalog: DeviceCatalog {
    public init() {}
    public func snapshot() -> DeviceList {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        return DeviceList(devices: session.devices.map { CaptureDeviceInfo(id: $0.uniqueID, name: $0.localizedName) },
                          defaultID: AVCaptureDevice.default(for: .audio)?.uniqueID)
    }
}

/// Connected cameras (built-in, external, Continuity Camera).
public struct CameraCatalog: DeviceCatalog {
    public init() {}
    public func snapshot() -> DeviceList {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video, position: .unspecified)
        return DeviceList(devices: session.devices.map { CaptureDeviceInfo(id: $0.uniqueID, name: $0.localizedName) },
                          defaultID: AVCaptureDevice.default(for: .video)?.uniqueID)
    }
}

extension AVCaptureDevice {
    /// The device with `uniqueID` while it's connected, else the system default.
    static func connected(_ uniqueID: String?, else mediaType: AVMediaType) -> AVCaptureDevice? {
        uniqueID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: mediaType)
    }
}
