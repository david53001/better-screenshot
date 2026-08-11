namespace BetterScreenshot.Capture;

/// <summary>
/// Maps between the Settings "Keep temp copies for" slider position and the persisted
/// <see cref="CaptureSettings.TempRetentionMinutes"/> value.
///
/// The bar runs from <see cref="MinMinutes"/> to <see cref="MaxMinutes"/> whole minutes — the lifetime of the
/// throwaway PNGs written to <c>%TEMP%\BetterScreenshot-{guid}\</c> that back clipboard file-drops and
/// drag-to-export (see <c>BetterScreenshot.Platform.TempFiles</c>). There is deliberately no "forever" stop:
/// these are disposable copies, the capture itself lives in History. Keeping the mapping in one pure, testable
/// place means the slider and the persisted int can never drift apart.
/// </summary>
public static class TempRetentionScale
{
    /// <summary>Shortest retention the bar allows, in minutes (also the default — today's fixed behavior).</summary>
    public const int MinMinutes = 5;

    /// <summary>Longest retention the bar allows, in minutes.</summary>
    public const int MaxMinutes = 30;

    /// <summary>Retention used until the user moves the slider.</summary>
    public const int DefaultMinutes = MinMinutes;

    /// <summary>Brings any value — a hand-edited settings.json, an out-of-range legacy value — into 5..30.</summary>
    public static int Clamp(int minutes) => Math.Clamp(minutes, MinMinutes, MaxMinutes);

    /// <summary>Persisted minutes for a slider position: rounded to the nearest whole minute, clamped to 5..30.</summary>
    public static int PositionToMinutes(double position) =>
        Clamp((int)Math.Round(position, MidpointRounding.AwayFromZero));

    /// <summary>Human-readable label for a retention value, e.g. "5 min".</summary>
    public static string Label(int minutes) => $"{Clamp(minutes)} min";
}
