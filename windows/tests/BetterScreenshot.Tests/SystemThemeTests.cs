using System.IO;
using System.Text.RegularExpressions;
using BetterScreenshot.App.Controls;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>Round 3 #2: Settings and History follow Windows' light/dark mode through a second palette.</summary>
public class SystemThemeTests
{
    [Theory]
    [InlineData(1, null, true)]
    [InlineData(0, null, false)]
    [InlineData(null, null, true)]   // no value: Windows' own default is light
    [InlineData("junk", null, true)]
    [InlineData(1, "dark", false)]   // the preview/test override wins
    [InlineData(0, " Light ", true)]
    [InlineData(0, "sepia", false)]  // an unknown override is ignored
    public void The_mode_comes_from_AppsUseLightTheme_unless_overridden(object? registry, string? overrideValue, bool light)
        => Assert.Equal(light, SystemTheme.Resolve(registry, overrideValue));

    private static string Resources(string file)
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "src", "BetterScreenshot.App", "Resources", file)))
            dir = dir.Parent;
        Assert.NotNull(dir);
        return Path.Combine(dir!.FullName, "src", "BetterScreenshot.App");
    }

    private static HashSet<string> Keys(string xaml) =>
        Regex.Matches(xaml, @"x:Key=""([\w.]+Brush|Theme\.TextW85)""").Select(m => m.Groups[1].Value).ToHashSet();

    [Fact]
    public void The_light_palette_overrides_every_brush_the_following_windows_read_by_reference()
    {
        string app = Resources("ThemeLight.xaml");
        var dark = Keys(File.ReadAllText(Path.Combine(app, "Resources", "Theme.xaml")));
        var light = Keys(File.ReadAllText(Path.Combine(app, "Resources", "ThemeLight.xaml")));
        Assert.Empty(light.Except(dark)); // no typo'd key that would silently never apply

        // Every palette brush read dynamically by the shared styles, the two windows and their code-built rows.
        var sources = new[]
        {
            "Resources/Theme.xaml", "Settings/SettingsWindow.xaml", "Settings/SettingsWindow.xaml.cs",
            "History/HistoryWindow.xaml", "History/HistoryWindow.xaml.cs", "Controls/InfoTip.cs", "Tours/InfoButton.cs",
        }.Select(f => File.ReadAllText(Path.Combine(app, f))).ToList();
        var read = sources.SelectMany(s =>
                Regex.Matches(s, @"DynamicResource ((?:Theme|History)\.\w+)\}|""((?:Theme|History)\.\w+(?:Brush|W85))""")
                    .Select(m => m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value))
            .ToHashSet();
        Assert.Contains("Theme.TextBrush", read);
        Assert.Contains("History.CellBrush", read);
        var darkOnly = read.Except(light).Where(dark.Contains).ToList();
        Assert.Empty(darkOnly); // a dark-only key would stay dark in a light window
    }
}
