using System.Globalization;

namespace BetterScreenshot.Recording;

public enum RecordingFormat { Mp4, Gif }
public enum CameraSize { Small, Medium }

/// <summary>Where system sound comes from (v3 Part 4 <c>systemAudioMode</c>). <see cref="ExcludeSelf"/> needs WASAPI
/// process loopback, which the port's dshow loopback can't do: it stays readable (a synced/ported settings file
/// loads) and records like <see cref="All"/>; the Windows menus don't offer it.</summary>
public enum SystemAudioMode { Off, All, ExcludeSelf }

public static class CameraSizeExtensions
{
    /// <summary>Camera bubble diameter in pixels.</summary>
    public static int Diameter(this CameraSize size) => size == CameraSize.Small ? 160 : 240;
}

public static class SystemAudioModeExtensions
{
    public static string Title(this SystemAudioMode mode) => mode switch
    {
        SystemAudioMode.Off => "Off",
        SystemAudioMode.All => "All apps",
        _ => "All apps except BetterScreenshot",
    };

    public static bool ExcludesOwnAudio(this SystemAudioMode mode) => mode == SystemAudioMode.ExcludeSelf;

    internal static string Key(this SystemAudioMode mode) => mode switch
    {
        SystemAudioMode.Off => "off",
        SystemAudioMode.All => "all",
        _ => "excludeSelf",
    };
}

/// <summary>
/// Recording preferences, persisted as a flat string dictionary (1:1 with the macOS app). Defaults: MP4,
/// 30fps, system audio All apps, mic/camera off (system-default devices), small camera, cursor shown, click
/// highlights on, keystroke overlay off, no countdown.
/// </summary>
public sealed record RecordingConfig
{
    public RecordingFormat Format { get; init; } = RecordingFormat.Mp4;
    public int Fps { get; init; } = 30;
    public SystemAudioMode SystemAudioMode { get; init; } = SystemAudioMode.All;

    /// <summary>Bool view of <see cref="SystemAudioMode"/> (still written as <c>systemAudio</c> for older builds):
    /// true when Off picks All apps, true when already on keeps the mode, false → Off.</summary>
    public bool SystemAudio
    {
        get => SystemAudioMode != SystemAudioMode.Off;
        init => SystemAudioMode = value
            ? (SystemAudioMode == SystemAudioMode.Off ? SystemAudioMode.All : SystemAudioMode)
            : SystemAudioMode.Off;
    }

    public bool Microphone { get; init; } = false;
    /// <summary>Chosen microphone (the dshow device name on Windows); null = the system default.</summary>
    public string? MicrophoneDeviceId { get; init; }
    public bool Camera { get; init; } = false;
    /// <summary>Chosen camera (a WinRT VideoCapture device id on Windows); null = the system default.</summary>
    public string? CameraDeviceId { get; init; }
    public CameraSize CameraSize { get; init; } = CameraSize.Small;
    /// <summary>"Mouse cursor": Shown (true) draws the pointer into the video, Hidden (false) leaves it out.</summary>
    public bool ShowsCursor { get; init; } = true;
    public bool ClickHighlights { get; init; } = true;
    public bool KeystrokeOverlay { get; init; } = false;
    public int CountdownSeconds { get; init; } = 0;
    /// <summary>"Show recording controls in the video" (v3 A.2 <c>controlsInRecording</c>): off keeps the floating
    /// pill out of the video (<c>WDA_EXCLUDEFROMCAPTURE</c>); on records it like any other window.</summary>
    public bool ControlsInRecording { get; init; } = false;

    public const int GifFps = 10;
    public const int GifMaxWidth = 960;

    public static RecordingConfig Default => new();

    /// <summary>GIFs have no sound: a GIF recording ignores both audio sources (no mic in use, no prompt).</summary>
    public bool RecordsAudio => Format == RecordingFormat.Mp4;

    /// <summary>The strip/Settings Microphone menu: Off keeps the last device id; a device turns the mic on and saves it.</summary>
    public RecordingConfig WithMicrophone(DeviceChoice choice) => choice.IsOff
        ? this with { Microphone = false }
        : this with { Microphone = true, MicrophoneDeviceId = choice.DeviceId };

    /// <summary>The Camera menu, same rules as <see cref="WithMicrophone"/>.</summary>
    public RecordingConfig WithCamera(DeviceChoice choice) => choice.IsOff
        ? this with { Camera = false }
        : this with { Camera = true, CameraDeviceId = choice.DeviceId };

    /// <summary>H.264 target bitrate = clamp(w*h*fps*0.12, 2..40 Mbps).</summary>
    public long VideoBitrate(int width, int height)
    {
        double raw = (double)width * height * Fps * 0.12;
        return (long)Math.Clamp(raw, 2_000_000d, 40_000_000d);
    }

    public Dictionary<string, string> ToDictionary()
    {
        var d = new Dictionary<string, string>
        {
            ["format"] = Format == RecordingFormat.Gif ? "gif" : "mp4",
            ["fps"] = Fps.ToString(CultureInfo.InvariantCulture),
            ["systemAudioMode"] = SystemAudioMode.Key(),
            ["systemAudio"] = SystemAudio ? "true" : "false",
            ["microphone"] = Microphone ? "true" : "false",
            ["camera"] = Camera ? "true" : "false",
            ["cameraSize"] = CameraSize == CameraSize.Medium ? "medium" : "small",
            ["showsCursor"] = ShowsCursor ? "true" : "false",
            ["clickHighlights"] = ClickHighlights ? "true" : "false",
            ["keystrokeOverlay"] = KeystrokeOverlay ? "true" : "false",
            ["countdownSeconds"] = CountdownSeconds.ToString(CultureInfo.InvariantCulture),
            ["controlsInRecording"] = ControlsInRecording ? "true" : "false",
        };
        if (!string.IsNullOrEmpty(MicrophoneDeviceId)) d["microphoneDeviceID"] = MicrophoneDeviceId;
        if (!string.IsNullOrEmpty(CameraDeviceId)) d["cameraDeviceID"] = CameraDeviceId;
        return d;
    }

    public static RecordingConfig FromDictionary(IReadOnlyDictionary<string, string> d)
    {
        var def = Default;
        int fps = ParseInt(d, "fps", def.Fps);
        if (fps != 30 && fps != 60) fps = 30;
        int countdown = ParseInt(d, "countdownSeconds", def.CountdownSeconds);
        if (countdown is not (0 or 3 or 5 or 10)) countdown = 0;

        // systemAudioMode wins when valid; otherwise derive from the legacy Bool (missing → All apps).
        var mode = (d.TryGetValue("systemAudioMode", out var m) ? m : null) switch
        {
            "off" => SystemAudioMode.Off,
            "all" => SystemAudioMode.All,
            "excludeSelf" => SystemAudioMode.ExcludeSelf,
            _ => ParseBool(d, "systemAudio", true) ? SystemAudioMode.All : SystemAudioMode.Off,
        };

        return new RecordingConfig
        {
            Format = d.TryGetValue("format", out var f) ? (f == "gif" ? RecordingFormat.Gif : RecordingFormat.Mp4) : def.Format,
            Fps = fps,
            SystemAudioMode = mode,
            Microphone = ParseBool(d, "microphone", def.Microphone),
            MicrophoneDeviceId = NonEmpty(d, "microphoneDeviceID"),
            Camera = ParseBool(d, "camera", def.Camera),
            CameraDeviceId = NonEmpty(d, "cameraDeviceID"),
            CameraSize = d.TryGetValue("cameraSize", out var cs) ? (cs == "medium" ? CameraSize.Medium : CameraSize.Small) : def.CameraSize,
            ShowsCursor = ParseBool(d, "showsCursor", def.ShowsCursor),
            ClickHighlights = ParseBool(d, "clickHighlights", def.ClickHighlights),
            KeystrokeOverlay = ParseBool(d, "keystrokeOverlay", def.KeystrokeOverlay),
            CountdownSeconds = countdown,
            ControlsInRecording = ParseBool(d, "controlsInRecording", def.ControlsInRecording),
        };
    }

    private static string? NonEmpty(IReadOnlyDictionary<string, string> d, string key) =>
        d.TryGetValue(key, out var v) && !string.IsNullOrEmpty(v) ? v : null;

    private static int ParseInt(IReadOnlyDictionary<string, string> d, string key, int fallback) =>
        d.TryGetValue(key, out var v) && int.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? n : fallback;

    private static bool ParseBool(IReadOnlyDictionary<string, string> d, string key, bool fallback) =>
        d.TryGetValue(key, out var v) ? v == "true" : fallback;
}
