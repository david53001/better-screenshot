namespace BetterScreenshot.Capture;

/// <summary>
/// Settings → "Keep temp copies for" (v3 §4.2, Mac v2.7.0 <c>TempFileRetentionScale</c>): how long the throwaway PNGs
/// in <c>%TEMP%\BetterScreenshot-{guid}\</c> that back clipboard file-drops and drag-to-export survive. The Mac's stops,
/// <b>10 s · 30 s · 5 min · 10 min · 30 min · 1 hour · ∞</b>, persisted as <see cref="CaptureSettings.TempRetentionSeconds"/>
/// (default 300 = the old fixed behaviour; 0 = ∞, never deleted). The slider position is the stop's index. Replaces
/// the Windows-only 5–30 minute bar (eb16ae0); a stored minutes value maps to the nearest stop. The capture itself is
/// never affected — History keeps its own copy.
/// </summary>
public static class TempRetentionScale
{
    /// <summary>Persisted value that means "keep forever" (the ∞ stop).</summary>
    public const int NeverSeconds = 0;

    /// <summary>Retention used until the user moves the slider (the old fixed 5 minutes).</summary>
    public const int DefaultSeconds = 300;

    /// <summary>The stops in slider order; the last (0) is ∞.</summary>
    public static readonly IReadOnlyList<int> StopsSeconds = new[] { 10, 30, 300, 600, 1800, 3600, NeverSeconds };

    /// <summary>The "never expire" stop's label (both scales show it as ∞, Mac v2.6.1).</summary>
    public const string NeverLabel = "∞";

    public static int MaxPosition => StopsSeconds.Count - 1;

    /// <summary>Any stored seconds value onto a stop: 0 stays ∞; a negative value reads as the default; anything
    /// else snaps to the nearest finite stop (a hand-edited 45 → 30 s, 2 h → 1 hour).</summary>
    public static int Normalize(int seconds)
    {
        if (seconds == NeverSeconds) return NeverSeconds;
        if (seconds < 0) return DefaultSeconds;
        return Nearest(seconds);
    }

    /// <summary>The Windows-only setting this replaced stored whole minutes (5..30); map it to the nearest stop.</summary>
    public static int FromLegacyMinutes(int minutes) => minutes <= 0 ? DefaultSeconds : Nearest((long)minutes * 60);

    public static int PositionToSeconds(double position) =>
        StopsSeconds[Math.Clamp((int)Math.Round(position, MidpointRounding.AwayFromZero), 0, MaxPosition)];

    public static int SecondsToPosition(int seconds)
    {
        int normalized = Normalize(seconds);
        for (int i = 0; i < StopsSeconds.Count; i++)
            if (StopsSeconds[i] == normalized) return i;
        return 2;
    }

    /// <summary>"10 s", "5 min", "1 hour", "∞".</summary>
    public static string Label(int seconds) => Normalize(seconds) switch
    {
        NeverSeconds => NeverLabel,
        < 60 and var s => $"{s} s",
        3600 => "1 hour",
        var s => $"{s / 60} min",
    };

    /// <summary>The lifetime as a span, or null for ∞.</summary>
    public static TimeSpan? Lifetime(int seconds) =>
        Normalize(seconds) is var s && s == NeverSeconds ? null : TimeSpan.FromSeconds(s);

    private static int Nearest(long seconds)
    {
        int best = StopsSeconds[0];
        foreach (var stop in StopsSeconds)
            if (stop != NeverSeconds && Math.Abs(stop - seconds) < Math.Abs(best - seconds)) best = stop;
        return best;
    }
}
