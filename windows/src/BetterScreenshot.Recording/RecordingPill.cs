using System.Globalization;
using BetterScreenshot.Core;

namespace BetterScreenshot.Recording;

/// <summary>
/// Geometry for the live recording pill (Mac v3 Part 5 <c>RecordingPillLayout</c>), in screen DIPs with a
/// top-left origin (the Mac original is bottom-left; the cases in the parity doc are translated in the tests).
/// </summary>
public static class RecordingPillLayout
{
    public const double CapsuleHeight = 40;
    public const double HintHeight = 24;
    public const double HintGap = 6;
    public const double ScreenMargin = 8;
    public const double BottomInset = 20;

    /// <summary>Restart/Discard icon-button width: wide enough that the two plus their spacing hold either confirm capsule.</summary>
    public static double ConfirmPairButtonWidth(IEnumerable<double> confirmWidths, double spacing, double minimum)
    {
        var widths = confirmWidths.ToList();
        if (widths.Count == 0) return minimum;
        return Math.Max(minimum, Math.Ceiling((widths.Max() - spacing) / 2));
    }

    public static double ConfirmSlotWidth(double buttonWidth, double spacing) => 2 * buttonWidth + spacing;

    /// <summary>The hint bubble: above the pill when it fits inside <paramref name="visible"/>, else below; centred on
    /// <paramref name="anchorX"/>, narrowed to the screen and kept <paramref name="margin"/> inside it.</summary>
    public static PxRect HintFrame(PxSize size, double anchorX, PxRect pill, PxRect visible,
        double gap = HintGap, double margin = ScreenMargin)
    {
        double y = pill.Y - gap - size.Height >= visible.Y ? pill.Y - gap - size.Height : pill.Bottom + gap;
        double width = Math.Min(size.Width, visible.Width - 2 * margin);
        double x = Math.Round(Math.Clamp(anchorX - width / 2, visible.X + margin, Math.Max(visible.X + margin, visible.Right - margin - width)),
            MidpointRounding.AwayFromZero);
        return new PxRect(x, y, width, size.Height);
    }

    /// <summary>First show with no saved spot: bottom-centre of the work area, bottom edge 20 above its bottom.</summary>
    public static PxRect DefaultFrame(PxSize size, PxRect work) =>
        new(work.X + Math.Round((work.Width - size.Width) / 2), work.Bottom - BottomInset - size.Height, size.Width, size.Height);

    /// <summary>A capsule whose bottom-right corner sits on <paramref name="bottomRight"/> (width changes keep that corner).</summary>
    public static PxRect FromBottomRight(PxPoint bottomRight, PxSize size) =>
        new(bottomRight.X - size.Width, bottomRight.Y - size.Height, size.Width, size.Height);

    /// <summary>Moves <paramref name="frame"/> (never resizes it) so it sits <paramref name="margin"/> inside <paramref name="work"/>.</summary>
    public static PxRect ClampInside(PxRect frame, PxRect work, double margin = ScreenMargin)
    {
        double x = Math.Clamp(frame.X, work.X + margin, Math.Max(work.X + margin, work.Right - margin - frame.Width));
        double y = Math.Clamp(frame.Y, work.Y + margin, Math.Max(work.Y + margin, work.Bottom - margin - frame.Height));
        return frame with { X = x, Y = y };
    }

    /// <summary><c>recordingPillAnchor</c> text: the capsule's bottom-right corner as "{x, y}" (DIPs, top-left origin).</summary>
    public static string FormatAnchor(PxPoint p) =>
        string.Create(CultureInfo.InvariantCulture, $"{{{Math.Round(p.X)}, {Math.Round(p.Y)}}}");

    public static PxPoint? ParseAnchor(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var parts = text.Trim().TrimStart('{').TrimEnd('}').Split(',');
        if (parts.Length != 2) return null;
        return double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var x)
               && double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var y)
               && double.IsFinite(x) && double.IsFinite(y)
            ? new PxPoint(x, y)
            : null;
    }
}

public enum PillPhase { Countdown, Recording, Paused }
public enum PillCamera { Showing, Hidden, NoCamera, Denied }
public enum PillTarget { FullScreen, Window, Area }
public enum PillConfirm { None, Restart, Discard }
public enum PillItemId { Mic, SystemAudio, Camera, Switch, Restart, Discard, PauseResume, Stop, Chevron }

/// <summary>How a pill control draws: normal white, 60 % white (camera off), red muted chip, 30 % disabled,
/// red glyph (Stop), 55 % white (chevron), or the red "Restart?"/"Discard?" confirm capsule.</summary>
public enum PillLook { Normal, Dim, RedChip, Disabled, RedGlyph, Chevron, ConfirmCapsule }

/// <summary>One control's state. <see cref="Label"/> is null for icon-only buttons; the confirm capsule has text and no icon.</summary>
public sealed record PillItem(PillItemId Id, bool Visible, bool Enabled, string? Icon, string? Label, PillLook Look, string Hint);

/// <summary>Everything that decides what the pill shows (per session — nothing here is persisted but Collapsed).</summary>
public sealed record PillState
{
    public PillPhase Phase { get; init; } = PillPhase.Countdown;
    public TimeSpan Elapsed { get; init; }
    public bool MicTrack { get; init; }
    public bool MicMuted { get; init; }
    public bool SystemTrack { get; init; }
    public bool SystemMuted { get; init; }
    public PillCamera Camera { get; init; } = PillCamera.Hidden;
    public PillTarget Target { get; init; } = PillTarget.FullScreen;
    public PillConfirm Confirm { get; init; } = PillConfirm.None;
    public bool Collapsed { get; init; }
}

/// <summary>
/// The pill's item table (Mac v3 Part 5 "States of each item"), pure so every icon/look/hint is unit-tested.
/// Hints are verbatim; Windows wording only where the doc gives one (camera privacy path).
/// </summary>
public static class RecordingPillModel
{
    public const string AvailableOnceRecording = "Available once recording starts";

    public static bool DotIsRed(PillState s) => s.Phase == PillPhase.Recording;
    public static bool TimerIsDim(PillState s) => s.Phase != PillPhase.Recording;
    public static bool ShowsPausedLabel(PillState s) => s.Phase == PillPhase.Paused;

    /// <summary>"m:ss", minutes unbounded; the countdown always reads "0:00".</summary>
    public static string TimerText(PillState s)
    {
        if (s.Phase == PillPhase.Countdown) return "0:00";
        int total = Math.Max(0, (int)s.Elapsed.TotalSeconds);
        return $"{total / 60}:{total % 60:D2}";
    }

    /// <summary>The separator + Switch group shows only for window / area recordings, expanded.</summary>
    public static bool ShowsSwitchGroup(PillState s) => !s.Collapsed && s.Target != PillTarget.FullScreen;

    public static IReadOnlyList<PillItem> Items(PillState s)
    {
        bool expanded = !s.Collapsed;
        bool live = s.Phase != PillPhase.Countdown;
        return new[]
        {
            Mic(s, expanded), SystemAudio(s, expanded), Camera(s, expanded), Switch(s, expanded, live),
            Restart(s, expanded, live), Discard(s, expanded, live), PauseResume(s, live), Stop(s), Chevron(s),
        };
    }

    public static PillItem Item(PillState s, PillItemId id) => Items(s).First(i => i.Id == id);

    private static PillItem Mic(PillState s, bool visible) =>
        !s.MicTrack ? new(PillItemId.Mic, visible, false, "mic-slash", "Mic", PillLook.Disabled,
                          "Mic wasn't on when this recording started — there's no mic track to mute")
        : s.MicMuted ? new(PillItemId.Mic, visible, true, "mic-slash", "Mic", PillLook.RedChip, "Unmute microphone")
        : new(PillItemId.Mic, visible, true, "mic", "Mic", PillLook.Normal,
              "Mute microphone — the video keeps a silent gap, stays in sync");

    private static PillItem SystemAudio(PillState s, bool visible) =>
        !s.SystemTrack ? new(PillItemId.SystemAudio, visible, false, "speaker-slash", "System audio", PillLook.Disabled,
                             "System audio wasn't on when this recording started — there's no system audio track to mute")
        : s.SystemMuted ? new(PillItemId.SystemAudio, visible, true, "speaker-slash", "System audio", PillLook.RedChip, "Unmute system audio")
        : new(PillItemId.SystemAudio, visible, true, "speaker", "System audio", PillLook.Normal,
              "Mute system audio — the video keeps a silent gap, stays in sync");

    private static PillItem Camera(PillState s, bool visible) => s.Camera switch
    {
        PillCamera.Showing => new(PillItemId.Camera, visible, true, "video-fill", "Camera", PillLook.Normal, "Hide camera bubble"),
        PillCamera.NoCamera => new(PillItemId.Camera, visible, false, "video-slash", "Camera", PillLook.Disabled, "No camera found"),
        PillCamera.Denied => new(PillItemId.Camera, visible, false, "video-slash", "Camera", PillLook.Disabled,
            "Camera access is off — allow BetterScreenshot in Settings › Privacy & security › Camera"),
        _ => new(PillItemId.Camera, visible, true, "video", "Camera", PillLook.Dim, "Show camera bubble"),
    };

    private static PillItem Switch(PillState s, bool expanded, bool live)
    {
        bool window = s.Target == PillTarget.Window;
        string icon = window ? "window" : "rect-dashed";
        string label = window ? "Switch Window…" : "Switch Area…";
        string hint = !live ? AvailableOnceRecording
            : window ? "Record a different window — it's scaled to fit this video's frame"
            : "Record a different area — it's scaled to fit this video's frame";
        return new(PillItemId.Switch, ShowsSwitchGroup(s) && expanded, live, icon, label, live ? PillLook.Normal : PillLook.Disabled, hint);
    }

    private static PillItem Restart(PillState s, bool expanded, bool live)
    {
        if (s.Confirm == PillConfirm.Restart && live)
            return new(PillItemId.Restart, expanded, true, null, "Restart?", PillLook.ConfirmCapsule,
                "Click again to restart — what's recorded so far is deleted");
        return new(PillItemId.Restart, expanded && !(s.Confirm == PillConfirm.Discard && live), live, "restart", null,
            live ? PillLook.Normal : PillLook.Disabled,
            live ? "Restart — delete what's recorded so far and start over" : AvailableOnceRecording);
    }

    private static PillItem Discard(PillState s, bool expanded, bool live)
    {
        if (s.Confirm == PillConfirm.Discard && live)
            return new(PillItemId.Discard, expanded, true, null, "Discard?", PillLook.ConfirmCapsule,
                "Click again to delete this recording");
        return new(PillItemId.Discard, expanded && !(s.Confirm == PillConfirm.Restart && live), live, "trash", null,
            live ? PillLook.Normal : PillLook.Disabled,
            live ? "Discard — stop and delete this recording" : AvailableOnceRecording);
    }

    private static PillItem PauseResume(PillState s, bool live) => s.Phase switch
    {
        PillPhase.Paused => new(PillItemId.PauseResume, true, true, "play", null, PillLook.Normal, "Resume recording"),
        PillPhase.Recording => new(PillItemId.PauseResume, true, true, "pause", null, PillLook.Normal, "Pause recording"),
        _ => new(PillItemId.PauseResume, true, false, "pause", null, PillLook.Disabled, AvailableOnceRecording),
    };

    private static PillItem Stop(PillState s) =>
        new(PillItemId.Stop, true, true, "stop", null, PillLook.RedGlyph,
            s.Phase == PillPhase.Countdown ? "Cancel recording" : "Stop recording");

    private static PillItem Chevron(PillState s) => s.Collapsed
        ? new(PillItemId.Chevron, true, true, "chevron-left", null, PillLook.Chevron, "Show all controls")
        : new(PillItemId.Chevron, true, true, "chevron-right", null, PillLook.Chevron, "Collapse to timer, Pause and Stop");
}
