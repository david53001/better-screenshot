using System.IO;
using System.Text.RegularExpressions;
using BetterScreenshot.App.Recording;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>Real ffmpeg recordings (v3 Part 5 engine): a mute toggle and a Switch to a different-shaped target split
/// the session into segments that still concat into one video at the first frame size; Discard leaves nothing.</summary>
public class RecordingEngineTests
{
    private static string TempMp4() => Path.Combine(Path.GetTempPath(), $"bs-engine-test-{Guid.NewGuid():N}.mp4");

    [Fact]
    [Trait("category", "hardware")]
    public async Task MuteAndSwitchSegmentsConcatAtTheFirstFrameSize()
    {
        string path = TempMp4();
        var engine = new RecordingEngine();
        try
        {
            Assert.True(engine.Start(RecordingConfig.Default with { SystemAudio = false }, new PxRect(0, 0, 640, 400), path));
            await Task.Delay(1200);
            await engine.SetMutedAsync(systemAudio: true, microphone: false); // ends + restarts the running segment
            await Task.Delay(1000);
            await engine.PauseAsync();
            engine.Retarget(new PxRect(0, 0, 300, 520)); // portrait: letterboxed into 640×400
            Assert.Equal(new PxRect(0, 0, 300, 520), engine.Region);
            engine.Resume();
            await Task.Delay(1200);
            string? final = await engine.StopAsync();

            Assert.Equal(path, final);
            var (_, info) = await FfmpegRunner.RunAsync(new[] { "-hide_banner", "-i", path });
            Assert.Matches(@"Video: h264.*640x400", info);
            var m = Regex.Match(info, @"Duration: (\d+):(\d+):(\d+\.\d+)");
            Assert.True(m.Success, info);
            double seconds = int.Parse(m.Groups[1].Value) * 3600 + int.Parse(m.Groups[2].Value) * 60
                             + double.Parse(m.Groups[3].Value, System.Globalization.CultureInfo.InvariantCulture);
            Assert.InRange(seconds, 1.5, 6);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    [Trait("category", "hardware")]
    public async Task DiscardDeletesEverything()
    {
        string path = TempMp4();
        var before = Directory.GetFiles(Path.GetTempPath(), "bs_rec_*").Length;
        var engine = new RecordingEngine();
        Assert.True(engine.Start(RecordingConfig.Default with { SystemAudio = false }, new PxRect(0, 0, 320, 240), path));
        await Task.Delay(800);
        await engine.DiscardAsync();
        Assert.False(engine.IsRecording);
        Assert.False(File.Exists(path));
        Assert.Null(await engine.StopAsync());
        Assert.True(Directory.GetFiles(Path.GetTempPath(), "bs_rec_*").Length <= before);
    }

    [Fact]
    [Trait("category", "hardware")]
    public async Task A_force_killed_segment_is_still_recoverable()
    {
        // Round 2 #2: a crash or the 8 s stop timeout kills ffmpeg; the fragmented segment must keep what it recorded,
        // and the launch sweep must turn it into a normal MP4.
        string dir = Path.Combine(Path.GetTempPath(), "bs-recover-test-" + Guid.NewGuid().ToString("N"));
        string outDir = Path.Combine(dir, "out");
        Directory.CreateDirectory(dir);
        try
        {
            string seg = Path.Combine(dir, $"bs_rec_{Guid.NewGuid():N}_0.mp4");
            var p = FfmpegRunner.StartRecording(FfmpegArgs.BuildRecording(
                RecordingConfig.Default with { SystemAudio = false }, new PxRect(0, 0, 320, 240), seg, AudioInputs.None));
            await Task.Delay(2500);
            p.Kill(entireProcessTree: true);
            await p.WaitForExitAsync();
            Assert.True(RecordingEngine.HasRecordedMedia(seg));

            File.WriteAllBytes(Path.Combine(dir, $"bs_rec_{Guid.NewGuid():N}_0.mp4"), Array.Empty<byte>()); // nothing recorded
            Assert.Equal(1, await RecordingEngine.RecoverOrphansAsync(outDir, dir));
            Assert.Empty(Directory.GetFiles(dir, "bs_rec_*"));
            var recovered = Assert.Single(Directory.GetFiles(outDir, "*.mp4"));
            await using var fs = File.OpenRead(recovered);
            Assert.True(BetterScreenshot.History.MediaInfo.Mp4Duration(fs) is { } d && d > TimeSpan.FromSeconds(0.5));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void A_window_entirely_off_screen_is_refused_with_a_reason()
    {
        var engine = new RecordingEngine();
        Assert.False(engine.Start(RecordingConfig.Default, new PxRect(-90000, -90000, 400, 300), TempMp4()));
        Assert.Contains("off-screen", engine.LastFailure);
    }

    [Fact]
    [Trait("category", "hardware")]
    public async Task A_segment_that_dies_is_reported_not_silent()
    {
        // Round 2 #1: a mic ffmpeg can't open — the segment exits at once, writes nothing, and the take must say so.
        string path = TempMp4();
        var engine = new RecordingEngine();
        var died = new TaskCompletionSource();
        engine.SegmentDied += () => died.TrySetResult();
        Assert.True(engine.Start(RecordingConfig.Default with { SystemAudio = false, Microphone = true },
            new PxRect(0, 0, 320, 240), path, new AudioInputs { MicrophoneDevice = "No Such Microphone 7f3a" }));
        Assert.Same(died.Task, await Task.WhenAny(died.Task, Task.Delay(10000)));
        Assert.Null(await engine.StopAsync());
        Assert.NotNull(engine.LastFailure);
        Assert.False(File.Exists(path));
    }

    [Fact]
    [Trait("category", "hardware")]
    public async Task System_audio_by_wasapi_loopback_records_a_track_in_step_with_the_video()
    {
        // Round 3 #1: no "Stereo Mix" needed. Nothing is played (silent), so the keep-alive alone drives the stream.
        if (!LoopbackPipe.Available()) return; // no output device on this machine
        string path = TempMp4();
        var engine = new RecordingEngine();
        try
        {
            var config = RecordingConfig.Default with { SystemAudio = true, Microphone = false };
            Assert.True(engine.Start(config, new PxRect(0, 0, 320, 240), path, new AudioInputs { SystemAudioLoopback = true }));
            await Task.Delay(2000);
            await engine.PauseAsync();
            engine.Resume(); // a second segment with its own pipe
            await Task.Delay(2000);
            Assert.Equal(path, await engine.StopAsync());
            Assert.Null(engine.LastFailure);

            var (_, info) = await FfmpegRunner.RunAsync(new[] { "-hide_banner", "-i", path });
            Assert.Matches(@"Audio: aac", info);
            static double Secs(Match m) => int.Parse(m.Groups[1].Value) * 60 + double.Parse(m.Groups[2].Value, System.Globalization.CultureInfo.InvariantCulture);
            var (_, v) = await FfmpegRunner.RunAsync(new[] { "-hide_banner", "-i", path, "-map", "0:v", "-c", "copy", "-f", "null", "-" });
            var (_, a) = await FfmpegRunner.RunAsync(new[] { "-hide_banner", "-i", path, "-map", "0:a", "-c", "copy", "-f", "null", "-" });
            double video = Secs(Regex.Matches(v, @"time=00:(\d+):(\d+\.\d+)").Last());
            double audio = Secs(Regex.Matches(a, @"time=00:(\d+):(\d+\.\d+)").Last());
            Assert.InRange(video, 2.5, 6);
            // ≤ 0.1 s: before -tune zerolatency, x264's lookahead held ffmpeg's audio reader back and Stop lost ~0.35 s.
            Assert.True(Math.Abs(video - audio) <= 0.1, $"video {video:0.00} s vs audio {audio:0.00} s");
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }
}
