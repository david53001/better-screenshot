namespace BetterScreenshot.Capture;

/// <summary>
/// Maps between the Quick Access "Auto-dismiss after" slider position and the persisted
/// <see cref="CaptureSettings.OverlayAutoDismissSeconds"/> value.
///
/// The slider runs from <see cref="MinSeconds"/> up to a final <see cref="NeverPosition"/> stop. Positions
/// 2..30 mean "that many seconds"; the last stop means "Never" and persists as <see cref="NeverSeconds"/> (0) —
/// which the overlay already treats as "stay on screen until the user closes it" (see
/// <c>QuickAccessWindow.StartAutoDismiss</c>). Keeping this mapping in one pure, testable place means the
/// Settings slider and the persisted int can never drift apart.
/// </summary>
public static class OverlayDismissScale
{
    /// <summary>Shortest auto-dismiss the bar allows, in seconds.</summary>
    public const int MinSeconds = 2;

    /// <summary>Longest finite auto-dismiss the bar allows, in seconds (the stop just before "Never").</summary>
    public const int MaxSeconds = 30;

    /// <summary>Persisted value that means "never auto-dismiss".</summary>
    public const int NeverSeconds = 0;

    /// <summary>Slider position representing the "Never" stop — one past the largest finite second.</summary>
    public const int NeverPosition = MaxSeconds + 1;

    /// <summary>Slider position (2..31) for a persisted seconds value. 0 or negative maps to the "Never" stop;
    /// any finite value is clamped into the bar's 2..30 range.</summary>
    public static int SecondsToPosition(int seconds) =>
        seconds <= 0 ? NeverPosition : Math.Clamp(seconds, MinSeconds, MaxSeconds);

    /// <summary>Persisted seconds for a slider position. At/after the "Never" stop maps to 0; otherwise the
    /// position is rounded to the nearest whole second and clamped to 2..30.</summary>
    public static int PositionToSeconds(double position) =>
        position >= NeverPosition
            ? NeverSeconds
            : Math.Clamp((int)Math.Round(position, MidpointRounding.AwayFromZero), MinSeconds, MaxSeconds);

    /// <summary>Human-readable label for a persisted seconds value: "∞" for never, otherwise e.g. "6s".</summary>
    public static string Label(int seconds) => seconds <= 0 ? "∞" : $"{seconds}s"; // the Mac's "∞" (v2.6.1)
}
