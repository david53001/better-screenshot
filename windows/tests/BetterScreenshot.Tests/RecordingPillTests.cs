using BetterScreenshot.Core;
using BetterScreenshot.Recording;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>Mac v3 A.2 + Part 5 pure logic: LetterboxFit, RecordingPillLayout (cases translated from the Mac's
/// bottom-left origin to top-left), the pill's item table, per-segment ffmpeg options.</summary>
public class RecordingPillTests
{
    // ---------------------------------------------------------------- LetterboxFit

    [Theory]
    [InlineData(640, 400, 1280, 800, 0, 0, 1280, 800)]
    [InlineData(300, 520, 1280, 800, 409, 0, 462, 800)]
    [InlineData(1600, 400, 800, 600, 0, 200, 800, 200)]
    [InlineData(100, 50, 1000, 500, 0, 0, 1000, 500)] // scales up
    [InlineData(0, 0, 1280, 800, 0, 0, 1280, 800)]
    [InlineData(10, 0, 1280, 800, 0, 0, 1280, 800)]
    public void LetterboxFitMatchesMac(double cw, double ch, double ow, double oh, double x, double y, double w, double h) =>
        Assert.Equal(new PxRect(x, y, w, h), LetterboxFit.Rect(new PxSize(cw, ch), new PxSize(ow, oh)));

    // ---------------------------------------------------------------- RecordingPillLayout

    [Fact]
    public void ConfirmPairWidths()
    {
        Assert.Equal(33, RecordingPillLayout.ConfirmPairButtonWidth(new double[] { 66, 68 }, 2, 28));
        Assert.Equal(68, RecordingPillLayout.ConfirmSlotWidth(33, 2));
        Assert.Equal(28, RecordingPillLayout.ConfirmPairButtonWidth(new double[] { 40, 30 }, 2, 28));
        Assert.Equal(28, RecordingPillLayout.ConfirmPairButtonWidth(Array.Empty<double>(), 2, 28));
        Assert.Equal(34, RecordingPillLayout.ConfirmPairButtonWidth(new double[] { 69 }, 2, 28));
        Assert.Equal(70, RecordingPillLayout.ConfirmSlotWidth(34, 2));
    }

    private static readonly PxRect Visible = new(0, 0, 1470, 900);

    // Mac pill (400, 100, 600×40) bottom-left → top-left y = 900 − 140 = 760; bubble Mac y 146 → 900 − 170 = 730.
    [Fact]
    public void HintSitsAboveThePill() =>
        Assert.Equal(new PxRect(600, 730, 200, 24),
            RecordingPillLayout.HintFrame(new PxSize(200, 24), 700, new PxRect(400, 760, 600, 40), Visible));

    // Mac pill at y 850 → top-left y 10: no room above → below, Mac y 820 → 900 − 844 = 56.
    [Fact]
    public void HintGoesBelowWhenNoRoomAbove() =>
        Assert.Equal(new PxRect(600, 56, 200, 24),
            RecordingPillLayout.HintFrame(new PxSize(200, 24), 700, new PxRect(400, 10, 600, 40), Visible));

    [Fact]
    public void HintStaysInsideTheScreen()
    {
        Assert.Equal(8, RecordingPillLayout.HintFrame(new PxSize(200, 24), 20, new PxRect(8, 760, 180, 40), Visible).X);
        Assert.Equal(1462, RecordingPillLayout.HintFrame(new PxSize(200, 24), 1460, new PxRect(1280, 760, 182, 40), Visible).Right);
        var narrow = RecordingPillLayout.HintFrame(new PxSize(500, 24), 250, new PxRect(150, 760, 100, 40), new PxRect(100, 0, 300, 900));
        Assert.Equal(284, narrow.Width);
        Assert.Equal(108, narrow.X);
    }

    [Fact]
    public void DefaultFrameIsBottomCentre20AboveTheWorkArea()
    {
        var f = RecordingPillLayout.DefaultFrame(new PxSize(700, 40), new PxRect(0, 0, 1600, 1040));
        Assert.Equal(new PxRect(450, 980, 700, 40), f);
    }

    [Fact]
    public void WidthChangesKeepTheBottomRightCorner()
    {
        var wide = RecordingPillLayout.FromBottomRight(new PxPoint(1200, 1000), new PxSize(715, 40));
        var narrow = RecordingPillLayout.FromBottomRight(new PxPoint(wide.Right, wide.Bottom), new PxSize(178, 40));
        Assert.Equal(wide.Right, narrow.Right);
        Assert.Equal(wide.Bottom, narrow.Bottom);
        Assert.Equal(1022, narrow.X);
    }

    [Fact]
    public void ClampKeepsTheCapsule8Inside()
    {
        var work = new PxRect(0, 0, 1600, 1040);
        Assert.Equal(new PxRect(8, 8, 300, 40), RecordingPillLayout.ClampInside(new PxRect(-50, -20, 300, 40), work));
        Assert.Equal(new PxRect(1292, 992, 300, 40), RecordingPillLayout.ClampInside(new PxRect(1500, 1030, 300, 40), work));
    }

    [Fact]
    public void AnchorRoundTripsAndRejectsJunk()
    {
        string s = RecordingPillLayout.FormatAnchor(new PxPoint(1234.4, 987.6));
        Assert.Equal("{1234, 988}", s);
        Assert.Equal(new PxPoint(1234, 988), RecordingPillLayout.ParseAnchor(s));
        Assert.Null(RecordingPillLayout.ParseAnchor(null));
        Assert.Null(RecordingPillLayout.ParseAnchor("{1, 2, 3}"));
        Assert.Null(RecordingPillLayout.ParseAnchor("{a, b}"));
        Assert.Null(RecordingPillLayout.ParseAnchor("{NaN, 2}"));
    }

    // ---------------------------------------------------------------- the item table

    private static PillState Live(PillTarget target = PillTarget.Window) => new()
    {
        Phase = PillPhase.Recording, Elapsed = TimeSpan.FromSeconds(727), MicTrack = true, SystemTrack = true,
        Camera = PillCamera.Hidden, Target = target,
    };

    [Fact]
    public void TimerFormatsAndDims()
    {
        Assert.Equal("12:07", RecordingPillModel.TimerText(Live()));
        Assert.Equal("0:00", RecordingPillModel.TimerText(Live() with { Phase = PillPhase.Countdown }));
        Assert.True(RecordingPillModel.DotIsRed(Live()));
        Assert.False(RecordingPillModel.TimerIsDim(Live()));
        var paused = Live() with { Phase = PillPhase.Paused };
        Assert.False(RecordingPillModel.DotIsRed(paused));
        Assert.True(RecordingPillModel.TimerIsDim(paused));
        Assert.True(RecordingPillModel.ShowsPausedLabel(paused));
        Assert.False(RecordingPillModel.ShowsPausedLabel(Live() with { Phase = PillPhase.Countdown }));
    }

    [Fact]
    public void MicStatesAndHints()
    {
        var on = RecordingPillModel.Item(Live(), PillItemId.Mic);
        Assert.Equal(("mic", PillLook.Normal, true), (on.Icon, on.Look, on.Enabled));
        Assert.Equal("Mute microphone — the video keeps a silent gap, stays in sync", on.Hint);
        var muted = RecordingPillModel.Item(Live() with { MicMuted = true }, PillItemId.Mic);
        Assert.Equal(("mic-slash", PillLook.RedChip, "Unmute microphone"), (muted.Icon, muted.Look, muted.Hint));
        var none = RecordingPillModel.Item(Live() with { MicTrack = false }, PillItemId.Mic);
        Assert.False(none.Enabled);
        Assert.Equal(PillLook.Disabled, none.Look);
        Assert.Equal("Mic wasn't on when this recording started — there's no mic track to mute", none.Hint);
    }

    [Fact]
    public void SystemAudioStatesAndHints()
    {
        Assert.Equal("Mute system audio — the video keeps a silent gap, stays in sync",
            RecordingPillModel.Item(Live(), PillItemId.SystemAudio).Hint);
        Assert.Equal(PillLook.RedChip, RecordingPillModel.Item(Live() with { SystemMuted = true }, PillItemId.SystemAudio).Look);
        var none = RecordingPillModel.Item(Live() with { SystemTrack = false }, PillItemId.SystemAudio);
        Assert.Equal("System audio wasn't on when this recording started — there's no system audio track to mute", none.Hint);
        Assert.False(none.Enabled);
    }

    [Fact]
    public void CameraOffIsDimNotAWarning()
    {
        var off = RecordingPillModel.Item(Live(), PillItemId.Camera);
        Assert.Equal(("video", PillLook.Dim, "Show camera bubble"), (off.Icon, off.Look, off.Hint));
        var on = RecordingPillModel.Item(Live() with { Camera = PillCamera.Showing }, PillItemId.Camera);
        Assert.Equal(("video-fill", PillLook.Normal, "Hide camera bubble"), (on.Icon, on.Look, on.Hint));
        Assert.Equal("No camera found", RecordingPillModel.Item(Live() with { Camera = PillCamera.NoCamera }, PillItemId.Camera).Hint);
        var denied = RecordingPillModel.Item(Live() with { Camera = PillCamera.Denied }, PillItemId.Camera);
        Assert.False(denied.Enabled);
        Assert.Contains("Settings › Privacy & security › Camera", denied.Hint);
    }

    [Fact]
    public void SwitchFollowsTheTargetAndHidesForFullScreen()
    {
        var w = RecordingPillModel.Item(Live(PillTarget.Window), PillItemId.Switch);
        Assert.Equal(("window", "Switch Window…", true), (w.Icon, w.Label, w.Visible));
        Assert.Equal("Record a different window — it's scaled to fit this video's frame", w.Hint);
        var a = RecordingPillModel.Item(Live(PillTarget.Area), PillItemId.Switch);
        Assert.Equal(("rect-dashed", "Switch Area…"), (a.Icon, a.Label));
        Assert.Equal("Record a different area — it's scaled to fit this video's frame", a.Hint);
        Assert.False(RecordingPillModel.Item(Live(PillTarget.FullScreen), PillItemId.Switch).Visible);
        Assert.False(RecordingPillModel.ShowsSwitchGroup(Live(PillTarget.FullScreen)));
        Assert.False(RecordingPillModel.ShowsSwitchGroup(Live() with { Collapsed = true }));
    }

    [Fact]
    public void CountdownGreysEverythingButStop()
    {
        var s = Live() with { Phase = PillPhase.Countdown };
        foreach (var id in new[] { PillItemId.Switch, PillItemId.Restart, PillItemId.Discard, PillItemId.PauseResume })
        {
            var item = RecordingPillModel.Item(s, id);
            Assert.False(item.Enabled);
            Assert.Equal(RecordingPillModel.AvailableOnceRecording, item.Hint);
        }
        var stop = RecordingPillModel.Item(s, PillItemId.Stop);
        Assert.True(stop.Enabled);
        Assert.Equal("Cancel recording", stop.Hint);
        Assert.True(RecordingPillModel.Item(s, PillItemId.Mic).Enabled); // toggles already work
    }

    [Fact]
    public void ConfirmTakesTheOtherButtonsSlot()
    {
        var restart = Live() with { Confirm = PillConfirm.Restart };
        var r = RecordingPillModel.Item(restart, PillItemId.Restart);
        Assert.Equal((null, "Restart?", PillLook.ConfirmCapsule), (r.Icon, r.Label, r.Look));
        Assert.Equal("Click again to restart — what's recorded so far is deleted", r.Hint);
        Assert.False(RecordingPillModel.Item(restart, PillItemId.Discard).Visible);

        var discard = Live() with { Confirm = PillConfirm.Discard };
        Assert.Equal("Discard?", RecordingPillModel.Item(discard, PillItemId.Discard).Label);
        Assert.Equal("Click again to delete this recording", RecordingPillModel.Item(discard, PillItemId.Discard).Hint);
        Assert.False(RecordingPillModel.Item(discard, PillItemId.Restart).Visible);
    }

    [Fact]
    public void PauseStopChevronHints()
    {
        Assert.Equal(("pause", "Pause recording"), Pair(RecordingPillModel.Item(Live(), PillItemId.PauseResume)));
        Assert.Equal(("play", "Resume recording"), Pair(RecordingPillModel.Item(Live() with { Phase = PillPhase.Paused }, PillItemId.PauseResume)));
        Assert.Equal(("stop", "Stop recording"), Pair(RecordingPillModel.Item(Live(), PillItemId.Stop)));
        Assert.Equal(PillLook.RedGlyph, RecordingPillModel.Item(Live(), PillItemId.Stop).Look);
        Assert.Equal(("chevron-right", "Collapse to timer, Pause and Stop"), Pair(RecordingPillModel.Item(Live(), PillItemId.Chevron)));
        Assert.Equal(("chevron-left", "Show all controls"), Pair(RecordingPillModel.Item(Live() with { Collapsed = true }, PillItemId.Chevron)));
        Assert.Equal("Restart — delete what's recorded so far and start over", RecordingPillModel.Item(Live(), PillItemId.Restart).Hint);
        Assert.Equal("Discard — stop and delete this recording", RecordingPillModel.Item(Live(), PillItemId.Discard).Hint);

        static (string?, string) Pair(PillItem i) => (i.Icon, i.Hint);
    }

    [Fact]
    public void CollapsedShowsOnlyTimerPauseStopChevron()
    {
        var visible = RecordingPillModel.Items(Live() with { Collapsed = true }).Where(i => i.Visible).Select(i => i.Id);
        Assert.Equal(new[] { PillItemId.PauseResume, PillItemId.Stop, PillItemId.Chevron }, visible);
    }

    // ---------------------------------------------------------------- engine-facing pure bits

    [Fact]
    public void ControlsInRecordingDefaultsOffAndRoundTrips()
    {
        Assert.False(RecordingConfig.Default.ControlsInRecording);
        var d = (RecordingConfig.Default with { ControlsInRecording = true }).ToDictionary();
        Assert.Equal("true", d["controlsInRecording"]);
        Assert.True(RecordingConfig.FromDictionary(d).ControlsInRecording);
    }

    [Fact]
    public void ElapsedFreezesWhilePaused()
    {
        var t0 = new DateTime(2026, 10, 2, 12, 0, 0);
        var s = RecorderState.Idle;
        s.Transition(RecorderEvent.Arm);
        s.Transition(RecorderEvent.Begin, t0);
        Assert.Equal(TimeSpan.FromSeconds(10), s.Elapsed(t0.AddSeconds(10)));
        s.Transition(RecorderEvent.Pause, t0.AddSeconds(10));
        Assert.Equal(TimeSpan.FromSeconds(10), s.Elapsed(t0.AddSeconds(99)));
        s.Transition(RecorderEvent.Resume, t0.AddSeconds(20));
        Assert.Equal(TimeSpan.FromSeconds(15), s.Elapsed(t0.AddSeconds(25)));
        Assert.Equal(TimeSpan.Zero, RecorderState.Idle.Elapsed(t0));
    }

    private static readonly AudioInputs BothDevices = new() { SystemAudioDevice = "Stereo Mix", MicrophoneDevice = "Mic" };
    private static readonly RecordingConfig BothOn = RecordingConfig.Default with { SystemAudio = true, Microphone = true };

    [Fact]
    public void MutedTrackKeepsItsSlotFedBySilence()
    {
        var args = FfmpegArgs.BuildRecording(BothOn, new PxRect(0, 0, 640, 480), @"C:\a.mp4", BothDevices,
            new SegmentOptions { MuteMicrophone = true }).ToList();
        Assert.Contains("audio=Stereo Mix", args);
        Assert.DoesNotContain("audio=Mic", args);
        Assert.Contains("anullsrc=r=48000:cl=stereo", args);
        // Still two audio maps (track count must not change or the -c copy concat breaks).
        Assert.Equal(new[] { "1:a", "2:a" }, args.Where((a, i) => i > 0 && args[i - 1] == "-map" && a.EndsWith(":a")).ToArray());

        var sysMuted = FfmpegArgs.BuildRecording(BothOn, new PxRect(0, 0, 640, 480), @"C:\a.mp4", BothDevices,
            new SegmentOptions { MuteSystemAudio = true }).ToList();
        Assert.Equal(sysMuted.IndexOf("anullsrc=r=48000:cl=stereo"), sysMuted.IndexOf("lavfi") + 2);
        Assert.True(sysMuted.IndexOf("anullsrc=r=48000:cl=stereo") < sysMuted.IndexOf("audio=Mic"));
    }

    [Fact]
    public void OutputSizeLetterboxesIntoTheFirstFrame()
    {
        var args = FfmpegArgs.BuildRecording(RecordingConfig.Default, new PxRect(100, 50, 301, 521), @"C:\a.mp4", AudioInputs.None,
            new SegmentOptions { OutputSize = new PxSize(1280, 800) }).ToList();
        int vf = args.IndexOf("-vf");
        Assert.True(vf > 0);
        Assert.Equal("scale=1280:800:force_original_aspect_ratio=decrease:flags=lanczos,pad=1280:800:(ow-iw)/2:(oh-ih)/2:black,setsar=1", args[vf + 1]);
        Assert.Contains("300x520", args); // the capture itself is still the (even) region
        // Bitrate is sized off the output frame.
        Assert.Equal(RecordingConfig.Default.VideoBitrate(1280, 800).ToString(), args[args.IndexOf("-b:v") + 1]);
    }

    [Fact]
    public void NoOptionsKeepsTheOldArgs()
    {
        var a = FfmpegArgs.BuildRecording(BothOn, new PxRect(0, 0, 640, 480), @"C:\a.mp4", BothDevices);
        var b = FfmpegArgs.BuildRecording(BothOn, new PxRect(0, 0, 640, 480), @"C:\a.mp4", BothDevices, SegmentOptions.None);
        Assert.Equal(a, b);
        Assert.DoesNotContain("-vf", a);
        Assert.Equal(new PxSize(640, 480), FfmpegArgs.EvenSize(new PxRect(0, 0, 641, 481)));
    }
}
