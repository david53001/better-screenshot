using System.Text.RegularExpressions;
using BetterScreenshot.Tours;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>Mac v3 Part 7 pure logic: audience, rules, text placeholders, the engine (incl. requires + progress),
/// tag layout / keys / colours, and the catalog lint.</summary>
public class TourTests
{
    private const string AppId = "BetterScreenshot.Windows";

    // ---------------------------------------------------------------- audience + rules

    private static AudienceSignals S(string[]? keys = null, bool folder = false, bool perm = false, string? id = AppId) =>
        new(id, keys ?? Array.Empty<string>(), folder, perm);

    [Fact]
    public void AudienceClassification()
    {
        var owner = new[] { "captureSettings", "hotkeyBindings", "recordingConfig", "saveDirectory", "editorDefaultStyle", "editorRecentColors" };
        Assert.Equal(TourAudienceKind.Existing, TourAudience.Classify(S(owner), AppId));
        Assert.Equal(TourAudienceKind.Existing, TourAudience.Classify(S(owner.Concat(TourAudience.TourKeys).ToArray()), AppId));
        Assert.Equal(TourAudienceKind.New, TourAudience.Classify(S(), AppId));
        Assert.Equal(TourAudienceKind.New, TourAudience.Classify(S(TourAudience.TourKeys.ToArray()), AppId));
        foreach (var k in new[] { "windowPlacement.history", "firstRunComplete", "anythingUnknown" })
            Assert.Equal(TourAudienceKind.Existing, TourAudience.Classify(S(new[] { k }), AppId));
        Assert.Equal(TourAudienceKind.Existing, TourAudience.Classify(S(folder: true), AppId));
        Assert.Equal(TourAudienceKind.Existing, TourAudience.Classify(S(perm: true), AppId));
        foreach (var id in new string?[] { null, "", "com.betterscreenshot.app" })
            Assert.Equal(TourAudienceKind.Existing, TourAudience.Classify(S(id: id), AppId));
    }

    [Fact]
    public void StoredAudienceParsingIsFailSafe()
    {
        Assert.Null(TourAudience.Parse(null));
        Assert.Equal(TourAudienceKind.New, TourAudience.Parse("new"));
        foreach (var s in new[] { "existing", "New", "" }) Assert.Equal(TourAudienceKind.Existing, TourAudience.Parse(s));
    }

    [Fact]
    public void Rules()
    {
        Assert.True(TourRules.ShouldAskQuestion(TourAudienceKind.New, false));
        Assert.False(TourRules.ShouldAskQuestion(TourAudienceKind.New, true));
        Assert.False(TourRules.ShouldAskQuestion(TourAudienceKind.Existing, false));
        Assert.False(TourRules.ShouldAskQuestion(null, false));
        Assert.True(TourRules.ShouldOpenWelcomeOnLaunch(TourAudienceKind.New, false, true));
        Assert.False(TourRules.ShouldOpenWelcomeOnLaunch(TourAudienceKind.New, false, false));
        var tour = TourCatalog.Settings;
        Assert.True(TourRules.ShouldAutoStart(tour, true, null));
        Assert.False(TourRules.ShouldAutoStart(tour, false, null));
        Assert.False(TourRules.ShouldAutoStart(tour, null, null));
        Assert.False(TourRules.ShouldAutoStart(tour, true, 1));
        var v2 = tour with { Version = 2 };
        Assert.True(TourRules.ShouldAutoStart(v2, true, 1));
        Assert.False(TourRules.ShouldAutoStart(v2, null, 1));
        Assert.Equal("Tours reset", TourRules.ResetConfirmation(true));
        Assert.Equal("Tours reset — turn on Tours & tips to see them again", TourRules.ResetConfirmation(false));
    }

    [Fact]
    public void ShortcutPlaceholders()
    {
        string? R(string n) => n switch { "captureArea" => "Ctrl+Shift+4", "captureWindow" => "Ctrl+Shift+8", _ => null };
        Assert.Equal("Press Ctrl+Shift+4 now", TourText.Resolve("Press {shortcut:captureArea} now", R));
        Assert.Equal("Ctrl+Shift+4 and Ctrl+Shift+8", TourText.Resolve("{shortcut:captureArea} and {shortcut:captureWindow}", R));
        Assert.Equal("plain", TourText.Resolve("plain", R));
        Assert.Equal("{shortcut:nope}", TourText.Resolve("{shortcut:nope}", R));
        Assert.Equal("{shortcut:captureArea", TourText.Resolve("{shortcut:captureArea", R));
        Assert.Equal(new[] { "captureArea", "captureWindow" }, TourText.Names("{shortcut:captureArea} {shortcut:captureWindow}"));
        Assert.Equal("Capture Area", TourText.Resolve("{shortcut:captureArea}", n => n == "captureArea" ? "Capture Area" : null)); // unbound → title
    }

    [Fact]
    public void TourIdsRoundTrip()
    {
        foreach (var id in Enum.GetValues<TourId>()) Assert.Equal(id, TourIds.Parse(id.Raw()));
        Assert.Equal("quickAccess", TourId.QuickAccess.Raw());
        Assert.Null(TourIds.Parse("nope"));
        Assert.Equal("Blur & Pixelate Tour", TourId.Redaction.MenuTitle());
    }

    // ---------------------------------------------------------------- engine

    private static readonly TourEvent Ev = TourEvent.Action("x.did");

    private static Tour Make(params TourStep[] steps) => new(TourId.Settings, TourSurface.Settings, TourTrigger.ByApp, steps, TourId.History);
    private static TourStep Ex(string a) => new(a, "T", "B");
    private static TourStep Tr(string a, TourEvent e) => new(a, "T", "B", e);
    private static bool All(string _) => true;

    [Fact]
    public void EngineWalksExplainStepsAndFinishesWithHandOver()
    {
        var e = new TourEngine(Make(Ex("a.a"), Ex("a.b")));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 0), e.Start(0, All));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 1), e.Next(All));
        Assert.Equal(new TourEffect(TourEffectKind.Finished, HandsOverTo: TourId.History), e.Next(All));
        Assert.Equal(TourEffect.None, e.Next(All));
        Assert.Equal(TourStatus.Finished, e.Status);
    }

    [Fact]
    public void TryStepsAdvanceOnlyOnTheirExactEvent()
    {
        var e = new TourEngine(Make(Tr("a.a", TourEvent.ToolSelected("text")), Ex("a.b")));
        e.Start(0, All);
        Assert.Equal(TourEffect.None, e.Next(All)); // Next ignored on Try
        Assert.Equal(TourEffect.None, e.Handle(TourEvent.ToolSelected("arrow"), All));
        Assert.Equal(TourEffect.None, e.Handle(TourEvent.AnnotationAdded("text"), All));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 1), e.Handle(TourEvent.ToolSelected("text"), All));
        Assert.Equal(TourEffect.None, e.Handle(TourEvent.ToolSelected("text"), All)); // events do nothing on Explain
    }

    [Fact]
    public void EventSeenEarlierMakesALaterTryStepSkip()
    {
        var e = new TourEngine(Make(Ex("a.a"), Tr("a.b", Ev), Ex("a.c")));
        e.Start(0, All);
        e.Handle(Ev, All);
        Assert.Equal(new TourEffect(TourEffectKind.Show, 2), e.Next(All));
    }

    [Fact]
    public void SkipStepLeavesATryStepAndTryOnLastStepFinishes()
    {
        var e = new TourEngine(Make(Tr("a.a", Ev), Tr("a.b", TourEvent.CaptureTaken)));
        e.Start(0, All);
        Assert.Equal(new TourEffect(TourEffectKind.Show, 1), e.SkipStep(All));
        Assert.Equal(TourEffectKind.Finished, e.Handle(TourEvent.CaptureTaken, All).Kind);
    }

    [Fact]
    public void MissingAnchorsAreSkipped()
    {
        bool P(string a) => a != "a.b";
        var e = new TourEngine(Make(Ex("a.b"), Ex("a.a"), Ex("a.b"), Ex("a.c")));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 1), e.Start(0, P));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 3), e.Next(P));
        // vanishing mid-step
        Assert.Equal(TourEffectKind.Finished, e.SkipIfAnchorMissing(a => a != "a.c").Kind);
        // trailing missing anchors finish
        var t = new TourEngine(Make(Ex("a.a"), Ex("a.z")));
        t.Start(0, a => a == "a.a");
        Assert.Equal(TourEffectKind.Finished, t.Next(a => a == "a.a").Kind);
    }

    [Fact]
    public void NothingPresentChangesNothing()
    {
        var e = new TourEngine(Make(Ex("a.a")));
        Assert.Equal(TourEffect.NothingToShow, e.Start(0, _ => false));
        Assert.Equal(TourStatus.Idle, e.Status);
        Assert.Equal(TourEffect.NothingToShow, new TourEngine(Make()).Start(0, All));
    }

    [Fact]
    public void SkipPauseResume()
    {
        var e = new TourEngine(Make(Ex("a.a"), Ex("a.b"), Ex("a.c")));
        Assert.Equal(TourEffect.None, e.Pause());
        e.Start(0, All);
        e.Next(All);
        Assert.Equal(new TourEffect(TourEffectKind.Paused, 1), e.Pause());
        Assert.Equal(TourEffect.None, e.Next(All));
        Assert.Equal(TourEffect.None, e.Handle(Ev, All));
        Assert.Equal(TourEffect.NothingToShow, e.Resume(_ => false));
        Assert.Equal(TourStatus.Paused, e.Status);
        Assert.Equal(new TourEffect(TourEffectKind.Show, 2), e.Resume(a => a != "a.b")); // resume skips steps now missing
        Assert.Equal(TourEffect.Skipped, e.SkipTour());
        var p = new TourEngine(Make(Ex("a.a")));
        p.Start(0, All);
        p.Pause();
        Assert.Equal(TourEffect.Skipped, p.SkipTour());
        Assert.Equal(TourEffect.None, new TourEngine(Make(Ex("a.a"))).Resume(All));
    }

    [Fact]
    public void StartAtPersistedIndex()
    {
        var e = new TourEngine(Make(Ex("a.a"), Ex("a.b")));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 1), e.Start(1, All));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 0), new TourEngine(Make(Ex("a.a"))).Start(99, All));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 0), new TourEngine(Make(Ex("a.a"))).Start(-1, All));
    }

    [Fact]
    public void RequiresGatesAStep()
    {
        var req = new TourStep("a.r", "T", "B", Requires: Ev);
        var e = new TourEngine(Make(Ex("a.a"), req, Ex("a.c")));
        e.Start(0, All);
        Assert.Equal(new TourEffect(TourEffectKind.Show, 2), e.Next(All)); // never seen → skipped
        var seen = new TourEngine(Make(Ex("a.a"), req));
        seen.Start(0, All);
        seen.Handle(Ev, All); // seen during an Explain step counts
        Assert.Equal(new TourEffect(TourEffectKind.Show, 1), seen.Next(All));
        Assert.Equal(TourEffect.NothingToShow, new TourEngine(Make(req)).Start(0, All));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 0), new TourEngine(Make(req), new[] { Ev }).Start(0, All));
        var trailing = new TourEngine(Make(Ex("a.a"), req));
        trailing.Start(0, All);
        Assert.Equal(TourEffectKind.Finished, trailing.Next(All).Kind);
    }

    [Fact]
    public void ProgressCountsOnlyStepsThatShow()
    {
        var e = new TourEngine(Make(Ex("a.a"), Ex("a.b"), Ex("a.c"), Ex("a.d"), Ex("a.e")));
        Assert.Null(e.Progress(All));
        e.Start(0, All);
        Assert.Equal((1, 5), e.Progress(All));
        e.Next(All);
        Assert.Equal((2, 5), e.Progress(All));

        // 10-step pill without steps 2 and 5 → 1/8 … 8/8
        var ten = new TourEngine(Make(Enumerable.Range(1, 10).Select(i => Ex($"p.s{i}")).ToArray()));
        bool P(string a) => a != "p.s2" && a != "p.s5";
        ten.Start(0, P);
        Assert.Equal((1, 8), ten.Progress(P));
        for (int i = 0; i < 7; i++) ten.Next(P);
        Assert.Equal((8, 8), ten.Progress(P));

        // the total follows controls appearing / going
        var f = new TourEngine(Make(Ex("a.a"), Ex("a.b"), Ex("a.c")));
        f.Start(0, All);
        Assert.Equal((1, 2), f.Progress(a => a != "a.c"));

        // a Try step already done isn't counted
        var t = new TourEngine(Make(Ex("a.a"), Tr("a.b", Ev), Ex("a.c")));
        t.Start(0, All);
        t.Handle(Ev, All);
        Assert.Equal((1, 2), t.Progress(All));

        // a requires-step counted while the Try step that meets it is ahead; dropped once that Try step is skipped
        var r = new TourEngine(Make(Tr("a.a", Ev), new TourStep("a.r", "T", "B", Requires: Ev)));
        r.Start(0, All);
        Assert.Equal((1, 2), r.Progress(All));
        var r2 = new TourEngine(Make(Tr("a.a", Ev), Ex("a.b"), new TourStep("a.r", "T", "B", Requires: Ev)));
        r2.Start(0, All);
        r2.SkipStep(All);
        Assert.Equal((2, 2), r2.Progress(All));

        // a resumed run at step 3 reads 3/5 (2/4 once step 1's control is gone)
        var res = new TourEngine(Make(Ex("a.a"), Ex("a.b"), Ex("a.c"), Ex("a.d"), Ex("a.e")));
        res.Start(2, All);
        Assert.Equal((3, 5), res.Progress(All));
        Assert.Equal((2, 4), res.Progress(a => a != "a.a"));

        res.SkipTour();
        Assert.Null(res.Progress(All));
    }

    // ---------------------------------------------------------------- layout + keys + colours

    private static readonly TagRect Screen = new(0, 0, 1600, 1040);

    [Fact]
    public void TagGoesLeftFirstThenFallsBack()
    {
        var r = TagLayout.Place(new TagLayoutInput(new TagRect(800, 400, 100, 30), 240, 80, Screen));
        Assert.Equal(TagSide.Left, r.Side);
        Assert.Equal(800 - 4 - 24 - 240, r.Tag.X);
        Assert.NotNull(r.Leader);
        var edge = TagLayout.Place(new TagLayoutInput(new TagRect(20, 400, 100, 30), 240, 80, Screen));
        Assert.Equal(TagSide.Right, edge.Side);
    }

    [Fact]
    public void BarsAndTitleBarControlsGoVertical()
    {
        var r = TagLayout.Place(new TagLayoutInput(new TagRect(800, 100, 30, 22), 240, 80, Screen, VerticalFirst: true));
        Assert.Equal(TagSide.Below, r.Side);
    }

    [Fact]
    public void StepPlacementWinsWhenItFits()
    {
        var r = TagLayout.Place(new TagLayoutInput(new TagRect(800, 400, 100, 30), 240, 80, Screen, Placement: TagPlacement.Below));
        Assert.Equal(TagSide.Below, r.Side);
        var top = TagLayout.Place(new TagLayoutInput(new TagRect(800, 10, 100, 30), 240, 80, Screen, Placement: TagPlacement.Above));
        Assert.NotEqual(TagSide.Above, top.Side); // doesn't fit → automatic
    }

    [Fact]
    public void KeepOutPanelsAreCleared()
    {
        var panel = new TagRect(300, 850, 964, 164);
        var control = new TagRect(320, 870, 300, 28);
        var r = TagLayout.Place(new TagLayoutInput(control, 240, 80, Screen, Host: panel, KeepOut: panel, VerticalFirst: true));
        Assert.Equal(TagSide.Above, r.Side);
        Assert.True(r.Tag.Bottom <= panel.Y - 24 + 1e-6);
    }

    [Fact]
    public void BigControlsGoBesideTheWindowOrInsideTheCorner()
    {
        var host = new TagRect(100, 100, 1000, 700);
        var canvas = new TagRect(110, 150, 900, 600);
        Assert.True(TagLayout.IsBig(canvas, host));
        var r = TagLayout.Place(new TagLayoutInput(canvas, 240, 80, Screen, Host: host));
        Assert.Equal(TagSide.Right, r.Side); // left of the window doesn't fit, right does
        Assert.True(r.Tag.X >= host.Right);

        var full = new TagRect(0, 0, 1600, 1040);
        var inside = TagLayout.Place(new TagLayoutInput(new TagRect(10, 60, 1500, 900), 240, 80, Screen, Host: full));
        Assert.Equal(TagSide.InsideCorner, inside.Side);
        Assert.Null(inside.Leader);
        Assert.Equal(1510 - 16 - 240, inside.Tag.X);

        Assert.False(TagLayout.IsBig(new TagRect(110, 600, 900, 150), host)); // a wide strip isn't big
    }

    [Fact]
    public void NothingFitsGoesOver()
    {
        var r = TagLayout.Place(new TagLayoutInput(new TagRect(0, 0, 1600, 1040), 240, 80, Screen));
        Assert.Equal(TagSide.Over, r.Side);
        Assert.True(Screen.Inflate(-8).Contains(r.Tag) || Screen.Contains(r.Tag));
    }

    [Fact]
    public void TagNeverLeavesTheScreen()
    {
        foreach (var p in Enum.GetValues<TagPlacement>())
            foreach (var c in new[] { new TagRect(0, 0, 40, 40), new TagRect(1560, 1000, 40, 40), new TagRect(700, 500, 200, 40) })
            {
                var r = TagLayout.Place(new TagLayoutInput(c, 240, 80, Screen, Host: new TagRect(0, 0, 1600, 1040), Placement: p));
                Assert.True(Screen.Contains(r.Tag), $"{p} {c}");
            }
    }

    [Fact]
    public void LeaderIsStraightWhenSidesOverlap()
    {
        var box = new TagRect(400, 400, 100, 30).Inflate(4);
        var (from, to) = TagLayout.Leader(new TagRect(100, 380, 240, 80), TagSide.Left, box);
        Assert.Equal(from.Y, to.Y);
        Assert.Equal(340, from.X);
        Assert.Equal(box.X - 2, to.X);
    }

    [Fact]
    public void KeysAct()
    {
        Assert.Equal(TagKeyAction.Next, TagKeys.Action(TagKey.Enter, false, false, false, true, false));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Enter, false, false, false, false, false)); // Try step
        Assert.Equal(TagKeyAction.SkipTour, TagKeys.Action(TagKey.Escape, false, false, false, false, false));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Escape, true, false, false, true, false));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Enter, false, true, false, true, false));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Enter, false, false, true, true, false));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Escape, false, false, false, true, false, hostClaimsEscape: true));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Enter, false, false, false, true, false, hostClaimsKeys: true));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Enter, false, false, false, true, doneState: true));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Other, false, false, false, true, false));
    }

    [Fact]
    public void TourRedClearsAA()
    {
        Assert.Equal(5.53, TagColors.WhiteOnRed(), 2);
        Assert.Equal(4.73, TagColors.WhiteOnRed(0.9), 2);
    }

    // ---------------------------------------------------------------- catalog lint

    private static readonly Regex AnchorRx = new(@"^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)+$");
    private static readonly Regex NameRx = new(@"^[a-z][A-Za-z0-9]*$");
    private static int Words(string s) => s.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Count(w => w.Any(char.IsLetterOrDigit));

    [Fact]
    public void CatalogLint()
    {
        Assert.Equal(12, TourCatalog.All.Count);
        foreach (var tour in TourCatalog.All)
        {
            Assert.NotEmpty(tour.Steps);
            var tryEvents = tour.Steps.Where(s => s.AdvanceOn is not null).Select(s => s.AdvanceOn!.Value).ToList();
            Assert.Equal(tryEvents.Count, tryEvents.Distinct().Count());
            foreach (var s in tour.Steps)
            {
                string where = $"{tour.Id}/{s.Title}";
                Assert.InRange(Words(s.Title), 1, 4);
                Assert.InRange(Words(s.Body), 1, 20);
                Assert.True(Regex.Split(s.Body.Trim(), @"(?<=[.!?…])\s+").Length <= 2, where);
                Assert.Matches(AnchorRx, s.Anchor);
                Assert.DoesNotContain("{", s.Title);
                foreach (var n in TourText.Names(s.Body)) Assert.Contains(n, TourCatalog.ShortcutNames);
                Assert.DoesNotContain("{", Regex.Replace(s.Body, @"\{shortcut:[A-Za-z0-9]+\}", ""));
                if (s.IsTry)
                {
                    string first = s.Body.Split(' ')[0].ToLowerInvariant();
                    Assert.DoesNotContain(first, new[] { "this", "these", "that", "the", "your", "a", "an", "here", "it", "you" });
                }
                foreach (var e in new[] { s.AdvanceOn, s.Requires }.Where(e => e is not null).Select(e => e!.Value))
                {
                    if (e.Kind is TourEventKind.MenuOpened or TourEventKind.ChoiceMade or TourEventKind.Action) Assert.Matches(AnchorRx, e.Name);
                    if (e.Kind is TourEventKind.ToolSelected or TourEventKind.AnnotationAdded or TourEventKind.StyleChanged) Assert.Matches(NameRx, e.Name);
                }
            }
        }
    }

    [Fact]
    public void LintBitesOnBadSamples()
    {
        Assert.DoesNotMatch(AnchorRx, "Editor.canvas");
        Assert.DoesNotMatch(AnchorRx, "editor");
        Assert.True(Words("This is a much too long title") > 4);
        Assert.Equal(1, Words("— {shortcut:captureArea} —"));
    }

    [Fact]
    public void Outline_follows_the_control_shape()
    {
        Assert.Equal(19, TagLayout.OutlineRadius(15, 300, 60));   // the editor tool pill: concentric (+4)
        Assert.Equal(14, TagLayout.OutlineRadius(10, 600, 300));  // Settings' Keyboard Shortcuts card
        Assert.Equal(6, TagLayout.OutlineRadius(0, 100, 40));     // a square control
        Assert.Equal(10, TagLayout.OutlineRadius(15, 20, 300));   // never rounder than a capsule (narrow box)
        Assert.Equal(15, TagLayout.OutlineRadius(30, 400, 30));   // or a short one
    }
}
