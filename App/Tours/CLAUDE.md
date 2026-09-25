# App/Tours — the guided-tour coordinator (v3 Part 7)

Design: `docs/superpowers/specs/2026-09-24-betterscreenshot-editor-recording-v3-design.md` §14 and **§14.9**
(new users only, asked first). Pure logic + tests live in `Packages/TourKit` (`TourAudience`, `TourRules`,
`TourEngine`, `TourText`); Windows-port notes: `docs/MAC-TO-WINDOWS-PARITY-v3.md` §7.1–7.2.

Terms: a **tour** is an ordered list of **steps** for one part of the app; each step outlines one real
control (its **anchor**, an id like `editor.inspector.colour` set with `view.tourAnchor`) with a short tag.
**Explain** steps advance on Next; **Try** steps advance when the user does the thing (the app posts a
`TourEvent`). A **surface** is a window a tour runs on (editor, Settings…). "Lane 7B" = the parallel work
stream building the tag overlay + ⓘ button in TourKit (status: `docs/PROGRESS-v3.md`, lane "Tours & help").

- `TourCoordinator.swift` — owns who gets tours, triggers, persistence and the on-screen tag:
  - `classifyAudienceIfNeeded(screenRecordingGranted:)` — called **first thing** in
    `AppDelegate.applicationDidFinishLaunching`, before anything writes a preference. Reads only the app's
    own domain (`persistentDomain(forName: bundleID)`), `~/Library/Application Support/BetterScreenshot/`,
    and the Screen Recording grant; stores `tourAudience` once and never recomputes. Doubt → `existing`.
  - Sets the `TourEvents` handlers (`install()`): `surfaceShown` → queued tour for that surface, else a
    paused one (resumes at its step), else an automatic one; `post(event)` → the running Try step, then
    `.event(…)`-triggered tours (only when nothing is running); `replay(id, window)` → now in that window,
    or (nil) now if its surface is on screen, else queued + the surface opened (`openSurface`) or a HUD note.
  - Automatic starts need `firstUseToursEnabled == true` (absent = false) and an unseen tour version. The
    audience only decides whether the Welcome window asks.
  - One tour on screen: another surface's tour pauses the running one (resumed when that one ends, if its
    window is still up). A tour on its last step that `handsOverTo` the starting tour is finished instead.
    Host window closed or ordered out → pause (0.5 s watchdog while a tour runs; panels are ordered out,
    not closed). A step whose anchor disappears is skipped. Skip tour / finish → `toursSeen[id] = version`.
  - Persists exactly: `tourAudience`, `tourQuestionAnswered`, `firstUseToursEnabled`, `toursSeen`,
    `toursPaused` (`TourPreferenceKey`).
- `NoOpTourTagPresenter.swift` — shows nothing; stands in for lane 7B's `TagOverlayController` until the
  merge switches `AppDelegate`'s `makePresenter:` factory to the real overlay.

Wired in: `App/Lifecycle/AppDelegate.swift` (launch classification, factory, menu/Settings/onboarding
closures, `openSurface` for Welcome/Settings/History), `App/MenuBar/OnboardingController.swift` (the
question), `App/MenuBar/MenuBarController.swift` (Help & Tours), `App/Settings/SettingsView.swift`
(Startup → Tours & tips).

Verify: `swift run -j 2 --package-path Packages/TourKit TourKitTests`; end-to-end, a probe that compiles
the App sources with a fake presenter and its own `UserDefaults(suiteName:)` (never the real
`com.betterscreenshot.mac` domain), windows at desktop level + `orderBack` only.
