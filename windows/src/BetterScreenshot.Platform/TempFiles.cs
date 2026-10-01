using System.IO;
using System.Text.RegularExpressions;
using BetterScreenshot.Capture;

namespace BetterScreenshot.Platform;

/// <summary>
/// Lifetime of the temp PNGs that back clipboard/drag-export payloads (v3 §4.2, Mac v2.7.0 <c>TempFileService</c>). Each
/// lives in its own <c>%TEMP%\BetterScreenshot-{guid}\</c> directory (<see cref="ImageIo.WriteTempPng"/>), separate from
/// History, so deleting one never removes the capture itself.
///
/// <list type="bullet">
/// <item>A payload handed to the clipboard or the drag card is <see cref="Track"/>ed; its age counts from then.</item>
/// <item>A 5 s sweep deletes tracked directories older than the setting — the timer runs only while something is
/// tracked and the setting is finite, so an idle app does no work.</item>
/// <item>At launch, <see cref="SweepOrphans"/> removes expired <c>BetterScreenshot-{32 hex}</c> directories a previous
/// run left behind (the per-file timers it replaced died with the process). Only that exact name shape is touched —
/// never <c>BetterScreenshot-preview-*</c> or anything else in %TEMP%.</item>
/// </list>
/// ∞ (0) keeps payloads; changing the setting applies to tracked payloads on the next sweep.
/// </summary>
public static class TempFiles
{
    private static readonly object Gate = new();
    private static readonly Dictionary<string, DateTime> Tracked = new(StringComparer.OrdinalIgnoreCase);
    private static readonly Regex PayloadDirName = new(@"^BetterScreenshot-[0-9a-fA-F]{32}$", RegexOptions.Compiled);
    private static Timer? _timer;

    /// <summary>How often the sweep runs while payloads are tracked (the Mac's 5 s).</summary>
    public static readonly TimeSpan SweepInterval = TimeSpan.FromSeconds(5);

    /// <summary>Current retention in seconds (a stop; 0 = ∞) — set through <see cref="Configure"/>.</summary>
    public static int RetentionSeconds { get; private set; } = TempRetentionScale.DefaultSeconds;

    /// <summary>The payload lifetime, or null for ∞.</summary>
    public static TimeSpan? PayloadLifetime => TempRetentionScale.Lifetime(RetentionSeconds);

    /// <summary>Applies the user's setting (snapped to a stop). Called at startup and whenever settings change.</summary>
    public static void Configure(int seconds)
    {
        RetentionSeconds = TempRetentionScale.Normalize(seconds);
        lock (Gate) UpdateTimerLocked();
    }

    /// <summary>The payload directory name shape the sweeps may delete.</summary>
    public static bool IsPayloadDirectory(string name) => PayloadDirName.IsMatch(name);

    /// <summary>True when something tracked/written at <paramref name="since"/> has outlived the setting at <paramref name="now"/>.</summary>
    public static bool IsExpired(DateTime since, DateTime now, int retentionSeconds) =>
        TempRetentionScale.Lifetime(retentionSeconds) is { } life && now - since >= life;

    /// <summary>Starts the clock on the payload directory that contains <paramref name="filePath"/>. Null/empty is a no-op.</summary>
    public static void Track(string? filePath)
    {
        if (string.IsNullOrEmpty(filePath) || Path.GetDirectoryName(filePath) is not { Length: > 0 } dir) return;
        var now = DateTime.UtcNow;
        try { if (Directory.Exists(dir)) Directory.SetLastWriteTimeUtc(dir, now); } catch { /* best-effort */ }
        lock (Gate)
        {
            Tracked[dir] = now;
            UpdateTimerLocked();
        }
    }

    /// <summary>Deletes tracked payloads that have expired at <paramref name="now"/>; returns how many were removed.</summary>
    public static int Sweep(DateTime now)
    {
        List<string> expired;
        lock (Gate)
        {
            expired = Tracked.Where(p => IsExpired(p.Value, now, RetentionSeconds)).Select(p => p.Key).ToList();
            foreach (var dir in expired) Tracked.Remove(dir);
            UpdateTimerLocked();
        }
        foreach (var dir in expired) TryDelete(dir);
        return expired.Count;
    }

    /// <summary>The launch sweep: expired payload directories left in <paramref name="tempRoot"/> (default %TEMP%) by a
    /// previous run. Uses each directory's last-write time (Track stamps it). Returns how many were removed.</summary>
    public static int SweepOrphans(string? tempRoot = null, DateTime? now = null)
    {
        if (PayloadLifetime is null) return 0;
        var root = tempRoot ?? Path.GetTempPath();
        var at = now ?? DateTime.UtcNow;
        int removed = 0;
        try
        {
            foreach (var dir in Directory.EnumerateDirectories(root, "BetterScreenshot-*"))
            {
                if (!IsPayloadDirectory(Path.GetFileName(dir))) continue;
                lock (Gate) if (Tracked.ContainsKey(dir)) continue;
                DateTime written;
                try { written = Directory.GetLastWriteTimeUtc(dir); } catch { continue; }
                if (!IsExpired(written, at, RetentionSeconds)) continue;
                if (TryDelete(dir)) removed++;
            }
        }
        catch { /* temp unreadable: nothing to do */ }
        return removed;
    }

    /// <summary>Tracked payload directories right now (tests, diagnostics).</summary>
    public static int TrackedCount { get { lock (Gate) return Tracked.Count; } }

    /// <summary>Whether the 5 s sweep timer is running (tests: an idle app must have it off).</summary>
    public static bool SweepRunning { get { lock (Gate) return _timer is not null; } }

    private static void UpdateTimerLocked()
    {
        bool want = Tracked.Count > 0 && PayloadLifetime is not null;
        if (want && _timer is null)
            _timer = new Timer(_ => Sweep(DateTime.UtcNow), null, SweepInterval, SweepInterval);
        else if (!want && _timer is not null)
        {
            _timer.Dispose();
            _timer = null;
        }
    }

    private static bool TryDelete(string dir)
    {
        try
        {
            if (Directory.Exists(dir)) Directory.Delete(dir, recursive: true);
            return true;
        }
        catch { return false; } // locked or already gone: best-effort
    }
}
