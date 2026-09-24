import TestKit
import Foundation
@testable import RecordingKit

/// A fixed device list standing in for AVFoundation.
private struct FakeCatalog: DeviceCatalog {
    var list: DeviceList
    func snapshot() -> DeviceList { list }
}

private let builtIn = CaptureDeviceInfo(id: "BuiltInMic", name: "MacBook Pro Microphone")
private let airPods = CaptureDeviceInfo(id: "AirPods-1", name: "AirPods Pro")
private let usb = CaptureDeviceInfo(id: "USB-7", name: "USB Audio CODEC")

let deviceChoiceTests: [TestCase] = [
    TestCase("resolvedIDPrefersSavedThenDefaultThenFirst") { t in
        let list = DeviceList(devices: [builtIn, airPods, usb], defaultID: "BuiltInMic")
        t.equal(list.resolvedID(saved: "AirPods-1"), "AirPods-1")
        // Saved device unplugged → the system default.
        t.equal(list.resolvedID(saved: "Gone-9"), "BuiltInMic")
        // Legacy config (no device saved) → the system default.
        t.equal(list.resolvedID(saved: nil), "BuiltInMic")
        // Default not among the listed devices → the first listed one.
        let odd = DeviceList(devices: [airPods, usb], defaultID: "Aggregate-3")
        t.equal(odd.resolvedID(saved: nil), "AirPods-1")
        // Nothing connected.
        t.isNil(DeviceList(devices: [], defaultID: nil).resolvedID(saved: "AirPods-1"))
    },
    TestCase("choiceShowsOffOrTheDeviceThatWillRecord") { t in
        let catalog = FakeCatalog(list: DeviceList(devices: [builtIn, airPods], defaultID: "BuiltInMic"))
        let list = catalog.snapshot()
        t.equal(list.choice(enabled: false, saved: "AirPods-1"), .off)
        t.equal(list.choice(enabled: true, saved: "AirPods-1"), .device("AirPods-1"))
        // Legacy `microphone = true` with no device id → the default device.
        t.equal(list.choice(enabled: true, saved: nil), .device("BuiltInMic"))
        t.equal(list.choice(enabled: true, saved: "Gone-9"), .device("BuiltInMic"))
        // Enabled, but no device at all: the menu honestly shows Off.
        t.equal(DeviceList(devices: [], defaultID: nil).choice(enabled: true, saved: nil), .off)
    },
    TestCase("optionsListOffThenDevicesWithUniqueTitles") { t in
        let twin = CaptureDeviceInfo(id: "USB-8", name: "USB Audio CODEC")
        let list = DeviceList(devices: [builtIn, usb, twin], defaultID: "BuiltInMic")
        let options = list.options
        t.equal(options.map(\.choice), [.off, .device("BuiltInMic"), .device("USB-7"), .device("USB-8")])
        t.equal(options.map(\.title), ["Off", "MacBook Pro Microphone", "USB Audio CODEC", "USB Audio CODEC (2)"])
        t.equal(DeviceList(devices: [], defaultID: nil).options.map(\.title), ["Off"])
    },
    TestCase("applyingChoicesToConfig") { t in
        var c = RecordingConfig.default
        c.setMicrophone(.device("AirPods-1"))
        t.isTrue(c.microphone)
        t.equal(c.microphoneDeviceID, "AirPods-1")
        // Off keeps the last device so the saved choice isn't lost.
        c.setMicrophone(.off)
        t.isFalse(c.microphone)
        t.equal(c.microphoneDeviceID, "AirPods-1")
        c.setCamera(.device("Cam-2"))
        t.isTrue(c.camera)
        t.equal(c.cameraDeviceID, "Cam-2")
        c.setCamera(.off)
        t.isFalse(c.camera)
        t.equal(c.cameraDeviceID, "Cam-2")
    },
]

let micLevelTests: [TestCase] = [
    TestCase("decibelsMapToAFraction") { t in
        t.approxEqual(MicLevel.fraction(decibels: 0), 1)
        t.approxEqual(MicLevel.fraction(decibels: 6), 1)          // clipping clamps
        t.approxEqual(MicLevel.fraction(decibels: -30), 0.5)
        t.approxEqual(MicLevel.fraction(decibels: -60), 0)
        t.approxEqual(MicLevel.fraction(decibels: -72), 0)        // quiet room
        t.approxEqual(MicLevel.fraction(decibels: -120), 0)
        t.approxEqual(MicLevel.fraction(decibels: -.infinity), 0)  // digital silence
        t.approxEqual(MicLevel.fraction(decibels: .nan), 0)
    },
    TestCase("fastAttackSlowRelease") { t in
        t.approxEqual(MicLevel.smoothed(previous: 0.2, target: 0.9), 0.9)
        t.approxEqual(MicLevel.smoothed(previous: 0.9, target: 0.1), 0.9 - MicLevel.release, tol: 1e-12)
        t.approxEqual(MicLevel.smoothed(previous: 0.03, target: 0), 0)
    },
    TestCase("litSegments") { t in
        t.equal(MicLevel.litSegments(fraction: 0, count: 12), 0)
        t.equal(MicLevel.litSegments(fraction: 0.5, count: 12), 6)
        t.equal(MicLevel.litSegments(fraction: 0.04, count: 12), 0)
        t.equal(MicLevel.litSegments(fraction: 1, count: 12), 12)
        t.equal(MicLevel.litSegments(fraction: 1.7, count: 12), 12)
    },
]
