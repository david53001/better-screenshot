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
            "-draw_mouse", config.ShowsCursor ? "1" : "0",
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
            // A keyframe at least every 0.5 s so passthrough trims start close to the chosen frame (v3 Part 6).
            "-g", Math.Max(1, config.Fps / 2).ToString(CultureInfo.InvariantCulture),
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

        // Fragmented MP4 (round 2 #2): the index is written up front and each fragment is playable on its own, so a
        // segment that is force-killed (a crash, the 8 s stop timeout) still holds everything up to its last fragment
        // (-flush_packets: without it the fragments sit in the output buffer and a kill loses them all).
        // The join at Stop re-muxes into an ordinary MP4. -nostats keeps the captured stderr to real messages.
        args.AddRange(new[] { "-movflags", "+frag_keyframe+empty_moov", "-flush_packets", "1", "-nostats" });
        args.Add(outputPath);
        return args;
    }

    /// <summary>The GIF frame filter (mac <c>GIFExporter</c>): <see cref="RecordingConfig.GifFps"/>fps, downscaled to
    /// ≤<see cref="RecordingConfig.GifMaxWidth"/>px with lanczos, never upscaling (<c>min(W,iw)</c>; the comma is
    /// escaped so the filtergraph parser doesn't treat it as a filter separator).</summary>
    private static string GifFrames =>
        $"fps={RecordingConfig.GifFps},scale=min({RecordingConfig.GifMaxWidth}\\,iw):-1:flags=lanczos";

    /// <summary>
    /// GIF pass 1: the palette for good colours, written to <paramref name="palettePng"/>. Two passes instead of a
    /// single <c>split</c>+<c>palettegen</c> graph, which holds every frame in memory until the end (review round 1 #17:
    /// a minute-long GIF buffered ~1 GB).
    /// </summary>
    public static IReadOnlyList<string> BuildGifPalette(string inputMp4, string palettePng) => new List<string>
    {
        "-hide_banner", "-y",
        "-i", inputMp4,
        "-vf", GifFrames + ",palettegen",
        palettePng,
    };

    /// <summary>GIF pass 2: map the frames through the palette, looping forever (<c>-loop 0</c>), with
    /// <c>-progress pipe:1</c> so the export can show real progress.</summary>
    public static IReadOnlyList<string> BuildGifConversion(string inputMp4, string palettePng, string outputGif) => new List<string>
    {
        "-hide_banner", "-y",
        "-i", inputMp4,
        "-i", palettePng,
        "-lavfi", GifFrames + "[x];[x][1:v]paletteuse",
        "-loop", "0",
        "-progress", "pipe:1", "-nostats",
        outputGif,
    };

    /// <summary>
    /// Lossless start/end trim (v3 A.3 / Part 6 passthrough): stream copy, starting on the keyframe at or before
    /// <paramref name="start"/>; <paramref name="muted"/> drops every audio track.
    /// </summary>
    public static IReadOnlyList<string> BuildPassthroughTrim(string input, double start, double end, bool muted, string output)
    {
        var args = new List<string>
        {
            "-hide_banner", "-y", "-ss", Secs(start), "-to", Secs(end), "-i", input,
            "-map", "0:v:0", "-map", "0:a?", "-c", "copy",
        };
        if (muted) args.Add("-an");
        args.AddRange(new[] { "-avoid_negative_ts", "make_zero", "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", output });
        return args;
    }

    /// <summary>
    /// Re-encode a cut list (v3 Part 6): one trim/atrim chain per kept segment, speed via setpts + atempo (pitch
    /// kept; 4× = atempo=2,atempo=2), per-segment mute via volume=0 (the audio stays continuous), then concat.
    /// Every audio track is kept as its own track. <paramref name="muteAll"/> (or no audio) drops audio entirely.
    /// </summary>
    public static IReadOnlyList<string> BuildCutExport(string input, CutList cuts, int audioTracks, bool muteAll,
        double sourceFps, bool nvenc, string output)
    {
        int tracks = muteAll ? 0 : Math.Max(0, audioTracks);
        var graph = new List<string>();
        var concatInputs = new System.Text.StringBuilder();
        for (int i = 0; i < cuts.Segments.Count; i++)
        {
            var s = cuts.Segments[i];
            string pts = Math.Abs(s.Speed - 1) < 1e-9 ? "PTS-STARTPTS" : $"(PTS-STARTPTS)/{Num(s.Speed)}";
            graph.Add($"[0:v]trim=start={Secs(s.Start)}:end={Secs(s.End)},setpts={pts}[v{i}]");
            concatInputs.Append($"[v{i}]");
            for (int a = 0; a < tracks; a++)
            {
                string chain = $"[0:a:{a}]atrim=start={Secs(s.Start)}:end={Secs(s.End)},asetpts=PTS-STARTPTS{Atempo(s.Speed)}";
                if (s.Muted) chain += ",volume=0";
                graph.Add(chain + $"[a{i}_{a}]");
                concatInputs.Append($"[a{i}_{a}]");
            }
        }
        var outs = new System.Text.StringBuilder("[v]");
        for (int a = 0; a < tracks; a++) outs.Append($"[a{a}]");
        graph.Add($"{concatInputs}concat=n={cuts.Segments.Count}:v=1:a={tracks}{outs}");

        double fps = Math.Clamp(sourceFps > 0 ? sourceFps : 30, 30, 60);
        var args = new List<string> { "-hide_banner", "-y", "-i", input, "-filter_complex", string.Join(";", graph), "-map", "[v]" };
        for (int a = 0; a < tracks; a++) args.AddRange(new[] { "-map", $"[a{a}]" });
        args.AddRange(new[] { "-r", Num(fps) });
        args.AddRange(nvenc
            ? new[] { "-c:v", "h264_nvenc", "-preset", "p5", "-cq", "19" }
            : new[] { "-c:v", "libx264", "-preset", "veryfast", "-crf", "18" });
        args.AddRange(new[] { "-pix_fmt", "yuv420p" });
        if (tracks > 0) args.AddRange(new[] { "-c:a", "aac", "-b:a", "128k" });
        else args.Add("-an");
        args.AddRange(new[] { "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", output });
        return args;
    }

    /// <summary>Progress fraction from a <c>-progress pipe:1</c> line ("out_time_us=…" / "out_time_ms=…" are both µs).</summary>
    public static double? ProgressFraction(string line, double outputSeconds)
    {
        if (outputSeconds <= 0) return null;
        int eq = line.IndexOf('=');
        if (eq < 0) return null;
        string key = line[..eq];
        if (key is not ("out_time_us" or "out_time_ms")) return null;
        return long.TryParse(line[(eq + 1)..], NumberStyles.Integer, CultureInfo.InvariantCulture, out long us)
            ? Math.Clamp(us / (outputSeconds * 1e6), 0, 1)
            : null;
    }

    /// <summary>Filmstrip thumbnails in one pass: <paramref name="count"/> frames spread over the file, 100 px tall
    /// (keyframes only for long files — decoding an hour of video frame by frame takes minutes).</summary>
    public static IReadOnlyList<string> BuildFilmstrip(string input, double duration, int count, string outPattern)
    {
        var args = new List<string> { "-hide_banner", "-y" };
        if (duration > 60) args.AddRange(new[] { "-skip_frame", "nokey" });
        args.AddRange(new[]
        {
            "-i", input, "-an", "-vf", $"fps={Num(count / Math.Max(0.1, duration))},scale=-2:100",
            "-fps_mode", "vfr", "-frames:v", count.ToString(CultureInfo.InvariantCulture), outPattern,
        });
        return args;
    }

    private static string Atempo(double speed) =>
        Math.Abs(speed - 1) < 1e-9 ? "" : Math.Abs(speed - 4) < 1e-9 ? ",atempo=2,atempo=2" : $",atempo={Num(speed)}";

    private static string Secs(double s) => s.ToString("0.###", CultureInfo.InvariantCulture);
    private static string Num(double v) => v.ToString("0.###", CultureInfo.InvariantCulture);

    private static readonly string[] SilentInput = { "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo" };

    /// <summary>A region's recorded frame size: H.264 needs even dimensions.</summary>
    public static PxSize EvenSize(PxRect region) => new(EvenFloor(region.Width), EvenFloor(region.Height));

    private static int EvenFloor(double v)
    {
        int n = (int)Math.Floor(v);
        return n - (n & 1);
    }
}
