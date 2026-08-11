using System.Globalization;

namespace BetterScreenshot.Capture;

public enum AfterCaptureBehavior { CopyOnly, SaveOnly, CopyAndSave, ShowOverlay }
public enum SettingsImageFormat { Png, Jpg }
public enum SettingsOverlayCorner { TopLeft, TopRight, BottomLeft, BottomRight }

/// <summary>
/// Capture behavior settings, persisted as a flat string dictionary (1:1 with the macOS app's persisted keys).
/// Defaults: show the quick-access overlay, PNG, bottom-right corner, 6s auto-dismiss, pin radius 8 + shadow,
/// history enabled with a 50-item cap, screen frozen while selecting, temp copies kept 5 minutes.
/// </summary>
public sealed record CaptureSettings
{
    public AfterCaptureBehavior AfterCapture { get; init; } = AfterCaptureBehavior.ShowOverlay;
    public SettingsImageFormat Format { get; init; } = SettingsImageFormat.Png;

    /// <summary>
    /// Freeze the screen while you pick an area or a window: the still is grabbed the instant the shortcut fires
    /// (before any overlay steals focus) and the capture is cropped out of that still. Without it, an app that
    /// reacts to losing focus — a game pausing to its menu, a video overlay fading out — changes the screen
    /// between the keypress and the capture. On by default.
    /// </summary>
    public bool FreezeScreen { get; init; } = true;
    public SettingsOverlayCorner OverlayCorner { get; init; } = SettingsOverlayCorner.BottomRight;
    public int OverlayAutoDismissSeconds { get; init; } = 6;
    public int PinCornerRadius { get; init; } = 8;
    public bool PinShadow { get; init; } = true;
    public bool HistoryEnabled { get; init; } = true;
    public int HistoryCap { get; init; } = 50;

    /// <summary>
    /// How long (in minutes, <see cref="TempRetentionScale.MinMinutes"/>..<see cref="TempRetentionScale.MaxMinutes"/>)
    /// the throwaway PNGs under <c>%TEMP%\BetterScreenshot-{guid}\</c> — the files behind clipboard file-drops and
    /// Quick Access drag-to-export — are kept before they are auto-deleted. Raising it lets you paste or drop a
    /// capture as a *file* long after you took it; the capture itself is never affected (History keeps its own copy).
    /// </summary>
    public int TempRetentionMinutes { get; init; } = TempRetentionScale.DefaultMinutes;

    public static CaptureSettings Default => new();

    public Dictionary<string, string> ToDictionary() => new()
    {
        ["afterCapture"] = AfterCapture switch
        {
            AfterCaptureBehavior.CopyOnly => "copyOnly",
            AfterCaptureBehavior.SaveOnly => "saveOnly",
            AfterCaptureBehavior.CopyAndSave => "copyAndSave",
            _ => "showOverlay",
        },
        ["format"] = Format == SettingsImageFormat.Jpg ? "jpg" : "png",
        ["overlayCorner"] = OverlayCorner switch
        {
            SettingsOverlayCorner.TopLeft => "topLeft",
            SettingsOverlayCorner.TopRight => "topRight",
            SettingsOverlayCorner.BottomLeft => "bottomLeft",
            _ => "bottomRight",
        },
        ["overlayAutoDismissSeconds"] = OverlayAutoDismissSeconds.ToString(CultureInfo.InvariantCulture),
        ["pinCornerRadius"] = PinCornerRadius.ToString(CultureInfo.InvariantCulture),
        ["pinShadow"] = PinShadow ? "true" : "false",
        ["historyEnabled"] = HistoryEnabled ? "true" : "false",
        ["historyCap"] = HistoryCap.ToString(CultureInfo.InvariantCulture),
        ["freezeScreen"] = FreezeScreen ? "true" : "false",
        ["tempRetentionMinutes"] = TempRetentionMinutes.ToString(CultureInfo.InvariantCulture),
    };

    public static CaptureSettings FromDictionary(IReadOnlyDictionary<string, string> d)
    {
        var def = Default;
        return new CaptureSettings
        {
            AfterCapture = d.TryGetValue("afterCapture", out var ac)
                ? ac switch
                {
                    "copyOnly" => AfterCaptureBehavior.CopyOnly,
                    "saveOnly" => AfterCaptureBehavior.SaveOnly,
                    "copyAndSave" => AfterCaptureBehavior.CopyAndSave,
                    "showOverlay" => AfterCaptureBehavior.ShowOverlay,
                    _ => def.AfterCapture,
                }
                : def.AfterCapture,
            Format = d.TryGetValue("format", out var f) ? (f == "jpg" ? SettingsImageFormat.Jpg : SettingsImageFormat.Png) : def.Format,
            OverlayCorner = d.TryGetValue("overlayCorner", out var oc)
                ? oc switch
                {
                    "topLeft" => SettingsOverlayCorner.TopLeft,
                    "topRight" => SettingsOverlayCorner.TopRight,
                    "bottomLeft" => SettingsOverlayCorner.BottomLeft,
                    "bottomRight" => SettingsOverlayCorner.BottomRight,
                    _ => def.OverlayCorner,
                }
                : def.OverlayCorner,
            OverlayAutoDismissSeconds = ParseInt(d, "overlayAutoDismissSeconds", def.OverlayAutoDismissSeconds),
            PinCornerRadius = ParseInt(d, "pinCornerRadius", def.PinCornerRadius),
            PinShadow = ParseBool(d, "pinShadow", def.PinShadow),
            HistoryEnabled = ParseBool(d, "historyEnabled", def.HistoryEnabled),
            HistoryCap = ParseInt(d, "historyCap", def.HistoryCap),
            FreezeScreen = ParseBool(d, "freezeScreen", def.FreezeScreen),
            // Clamped on read: a hand-edited or future-written value can never shorten the lifetime below the
            // 5 minutes an in-flight drop needs, nor leave temp files lying around past the bar's 30-minute end.
            TempRetentionMinutes = TempRetentionScale.Clamp(ParseInt(d, "tempRetentionMinutes", def.TempRetentionMinutes)),
        };
    }

    private static int ParseInt(IReadOnlyDictionary<string, string> d, string key, int fallback) =>
        d.TryGetValue(key, out var v) && int.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? n : fallback;

    private static bool ParseBool(IReadOnlyDictionary<string, string> d, string key, bool fallback) =>
        d.TryGetValue(key, out var v) ? v == "true" : fallback;
}
