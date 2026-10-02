using System.Runtime.CompilerServices;
using System.Windows;
using Microsoft.Win32;

namespace BetterScreenshot.App.Controls;

/// <summary>
/// Windows' app light/dark mode for the windows that follow it (review round 3 #2; v3 Part 9 "Settings follows the
/// system theme", Parity §5). Settings and History follow; the HUDs, the editor and the video editor stay dark.
/// A follower gets <c>Resources/ThemeLight.xaml</c> merged into its own resources in light mode (every themed control
/// reads the palette by DynamicResource, so it repaints in place), a light window layer and card fill, and a light
/// title bar. The mode is read (never written) from <c>AppsUseLightTheme</c> and re-read on UserPreferenceChanged;
/// <c>BETTERSCREENSHOT_THEME=light|dark</c> overrides it for previews.
/// </summary>
public static class SystemTheme
{
    public const string OverrideVariable = "BETTERSCREENSHOT_THEME";
    private const string PersonalizeKey = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private static readonly Uri LightPalette = new("pack://application:,,,/BetterScreenshot.App;component/Resources/ThemeLight.xaml");

    private static bool? _isLight;
    private static readonly List<Window> Followers = new();
    private static readonly ConditionalWeakTable<Window, ResourceDictionary> Merged = new();

    /// <summary>Forces the mode for windows created while it is set (the preview renderer's light shots); null = system.</summary>
    internal static bool? PreviewOverride { get; set; }

    public static bool IsLight => PreviewOverride ?? (_isLight ??= Read());

    /// <summary>Light unless the override says otherwise or AppsUseLightTheme is 0 (Windows' own default is light).</summary>
    public static bool Resolve(object? appsUseLightTheme, string? overrideValue) => overrideValue?.Trim().ToLowerInvariant() switch
    {
        "light" => true,
        "dark" => false,
        _ => appsUseLightTheme is not int value || value != 0,
    };

    private static bool Read()
    {
        object? value = null;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(PersonalizeKey);
            value = key?.GetValue("AppsUseLightTheme");
        }
        catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException or System.IO.IOException) { }
        return Resolve(value, Environment.GetEnvironmentVariable(OverrideVariable));
    }

    /// <summary>Makes <paramref name="window"/> follow the system mode until it closes. Call after
    /// <see cref="Surfaces.UseMica"/> (so the title-bar colour set here wins).</summary>
    public static void Follow(Window window)
    {
        Followers.Add(window);
        window.Closed += (_, _) => Followers.Remove(window);
        Apply(window, IsLight);
    }

    /// <summary>Re-reads the mode (a Windows personalisation change) and repaints the followers if it flipped.</summary>
    public static void Invalidate()
    {
        bool was = IsLight;
        _isLight = null;
        if (IsLight != was) Refresh(IsLight);
    }

    /// <summary>Re-applies <paramref name="light"/> (or each follower's current mode) to every follower — the Opacity
    /// setting changes their layer too.</summary>
    internal static void Refresh(bool? light = null)
    {
        foreach (var window in Followers.ToList()) Apply(window, light ?? Merged.TryGetValue(window, out _));
    }

    private static void Apply(Window window, bool light)
    {
        var dictionaries = window.Resources.MergedDictionaries;
        if (Merged.TryGetValue(window, out var palette) && !light)
        {
            dictionaries.Remove(palette);
            Merged.Remove(window);
        }
        else if (palette is null && light)
        {
            palette = new ResourceDictionary { Source = LightPalette };
            dictionaries.Add(palette);
            Merged.Add(window, palette);
        }
        Surfaces.ApplyMode(window, light);
    }
}
