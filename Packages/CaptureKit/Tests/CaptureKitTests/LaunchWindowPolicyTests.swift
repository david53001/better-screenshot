import TestKit
@testable import CaptureKit

private func window(granted: Bool = true, loginItem: Bool = false, relaunched: Bool = false,
                    welcome: Bool = false) -> LaunchWindowPolicy.Window {
    LaunchWindowPolicy.window(permissionGranted: granted, launchedAsLoginItem: loginItem,
                              relaunchedAfterGrant: { relaunched }, opensWelcome: { welcome })
}

let launchWindowPolicyTests: [TestCase] = [
    TestCase("userLaunchShowsSettings") { t in
        t.equal(window(), .settings)
    },
    TestCase("loginItemLaunchShowsNothing") { t in
        t.equal(window(loginItem: true), LaunchWindowPolicy.Window.none)
    },
    TestCase("missingPermissionShowsSetupEvenAtLogin") { t in
        t.equal(window(granted: false), .setup)
        t.equal(window(granted: false, loginItem: true), .setup)
    },
    TestCase("relaunchAfterGrantShowsWelcomeEvenAtLogin") { t in
        t.equal(window(relaunched: true), .welcome)
        t.equal(window(loginItem: true, relaunched: true), .welcome)
    },
    TestCase("newUnaskedUserGetsWelcomeInsteadOfSettings") { t in
        t.equal(window(welcome: true), .welcome)
        t.equal(window(loginItem: true, welcome: true), .welcome)
    },
    TestCase("relaunchFlagIsOnlyConsumedOnceThePermissionIsIn") { t in
        var asked = 0
        _ = LaunchWindowPolicy.window(permissionGranted: false, launchedAsLoginItem: false,
                                      relaunchedAfterGrant: { asked += 1; return true }, opensWelcome: { false })
        t.equal(asked, 0)
        _ = LaunchWindowPolicy.window(permissionGranted: true, launchedAsLoginItem: false,
                                      relaunchedAfterGrant: { asked += 1; return true }, opensWelcome: { false })
        t.equal(asked, 1)
    },
    TestCase("welcomeCheckIsSkippedAfterARelaunch") { t in
        var asked = false
        _ = LaunchWindowPolicy.window(permissionGranted: true, launchedAsLoginItem: false,
                                      relaunchedAfterGrant: { true }, opensWelcome: { asked = true; return true })
        t.isFalse(asked)
    },
]
