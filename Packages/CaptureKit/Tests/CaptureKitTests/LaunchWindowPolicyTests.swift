import TestKit
@testable import CaptureKit

private func window(granted: Bool = true, loginItem: Bool = false, isDefault: Bool = true,
                    relaunched: Bool = false, welcome: Bool = false) -> LaunchWindowPolicy.Window {
    LaunchWindowPolicy.window(permissionGranted: granted, launchedAsLoginItem: loginItem, launchIsDefault: isDefault,
                              relaunchedAfterGrant: { relaunched }, opensWelcome: { welcome })
}

private func reopen(hidden: Bool = false, visible: Bool = false, minimized: Bool = false) -> LaunchWindowPolicy.Reopen {
    LaunchWindowPolicy.reopen(isHidden: hidden, hasVisibleWindow: visible, hasMinimizedWindow: minimized)
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
    TestCase("sessionRestoreLaunchShowsNothing") { t in
        // "Reopen windows when logging back in": not a default launch, maybe without the login-item flag.
        t.equal(window(isDefault: false), LaunchWindowPolicy.Window.none)
    },
    TestCase("sessionRestoreKeepsSetupAndWelcomeAfterTheGrant") { t in
        t.equal(window(granted: false, isDefault: false), .setup)
        t.equal(window(isDefault: false, relaunched: true), .welcome)
    },
    TestCase("dockClickWithNothingOpenShowsSettings") { t in
        t.equal(reopen(), .settings)
    },
    TestCase("dockClickWithAWindowUpBringsTheAppForward") { t in
        t.equal(reopen(visible: true), .bringForward)
        t.equal(reopen(visible: true, minimized: true), .bringForward)
    },
    TestCase("dockClickWithOnlyAMinimizedWindowRestoresIt") { t in
        t.equal(reopen(minimized: true), .restoreMinimized)
    },
    TestCase("dockClickWhileHiddenUnhides") { t in
        // While hidden every window reports not visible: unhide, never open Settings over them.
        t.equal(reopen(hidden: true), .unhide)
        t.equal(reopen(hidden: true, minimized: true), .unhide)
    },
]
