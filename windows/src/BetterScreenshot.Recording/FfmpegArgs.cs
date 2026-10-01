using System.Globalization;
using BetterScreenshot.Core;

namespace BetterScreenshot.Recording;

/// <summary>
/// The resolved audio capture devices for a recording. The pure arg builder only formats these into ffmpeg
/// <c>dshow</c> inputs; discovering the actual device names (a loopback-capable device for system audio, the
/// default microphone) is the Platform/engine's job. A null device means "unavailable" — that track is dropped.
/// </summary>
public sealed record AudioInputs
{
    /// <summary>dshow device name that captures system-audio loopback (e.g. "Stereo Mix" or a virtual cable), or null.</summary>
    public string? SystemAudioDevice { get; init; }

    /// <summary>dshow device name for the microphone, or null.</summary>
    public string? MicrophoneDevice { get; init; }

    /// <summary>No audio devices available — records video only.</summary>
    public static AudioInputs None => new();
}

/// <summary>
/// Per-segment variations of one recording session (v3 Part 5): the video's fixed output size (every segment is
/// encoded at the first one's size so the <c>-c copy</c> concat holds; a switched-to target is letterboxed into it)
/// and muted tracks (the track stays, fed from a silent <c>anullsrc</c> of the same shape — option A of the doc).
/// </summary>
public sealed record SegmentOptions
{
    /// <summary>Even output frame size; null = the region's own (even-floored) size, no scale/pad filter.</summary>
    public PxSize? OutputSize { get; init; }
    public bool MuteSystemAudio { get; init; }
    public bool MuteMicrophone { get; init; }

    public static SegmentOptions None => new();
}

/// <summary>
/// Builds the ffmpeg command-line arguments for a Windows screen recording (pure — deterministic strings, unit
/// tested). Video is captured with <c>gdigrab</c> over a desktop-relative pixel region (a display, an area
/// selection, or a tracked window rect all reduce to one region). System audio and the microphone become separate
/// <c>dshow</c> AAC tracks, included only when the config requests them and a device name is supplied. The
/// recording pass always encodes H.264/MP4; a GIF request is a separate post-conversion pass (later task).
/// </summary>
public static class FfmpegArgs
{
    /// <summary>Args to record <paramref name="region"/> (physical desktop pixels, top-left) to <paramref name="outputPath"/> (MP4).</summary>
    public static IReadOnlyList<string> BuildRecording(
        RecordingConfig config, PxRect region, string outputPath, AudioInputs audio, SegmentOptions? options = null)
    {
        options ??= SegmentOptions.None;
        string fpsStr = config.Fps.ToString(CultureInfo.InvariantCulture);

        int offsetX = (int)Math.Round(region.X);
        int offsetY = (int)Math.Round(region.Y);
        // H.264 (yuv420p) needs even dimensions — floor width/height to even, and size the bitrate off the same dims.
        int width = EvenFloor(region.Width);
        int height = EvenFloor(region.Height);

        var args = new List<string> { "-hide_banner", "-y" };

        // Video input: gdigrab over the region (cursor drawn, per the mac recorder's showsCursor).
        args.AddRange(new[]
        {
            "-f", "gdigrab",
            "-framerate", fpsStr,
            "-draw_mouse", "1",
            "-offset_x", offsetX.ToString(CultureInfo.InvariantCulture),
            "-offset_y", offsetY.ToString(CultureInfo.InvariantCulture),
            "-video_size", $"{width}x{height}",
            "-i", "desktop",
        });

        // Audio inputs (system first, then mic) — only when requested AND a device is available.
        bool includeSystem = config.SystemAudio && audio.SystemAudioDevice is not null;
        bool includeMic = config.Microphone && audio.MicrophoneDevice is not null;
        // A muted track keeps its slot (same index, same AAC shape) but reads silence, so the segments still concat.
        if (includeSystem)
            args.AddRange(options.MuteSystemAudio ? SilentInput : new[] { "-f", "dshow", "-i", $"audio={audio.SystemAudioDevice}" });
        if (includeMic)
            args.AddRange(options.MuteMicrophone ? SilentInput : new[] { "-f", "dshow", "-i", $"audio={audio.MicrophoneDevice}" });

        // Fixed output size: scale to fit + centre with black bars (exactly LetterboxFit; small targets scale up).
        if (options.OutputSize is { } output)
        {
            int ow = EvenFloor(output.Width), oh = EvenFloor(output.Height);
            args.AddRange(new[]
            {
                "-vf",
                $"scale={ow}:{oh}:force_original_aspect_ratio=decrease:flags=lanczos," +
                $"pad={ow}:{oh}:(ow-iw)/2:(oh-ih)/2:black,setsar=1",
            });
            width = ow;
            height = oh;
        }

        // Video encode (H.264, target bitrate from the pure config formula).
        long bitrate = config.VideoBitrate(width, height);
        args.AddRange(new[]
        {
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-pix_fmt", "yuv420p",
            "-b:v", bitrate.ToString(CultureInfo.InvariantCulture),
            "-r", fpsStr,
        });

        // Audio encode + explicit mapping (each audio input is its own 48kHz/2ch/128k AAC track, not pre-mixed).
        if (includeSystem || includeMic)
        {
            args.AddRange(new[] { "-c:a", "aac", "-b:a", "128k", "-ar", "48000", "-ac", "2" });
            args.AddRange(new[] { "-map", "0:v" });
            int audioIndex = 1;
            if (includeSystem) { args.AddRange(new[] { "-map", $"{audioIndex}:a" }); audioIndex++; }
            if (includeMic) { args.AddRange(new[] { "-map", $"{audioIndex}:a" }); }
        }

        args.Add(outputPath);
        return args;
    }

    /// <summary>
    /// Args to convert a recorded MP4 into a looping GIF (mac <c>GIFExporter</c>): downscale to ≤<see cref="RecordingConfig.GifMaxWidth"/>px
    /// (never upscaling — <c>min(W,iw)</c>) at <see cref="RecordingConfig.GifFps"/>fps with lanczos, then a single-pass
    /// palettegen/paletteuse for good colors, looping forever (<c>-loop 0</c>). The comma inside <c>min()</c> is
    /// escaped so the filtergraph parser doesn't treat it as a filter separator.
    /// </summary>
    public static IReadOnlyList<string> BuildGifConversion(string inputMp4, string outputGif)
    {
        string filter =
            $"fps={RecordingConfig.GifFps}," +
            $"scale=min({RecordingConfig.GifMaxWidth}\\,iw):-1:flags=lanczos," +
            "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse";

        return new List<string>
        {
            "-hide_banner", "-y",
            "-i", inputMp4,
            "-vf", filter,
            "-loop", "0",
            outputGif,
        };
    }

    private static readonly string[] SilentInput = { "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo" };

    /// <summary>A region's recorded frame size: H.264 needs even dimensions.</summary>
    public static PxSize EvenSize(PxRect region) => new(EvenFloor(region.Width), EvenFloor(region.Height));

    private static int EvenFloor(double v)
    {
        int n = (int)Math.Floor(v);
        return n - (n & 1);
    }
}
