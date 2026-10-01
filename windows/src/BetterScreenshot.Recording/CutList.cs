using System.Globalization;
using System.Text.RegularExpressions;

namespace BetterScreenshot.Recording;

/// <summary>Single-range trim rules (Mac v3 A.3 <c>TrimRange</c>): ordered, clamped, ≥ 0.5 s, "whole" within 0.05 s.</summary>
public static class TrimRange
{
    public const double MinimumLength = 0.5;
    public const double WholeTolerance = 0.05;

    public static (double Start, double End) Normalize(double a, double b, double duration)
    {
        duration = Math.Max(0, duration);
        double start = Math.Clamp(Math.Min(a, b), 0, duration);
        double end = Math.Clamp(Math.Max(a, b), 0, duration);
        if (duration < MinimumLength) return (0, duration);
        if (end - start < MinimumLength)
        {
            end = start + MinimumLength;
            if (end > duration) { end = duration; start = duration - MinimumLength; }
        }
        return (start, end);
    }

    public static bool IsWhole(double start, double end, double duration) =>
        start <= WholeTolerance && end >= duration - WholeTolerance;

    /// <summary>"m:ss.t", rounded to tenths: 2.14 → "0:02.1", 61.96 → "1:02.0".</summary>
    public static string Timestamp(double seconds)
    {
        long tenths = (long)Math.Round(Math.Max(0, seconds) * 10, MidpointRounding.AwayFromZero);
        long minutes = tenths / 600;
        double rest = (tenths % 600) / 10.0;
        return minutes.ToString(CultureInfo.InvariantCulture) + ":" + rest.ToString("00.0", CultureInfo.InvariantCulture);
    }
}

/// <summary>Names for exported edits (Mac v3 A.3 / Part 6 <c>TrimmedFileName</c>): "&lt;stem&gt; (trimmed).mp4",
/// "&lt;stem&gt; (edited).gif", " 2", " 3"… on collision; an existing (trimmed)/(edited) suffix is reused, not stacked.</summary>
public static class TrimmedFileName
{
    private static readonly Regex Suffix = new(@" \((trimmed|edited)\)( \d+)?$", RegexOptions.Compiled);

    public static string Name(string originalPath, string suffix = "trimmed", string? ext = null)
    {
        string stem = Stem(originalPath);
        ext ??= Path.GetExtension(originalPath).TrimStart('.');
        return $"{stem} ({suffix}).{ext}";
    }

    /// <summary>A free full path next to the original.</summary>
    public static string Unique(string originalPath, Func<string, bool> exists, string suffix = "trimmed", string? ext = null)
    {
        string dir = Path.GetDirectoryName(originalPath) ?? "";
        string stem = Stem(originalPath);
        ext ??= Path.GetExtension(originalPath).TrimStart('.');
        string candidate = Path.Combine(dir, $"{stem} ({suffix}).{ext}");
        for (int n = 2; exists(candidate); n++)
            candidate = Path.Combine(dir, $"{stem} ({suffix}) {n}.{ext}");
        return candidate;
    }

    private static string Stem(string path) => Suffix.Replace(Path.GetFileNameWithoutExtension(path), "");
}

/// <summary>A kept piece of the source: [Start, End) in source seconds, played at Speed, optionally muted.</summary>
public readonly record struct CutSegment(double Start, double End, double Speed = 1, bool Muted = false)
{
    public double Length => End - Start;
    public double OutputLength => Length / Speed;
}

/// <summary>One drawn timeline block: a kept segment (display length = output length) or a removed stretch (display = source length).</summary>
public readonly record struct TimelineItem(bool Kept, int Index, double SourceStart, double SourceEnd, double DisplayStart, double DisplayLength)
{
    public double DisplayEnd => DisplayStart + DisplayLength;
}

/// <summary>
/// The video editor's model (Mac v3 Part 6 <c>CutList</c>): the ordered, non-overlapping kept segments of a
/// recording, never empty. Edits return false and change nothing when they can't apply. Copy with <see cref="Clone"/>.
/// </summary>
public sealed class CutList : IEquatable<CutList>
{
    public static readonly double[] Speeds = { 1, 1.5, 2, 4 };
    public const double MinimumSegment = 0.1;
    private const double Eps = 1e-6;

    private readonly List<CutSegment> _segments;

    public double Duration { get; }
    public IReadOnlyList<CutSegment> Segments => _segments;

    public CutList(double duration)
    {
        Duration = Math.Max(0, duration);
        _segments = new List<CutSegment> { new(0, Duration) };
    }

    /// <summary>The single-segment case of a plain trim.</summary>
    public CutList(double start, double end, double duration)
    {
        Duration = Math.Max(0, duration);
        var (s, e) = TrimRange.Normalize(start, end, Duration);
        _segments = new List<CutSegment> { new(s, e) };
    }

    private CutList(double duration, IEnumerable<CutSegment> segments)
    {
        Duration = duration;
        _segments = segments.ToList();
    }

    public CutList Clone() => new(Duration, _segments);

    public double KeptDuration => _segments.Sum(s => s.OutputLength);

    public double OutputStart(int index) => _segments.Take(index).Sum(s => s.OutputLength);

    /// <summary>A boundary belongs to the later segment; the very end to the last.</summary>
    public int SegmentIndexAtOutput(double t)
    {
        double acc = 0;
        for (int i = 0; i < _segments.Count; i++)
        {
            acc += _segments[i].OutputLength;
            if (t < acc - Eps) return i;
        }
        return _segments.Count - 1;
    }

    public double SourceTimeForOutput(double t)
    {
        int i = SegmentIndexAtOutput(t);
        var s = _segments[i];
        return Math.Clamp(s.Start + (t - OutputStart(i)) * s.Speed, s.Start, s.End);
    }

    /// <summary>Shared boundary → the later segment; the last segment's end is inclusive; inside a cut → null.</summary>
    public int? SegmentIndexContainingSource(double t)
    {
        for (int i = 0; i < _segments.Count; i++)
        {
            var s = _segments[i];
            bool last = i == _segments.Count - 1;
            if (t >= s.Start - Eps && (t < s.End - Eps || (last && t <= s.End + Eps))) return i;
        }
        return null;
    }

    public double? OutputTimeForSource(double t) =>
        SegmentIndexContainingSource(t) is { } i ? OutputStart(i) + (t - _segments[i].Start) / _segments[i].Speed : null;

    /// <summary>A plain start/end trim at 1× with one mute state → (range, muted); anything else must be re-encoded.</summary>
    public (double Start, double End, bool Muted)? Passthrough
    {
        get
        {
            for (int i = 0; i < _segments.Count; i++)
            {
                if (Math.Abs(_segments[i].Speed - 1) > Eps || _segments[i].Muted != _segments[0].Muted) return null;
                if (i > 0 && Math.Abs(_segments[i - 1].End - _segments[i].Start) > Eps) return null;
            }
            return (_segments[0].Start, _segments[^1].End, _segments[0].Muted);
        }
    }

    /// <summary>True when this is the untouched whole recording.</summary>
    public bool IsWhole => Passthrough is { Muted: false } p && p.Start <= Eps && p.End >= Duration - Eps;

    // ---------------------------------------------------------------- edits

    public bool Split(double t)
    {
        for (int i = 0; i < _segments.Count; i++)
        {
            var s = _segments[i];
            if (t >= s.Start + MinimumSegment - Eps && t <= s.End - MinimumSegment + Eps)
            {
                _segments[i] = s with { End = t };
                _segments.Insert(i + 1, s with { Start = t });
                return true;
            }
        }
        return false;
    }

    public bool Remove(int index)
    {
        if (_segments.Count <= 1 || index < 0 || index >= _segments.Count) return false;
        _segments.RemoveAt(index);
        return true;
    }

    public bool SetStart(double t, int index)
    {
        if (index < 0 || index >= _segments.Count) return false;
        var s = _segments[index];
        double lo = index > 0 ? _segments[index - 1].End : 0;
        double v = Math.Clamp(t, lo, s.End - MinimumSegment);
        if (Math.Abs(v - s.Start) <= Eps) return false;
        _segments[index] = s with { Start = v };
        return true;
    }

    public bool SetEnd(double t, int index)
    {
        if (index < 0 || index >= _segments.Count) return false;
        var s = _segments[index];
        double hi = index < _segments.Count - 1 ? _segments[index + 1].Start : Duration;
        double v = Math.Clamp(t, s.Start + MinimumSegment, hi);
        if (Math.Abs(v - s.End) <= Eps) return false;
        _segments[index] = s with { End = v };
        return true;
    }

    /// <summary>1× → faster also mutes; back to 1× unmutes; between faster speeds the mute is kept.</summary>
    public bool SetSpeed(double speed, int index)
    {
        if (index < 0 || index >= _segments.Count || !Speeds.Any(x => Math.Abs(x - speed) <= Eps)) return false;
        var s = _segments[index];
        if (Math.Abs(s.Speed - speed) <= Eps) return false;
        bool muted = Math.Abs(speed - 1) <= Eps ? false : Math.Abs(s.Speed - 1) <= Eps ? true : s.Muted;
        _segments[index] = s with { Speed = speed, Muted = muted };
        return true;
    }

    public bool SetMuted(bool muted, int index)
    {
        if (index < 0 || index >= _segments.Count || _segments[index].Muted == muted) return false;
        _segments[index] = _segments[index] with { Muted = muted };
        return true;
    }

    /// <summary>In point: drop everything before <paramref name="t"/> (the first kept piece stays ≥ 0.1 s).</summary>
    public bool TrimBefore(double t)
    {
        var before = Clone();
        var keep = _segments.Where(s => s.End > t + Eps).ToList();
        if (keep.Count == 0) keep.Add(_segments[^1]);
        var first = keep[0];
        if (first.Start < t) keep[0] = first with { Start = Math.Min(t, first.End - MinimumSegment) };
        _segments.Clear();
        _segments.AddRange(keep);
        return !Equals(before);
    }

    /// <summary>Out point: drop everything after <paramref name="t"/> (the last kept piece stays ≥ 0.1 s).</summary>
    public bool TrimAfter(double t)
    {
        var before = Clone();
        var keep = _segments.Where(s => s.Start < t - Eps).ToList();
        if (keep.Count == 0) keep.Add(_segments[0]);
        var last = keep[^1];
        if (last.End > t) keep[^1] = last with { End = Math.Max(t, last.Start + MinimumSegment) };
        _segments.Clear();
        _segments.AddRange(keep);
        return !Equals(before);
    }

    // ---------------------------------------------------------------- timeline

    /// <summary>Kept segments at their output length, cuts (incl. before the first / after the last) at their source length.</summary>
    public IReadOnlyList<TimelineItem> Timeline
    {
        get
        {
            var items = new List<TimelineItem>();
            double pos = 0, cursor = 0;
            for (int i = 0; i < _segments.Count; i++)
            {
                var s = _segments[i];
                if (s.Start - cursor > Eps) { items.Add(new TimelineItem(false, -1, cursor, s.Start, pos, s.Start - cursor)); pos += s.Start - cursor; }
                items.Add(new TimelineItem(true, i, s.Start, s.End, pos, s.OutputLength));
                pos += s.OutputLength;
                cursor = s.End;
            }
            if (Duration - cursor > Eps) items.Add(new TimelineItem(false, -1, cursor, Duration, pos, Duration - cursor));
            return items;
        }
    }

    public double TimelineLength => Timeline.Sum(i => i.DisplayLength);

    public double TimelinePositionForOutput(double t)
    {
        int i = SegmentIndexAtOutput(t);
        var item = Timeline.First(x => x.Kept && x.Index == i);
        return item.DisplayStart + Math.Clamp(t - OutputStart(i), 0, item.DisplayLength);
    }

    /// <summary>Inside a cut → the next kept segment's output start (or the end if none).</summary>
    public double OutputTimeForTimelinePosition(double x)
    {
        var items = Timeline;
        for (int k = 0; k < items.Count; k++)
        {
            var it = items[k];
            if (x >= it.DisplayEnd && k < items.Count - 1) continue;
            if (it.Kept) return OutputStart(it.Index) + Math.Clamp(x - it.DisplayStart, 0, it.DisplayLength);
            var next = items.Skip(k + 1).FirstOrDefault(n => n.Kept);
            return next.Kept ? OutputStart(next.Index) : KeptDuration;
        }
        return KeptDuration;
    }

    /// <summary>Cuts map 1:1, kept segments × their speed (what the filmstrip shows).</summary>
    public double SourceTimeForTimelinePosition(double x)
    {
        foreach (var it in Timeline)
        {
            if (x >= it.DisplayEnd) continue;
            double into = Math.Max(0, x - it.DisplayStart);
            return it.Kept ? it.SourceStart + into * _segments[it.Index].Speed : it.SourceStart + into;
        }
        return Duration;
    }

    public bool Equals(CutList? other) =>
        other is not null && Math.Abs(Duration - other.Duration) <= Eps && _segments.SequenceEqual(other._segments);

    public override bool Equals(object? obj) => Equals(obj as CutList);
    public override int GetHashCode() => HashCode.Combine(Duration, _segments.Count);
}

/// <summary>Undo / redo of whole cut lists (Mac <c>CutHistory</c>). An edge drag edits a working copy and commits once.</summary>
public sealed class CutHistory
{
    private readonly Stack<CutList> _undo = new(), _redo = new();

    public CutHistory(CutList initial) => Current = initial;

    public CutList Current { get; private set; }
    public bool CanUndo => _undo.Count > 0;
    public bool CanRedo => _redo.Count > 0;

    public bool Commit(CutList list)
    {
        if (list.Equals(Current)) return false;
        _undo.Push(Current);
        _redo.Clear();
        Current = list;
        return true;
    }

    public bool Apply(Func<CutList, bool> edit)
    {
        var copy = Current.Clone();
        return edit(copy) && Commit(copy);
    }

    public bool Undo()
    {
        if (_undo.Count == 0) return false;
        _redo.Push(Current);
        Current = _undo.Pop();
        return true;
    }

    public bool Redo()
    {
        if (_redo.Count == 0) return false;
        _undo.Push(Current);
        Current = _redo.Pop();
        return true;
    }

    public void Reset(CutList list)
    {
        _undo.Clear();
        _redo.Clear();
        Current = list;
    }
}

/// <summary>The timeline's time ruler (Mac v3 Part 6 <c>TimeRuler</c>): ticks at round output times over kept segments only.</summary>
public static class TimeRuler
{
    public readonly record struct Span(double X, double Width, double OutputStart);
    public readonly record struct Tick(double Time, double X, bool Major, string? Label);

    private static readonly double[] Steps = { 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600 };
    private static readonly int[] MinorDivisions = { 2, 2, 5, 4, 4, 5, 5, 3, 6, 4, 4, 5, 5, 3, 6, 4 };

    /// <summary>"0:05" / "1:30" for whole-second steps; "0:04.5" (TrimRange.Timestamp) for finer ones.</summary>
    public static string Format(double t, double step)
    {
        if (step >= 1 - 1e-9)
        {
            long s = (long)Math.Round(t, MidpointRounding.AwayFromZero);
            return $"{s / 60}:{s % 60:00}";
        }
        return TrimRange.Timestamp(t);
    }

    /// <summary>Index into the step table: the smallest step whose widest label + 3 + 12 fits between two ticks.</summary>
    public static int StepIndex(double pointsPerSecond, double totalSeconds, Func<string, double> labelWidth)
    {
        for (int i = 0; i < Steps.Length; i++)
        {
            double widest = labelWidth(Format(totalSeconds, Steps[i]));
            if (Steps[i] * pointsPerSecond >= widest + 3 + 12) return i;
        }
        return Steps.Length - 1;
    }

    public static double Step(double pointsPerSecond, double totalSeconds, Func<string, double> labelWidth) =>
        Steps[StepIndex(pointsPerSecond, totalSeconds, labelWidth)];

    public static IReadOnlyList<Tick> Ticks(IReadOnlyList<Span> spans, double pointsPerSecond, double maxX, Func<string, double> labelWidth)
    {
        var ticks = new List<Tick>();
        if (spans.Count == 0 || pointsPerSecond <= 0) return ticks;
        double total = spans.Max(s => s.OutputStart + s.Width / pointsPerSecond);
        int si = StepIndex(pointsPerSecond, total, labelWidth);
        double step = Steps[si];
        int div = MinorDivisions[si];
        double minor = step / div;
        bool showMinor = minor * pointsPerSecond >= 4;
        double unit = showMinor ? minor : step;
        int per = showMinor ? div : 1;

        double lastLabelEnd = double.NegativeInfinity;
        foreach (var span in spans)
        {
            double t0 = span.OutputStart, t1 = span.OutputStart + span.Width / pointsPerSecond;
            long k = (long)Math.Ceiling(t0 / unit - 1e-6);
            for (; k * unit < t1 - 1e-6; k++)
            {
                double t = k * unit;
                double x = span.X + (t - t0) * pointsPerSecond;
                bool major = k % per == 0;
                string? label = null;
                if (major)
                {
                    string text = Format(t, step);
                    double lx = x + 3, w = labelWidth(text);
                    if (lx >= lastLabelEnd + 12 && lx + w <= maxX - 2) { label = text; lastLabelEnd = lx + w; }
                }
                ticks.Add(new Tick(t, x, major, label));
            }
        }
        return ticks;
    }
}

/// <summary>How many filmstrip thumbnails to extract and when (Mac v3 Part 6 <c>FilmstripFrames</c>).</summary>
public static class FilmstripFrames
{
    public static int Count(double duration, double timelineWidth, double tileWidth) =>
        Math.Min(Math.Min(Math.Max((int)Math.Ceiling(timelineWidth / Math.Max(1, tileWidth)), 12), 400),
            Math.Max(12, (int)Math.Floor(duration * 30)));

    /// <summary>(index, time) pairs at (k + 0.5)·duration/count, coarse to fine: every 8th, then 4th, 2nd, the rest.</summary>
    public static IReadOnlyList<(int Index, double Time)> Times(double duration, int count)
    {
        var order = new List<int>();
        var seen = new HashSet<int>();
        foreach (int stride in new[] { 8, 4, 2, 1 })
            for (int k = 0; k < count; k += stride)
                if (seen.Add(k)) order.Add(k);
        return order.Select(k => (k, (k + 0.5) * duration / count)).ToList();
    }
}

/// <summary>What <c>ffmpeg -i file</c> says about a recording: duration, frame size, frame rate, audio track count.</summary>
public sealed record MediaInfo(double Duration, int Width, int Height, double Fps, int AudioTracks, bool HasVideo)
{
    private static readonly Regex DurationRx = new(@"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)", RegexOptions.Compiled);
    private static readonly Regex VideoRx = new(@"Stream #\d+:\d+.*?: Video: .*?, (\d{2,5})x(\d{2,5})", RegexOptions.Compiled);
    private static readonly Regex FpsRx = new(@"(\d+(?:\.\d+)?) fps", RegexOptions.Compiled);
    private static readonly Regex AudioRx = new(@"Stream #\d+:\d+.*?: Audio: ", RegexOptions.Compiled);

    public static MediaInfo? Parse(string ffmpegStderr)
    {
        var d = DurationRx.Match(ffmpegStderr);
        if (!d.Success) return null;
        double duration = int.Parse(d.Groups[1].Value) * 3600 + int.Parse(d.Groups[2].Value) * 60
                          + double.Parse(d.Groups[3].Value, CultureInfo.InvariantCulture);
        var v = VideoRx.Match(ffmpegStderr);
        double fps = 30;
        if (v.Success)
        {
            var line = ffmpegStderr[v.Index..];
            int nl = line.IndexOf('\n');
            var f = FpsRx.Match(nl > 0 ? line[..nl] : line);
            if (f.Success) fps = double.Parse(f.Groups[1].Value, CultureInfo.InvariantCulture);
        }
        return new MediaInfo(duration,
            v.Success ? int.Parse(v.Groups[1].Value) : 0, v.Success ? int.Parse(v.Groups[2].Value) : 0,
            fps, AudioRx.Matches(ffmpegStderr).Count, v.Success);
    }
}
