namespace BetterScreenshot.Recording;

/// <summary>A capture device as the menus list it: a platform id (dshow name for mics, WinRT id for cameras) + its name.</summary>
public sealed record CaptureDevice(string Id, string Name);

/// <summary>A device-menu row: Off, or a device by id.</summary>
public readonly record struct DeviceChoice(string? DeviceId)
{
    public static DeviceChoice Off => new(null);
    public static DeviceChoice Device(string id) => new(id);
    public bool IsOff => DeviceId is null;
}

/// <summary>
/// The microphone / camera menu (Mac v3 Part 4 <c>DeviceChoice.swift</c>): which device actually records, and the
/// rows to show. An unplugged saved device is never overwritten — when it comes back it is used again.
/// </summary>
public sealed record DeviceList(IReadOnlyList<CaptureDevice> Devices, string? DefaultId)
{
    public static DeviceList Empty => new(Array.Empty<CaptureDevice>(), null);

    /// <summary>The saved device while connected, else the system default, else the first listed; null if none.</summary>
    public string? ResolvedId(string? saved)
    {
        if (saved is not null && Devices.Any(d => d.Id == saved)) return saved;
        if (DefaultId is not null && Devices.Any(d => d.Id == DefaultId)) return DefaultId;
        return Devices.Count > 0 ? Devices[0].Id : null;
    }

    /// <summary>What the dropdown shows: Off when the source is off or no device exists; else the device that will record.</summary>
    public DeviceChoice Choice(bool enabled, string? saved) =>
        enabled && ResolvedId(saved) is { } id ? DeviceChoice.Device(id) : DeviceChoice.Off;

    /// <summary>"Off" + one row per device in list order; the n-th repeat of a name is titled "Name (n)".</summary>
    public IReadOnlyList<(DeviceChoice Choice, string Title)> Options()
    {
        var rows = new List<(DeviceChoice, string)> { (DeviceChoice.Off, "Off") };
        var seen = new Dictionary<string, int>();
        foreach (var d in Devices)
        {
            int n = seen.TryGetValue(d.Name, out var c) ? c + 1 : 1;
            seen[d.Name] = n;
            rows.Add((DeviceChoice.Device(d.Id), n == 1 ? d.Name : $"{d.Name} ({n})"));
        }
        return rows;
    }
}

/// <summary>Microphone level meter maths (Mac v3 Part 4 <c>MicLevel.swift</c>): −60 dBFS floor, fast attack / slow release.</summary>
public static class MicLevel
{
    public const double FloorDb = -60;

    /// <summary>0…1 position of <paramref name="db"/> above the floor; −∞ (silence) and NaN → 0.</summary>
    public static double Fraction(double db) =>
        double.IsFinite(db) ? Math.Clamp((db - FloorDb) / -FloorDb, 0, 1) : 0;

    /// <summary>Rises at once, falls at most 0.06 per update (~20 ms).</summary>
    public static double Smoothed(double previous, double target) =>
        target >= previous ? target : Math.Max(target, previous - 0.06);

    public static int LitSegments(double fraction, int segments) =>
        Math.Clamp((int)Math.Round(fraction * segments, MidpointRounding.AwayFromZero), 0, segments);

    /// <summary>Average power of float samples in dBFS (RMS); empty or all-zero → −∞.</summary>
    public static double AveragePowerDb(ReadOnlySpan<float> samples)
    {
        if (samples.IsEmpty) return double.NegativeInfinity;
        double sum = 0;
        foreach (float s in samples) sum += (double)s * s;
        double rms = Math.Sqrt(sum / samples.Length);
        return rms > 0 ? 20 * Math.Log10(rms) : double.NegativeInfinity;
    }

    /// <summary>Segment colour band: green for the first 70 % of the bar, yellow up to 90 %, red above.</summary>
    public static int Band(int segmentIndex, int segments)
    {
        double pos = (segmentIndex + 1) / (double)segments;
        return pos <= 0.7 ? 0 : pos <= 0.9 ? 1 : 2;
    }
}

/// <summary>Areas of the record strip that explain themselves in its hint line.</summary>
public enum StripArea { None, FullScreen, Area, Window, Format, Fps, Close, Microphone, SystemAudio, Camera, Cursor, MicAccessLink }

/// <summary>The record strip's hint line (Mac v3 Part 4, verbatim with the doc's Windows wording).</summary>
public static class RecordStripHints
{
    public const string Idle = "Pick what to record, then choose Full Screen, Area or Window.";
    public const string GifNoSound = "GIFs have no sound. Switch Format to MP4 to record audio.";

    public static string For(StripArea area, RecordingFormat format) => area switch
    {
        StripArea.FullScreen => "Full Screen: records everything on this screen.",
        StripArea.Area => "Area: drag over the part of the screen you want, then recording starts.",
        StripArea.Window => "Window: click a window to record just that window, even as it moves.",
        StripArea.Format => "Format: MP4 is a video with sound. GIF is a silent, looping animation.",
        StripArea.Fps => "Frame rate: 60 looks smoother, 30 makes smaller files.",
        StripArea.Close => "Close this strip without recording.",
        StripArea.Microphone when format == RecordingFormat.Gif => GifNoSound,
        StripArea.SystemAudio when format == RecordingFormat.Gif => GifNoSound,
        StripArea.Microphone => "Microphone: records your voice from the selected input. Choose \"Off\" to skip it.",
        StripArea.SystemAudio => "System audio: records the sound your PC plays, like videos and calls. Choose \"Off\" to skip it.",
        StripArea.Camera => "Camera: shows your webcam in a round bubble on the recording. Set its size in the menu.",
        StripArea.Cursor => "Mouse cursor: choose whether it appears in the video.",
        StripArea.MicAccessLink => "Microphone access is off. Click to open Settings and turn it on for BetterScreenshot.",
        _ => format == RecordingFormat.Gif ? GifNoSound : Idle,
    };

    /// <summary>Menu-item tooltips (verbatim, Windows wording).</summary>
    public static string SystemAudioTooltip(SystemAudioMode mode) => mode switch
    {
        SystemAudioMode.Off => "No system sound in the recording.",
        SystemAudioMode.All => "Every sound your PC plays, including BetterScreenshot's own.",
        _ => "Every sound except BetterScreenshot's own, like its capture sound.",
    };

    public static string CursorTooltip(bool shown) =>
        shown ? "The mouse cursor is recorded as it moves." : "The video shows no mouse cursor.";
}
