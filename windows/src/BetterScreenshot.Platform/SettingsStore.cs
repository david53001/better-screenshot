using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using BetterScreenshot.Capture;
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
    }
}
