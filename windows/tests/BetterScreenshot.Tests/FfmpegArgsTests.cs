using System.Collections.Generic;
using System.Linq;
using BetterScreenshot.Core;
using BetterScreenshot.Recording;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>
/// Locks the exact ffmpeg CLI argument list produced for a Windows screen recording. The recording pass always
/// targets H.264/MP4 (a GIF request is converted afterwards, in a later task); video is captured with gdigrab over
/// a desktop-relative pixel region; system audio and microphone are dshow inputs, each its own track, only when the
/// config asks for them AND a device name is available.
/// </summary>
public class FfmpegArgsTests
{
    private static string ValueAfter(IReadOnlyList<string> args, string flag)
    {
        int i = args.ToList().IndexOf(flag);
        Assert.True(i >= 0, $"flag '{flag}' not present in: {string.Join(' ', args)}");
        return args[i + 1];
    }

    [Fact]
    public void VideoOnly_FullHd_DefaultConfig_ProducesExactArgs()
    {
        var args = FfmpegArgs.BuildRecording(
            RecordingConfig.Default, // 30fps, systemAudio=true but no device supplied → no audio
            new PxRect(0, 0, 1920, 1080),
            @"C:\out.mp4",
            AudioInputs.None);

        Assert.Equal(new[]
        {
            "-hide_banner", "-y",
            "-f", "gdigrab", "-framerate", "30", "-draw_mouse", "1",
            "-offset_x", "0", "-offset_y", "0", "-video_size", "1920x1080", "-i", "desktop",
            "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-b:v", "7464960", "-r", "30", "-g", "15",
            @"C:\out.mp4",
        }, args);
    }

    [Fact]
    public void SystemAndMic_60fps_EvenRounding_ProducesExactArgs()
    {
        var config = RecordingConfig.Default with { Fps = 60, SystemAudio = true, Microphone = true };
        var args = FfmpegArgs.BuildRecording(
            config,
            new PxRect(100, 50, 801, 601), // odd size → floored to even 800x600
            @"C:\rec.mp4",
            new AudioInputs { SystemAudioDevice = "Stereo Mix", MicrophoneDevice = "Mic (USB)" });

        Assert.Equal(new[]
        {
            "-hide_banner", "-y",
            "-f", "gdigrab", "-framerate", "60", "-draw_mouse", "1",
            "-offset_x", "100", "-offset_y", "50", "-video_size", "800x600", "-i", "desktop",
            "-f", "dshow", "-i", "audio=Stereo Mix",
            "-f", "dshow", "-i", "audio=Mic (USB)",
            "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-b:v", "3456000", "-r", "60", "-g", "30",
            "-c:a", "aac", "-b:a", "128k", "-ar", "48000", "-ac", "2",
            "-map", "0:v", "-map", "1:a", "-map", "2:a",
            @"C:\rec.mp4",
        }, args);
    }

    [Fact]
    public void MicOnly_MapsAudioAtInputIndexOne()
    {
        var config = RecordingConfig.Default with { SystemAudio = false, Microphone = true };
        var args = FfmpegArgs.BuildRecording(
            config,
            new PxRect(0, 0, 1920, 1080),
            @"C:\m.mp4",
            new AudioInputs { MicrophoneDevice = "My Mic" });

        Assert.Contains("audio=My Mic", args);
        Assert.Contains("0:v", args);      // video mapped
        Assert.Contains("1:a", args);      // the single mic is input index 1
        Assert.DoesNotContain("2:a", args); // no second audio track
    }

    [Fact]
    public void SystemAudioRequested_ButNoDevice_OmitsAudioGracefully()
    {
        var args = FfmpegArgs.BuildRecording(
            RecordingConfig.Default, // systemAudio=true by default
            new PxRect(0, 0, 1280, 720),
            @"C:\v.mp4",
            AudioInputs.None); // but nothing is available

        Assert.DoesNotContain("dshow", args);
        Assert.DoesNotContain("-c:a", args);
        Assert.DoesNotContain("-map", args); // single video stream → rely on ffmpeg default mapping
    }

    [Fact]
    public void GifFormat_StillRecordsH264Mp4()
    {
        var config = RecordingConfig.Default with { Format = RecordingFormat.Gif };
        var args = FfmpegArgs.BuildRecording(config, new PxRect(0, 0, 640, 480), @"C:\g.mp4", AudioInputs.None);

        Assert.Contains("libx264", args); // recording is always MP4; GIF conversion is a separate pass
        Assert.DoesNotContain("gif", args);
    }

    [Fact]
    public void OutputPathIsAlwaysTheLastArg()
    {
        var args = FfmpegArgs.BuildRecording(
            RecordingConfig.Default, new PxRect(0, 0, 800, 600), @"C:\last.mp4",
            new AudioInputs { SystemAudioDevice = "Stereo Mix" });

        Assert.Equal(@"C:\last.mp4", args[^1]);
    }

    [Fact]
    public void Bitrate_ClampsUpToTwoMbpsFloorForTinyRegions()
    {
        var args = FfmpegArgs.BuildRecording(
            RecordingConfig.Default, new PxRect(0, 0, 100, 100), @"C:\tiny.mp4", AudioInputs.None);

        Assert.Equal("2000000", ValueAfter(args, "-b:v"));
    }

    [Fact]
    public void BuildGifConversion_ProducesExactArgs()
    {
        var args = FfmpegArgs.BuildGifConversion(@"C:\in.mp4", @"C:\p.png", @"C:\out.gif");

        Assert.Equal(new[]
        {
            "-hide_banner", "-y",
            "-i", @"C:\in.mp4",
            "-i", @"C:\p.png",
            "-lavfi", "fps=10,scale=min(960\\,iw):-1:flags=lanczos[x];[x][1:v]paletteuse",
            "-loop", "0",
            "-progress", "pipe:1", "-nostats",
            @"C:\out.gif",
        }, args);
    }

    [Fact]
    public void BuildGifPalette_ProducesExactArgs()
    {
        var args = FfmpegArgs.BuildGifPalette(@"C:\in.mp4", @"C:\p.png");

        Assert.Equal(new[]
        {
            "-hide_banner", "-y",
            "-i", @"C:\in.mp4",
            "-vf", "fps=10,scale=min(960\\,iw):-1:flags=lanczos,palettegen",
            @"C:\p.png",
        }, args);
    }

    [Fact]
    public void BuildGifConversion_OutputIsLastArg()
    {
        var args = FfmpegArgs.BuildGifConversion(@"C:\a.mp4", @"C:\p.png", @"C:\b.gif");
        Assert.Equal(@"C:\b.gif", args[^1]);
        Assert.Equal(@"C:\a.mp4", ValueAfter(args, "-i"));
    }
}
