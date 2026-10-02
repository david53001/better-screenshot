using System.Windows;
using System.Windows.Threading;

namespace BetterScreenshot.App.Overlays;

/// <summary>What a toast's leading icon says (review X5).</summary>
public enum HudIcon { None, Copy, Text, Warning, Done }

/// <summary>A transient bottom-center toast (auto-dismisses after 1.5s), e.g. the Capture-Text result message.</summary>
public partial class HudWindow : Window
{
    private readonly bool _autoClose;

    public HudWindow(string message, HudIcon icon = HudIcon.None, bool autoClose = true)
    {
        _autoClose = autoClose;
        InitializeComponent();
        Message.Text = message;
        if (IconKey(icon) is { } key)
        {
            IconGlyph.IconKey = key;
            IconGlyph.Visibility = Visibility.Visible;
        }
        Loaded += OnLoaded;
        // Toasts are the app talking, not content: keep them out of screenshots and recordings (round 3 #6 — a take
        // started during a GIF conversion recorded its progress toast).
        SourceInitialized += (_, _) => Controls.FloatingPanel.ExcludeFromCapture(this, true);
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
        SizeChanged += (_, _) => Left = work.X + (work.Width - ActualWidth) / 2; // stays centred as the text changes
        if (!_autoClose) return;

        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        timer.Tick += (_, _) => { timer.Stop(); Close(); };
        timer.Start();
    }
}

/// <summary>Shows transient HUD toasts.</summary>
public static class HudController
{
    public static void Show(string message, HudIcon icon = HudIcon.None) => new HudWindow(message, icon).Show();

    /// <summary>A toast that stays up until closed, for a long job (GIF conversion) whose text updates as it runs.</summary>
    public static HudProgress ShowProgress(string message)
    {
        var w = new HudWindow(message, HudIcon.None, autoClose: false);
        w.Show();
        return new HudProgress(w);
    }
}

/// <summary>A persistent toast from <see cref="HudController.ShowProgress"/>.</summary>
public sealed class HudProgress
{
    private readonly HudWindow _window;
    internal HudProgress(HudWindow window) => _window = window;
    /// <summary>Safe from any thread (ffmpeg progress arrives on the thread pool).</summary>
    public void Update(string message) => _window.Dispatcher.BeginInvoke(() => _window.Message.Text = message);
    public void Close() => _window.Close();
}
