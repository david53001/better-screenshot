using System.Windows;
using System.Windows.Threading;

namespace BetterScreenshot.App.Overlays;

/// <summary>What a toast's leading icon says (review X5).</summary>
public enum HudIcon { None, Copy, Text, Warning, Done }

/// <summary>A transient bottom-center toast (auto-dismisses after 1.5s), e.g. the Capture-Text result message.</summary>
public partial class HudWindow : Window
{
    public HudWindow(string message, HudIcon icon = HudIcon.None)
    {
        InitializeComponent();
        Message.Text = message;
        if (IconKey(icon) is { } key)
        {
            IconGlyph.IconKey = key;
            IconGlyph.Visibility = Visibility.Visible;
        }
        Loaded += OnLoaded;
    }

    internal static string? IconKey(HudIcon icon) => icon switch
    {
        HudIcon.Copy => "copy",
        HudIcon.Text => "text",
        HudIcon.Warning => "warning",
        HudIcon.Done => "check-circle",
        _ => null,
    };

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var work = SystemParameters.WorkArea;
        Left = work.X + (work.Width - ActualWidth) / 2;
        Top = work.Bottom - ActualHeight - 80;

        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        timer.Tick += (_, _) => { timer.Stop(); Close(); };
        timer.Start();
    }
}

/// <summary>Shows transient HUD toasts.</summary>
public static class HudController
{
    public static void Show(string message, HudIcon icon = HudIcon.None) => new HudWindow(message, icon).Show();
}
