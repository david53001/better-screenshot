using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using BetterScreenshot.App.Tours;
using BetterScreenshot.Capture;
using BetterScreenshot.Tours;
using FontFamily = System.Windows.Media.FontFamily;

namespace BetterScreenshot.App.Onboarding;

/// <summary>
/// First-run welcome: branding, a one-line blurb and the shortcut grid (the user's current bindings). For a new user
/// who hasn't answered, the "Want a quick tour?" question (Mac v3 §7.1 Step 2) replaces Start Capturing; closing
/// the window while it shows counts as No Thanks.
/// </summary>
public partial class WelcomeWindow : Window
{
    /// <summary>The answer: true = Show Me Around, false = No Thanks (or closed while asked).</summary>
    public event Action<bool>? Answered;

    private bool _asking;

    public WelcomeWindow() : this(HotkeyBindings.Defaults(), askQuestion: false) { }

    public WelcomeWindow(HotkeyBindings bindings, bool askQuestion)
    {
        InitializeComponent();
        Controls.WindowThemer.ApplyDark(this);
        BuildShortcuts(bindings);
        InfoSlot.Content = new InfoButton(TourId.Welcome);
        SetAsking(askQuestion);
        ContentRendered += (_, _) => TourEvents.SurfaceShown(TourSurface.Welcome, this);
    }

    private void BuildShortcuts(HotkeyBindings bindings)
    {
        var rows = new (HotkeyAction Action, string Label, string? Anchor)[]
        {
            (HotkeyAction.CaptureArea, "Capture an area", "welcome.captureArea"),
            (HotkeyAction.Record, "Record the screen", null),
            (HotkeyAction.CaptureFullscreen, "Capture the full screen", null),
            (HotkeyAction.CaptureWindow, "Capture a window", null),
        };
        foreach (var (action, label, anchor) in rows)
        {
            var grid = new Grid { Margin = new Thickness(0, 3, 0, 3) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) });
            grid.ColumnDefinitions.Add(new ColumnDefinition());
            var keys = new TextBlock
            {
                Text = bindings.Combo(action)?.DisplayString ?? "—",
                FontFamily = new FontFamily("Cascadia Mono, Consolas"), FontWeight = FontWeights.SemiBold,
                Foreground = (System.Windows.Media.Brush)FindResource("Theme.TextBrush"),
            };
            var text = new TextBlock { Text = label, Foreground = (System.Windows.Media.Brush)FindResource("Theme.SecondaryTextBrush") };
            Grid.SetColumn(text, 1);
            grid.Children.Add(keys);
            grid.Children.Add(text);
            if (anchor is not null) TourAnchors.Set(grid, anchor);
            ShortcutRows.Children.Add(grid);
        }
    }

    private void SetAsking(bool asking)
    {
        _asking = asking;
        QuestionBlock.Visibility = asking ? Visibility.Visible : Visibility.Collapsed;
        StartButton.Visibility = asking ? Visibility.Collapsed : Visibility.Visible;
        StartButton.IsDefault = !asking;
        ShowMeButton.IsDefault = asking;
        NoThanksButton.IsCancel = asking;
    }

    private void Start_Click(object sender, RoutedEventArgs e) => Close();

    private void ShowMe_Click(object sender, RoutedEventArgs e)
    {
        SetAsking(false);
        UpdateLayout(); // re-render first, so the tour's anchors are the final views
        Answered?.Invoke(true);
    }

    private void NoThanks_Click(object sender, RoutedEventArgs e) => Close();

    protected override void OnClosing(CancelEventArgs e)
    {
        base.OnClosing(e);
        if (!e.Cancel && _asking)
        {
            _asking = false;
            Answered?.Invoke(false);
        }
    }
}
