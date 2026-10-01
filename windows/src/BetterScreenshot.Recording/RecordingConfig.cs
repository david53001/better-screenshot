using System.Globalization;

namespace BetterScreenshot.Recording;

public enum RecordingFormat { Mp4, Gif }
public enum CameraSize { Small, Medium }

public static class CameraSizeExtensions
{
    /// <summary>Camera bubble diameter in pixels.</summary>
    public static int Diameter(this CameraSize size) => size == CameraSize.Small ? 160 : 240;
}

/// <summary>
/// Recording preferences, persisted as a flat string dictionary (1:1 with the macOS app). Defaults: MP4,
/// 30fps, system audio on, mic/camera off, small camera, click highlights on, keystroke overlay off, no countdown.
/// </summary>
public sealed record RecordingConfig
{
    public RecordingFormat Format { get; init; } = RecordingFormat.Mp4;
    public int Fps { get; init; } = 30;
    public bool SystemAudio { get; init; } = true;
    public bool Microphone { get; init; } = false;
    public bool Camera { get; init; } = false;
    public CameraSize CameraSize { get; init; } = CameraSize.Small;
    public bool ClickHighlights { get; init; } = true;
    public bool KeystrokeOverlay { get; init; } = false;
    public int CountdownSeconds { get; init; } = 0;
    /// <summary>"Show recording controls in the video" (v3 A.2 <c>controlsInRecording</c>): off keeps the floating
    /// pill out of the video (<c>WDA_EXCLUDEFROMCAPTURE</c>); on records it like any other window.</summary>
    public bool ControlsInRecording { get; init; } = false;

    public const int GifFps = 10;
    public const int GifMaxWidth = 960;

    public static RecordingConfig Default => new();

    /// <summary>H.264 target bitrate = clamp(w*h*fps*0.12, 2..40 Mbps).</summary>
    public long VideoBitrate(int width, int height)
    {
        double raw = (double)width * height * Fps * 0.12;
        return (long)Math.Clamp(raw, 2_000_000d, 40_000_000d);
    }

    public Dictionary<string, string> ToDictionary() => new()
    {
        ["format"] = Format == RecordingFormat.Gif ? "gif" : "mp4",
        ["fps"] = Fps.ToString(CultureInfo.InvariantCulture),
        ["systemAudio"] = SystemAudio ? "true" : "false",
        ["microphone"] = Microphone ? "true" : "false",
        ["camera"] = Camera ? "true" : "false",
        ["cameraSize"] = CameraSize == CameraSize.Medium ? "medium" : "small",
        ["clickHighlights"] = ClickHighlights ? "true" : "false",
        ["keystrokeOverlay"] = KeystrokeOverlay ? "true" : "false",
        ["countdownSeconds"] = CountdownSeconds.ToString(CultureInfo.InvariantCulture),
        ["controlsInRecording"] = ControlsInRecording ? "true" : "false",
    };

    public static RecordingConfig FromDictionary(IReadOnlyDictionary<string, string> d)
    {
        var def = Default;
        int fps = ParseInt(d, "fps", def.Fps);
        if (fps != 30 && fps != 60) fps = 30;
        int countdown = ParseInt(d, "countdownSeconds", def.CountdownSeconds);
        if (countdown is not (0 or 3 or 5 or 10)) countdown = 0;

        return new RecordingConfig
        {
            Format = d.TryGetValue("format", out var f) ? (f == "gif" ? RecordingFormat.Gif : RecordingFormat.Mp4) : def.Format,
            Fps = fps,
            SystemAudio = ParseBool(d, "systemAudio", def.SystemAudio),
            Microphone = ParseBool(d, "microphone", def.Microphone),
            Camera = ParseBool(d, "camera", def.Camera),
            CameraSize = d.TryGetValue("cameraSize", out var cs) ? (cs == "medium" ? CameraSize.Medium : CameraSize.Small) : def.CameraSize,
            ClickHighlights = ParseBool(d, "clickHighlights", def.ClickHighlights),
            KeystrokeOverlay = ParseBool(d, "keystrokeOverlay", def.KeystrokeOverlay),
            CountdownSeconds = countdown,
            ControlsInRecording = ParseBool(d, "controlsInRecording", def.ControlsInRecording),
        };
    }

    private static int ParseInt(IReadOnlyDictionary<string, string> d, string key, int fallback) =>
        d.TryGetValue(key, out var v) && int.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? n : fallback;

    private static bool ParseBool(IReadOnlyDictionary<string, string> d, string key, bool fallback) =>
        d.TryGetValue(key, out var v) ? v == "true" : fallback;
}
