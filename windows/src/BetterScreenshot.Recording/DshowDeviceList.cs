using System.Text.RegularExpressions;

namespace BetterScreenshot.Recording;

/// <summary>The dshow capture devices ffmpeg reported, split by kind (names as ffmpeg prints them).</summary>
public sealed record DshowDeviceSet(IReadOnlyList<string> Audio, IReadOnlyList<string> Video);

/// <summary>
/// Pure parsing + selection for ffmpeg dshow devices. <see cref="Parse"/> turns the stderr of
/// <c>ffmpeg -list_devices true -f dshow -i dummy</c> into named audio/video device lists; the pickers apply
/// name heuristics to choose a system-audio loopback device and a microphone. Actually running ffmpeg lives in
/// the Platform layer; this is unit-testable string logic.
/// </summary>
public static class DshowDeviceList
{
    // A device line looks like:  [in#0 @ ..] "Microphone (Yeti Classic)" (audio)
    // "Alternative name" lines end in a quoted device path (no "(audio)"/"(video)" suffix) and so never match.
    private static readonly Regex DeviceLine =
        new(@"""([^""]+)""\s+\((audio|video)\)\s*$", RegexOptions.Compiled);

    // Ordered by preference: a genuine loopback/"listen to output" device. Deliberately conservative — generic
    // "virtual audio" devices are ambiguous (some are mics), so they are not treated as loopback automatically.
    private static readonly string[] LoopbackKeywords =
    {
        "stereo mix", "what u hear", "wave out mix", "loopback", "cable output", "voicemeeter out",
    };

    public static DshowDeviceSet Parse(string ffmpegStderr)
    {
        var audio = new List<string>();
        var video = new List<string>();
        foreach (var raw in ffmpegStderr.Split('\n'))
        {
            var m = DeviceLine.Match(raw.TrimEnd('\r'));
            if (!m.Success) continue;
            (m.Groups[2].Value == "audio" ? audio : video).Add(m.Groups[1].Value);
        }
        return new DshowDeviceSet(audio, video);
    }

    /// <summary>The best system-audio loopback device by name, or null if none looks like a loopback.</summary>
    public static string? PickSystemLoopback(IEnumerable<string> audioDevices)
    {
        var list = audioDevices.ToList();
        foreach (var kw in LoopbackKeywords)
            foreach (var d in list)
                if (d.ToLowerInvariant().Contains(kw))
                    return d;
        return null;
    }

    /// <summary>
    /// The dshow device that is <paramref name="friendlyName"/> (a Core Audio / WinRT endpoint name): exact match
    /// first, then a dshow name the friendly name starts with (older dshow truncates names to 31 characters), case-insensitive.
    /// </summary>
    public static string? MatchName(IEnumerable<string> dshowNames, string friendlyName)
    {
        var list = dshowNames.ToList();
        return list.FirstOrDefault(n => string.Equals(n, friendlyName, StringComparison.OrdinalIgnoreCase))
               ?? list.Where(n => n.Length >= 8 && friendlyName.StartsWith(n, StringComparison.OrdinalIgnoreCase))
                   .OrderByDescending(n => n.Length).FirstOrDefault();
    }

    /// <summary>
    /// The best microphone: prefer a device whose name contains "microphone" (excluding <paramref name="excluding"/>,
    /// e.g. the chosen loopback); otherwise the first remaining device; null if nothing is left.
    /// </summary>
    public static string? PickMicrophone(IEnumerable<string> audioDevices, string? excluding = null)
    {
        var list = audioDevices.Where(d => d != excluding).ToList();
        foreach (var d in list)
            if (d.ToLowerInvariant().Contains("microphone"))
                return d;
        return list.Count > 0 ? list[0] : null;
    }
}
