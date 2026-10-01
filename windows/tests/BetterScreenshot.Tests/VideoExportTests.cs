using System.IO;
using System.Text.RegularExpressions;
using BetterScreenshot.App.Recording;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>Real ffmpeg exports of the video editor (v3 A.3 + Part 6) on a generated 3 s, 10 fps clip with a 440 Hz tone.</summary>
[Trait("category", "hardware")]
public sealed class VideoExportTests : IAsyncLifetime
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "bs-export-test-" + Guid.NewGuid().ToString("N"));
    private string _clip = "";
    private MediaInfo _info = null!;

    public async Task InitializeAsync()
    {
        Directory.CreateDirectory(_dir);
        _clip = Path.Combine(_dir, "Recording.mp4");
        var (ok, err) = await FfmpegRunner.RunAsync(new[]
        {
            "-hide_banner", "-y", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=10:duration=3",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=3", "-c:v", "libx264", "-g", "5", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-shortest", _clip,
        });
        Assert.True(ok, err);
        _info = (await VideoExporter.ProbeAsync(_clip))!;
        Assert.NotNull(_info);
    }

    public Task DisposeAsync()
    {
        try { Directory.Delete(_dir, recursive: true); } catch { }
        return Task.CompletedTask;
    }

    private static CutList ThreeSegments()
    {
        var c = new CutList(3);
        foreach (var t in new[] { 1.0, 1.5, 2.0, 2.5 }) c.Split(t);
        c.Remove(1);
        c.Remove(2); // [0,1] [1.5,2] [2.5,3]
        return c;
    }

    private static async Task<MediaInfo> Probe(string path) => (await VideoExporter.ProbeAsync(path))!;

    private static async Task<double> MeanVolume(string path, double from, double to)
    {
        var (_, err) = await FfmpegRunner.RunAsync(new[]
        {
            "-hide_banner", "-i", path, "-af", $"atrim={from.ToString(System.Globalization.CultureInfo.InvariantCulture)}:{to.ToString(System.Globalization.CultureInfo.InvariantCulture)},volumedetect", "-f", "null", "-",
        });
        var m = Regex.Match(err, @"mean_volume: (-?[\d.]+|-inf) dB");
        return m.Success && m.Groups[1].Value != "-inf" ? double.Parse(m.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture) : -200;
    }

    [Fact]
    public async Task ThreeSegmentCutIsReencodedWithAudio()
    {
        var copy = await VideoExporter.SaveCopyAsync(_clip, ThreeSegments(), _info, muteAll: false, _ => { });
        Assert.Equal(Path.Combine(_dir, "Recording (trimmed).mp4"), copy);
        var info = await Probe(copy!);
        Assert.InRange(info.Duration, 1.85, 2.2);
        Assert.Equal(1, info.AudioTracks);
    }

    [Fact]
    public async Task SpeedSegmentAndPerSegmentMute()
    {
        var c = new CutList(3);
        c.Split(2);
        c.SetSpeed(2, 0);   // [0,2] at 2× (auto-muted) + [2,3]
        var copy = await VideoExporter.SaveCopyAsync(_clip, c, _info, muteAll: false, _ => { });
        var info = await Probe(copy!);
        Assert.InRange(info.Duration, 1.85, 2.2);
        Assert.Equal(1, info.AudioTracks);
        Assert.True(await MeanVolume(copy!, 0.1, 0.9) < -60, "the muted sped-up segment must be silent");
        Assert.True(await MeanVolume(copy!, 1.2, 1.9) > -30, "the rest keeps its tone");
    }

    [Fact]
    public async Task PlainTrimWithASplitStaysPassthrough()
    {
        var c = new CutList(3);
        c.SetStart(0.5, 0);
        c.SetEnd(2.0, 0);
        c.Split(1.2);
        Assert.NotNull(c.Passthrough);
        var copy = await VideoExporter.SaveCopyAsync(_clip, c, _info, muteAll: false, _ => { });
        var info = await Probe(copy!);
        Assert.InRange(info.Duration, 1.3, 2.1); // stream copy snaps to the keyframe at or before 0.5 s
        Assert.Equal(1, info.AudioTracks);

        var muted = await VideoExporter.SaveCopyAsync(_clip, new CutList(1.0, 2.5, 3), _info, muteAll: true, _ => { });
        Assert.Equal(Path.Combine(_dir, "Recording (trimmed) 2.mp4"), muted);
        Assert.Equal(0, (await Probe(muted!)).AudioTracks);
        Assert.Equal(3, (await Probe(_clip)).Duration, 1); // the original stays 3 s
    }

    [Fact]
    public async Task GifExportNamesAndLeavesNoTemp()
    {
        int tempBefore = Directory.GetFiles(Path.GetTempPath(), "bs-gif-*").Length;
        var gif = await VideoExporter.ExportGifAsync(_clip, ThreeSegments(), _info, _ => { });
        Assert.Equal(Path.Combine(_dir, "Recording (edited).gif"), gif);
        var (_, err) = await FfmpegRunner.RunAsync(new[] { "-hide_banner", "-i", gif!, "-f", "null", "-" });
        var frames = Regex.Matches(err, @"frame=\s*(\d+)").Select(m => int.Parse(m.Groups[1].Value)).DefaultIfEmpty(0).Last();
        Assert.InRange(frames, 15, 25);
        var second = await VideoExporter.ExportGifAsync(_clip, ThreeSegments(), _info, _ => { });
        Assert.Equal(Path.Combine(_dir, "Recording (edited) 2.gif"), second);
        Assert.Equal(tempBefore, Directory.GetFiles(Path.GetTempPath(), "bs-gif-*").Length);
    }

    [Fact]
    public async Task ReplaceOriginalSwapsAtomically()
    {
        Assert.True(await VideoExporter.ReplaceAsync(_clip, ThreeSegments(), _info, muteAll: false, _ => { }));
        Assert.Equal(new[] { "Recording.mp4" }, Directory.GetFiles(_dir).Select(Path.GetFileName));
        Assert.InRange((await Probe(_clip)).Duration, 1.85, 2.2);
    }

    [Fact]
    public async Task FailedReplaceLeavesTheOriginalBytes()
    {
        string fake = Path.Combine(_dir, "notavideo.mp4");
        await File.WriteAllTextAsync(fake, "definitely not a video");
        byte[] before = await File.ReadAllBytesAsync(fake);
        Assert.False(await VideoExporter.ReplaceAsync(fake, ThreeSegments(), _info, muteAll: false, _ => { }));
        Assert.Equal(before, await File.ReadAllBytesAsync(fake));
        Assert.Equal(2, Directory.GetFiles(_dir).Length); // no temp left behind
    }

    [Fact]
    public async Task FirstFrameAndFilmstrip()
    {
        Assert.NotNull(await VideoExporter.FirstFrameAsync(_clip));
        var frames = await VideoExporter.FilmstripAsync(_clip, 3, 12, Path.Combine(_dir, "strip"));
        Assert.InRange(frames.Count, 10, 12);
    }
}
