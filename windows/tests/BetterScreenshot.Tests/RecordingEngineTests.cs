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
}
