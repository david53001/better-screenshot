using BetterScreenshot.Recording;

namespace BetterScreenshot.Platform;

/// <summary>
/// Discovers dshow capture devices by running <c>ffmpeg -list_devices</c> and parsing its stderr (via the pure
/// <see cref="DshowDeviceList"/>), then resolves the <see cref="AudioInputs"/> for a recording. The device list
/// is cached (it changes rarely and enumeration spawns an ffmpeg process); call <see cref="InvalidateCache"/>
/// after a known device change. Enumeration is best-effort — any failure yields "no devices", so recording simply
/// falls back to video-only.
/// </summary>
public static class DshowAudioDevices
{
    private static Task<DshowDeviceSet>? _cached;

    /// <summary>Enumerate (and cache) the dshow devices. Never throws — returns empty sets on failure.</summary>
    public static Task<DshowDeviceSet> EnumerateAsync() => _cached ??= EnumerateCoreAsync();

    private static async Task<DshowDeviceSet> EnumerateCoreAsync()
    {
        try
        {
            // -list_devices exits non-zero ("Error opening input file dummy") but still prints the list to stderr.
            var (_, stderr) = await FfmpegRunner
                .RunAsync(new[] { "-hide_banner", "-list_devices", "true", "-f", "dshow", "-i", "dummy" }, 8000)
                .ConfigureAwait(false);
            return DshowDeviceList.Parse(stderr);
        }
        catch
        {
            return new DshowDeviceSet(Array.Empty<string>(), Array.Empty<string>());
        }
    }

    /// <summary>
    /// Resolve which loopback/mic devices to feed ffmpeg for <paramref name="config"/> (each may be null → dropped).
    /// GIFs have no sound, so a GIF recording resolves no audio at all. The mic is the saved device while it's
    /// connected, else the Windows default input, else the name heuristic (v3 Part 4 <see cref="DeviceList"/>).
    /// </summary>
    public static async Task<AudioInputs> ResolveAsync(RecordingConfig config)
    {
        if (!config.RecordsAudio) return AudioInputs.None;
        var set = await EnumerateAsync().ConfigureAwait(false);
        string? system = config.SystemAudio ? DshowDeviceList.PickSystemLoopback(set.Audio) : null;
        string? mic = null;
        if (config.Microphone)
        {
            var mics = await MicrophonesAsync().ConfigureAwait(false);
            mic = mics.ResolvedId(config.MicrophoneDeviceId);
        }
        return new AudioInputs { SystemAudioDevice = system, MicrophoneDevice = mic };
    }

    /// <summary>The Microphone menu: every dshow audio input except the system-audio loopback, with the Windows
    /// default capture device (matched by name) as the default; the name heuristic when the default can't be read.</summary>
    public static async Task<DeviceList> MicrophonesAsync()
    {
        var set = await EnumerateAsync().ConfigureAwait(false);
        string? loopback = DshowDeviceList.PickSystemLoopback(set.Audio);
        var devices = set.Audio.Where(a => a != loopback).Select(a => new CaptureDevice(a, a)).ToList();
        string? defaultName = await DefaultCaptureNameAsync().ConfigureAwait(false);
        string? defaultId = defaultName is null ? null : DshowDeviceList.MatchName(devices.Select(d => d.Id), defaultName);
        defaultId ??= DshowDeviceList.PickMicrophone(devices.Select(d => d.Id));
        return new DeviceList(devices, defaultId);
    }

    /// <summary>The Windows default recording device's friendly name (Settings › Sound › Input), or null.</summary>
    private static async Task<string?> DefaultCaptureNameAsync()
    {
        try
        {
            string id = Windows.Media.Devices.MediaDevice.GetDefaultAudioCaptureId(Windows.Media.Devices.AudioDeviceRole.Default);
            if (string.IsNullOrEmpty(id)) return null;
            var info = await Windows.Devices.Enumeration.DeviceInformation.CreateFromIdAsync(id);
            return info?.Name;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>Drops the cached device list so the next resolve re-enumerates.</summary>
    public static void InvalidateCache() => _cached = null;
}
