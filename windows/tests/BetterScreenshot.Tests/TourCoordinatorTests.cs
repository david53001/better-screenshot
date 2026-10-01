using System.IO;
using System.Text.Json;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using BetterScreenshot.App.Tours;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;
using BetterScreenshot.Tours;
using Xunit;
using Border = System.Windows.Controls.Border;

namespace BetterScreenshot.Tests;

/// <summary>
/// The app-side tour coordinator (Mac v3 §7.2) with a fake tag presenter, real (off-screen) WPF host windows and
/// in-memory settings — existing users never get a tour by itself, replays always work, hand-overs, pause/resume.
/// Nothing is drawn on the real screen: windows sit far off-screen and the tag is a fake.
/// </summary>
public class TourCoordinatorTests
{
    private sealed class FakeTag : ITourTagPresenter
    {
        public Action? OnNext { get; set; }
        public Action? OnSkipStep { get; set; }
        public Action? OnSkipTour { get; set; }
        public bool IsDone { get; private set; }
        public List<string> Log { get; } = new();
        public (string Title, int N, int Total, bool Last)? Current;

        public void Show(Window host, TourStep step, string body, int number, int total, bool isLast)
        {
            IsDone = false;
            Current = (step.Title, number, total, isLast);
            Log.Add($"show {step.Title} {number}/{total}");
        }

        public void ShowCompleted() { IsDone = true; Log.Add("done"); }
        public void UpdateProgress(int number, int total, bool isLast) => Current = Current is { } c ? (c.Title, number, total, isLast) : null;
        public void Hide() { Current = null; IsDone = false; Log.Add("hide"); }
        public void Detach() { Current = null; IsDone = false; Log.Add("detach"); }
    }

    private static void RunSta(Action body)
    {
        Exception? error = null;
        var t = new Thread(() =>
        {
            try { body(); }
            catch (Exception e) { error = e; }
            finally { Dispatcher.CurrentDispatcher.InvokeShutdown(); }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        Assert.True(t.Join(TimeSpan.FromSeconds(30)), "STA test timed out");
        if (error is not null) throw new Xunit.Sdk.XunitException(error.ToString());
    }

    private static void Flush() => Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ContextIdle);

    private static void Pump(int ms)
    {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(ms) };
        timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; };
        timer.Start();
        Dispatcher.PushFrame(frame);
    }

    /// <summary>An off-screen, non-activated window holding one Border per anchor id.</summary>
    private static Window Host(params string[] anchors)
    {
        var panel = new StackPanel();
        foreach (var a in anchors)
        {
            var b = new Border { Width = 120, Height = 24, Margin = new Thickness(4) };
            TourAnchors.Set(b, a);
            panel.Children.Add(b);
        }
        var w = new Window
        {
            Left = -32000, Top = -32000, Width = 400, Height = 400, ShowActivated = false, ShowInTaskbar = false,
            WindowStyle = WindowStyle.None, Content = panel,
        };
        w.Show();
        w.UpdateLayout();
        return w;
    }

    private static (TourCoordinator C, FakeTag Tag, SettingsStore S) Make(bool? toursOn)
    {
        var s = new SettingsStore { FirstUseToursEnabled = toursOn };
        var tag = new FakeTag();
        var c = new TourCoordinator(s, n => n == "captureArea" ? "Ctrl+Shift+4" : null, tag, save: () => { });
        return (c, tag, s);
    }

    private static readonly string[] SettingsAnchors = { "settings.cards", "settings.tip", "settings.opacity", "settings.shortcuts" };

    [Fact]
    public void ExistingUsersNeverGetATourByThemselves() => RunSta(() =>
    {
        foreach (var flag in new bool?[] { null, false })
        {
            var (c, tag, s) = Make(flag);
            var w = Host(SettingsAnchors);
            c.SurfaceShown(TourSurface.Settings, w);
            Flush();
            Assert.Empty(tag.Log);
            Assert.Empty(s.ToursSeen);
            c.Post(TourEvent.ToolSelected("text"));
            Assert.Empty(tag.Log);
            w.Close();
        }
    });

    [Fact]
    public void ANewUserWhoSaidYesWalksTheTourOnceAndItIsMarkedSeen() => RunSta(() =>
    {
        var (c, tag, s) = Make(true);
        var w = Host(SettingsAnchors);
        c.SurfaceShown(TourSurface.Settings, w);
        Flush();
        Assert.Equal(("Your settings", 1, 4, false), tag.Current);
        for (int i = 0; i < 3; i++) { tag.OnNext!(); Flush(); }
        Assert.Equal(("Keyboard shortcuts", 4, 4, true), tag.Current);
        tag.OnNext!();
        Flush();
        Assert.Null(tag.Current);
        Assert.Equal(1, s.ToursSeen["settings"]);
        tag.Log.Clear();
        c.SurfaceShown(TourSurface.Settings, w);
        Flush();
        Assert.Empty(tag.Log); // seen → never again by itself
        w.Close();
    });

    [Fact]
    public void ProgressCountsOnlyAnchorsThatExist() => RunSta(() =>
    {
        var (c, tag, _) = Make(true);
        var w = Host("settings.cards", "settings.shortcuts");
        c.SurfaceShown(TourSurface.Settings, w);
        Flush();
        Assert.Equal(("Your settings", 1, 2, false), tag.Current);
        tag.OnNext!();
        Flush();
        Assert.Equal(("Keyboard shortcuts", 2, 2, true), tag.Current);
        w.Close();
    });

    [Fact]
    public void ReplayFromAWindowWorksForEveryoneAndRestarts() => RunSta(() =>
    {
        var (c, tag, s) = Make(null);
        s.ToursSeen["settings"] = 1;
        var w = Host(SettingsAnchors);
        c.Replay(TourId.Settings, w);
        Flush();
        tag.OnNext!();
        Flush();
        Assert.Equal(2, tag.Current!.Value.N);
        c.Replay(TourId.Settings, w);
        Flush();
        Assert.Equal(("Your settings", 1, 4, false), tag.Current);
        w.Close();
    });

    [Fact]
    public void MenuReplayQueuesOpensOrSaysWhenItStarts() => RunSta(() =>
    {
        var (c, tag, _) = Make(null);
        var opened = new List<TourSurface>();
        var hud = new List<string>();
        c.OpenSurface = surface => { opened.Add(surface); return surface == TourSurface.Settings; };
        c.Hud = hud.Add;

        c.Replay(TourId.Settings, null);
        Assert.Equal(new[] { TourSurface.Settings }, opened);
        Assert.Empty(tag.Log);
        var w = Host(SettingsAnchors);
        c.SurfaceShown(TourSurface.Settings, w); // queued → starts though tours are off
        Flush();
        Assert.Equal("Your settings", tag.Current!.Value.Title);

        c.Replay(TourId.Editor, null);
        Assert.Equal(new[] { "Editor Tour starts the next time you use it" }, hud);
        w.Close();
    });

    [Fact]
    public void ShortcutPlaceholdersResolveInTheShownBody() => RunSta(() =>
    {
        var s = new SettingsStore();
        string? body = null;
        var tag = new BodyTag(b => body = b);
        var c = new TourCoordinator(s, n => n == "captureArea" ? "Ctrl+Shift+4" : n == "captureWindow" ? "Ctrl+Shift+8" : n == "captureFullscreen" ? "Ctrl+Shift+6" : null, tag, () => { });
        var w = Host("welcome.shortcuts");
        c.Replay(TourId.Welcome, w);
        Flush();
        // The catalog keeps each shortcut with its word (no-break spaces), as the Mac strings do.
        Assert.Equal("Ctrl+Shift+4 area, Ctrl+Shift+8 window, Ctrl+Shift+6 full screen — in any app.", body);
        w.Close();
    });

    private sealed class BodyTag(Action<string> onBody) : ITourTagPresenter
    {
        public Action? OnNext { get; set; }
        public Action? OnSkipStep { get; set; }
        public Action? OnSkipTour { get; set; }
        public bool IsDone => false;
        public void Show(Window host, TourStep step, string body, int number, int total, bool isLast) => onBody(body);
        public void ShowCompleted() { }
        public void UpdateProgress(int number, int total, bool isLast) { }
        public void Hide() { }
        public void Detach() { }
    }

    [Fact]
    public void TheCaptureThatEndsWelcomeHandsOverToQuickAccessAndClosesWelcome() => RunSta(() =>
    {
        var (c, tag, s) = Make(null); // an existing user replaying Welcome: hand-overs ignore the switch
        var finished = new List<TourId>();
        c.OnFinished = finished.Add;
        var welcome = Host("welcome.shortcuts", "welcome.captureArea");
        c.Replay(TourId.Welcome, welcome);
        Flush();
        tag.OnNext!();
        Flush();
        Assert.Equal("Take a screenshot", tag.Current!.Value.Title);

        // The Quick Access card appears before the capture event arrives (either order must work).
        var card = Host("quickAccess.card", "quickAccess.actions");
        c.SurfaceShown(TourSurface.QuickAccess, card);
        Flush();
        Assert.Equal(new[] { TourId.Welcome }, finished);
        Assert.Equal(1, s.ToursSeen["welcome"]);
        Assert.Equal("Your screenshot", tag.Current!.Value.Title);
        c.Post(TourEvent.CaptureTaken); // goes to the Quick Access tour now — nothing breaks
        Flush();
        Assert.Equal("Your screenshot", tag.Current!.Value.Title);
        welcome.Close();
        card.Close();
    });

    [Fact]
    public void ATryStepShowsDoneThenTheNextStep() => RunSta(() =>
    {
        var (c, tag, s) = Make(true);
        var w = Host("history.grid", "history.item", "history.actions");
        c.SurfaceShown(TourSurface.History, w);
        Flush();
        tag.OnNext!();
        Flush();
        Assert.Equal("Select a capture", tag.Current!.Value.Title);
        tag.OnNext!(); // Next is ignored on a Try step
        Flush();
        Assert.Equal("Select a capture", tag.Current!.Value.Title);
        c.Post(TourEvent.Action("history.selected"));
        Assert.True(tag.IsDone);
        Pump(1100);
        Assert.Equal("Several at once", tag.Current!.Value.Title);
        Assert.False(tag.IsDone);
        w.Close();
    });

    [Fact]
    public void EventToursStartOnTheirEventButNeverInterrupt() => RunSta(() =>
    {
        var (c, tag, _) = Make(true);
        var editor = Host("editor.canvas", "editor.inspector.styles");
        c.SurfaceShown(TourSurface.Editor, editor); // the Editor tour's anchors are missing here → nothing to show
        Flush();
        Assert.Empty(tag.Log);
        c.Post(TourEvent.ToolSelected("text"));
        Flush();
        Assert.Equal("Click to type", tag.Current!.Value.Title);

        tag.Log.Clear();
        c.Post(TourEvent.Action("editor.redactionToolChosen")); // a running tour isn't interrupted
        Flush();
        Assert.DoesNotContain(tag.Log, l => l.StartsWith("show Hide"));
        editor.Close();
    });

    [Fact]
    public void ClosingTheHostPausesAndReopeningResumesThere() => RunSta(() =>
    {
        var (c, tag, s) = Make(true);
        var w = Host(SettingsAnchors);
        c.SurfaceShown(TourSurface.Settings, w);
        Flush();
        tag.OnNext!();
        Flush();
        w.Close();
        Flush();
        Assert.Equal(1, s.ToursPaused["settings"]);
        Assert.False(s.ToursSeen.ContainsKey("settings"));

        var again = Host(SettingsAnchors);
        c.SurfaceShown(TourSurface.Settings, again);
        Flush();
        Assert.Equal(("Tips on every row", 2, 4, false), tag.Current);
        Assert.False(s.ToursPaused.ContainsKey("settings"));
        again.Close();
    });

    [Fact]
    public void AnotherSurfacesTourPausesTheRunningOneWhichResumesAfter() => RunSta(() =>
    {
        var (c, tag, s) = Make(null);
        var settings = Host(SettingsAnchors);
        var history = Host("history.grid");
        c.Replay(TourId.Settings, settings);
        Flush();
        tag.OnNext!();
        Flush();
        c.Replay(TourId.History, history);
        Flush();
        Assert.Equal("Your capture history", tag.Current!.Value.Title);
        Assert.Equal(1, s.ToursPaused["settings"]);
        tag.OnNext!(); // History has one step here (empty) → finished
        Flush();
        Assert.Equal(("Tips on every row", 2, 4, false), tag.Current);
        settings.Close();
        history.Close();
    });

    [Fact]
    public void SkipTourMarksSeenWithoutHandOver() => RunSta(() =>
    {
        var (c, tag, s) = Make(null);
        var finished = new List<TourId>();
        c.OnFinished = finished.Add;
        var welcome = Host("welcome.shortcuts", "welcome.captureArea");
        c.Replay(TourId.Welcome, welcome);
        Flush();
        tag.OnSkipTour!();
        Flush();
        Assert.Null(tag.Current);
        Assert.Equal(1, s.ToursSeen["welcome"]);
        Assert.Empty(finished);
        var card = Host("quickAccess.card");
        c.SurfaceShown(TourSurface.QuickAccess, card);
        Flush();
        Assert.Null(tag.Current); // no hand-over after Skip Tour (and tours are off)
        welcome.Close();
        card.Close();
    });

    [Fact]
    public void ResetAllClearsSeenAndPausedOnly() => RunSta(() =>
    {
        var (c, _, s) = Make(false);
        s.TourAudience = "new";
        s.TourQuestionAnswered = true;
        s.ToursSeen["editor"] = 1;
        s.ToursPaused["history"] = 2;
        Assert.Equal("Tours reset — turn on Tours & tips to see them again", c.ResetAll());
        Assert.Empty(s.ToursSeen);
        Assert.Empty(s.ToursPaused);
        Assert.Equal("new", s.TourAudience);
        Assert.True(s.TourQuestionAnswered);
        Assert.False(s.FirstUseToursEnabled);
        s.FirstUseToursEnabled = true;
        Assert.Equal("Tours reset", c.ResetAll());
    });

    // ---------------------------------------------------------------- persistence + audience signals

    private static string TempDir()
    {
        string d = Path.Combine(Path.GetTempPath(), "bs-tour-tests-" + Guid.NewGuid().ToString("N"));
        return d;
    }

    [Fact]
    public void TourKeysPersistUnderTheirNamesAndAreAbsentUntilSet()
    {
        string dir = TempDir();
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "settings.json");
            new SettingsStore().Save(path);
            var names = JsonDocument.Parse(File.ReadAllText(path)).RootElement.EnumerateObject().Select(p => p.Name).ToList();
            Assert.DoesNotContain(names, TourAudience.TourKeys.Contains);

            var s = new SettingsStore { TourAudience = "existing", TourQuestionAnswered = true, FirstUseToursEnabled = false };
            s.ToursSeen["settings"] = 1;
            s.ToursPaused["history"] = 2;
            s.Save(path);
            names = JsonDocument.Parse(File.ReadAllText(path)).RootElement.EnumerateObject().Select(p => p.Name).ToList();
            foreach (var k in TourAudience.TourKeys) Assert.Contains(k, names);
            var back = SettingsStore.Load(path);
            Assert.Equal("existing", back.TourAudience);
            Assert.True(back.TourQuestionAnswered);
            Assert.False(back.FirstUseToursEnabled);
            Assert.Equal(1, back.ToursSeen["settings"]);
            Assert.Equal(2, back.ToursPaused["history"]);
            Assert.Null(SettingsStore.Load(Path.Combine(dir, "missing.json")).FirstUseToursEnabled); // absent = off
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public void AudienceSignalsReadTheFolderBeforeTheFirstSave()
    {
        string dir = TempDir();
        try
        {
            var none = SettingsStore.AudienceSignals(dir);
            Assert.Empty(none.Keys);
            Assert.False(none.FolderHasContent);
            Assert.Equal(TourAudienceKind.New, TourAudience.Classify(new AudienceSignals("x", none.Keys, none.FolderHasContent, false), "x"));

            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, "settings.json"), "{\"tourAudience\":\"new\",\"toursSeen\":{}}");
            var tourOnly = SettingsStore.AudienceSignals(dir);
            Assert.False(tourOnly.FolderHasContent);
            Assert.Equal(TourAudienceKind.New, TourAudience.Classify(new AudienceSignals("x", tourOnly.Keys, false, false), "x"));

            // Every earlier version wrote non-tour keys → existing.
            new SettingsStore().Save(Path.Combine(dir, "settings.json"));
            var owner = SettingsStore.AudienceSignals(dir);
            Assert.Contains("captureSettings", owner.Keys);
            Assert.Equal(TourAudienceKind.Existing, TourAudience.Classify(new AudienceSignals("x", owner.Keys, false, false), "x"));

            File.WriteAllText(Path.Combine(dir, "settings.json"), "{not json");
            Assert.Equal(TourAudienceKind.Existing,
                TourAudience.Classify(new AudienceSignals("x", SettingsStore.AudienceSignals(dir).Keys, false, false), "x"));

            File.Delete(Path.Combine(dir, "settings.json"));
            Directory.CreateDirectory(Path.Combine(dir, "History"));
            Assert.True(SettingsStore.AudienceSignals(dir).FolderHasContent); // even an empty History\ counts
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public void OpacityDemoPathFollowsTheMacTimings()
    {
        const double u = 0.4;
        Assert.Equal(u, OpacityDemoPath.Value(0, u), 6);
        Assert.Equal(u, OpacityDemoPath.Value(0.5, u), 6);           // holding at the user's value
        Assert.Equal(0, OpacityDemoPath.Value(3.0, u), 6);           // 0.6 + 2.4 → Transparent
        Assert.Equal(0, OpacityDemoPath.Value(3.7, u), 6);           // held 0.8 s
        Assert.Equal(1, OpacityDemoPath.Value(7.0, u), 6);           // + 3.2 → Opaque
        Assert.Equal(u, OpacityDemoPath.Value(9.4, u), 6);           // + 0.8 hold + 1.6 back
        Assert.Equal(10.4, OpacityDemoPath.Period, 6);
        Assert.Equal(OpacityDemoPath.Value(1.2, u), OpacityDemoPath.Value(1.2 + OpacityDemoPath.Period, u), 6);
        double mid = OpacityDemoPath.Value(1.8, u);                   // halfway down: smoothstep midpoint
        Assert.Equal(u / 2, mid, 6);
    }
}
