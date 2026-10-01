using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using BetterScreenshot.Recording;

namespace BetterScreenshot.Platform;

/// <summary>
/// Persisted application settings (JSON at %APPDATA%\BetterScreenshot\settings.json). Keys mirror the macOS app's
/// UserDefaults. Sub-configs are stored in their existing dictionary/JSON forms so they round-trip via their own
/// (already tested) serializers. Corrupt or missing files fall back to defaults — never throws on load.
/// </summary>
public sealed class SettingsStore
{
    public CaptureSettings Capture { get; set; } = CaptureSettings.Default;
    public HotkeyBindings Hotkeys { get; set; } = HotkeyBindings.Defaults();
    public RecordingConfig Recording { get; set; } = RecordingConfig.Default;
    public AnnotationStyle EditorStyle { get; set; } = AnnotationStyle.Default;
    /// <summary>The editor's Recent custom colours, newest first, at most 6 (v3 §1.5 <c>editorRecentColors</c>).</summary>
    public List<RGBAColor> EditorRecentColors { get; set; } = new();
    public string SaveDirectory { get; set; } = DefaultSaveDirectory;
    public string RecordingsDirectory { get; set; } = DefaultRecordingsDirectory;
    public bool CaptureSoundEnabled { get; set; }
    public bool LaunchAtLogin { get; set; }
    public bool FirstRunComplete { get; set; }
    /// <summary>Recording pill chevron state (v3 Part 5 <c>recordingPillCollapsed</c>), default expanded.</summary>
    public bool RecordingPillCollapsed { get; set; }
    /// <summary>Recording pill's bottom-right corner "{x, y}" in DIPs (v3 Part 5 <c>recordingPillAnchor</c>); null = bottom-centre.</summary>
    public string? RecordingPillAnchor { get; set; }

    // Guided tours (Mac v3 §7.2) — exactly these five keys, written only when set.
    /// <summary><c>tourAudience</c>: "new" / "existing", written once at the first launch with tours; null = not classified yet.</summary>
    public string? TourAudience { get; set; }
    /// <summary><c>tourQuestionAnswered</c>: the Welcome question was answered (or closed).</summary>
    public bool? TourQuestionAnswered { get; set; }
    /// <summary><c>firstUseToursEnabled</c>: tours start by themselves; absent = off.</summary>
    public bool? FirstUseToursEnabled { get; set; }
    /// <summary><c>toursSeen</c>: tour id → catalog version finished or skipped.</summary>
    public Dictionary<string, int> ToursSeen { get; set; } = new();
    /// <summary><c>toursPaused</c>: tour id → step index to resume at.</summary>
    public Dictionary<string, int> ToursPaused { get; set; } = new();
    /// <summary>v3 "Window placement": how the last window of each resizable kind (<c>annotate</c>, <c>editVideo</c>,
    /// <c>history</c>) was closed.</summary>
    public Dictionary<string, WindowPlacementMemo> WindowPlacements { get; set; } = new();

    /// <summary>Env var that relocates settings + History (dev/preview/new-user testing only — e.g.
    /// <c>--settings-dir</c>), so a throwaway profile never touches the real <c>%APPDATA%</c> files.</summary>
    public const string DirectoryOverrideVariable = "BETTERSCREENSHOT_SETTINGS_DIR";

    public static string DefaultDirectory =>
        Environment.GetEnvironmentVariable(DirectoryOverrideVariable) is { Length: > 0 } overridden
            ? overridden
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "BetterScreenshot");

    public static string DefaultSettingsPath => Path.Combine(DefaultDirectory, "settings.json");

    public static string DefaultSaveDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Screenshots");

    public static string DefaultRecordingsDirectory =>
        Environment.GetFolderPath(Environment.SpecialFolder.MyVideos);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    public void Save(string? path = null)
    {
        path ??= DefaultSettingsPath;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string json = JsonSerializer.Serialize(ToDto(), JsonOptions);
        string tmp = path + ".tmp";
        File.WriteAllText(tmp, json);
        File.Move(tmp, path, overwrite: true);
    }

    public static SettingsStore Load(string? path = null)
    {
        path ??= DefaultSettingsPath;
        try
        {
            if (!File.Exists(path)) return new SettingsStore();
            var dto = JsonSerializer.Deserialize<Dto>(File.ReadAllText(path), JsonOptions);
            return dto is null ? new SettingsStore() : FromDto(dto);
        }
        catch
        {
            return new SettingsStore();
        }
    }

    private Dto ToDto() => new()
    {
        CaptureSettings = Capture.ToDictionary(),
        HotkeyBindings = Hotkeys.ToDictionary(),
        RecordingConfig = Recording.ToDictionary(),
        EditorDefaultStyle = EditorStyle,
        EditorRecentColors = EditorRecentColors.Take(RecentColors.Capacity).ToList(),
        SaveDirectory = SaveDirectory,
        RecordingsDirectory = RecordingsDirectory,
        CaptureSoundEnabled = CaptureSoundEnabled,
        LaunchAtLogin = LaunchAtLogin,
        FirstRunComplete = FirstRunComplete,
        RecordingPillCollapsed = RecordingPillCollapsed,
        RecordingPillAnchor = RecordingPillAnchor,
        TourAudience = TourAudience,
        TourQuestionAnswered = TourQuestionAnswered,
        FirstUseToursEnabled = FirstUseToursEnabled,
        ToursSeen = ToursSeen.Count == 0 ? null : new Dictionary<string, int>(ToursSeen),
        ToursPaused = ToursPaused.Count == 0 ? null : new Dictionary<string, int>(ToursPaused),
        WindowPlacement = WindowPlacements.Count == 0 ? null : new Dictionary<string, WindowPlacementMemo>(WindowPlacements),
    };

    private static SettingsStore FromDto(Dto dto) => new()
    {
        Capture = dto.CaptureSettings is { } c ? CaptureSettings.FromDictionary(c) : CaptureSettings.Default,
        Hotkeys = dto.HotkeyBindings is { } h ? HotkeyBindings.FromDictionary(h) : HotkeyBindings.Defaults(),
        Recording = dto.RecordingConfig is { } r ? RecordingConfig.FromDictionary(r) : RecordingConfig.Default,
        EditorStyle = dto.EditorDefaultStyle ?? AnnotationStyle.Default,
        EditorRecentColors = new RecentColors(dto.EditorRecentColors ?? new List<RGBAColor>()).Colors.ToList(),
        SaveDirectory = string.IsNullOrWhiteSpace(dto.SaveDirectory) ? DefaultSaveDirectory : dto.SaveDirectory,
        RecordingsDirectory = string.IsNullOrWhiteSpace(dto.RecordingsDirectory) ? DefaultRecordingsDirectory : dto.RecordingsDirectory,
        CaptureSoundEnabled = dto.CaptureSoundEnabled ?? false,
        LaunchAtLogin = dto.LaunchAtLogin ?? false,
        FirstRunComplete = dto.FirstRunComplete ?? false,
        RecordingPillCollapsed = dto.RecordingPillCollapsed ?? false,
        RecordingPillAnchor = dto.RecordingPillAnchor,
        TourAudience = dto.TourAudience,
        TourQuestionAnswered = dto.TourQuestionAnswered,
        FirstUseToursEnabled = dto.FirstUseToursEnabled,
        ToursSeen = dto.ToursSeen ?? new Dictionary<string, int>(),
        ToursPaused = dto.ToursPaused ?? new Dictionary<string, int>(),
        WindowPlacements = dto.WindowPlacement ?? new Dictionary<string, WindowPlacementMemo>(),
    };

    private sealed class Dto
    {
        public Dictionary<string, string>? CaptureSettings { get; set; }
        public Dictionary<string, string>? HotkeyBindings { get; set; }
        public Dictionary<string, string>? RecordingConfig { get; set; }
        public AnnotationStyle? EditorDefaultStyle { get; set; }
        public List<RGBAColor>? EditorRecentColors { get; set; }
        public string? SaveDirectory { get; set; }
        public string? RecordingsDirectory { get; set; }
        public bool? CaptureSoundEnabled { get; set; }
        public bool? LaunchAtLogin { get; set; }
        public bool? FirstRunComplete { get; set; }
        public bool? RecordingPillCollapsed { get; set; }
        public string? RecordingPillAnchor { get; set; }
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public string? TourAudience { get; set; }
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public bool? TourQuestionAnswered { get; set; }
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public bool? FirstUseToursEnabled { get; set; }
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public Dictionary<string, int>? ToursSeen { get; set; }
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public Dictionary<string, int>? ToursPaused { get; set; }
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public Dictionary<string, WindowPlacementMemo>? WindowPlacement { get; set; }
    }

    /// <summary>
    /// The §7.1 audience signals for the settings folder <paramref name="directory"/>: the top-level property names of
    /// an existing <c>settings.json</c> (an unreadable one counts as a non-tour key — doubt means existing), and
    /// whether the folder holds anything besides <c>settings.json</c> (e.g. <c>History\</c>). Call before the first Save.
    /// </summary>
    public static (List<string> Keys, bool FolderHasContent) AudienceSignals(string? directory = null)
    {
        directory ??= DefaultDirectory;
        var keys = new List<string>();
        bool content = false;
        string settings = Path.Combine(directory, "settings.json");
        try
        {
            if (File.Exists(settings))
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(settings));
                if (doc.RootElement.ValueKind == JsonValueKind.Object)
                    foreach (var p in doc.RootElement.EnumerateObject()) keys.Add(p.Name);
                else keys.Add("<not an object>");
            }
        }
        catch (Exception) { keys.Add("<unreadable>"); }
        try
        {
            if (File.Exists(directory)) content = true; // a file where the folder should be = doubt
            else if (Directory.Exists(directory))
                content = Directory.EnumerateFileSystemEntries(directory)
                    .Any(e => !string.Equals(Path.GetFileName(e), "settings.json", StringComparison.OrdinalIgnoreCase)
                              && !string.Equals(Path.GetFileName(e), "settings.json.tmp", StringComparison.OrdinalIgnoreCase));
        }
        catch (Exception) { content = true; }
        return (keys, content);
    }
}
