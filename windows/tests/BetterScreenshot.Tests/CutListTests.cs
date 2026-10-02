using BetterScreenshot.Recording;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>Mac v3 A.3 + Part 6 pure logic: TrimRange, TrimmedFileName, CutList / CutHistory, TimeRuler,
/// FilmstripFrames, MediaInfo and the export argument builders.</summary>
public class CutListTests
{
    // ---------------------------------------------------------------- TrimRange

    [Fact]
    public void TrimRangeRules()
    {
        Assert.Equal((2.0, 8.0), TrimRange.Normalize(8, 2, 10));
        Assert.Equal((0.0, 10.0), TrimRange.Normalize(-3, 42, 10));
        Assert.Equal((4.0, 4.5), TrimRange.Normalize(4, 4.1, 10));
        Assert.Equal((9.5, 10.0), TrimRange.Normalize(9.9, 10, 10));
        Assert.Equal((0.0, 0.3), TrimRange.Normalize(0.1, 0.2, 0.3));
        Assert.True(TrimRange.IsWhole(0.04, 9.96, 10));
        Assert.False(TrimRange.IsWhole(0.2, 10, 10));
        Assert.Equal("0:02.1", TrimRange.Timestamp(2.14));
        Assert.Equal("1:02.0", TrimRange.Timestamp(61.96));
    }

    // ---------------------------------------------------------------- TrimmedFileName

    [Fact]
    public void TrimmedNames()
    {
        Assert.Equal("Recording 2026-09-24 at 10.00.00 (trimmed).mp4", TrimmedFileName.Name(@"C:\v\Recording 2026-09-24 at 10.00.00.mp4"));
        Assert.Equal("Recording 2026-09-24 at 10.00.00 (edited).gif", TrimmedFileName.Name(@"C:\v\Recording 2026-09-24 at 10.00.00.mp4", "edited", "gif"));
        Assert.Equal("Rec (edited).gif", TrimmedFileName.Name(@"C:\v\Rec (trimmed).mp4", "edited", "gif"));
        Assert.Equal("Rec (edited).gif", TrimmedFileName.Name(@"C:\v\Rec (trimmed) 2.mp4", "edited", "gif"));
        Assert.Equal("Rec (trimmed).mp4", TrimmedFileName.Name(@"C:\v\Rec (edited).mp4"));

        var taken = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { @"C:\v\Rec (trimmed).mp4", @"C:\v\Rec (trimmed) 2.mp4" };
        Assert.Equal(@"C:\v\Rec (trimmed) 3.mp4", TrimmedFileName.Unique(@"C:\v\Rec (trimmed).mp4", taken.Contains));
        Assert.Equal(@"C:\v\Rec (edited) 2.gif", TrimmedFileName.Unique(@"C:\v\Rec.mp4", new HashSet<string> { @"C:\v\Rec (edited).gif" }.Contains, "edited", "gif"));
    }

    // ---------------------------------------------------------------- CutList

    private static CutList Split(double duration, params double[] at)
    {
        var c = new CutList(duration);
        foreach (var t in at) Assert.True(c.Split(t));
        return c;
    }

    private static (double, double)[] Ranges(CutList c) => c.Segments.Select(s => (Math.Round(s.Start, 6), Math.Round(s.End, 6))).ToArray();

    [Fact]
    public void WholeRecordingIsOneSegment()
    {
        var c = new CutList(45);
        Assert.Single(c.Segments);
        Assert.Equal(45, c.KeptDuration);
        Assert.Equal((0.0, 45.0, false), c.Passthrough);
        Assert.True(c.IsWhole);
        var t = new CutList(2, 8, 10);
        Assert.Equal(new[] { (2.0, 8.0) }, Ranges(t));
        Assert.False(t.IsWhole);
    }

    [Fact]
    public void SplitRules()
    {
        var c = Split(10, 3, 7);
        Assert.Equal(new[] { (0.0, 3.0), (3.0, 7.0), (7.0, 10.0) }, Ranges(c));
        foreach (var bad in new[] { 0.05, 9.95, 0, 3 }) Assert.False(c.Split(bad));

        var s = new CutList(10);
        s.SetSpeed(2, 0);
        s.SetMuted(false, 0);
        Assert.True(s.Split(5));
        Assert.All(s.Segments, seg => Assert.Equal((2.0, false), (seg.Speed, seg.Muted)));

        var cut = Split(10, 3, 7);
        cut.Remove(1);
        Assert.False(cut.Split(5)); // inside a cut
    }

    [Fact]
    public void RemoveRules()
    {
        var c = Split(10, 3, 7);
        Assert.True(c.Remove(1));
        Assert.Equal(6, c.KeptDuration, 6);
        Assert.False(c.Remove(5));
        Assert.True(c.Remove(0));
        Assert.False(c.Remove(0)); // the last one stays
    }

    [Fact]
    public void KeptDurationWithSpeeds()
    {
        var c = Split(10, 2, 4, 8);
        c.Remove(1);           // [0,2] [4,8] [8,10]
        c.Remove(2);           // [0,2] [4,8]
        c.SetSpeed(2, 1);
        Assert.Equal(4, c.KeptDuration, 6);
        var four = new CutList(8);
        four.SetSpeed(4, 0);
        Assert.Equal(2, four.KeptDuration, 6);
        var oneHalf = new CutList(8);
        oneHalf.SetSpeed(1.5, 0);
        Assert.Equal(5.333333, oneHalf.KeptDuration, 5);
    }

    [Fact]
    public void SpeedMutesByDefault()
    {
        var c = new CutList(10);
        Assert.True(c.SetSpeed(2, 0));
        Assert.True(c.Segments[0].Muted);
        Assert.True(c.SetMuted(false, 0));
        Assert.True(c.SetSpeed(4, 0));
        Assert.False(c.Segments[0].Muted); // explicit unmute survives 2× → 4×
        Assert.True(c.SetMuted(true, 0));
        Assert.True(c.SetSpeed(1, 0));
        Assert.False(c.Segments[0].Muted); // back to 1× unmutes
        Assert.False(c.SetSpeed(3, 0));
        Assert.False(c.SetSpeed(1, 0));
    }

    [Fact]
    public void EdgeDragsClamp()
    {
        var c = Split(10, 3, 6);
        c.Remove(1); // [0,3] [6,10]
        Assert.True(c.SetStart(4, 1));
        Assert.Equal(4, c.Segments[1].Start);
        Assert.True(c.SetStart(1, 1));
        Assert.Equal(3, c.Segments[1].Start); // can't cross the neighbour
        Assert.False(c.SetEnd(9.99, 0));    // clamped to the neighbour's start = unchanged
        Assert.True(c.SetEnd(0, 0));
        Assert.Equal(0.1, c.Segments[0].End, 6);
        Assert.True(c.SetStart(99, 1));
        Assert.Equal(9.9, c.Segments[1].Start, 6);
    }

    [Fact]
    public void InAndOutPoints()
    {
        var c = Split(10, 3, 6);
        Assert.True(c.TrimBefore(4));
        Assert.Equal(new[] { (4.0, 6.0), (6.0, 10.0) }, Ranges(c));
        Assert.True(c.TrimAfter(8));
        Assert.Equal(new[] { (4.0, 6.0), (6.0, 8.0) }, Ranges(c));
        Assert.True(c.TrimAfter(6));
        Assert.Equal(new[] { (4.0, 6.0) }, Ranges(c));
        var fresh = new CutList(10);
        Assert.True(fresh.TrimBefore(9.99));
        Assert.Equal(9.9, fresh.Segments[0].Start, 6);
    }

    private static CutList TwoAtDouble()
    {
        var c = Split(10, 2, 4, 8);
        c.Remove(1);
        c.Remove(2);
        c.SetSpeed(2, 1); // [0,2] + [4,8]@2×
        return c;
    }

    [Fact]
    public void OutputSourceMapping()
    {
        var c = TwoAtDouble();
        Assert.Equal(1, c.SourceTimeForOutput(1), 6);
        Assert.Equal(6, c.SourceTimeForOutput(3), 6);
        Assert.Equal(8, c.SourceTimeForOutput(4), 6);
        Assert.Equal(3, c.OutputTimeForSource(6)!.Value, 6);
        Assert.Null(c.OutputTimeForSource(3));
        Assert.Equal(1, c.SegmentIndexAtOutput(2));
    }

    [Fact]
    public void PassthroughCases()
    {
        Assert.Equal((0.0, 10.0, false), Split(10, 5).Passthrough);
        var muted = Split(10, 5);
        muted.SetMuted(true, 0);
        muted.SetMuted(true, 1);
        Assert.Equal((0.0, 10.0, true), muted.Passthrough);
        var mixed = Split(10, 5);
        mixed.SetMuted(true, 0);
        Assert.Null(mixed.Passthrough);
        var middle = Split(10, 3, 7);
        middle.Remove(1);
        Assert.Null(middle.Passthrough);
        var fast = new CutList(10);
        fast.SetSpeed(1.5, 0);
        Assert.Null(fast.Passthrough);
        var trimmed = new CutList(10);
        trimmed.SetStart(1, 0);
        trimmed.SetEnd(9, 0);
        Assert.Equal((1.0, 9.0, false), trimmed.Passthrough);
    }

    [Fact]
    public void TimelineOfCutsAndSpeeds()
    {
        var c = TwoAtDouble();
        var t = c.Timeline;
        Assert.Equal(4, t.Count);
        Assert.Equal((true, 0, 0.0, 2.0), (t[0].Kept, t[0].Index, t[0].DisplayStart, t[0].DisplayEnd));
        Assert.Equal((false, 2.0, 4.0), (t[1].Kept, t[1].DisplayStart, t[1].DisplayEnd));
        Assert.Equal((true, 1, 4.0, 6.0), (t[2].Kept, t[2].Index, t[2].DisplayStart, t[2].DisplayEnd));
        Assert.Equal((false, 6.0, 8.0), (t[3].Kept, t[3].DisplayStart, t[3].DisplayEnd));
        Assert.Equal(8, c.TimelineLength, 6);
        Assert.Equal(5, c.TimelinePositionForOutput(3), 6);
        Assert.Equal(3, c.OutputTimeForTimelinePosition(5), 6);
        Assert.Equal(2, c.OutputTimeForTimelinePosition(3), 6);
        Assert.Equal(4, c.OutputTimeForTimelinePosition(7.5), 6);
        Assert.Equal(3, c.SourceTimeForTimelinePosition(3), 6);
        Assert.Equal(6, c.SourceTimeForTimelinePosition(5), 6);
    }

    [Fact]
    public void HistorySteps()
    {
        var h = new CutHistory(new CutList(10));
        Assert.True(h.Apply(c => c.Split(5)));
        Assert.True(h.Apply(c => c.Remove(0)));
        var only = h.Current;
        Assert.False(h.Apply(c => c.Remove(0))); // refused: no step
        Assert.Same(only, h.Current);
        Assert.True(h.Undo());
        Assert.True(h.Undo());
        Assert.False(h.Undo());
        Assert.Single(h.Current.Segments);
        Assert.True(h.Redo());
        Assert.Equal(2, h.Current.Segments.Count);
        var drag = h.Current.Clone();
        drag.SetEnd(3, 0);
        drag.SetEnd(2, 0);
        Assert.True(h.Commit(drag)); // one step for the whole drag
        Assert.False(h.CanRedo);
        Assert.True(h.Undo());
        Assert.Equal(5, h.Current.Segments[0].End, 6);
    }

    // ---------------------------------------------------------------- TimeRuler

    private static double Six(string s) => s.Length * 6;

    [Fact]
    public void RulerFormatsAndSteps()
    {
        Assert.Equal("0:05", TimeRuler.Format(5, 1));
        Assert.Equal("1:05", TimeRuler.Format(65, 5));
        Assert.Equal("60:00", TimeRuler.Format(3600, 300));
        Assert.Equal("0:04.5", TimeRuler.Format(4.5, 0.5));
        Assert.Equal("0:00.3", TimeRuler.Format(3 * 0.1, 0.1));
        Assert.Equal(1, TimeRuler.Step(50, 20, Six));
        Assert.Equal(2, TimeRuler.Step(38, 20, Six));
        Assert.Equal(0.1, TimeRuler.Step(520, 2, Six));
        Assert.Equal(300, TimeRuler.Step(936 / 3600.0, 3600, Six));
    }

    [Fact]
    public void RulerTicksOverKeptSegmentsOnly()
    {
        var ticks = TimeRuler.Ticks(new[] { new TimeRuler.Span(0, 1000, 0) }, 50, 1000, Six);
        Assert.Equal(Enumerable.Range(0, 20).Select(i => $"0:{i:00}"), ticks.Where(t => t.Label is not null).Select(t => t.Label));
        Assert.Equal(60, ticks.Count(t => !t.Major));

        // A 4 s cut between two spans gets no ticks; 0:05 sits at the second span's left edge.
        var spans = new[] { new TimeRuler.Span(0, 250, 0), new TimeRuler.Span(450, 250, 5) };
        var withCut = TimeRuler.Ticks(spans, 50, 1000, Six);
        Assert.DoesNotContain(withCut, t => t.X > 250 && t.X < 450);
        Assert.Contains(withCut, t => t.Label == "0:05" && Math.Abs(t.X - 450) < 1e-6);

        // A split at 5 s (±1e-9 noise) ticks 5 once.
        var split = TimeRuler.Ticks(new[] { new TimeRuler.Span(0, 250 - 5e-8, 0), new TimeRuler.Span(250, 250, 5 + 1e-9) }, 50, 1000, Six);
        Assert.Single(split, t => Math.Abs(t.Time - 5) < 1e-6);

        Assert.Empty(TimeRuler.Ticks(Array.Empty<TimeRuler.Span>(), 50, 1000, Six));
    }

    [Fact]
    public void RulerDropsTheLastLabelRatherThanClipIt()
    {
        var ticks = TimeRuler.Ticks(new[] { new TimeRuler.Span(0, 1000, 0) }, 50, 975, Six);
        Assert.Equal("0:18", ticks.Last(t => t.Label is not null).Label);
        Assert.Contains(ticks, t => t.Major && Math.Abs(t.Time - 19) < 1e-6 && t.Label is null); // its tick stays
    }

    [Fact]
    public void RulerAtFullZoomIsEvenAndUnique()
    {
        var ticks = TimeRuler.Ticks(new[] { new TimeRuler.Span(0, 12000, 0) }, 600, 12000, Six);
        var labels = ticks.Where(t => t.Label is not null).ToList();
        Assert.Equal(labels.Count, labels.Select(l => l.Label).Distinct().Count());
        Assert.Equal(200, labels.Count);
        var gaps = labels.Zip(labels.Skip(1), (a, b) => Math.Round(b.X - a.X, 6)).Distinct().ToList();
        Assert.Single(gaps);
    }

    // ---------------------------------------------------------------- FilmstripFrames

    [Fact]
    public void FilmstripCounts()
    {
        Assert.Equal(260, FilmstripFrames.Count(20, 1728 * 12, 80));
        Assert.Equal(400, FilmstripFrames.Count(3600, 5120 * 12, 80));
        Assert.Equal(30, FilmstripFrames.Count(1, 1728 * 12, 80));
        Assert.Equal(12, FilmstripFrames.Count(0.2, 1728 * 12, 80));
        Assert.Equal(12, FilmstripFrames.Count(0, 1728 * 12, 80));
        var times = FilmstripFrames.Times(16, 16);
        Assert.Equal(16, times.Select(t => t.Index).Distinct().Count());
        Assert.Equal(new[] { 0.5, 8.5, 4.5, 12.5 }, times.Take(4).Select(t => t.Time));
    }

    // ---------------------------------------------------------------- MediaInfo + args

    [Fact]
    public void MediaInfoParses()
    {
        const string err = """
            Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'a.mp4':
              Duration: 00:01:02.50, start: 0.000000, bitrate: 375 kb/s
              Stream #0:0[0x1](und): Video: h264 (High) (avc1 / 0x31637661), yuv420p(progressive), 1920x1080 [SAR 1:1 DAR 16:9], 368 kb/s, 60 fps, 60 tbr, 15360 tbn (default)
              Stream #0:1[0x2](und): Audio: aac (LC) (mp4a / 0x6134706D), 48000 Hz, stereo, fltp, 128 kb/s (default)
              Stream #0:2[0x3](und): Audio: aac (LC) (mp4a / 0x6134706D), 48000 Hz, stereo, fltp, 128 kb/s
            """;
        var info = MediaInfo.Parse(err)!;
        Assert.Equal(62.5, info.Duration, 6);
        Assert.Equal((1920, 1080, 60.0, 2, true), (info.Width, info.Height, info.Fps, info.AudioTracks, info.HasVideo));
        Assert.Null(MediaInfo.Parse("No such file"));
    }

    [Fact]
    public void PassthroughArgs()
    {
        var a = FfmpegArgs.BuildPassthroughTrim(@"C:\in.mp4", 1.5, 9.25, muted: true, @"C:\out.mp4").ToList();
        Assert.Equal(new[] { "-ss", "1.5", "-to", "9.25", "-i", @"C:\in.mp4" }, a.Skip(2).Take(6));
        Assert.Contains("-an", a);
        Assert.Equal("copy", a[a.IndexOf("-c") + 1]);
        Assert.Equal(@"C:\out.mp4", a[^1]);
    }

    [Fact]
    public void CutExportGraph()
    {
        var c = new CutList(60);
        c.Split(20); c.Split(25); c.Split(45); c.Split(50);
        c.Remove(1); c.Remove(2); // [0,20] [25,45] [50,60]
        c.SetSpeed(2, 1);
        var a = FfmpegArgs.BuildCutExport(@"C:\in.mp4", c, audioTracks: 1, muteAll: false, sourceFps: 60, nvenc: true, @"C:\o.mp4").ToList();
        string g = a[a.IndexOf("-filter_complex") + 1];
        Assert.Contains("[0:v]trim=start=25:end=45,setpts=(PTS-STARTPTS)/2[v1]", g);
        Assert.Contains("[0:a:0]atrim=start=25:end=45,asetpts=PTS-STARTPTS,atempo=2,volume=0[a1_0]", g);
        Assert.Contains("[v0][a0_0][v1][a1_0][v2][a2_0]concat=n=3:v=1:a=1[v][a0]", g);
        Assert.Equal("h264_nvenc", a[a.IndexOf("-c:v") + 1]);
        Assert.Equal("60", a[a.IndexOf("-r") + 1]);

        c.SetSpeed(4, 1);
        var two = FfmpegArgs.BuildCutExport(@"C:\in.mp4", c, audioTracks: 2, muteAll: false, sourceFps: 24, nvenc: false, @"C:\o.mp4").ToList();
        string g2 = two[two.IndexOf("-filter_complex") + 1];
        Assert.Contains("atempo=2,atempo=2", g2);
        Assert.Contains("concat=n=3:v=1:a=2[v][a0][a1]", g2);
        Assert.Equal("30", two[two.IndexOf("-r") + 1]); // clamped 30…60
        Assert.Equal("libx264", two[two.IndexOf("-c:v") + 1]);

        var silent = FfmpegArgs.BuildCutExport(@"C:\in.mp4", c, audioTracks: 2, muteAll: true, sourceFps: 30, nvenc: false, @"C:\o.mp4").ToList();
        Assert.Contains("concat=n=3:v=1:a=0[v]", silent[silent.IndexOf("-filter_complex") + 1]);
        Assert.Contains("-an", silent);
        Assert.DoesNotContain("atrim", silent[silent.IndexOf("-filter_complex") + 1]);
    }

    [Fact]
    public void ProgressAndKeyframes()
    {
        Assert.Equal(0.5, FfmpegArgs.ProgressFraction("out_time_us=5000000", 10));
        Assert.Equal(1, FfmpegArgs.ProgressFraction("out_time_ms=99000000", 10));
        Assert.Null(FfmpegArgs.ProgressFraction("frame=12", 10));
        var rec = FfmpegArgs.BuildRecording(RecordingConfig.Default with { Fps = 60 }, new BetterScreenshot.Core.PxRect(0, 0, 64, 64), "o.mp4", AudioInputs.None).ToList();
        Assert.Equal("30", rec[rec.IndexOf("-g") + 1]); // a keyframe every 0.5 s
    }

    [Fact]
    public void Edges_of_a_segment_shorter_than_the_minimum_refuse_instead_of_throwing()
    {
        var cuts = new CutList(0.05); // a 50 ms recording: one segment below MinimumSegment
        Assert.False(cuts.SetStart(0.02, 0));
        Assert.False(cuts.SetEnd(0.03, 0));
    }
}
