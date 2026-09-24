import Foundation

/// One capture device as the source menus show it; `id` is `AVCaptureDevice.uniqueID`.
public struct CaptureDeviceInfo: Equatable, Hashable {
    public let id: String
    public let name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Lists the connected devices of one kind. `AudioInputCatalog` / `CameraCatalog`
/// read AVFoundation; tests pass fixed lists.
public protocol DeviceCatalog {
    func snapshot() -> DeviceList
}

/// A source menu's value: Off, or one specific device.
public enum DeviceChoice: Hashable {
    case off
    case device(String)
}

/// The connected devices + the system default, read once. Pure: maps the saved
/// config onto what a menu shows and which device a recording will use.
public struct DeviceList: Equatable {
    public var devices: [CaptureDeviceInfo]
    public var defaultID: String?

    public init(devices: [CaptureDeviceInfo], defaultID: String?) {
        self.devices = devices
        self.defaultID = defaultID
    }

    /// The device a recording uses: the saved one while it's connected, else the
    /// system default, else the first listed device; nil when none is connected.
    public func resolvedID(saved: String?) -> String? {
        let ids = devices.map(\.id)
        if let saved, ids.contains(saved) { return saved }
        if let defaultID, ids.contains(defaultID) { return defaultID }
        return ids.first
    }

    /// What the menu shows for a source that's `enabled` with `saved` stored —
    /// the device that will actually record, or Off when there is none.
    public func choice(enabled: Bool, saved: String?) -> DeviceChoice {
        guard enabled, let id = resolvedID(saved: saved) else { return .off }
        return .device(id)
    }

    /// Menu rows: Off, then every connected device. Repeated names (two identical
    /// USB mics) get " (2)", " (3)" so every row is distinguishable.
    public var options: [(choice: DeviceChoice, title: String)] {
        var seen: [String: Int] = [:]
        let rows = devices.map { device -> (choice: DeviceChoice, title: String) in
            seen[device.name, default: 0] += 1
            let n = seen[device.name]!
            return (.device(device.id), n == 1 ? device.name : "\(device.name) (\(n))")
        }
        return [(.off, "Off")] + rows
    }
}
