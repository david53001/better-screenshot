import TestKit
import Foundation
@testable import RecordingKit

let recordingConfigTests: [TestCase] = [
    TestCase("defaultsAndRoundTrip") { t in
        let d = RecordingConfig.default
        t.equal(d.format, .mp4)
        t.equal(d.fps, 30)
        t.isTrue(d.systemAudio)
        t.isFalse(d.microphone)
        t.isFalse(d.camera)
        t.equal(d.cameraSize, .small)
        t.isTrue(d.clickHighlights)
        t.isFalse(d.keystrokeOverlay)
        t.equal(d.countdownSeconds, 0)   // off by default
        t.isFalse(d.controlsInRecording) // stop/pause pill hidden from the video by default
        var c = d
        c.format = .gif; c.fps = 60; c.microphone = true; c.cameraSize = .medium; c.countdownSeconds = 5
        c.controlsInRecording = true
        t.equal(RecordingConfig(dictionary: c.dictionary), c)
        // Malformed/missing keys fall back to defaults.
        t.equal(RecordingConfig(dictionary: [:]), .default)
        t.equal(RecordingConfig(dictionary: ["fps": "999"]).fps, 30) // not 30/60 → default
        // Countdown: unknown value falls back to 0 (off); valid values round-trip.
        t.equal(RecordingConfig(dictionary: ["countdownSeconds": "7"]).countdownSeconds, 0)
        t.equal(RecordingConfig(dictionary: ["countdownSeconds": "10"]).countdownSeconds, 10)
    },
    TestCase("sourceMenusDefaultsAndRoundTrip") { t in
        let d = RecordingConfig.default
        t.equal(d.systemAudioMode, .all)   // today's "system audio on"
        t.isNil(d.microphoneDeviceID)      // nil = system default device
        t.isNil(d.cameraDeviceID)
        t.isTrue(d.showsCursor)
        var c = d
        c.systemAudioMode = .allExceptSelf
        c.setMicrophone(.device("AirPods-1"))
        c.setCamera(.device("Cam-2"))
        c.showsCursor = false
        t.equal(RecordingConfig(dictionary: c.dictionary), c)
        c.systemAudioMode = .off
        t.equal(RecordingConfig(dictionary: c.dictionary), c)
        t.equal(RecordingConfig(dictionary: ["showsCursor": "false"]).showsCursor, false)
        t.equal(RecordingConfig(dictionary: ["microphoneDeviceID": ""]).microphoneDeviceID, nil)
    },
    TestCase("legacySettingsMapOntoTheMenus") { t in
        // Pre-v3 settings only have the Bool toggles.
        t.equal(RecordingConfig(dictionary: ["systemAudio": "true"]).systemAudioMode, .all)
        t.equal(RecordingConfig(dictionary: ["systemAudio": "false"]).systemAudioMode, .off)
        let legacyMic = RecordingConfig(dictionary: ["microphone": "true", "camera": "true"])
        t.isTrue(legacyMic.microphone)
        t.isNil(legacyMic.microphoneDeviceID)   // → the default device (DeviceList.resolvedID)
        t.isTrue(legacyMic.camera)
        t.isNil(legacyMic.cameraDeviceID)
        // The new key wins over the old one; unknown values fall back to the Bool.
        t.equal(RecordingConfig(dictionary: ["systemAudio": "true", "systemAudioMode": "excludeSelf"])
                    .systemAudioMode, .allExceptSelf)
        t.equal(RecordingConfig(dictionary: ["systemAudio": "false", "systemAudioMode": "bogus"])
                    .systemAudioMode, .off)
        // The old Bool keys are still written, so an older build reads sensible values.
        var c = RecordingConfig.default
        c.systemAudioMode = .allExceptSelf
        t.equal(c.dictionary["systemAudio"], "true")
        c.systemAudioMode = .off
        t.equal(c.dictionary["systemAudio"], "false")
    },
    TestCase("systemAudioBoolIsAViewOfTheMode") { t in
        var c = RecordingConfig.default
        c.systemAudioMode = .allExceptSelf
        t.isTrue(c.systemAudio)
        c.systemAudio = true                    // already on: keeps the chosen mode
        t.equal(c.systemAudioMode, .allExceptSelf)
        c.systemAudio = false
        t.equal(c.systemAudioMode, .off)
        c.systemAudio = true                    // off → on picks All apps
        t.equal(c.systemAudioMode, .all)
        t.isFalse(SystemAudioMode.all.excludesOwnAudio)
        t.isTrue(SystemAudioMode.allExceptSelf.excludesOwnAudio)
        t.equal(SystemAudioMode.allCases.map(\.title),
                ["Off", "All apps", "All apps except BetterScreenshot"])
    },
    TestCase("videoSettingsDerivation") { t in
        let s = RecordingConfig.default.videoSettings(width: 1920, height: 1080)
        t.equal(s[AVKey.codec] as? String, "avc1")
        t.equal(s[AVKey.width] as? Int, 1920)
        t.equal(s[AVKey.height] as? Int, 1080)
        let props = s[AVKey.compression] as? [String: Any]
        let bitrate = props?[AVKey.bitRate] as? Int
        // 1920*1080*30*0.12 ≈ 7.46 Mbps — inside the 2–40 Mbps clamp.
        t.equal(bitrate, Int(1920.0 * 1080.0 * 30.0 * 0.12))
        // Tiny recordings clamp up to 2 Mbps.
        let tiny = RecordingConfig.default.videoSettings(width: 100, height: 100)
        let tinyRate = (tiny[AVKey.compression] as? [String: Any])?[AVKey.bitRate] as? Int
        t.equal(tinyRate, 2_000_000)
    },
    TestCase("gifTiming") { t in
        // 2.5 s at 10 fps → 25 frames at 0.0, 0.1, …, 2.4.
        let times = GIFTiming.frameTimes(duration: 2.5, fps: 10)
        t.equal(times.count, 25)
        t.approxEqual(times.first ?? -1, 0.0)
        t.approxEqual(times.last ?? -1, 2.4)
        // Degenerate inputs produce at least one frame.
        t.equal(GIFTiming.frameTimes(duration: 0.01, fps: 10).count, 1)
        // Aspect-preserving downscale, never upscale.
        let down = GIFTiming.outputSize(source: CGSize(width: 1920, height: 1080), maxWidth: 960)
        t.equal(down, CGSize(width: 960, height: 540))
        let keep = GIFTiming.outputSize(source: CGSize(width: 800, height: 600), maxWidth: 960)
        t.equal(keep, CGSize(width: 800, height: 600))
    },
]
