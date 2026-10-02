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
        Controls.WindowPlacement.CentreUnderPointer(this);
        Controls.WindowThemer.ApplyDark(this);
        BuildShortcuts(bindings);
        // The tray icon is outside any window the tour can point into, so its step points at the line that says
        // where the app lives (review round 1 #18 — the step was always skipped for want of an anchor).
        TourAnchors.Set(TrayBlurb, "menuBar.icon");
        InfoSlot.Content = new InfoButton(TourId.Welcome);
        SetAsking(askQuestion);
        ContentRendered += (_, _) => TourEvents.SurfaceShown(TourSurface.Welcome, this);
    }

    /// <summary>
    /// The shortcut grid (review O1–O2): the live bindings in tray-menu order (<see cref="HotkeyCheatSheet"/>), keys
    /// right-aligned against left-aligned descriptions. Tour anchors (v3 §7.6): <c>welcome.shortcuts</c> is a
    /// transparent border spanning just the bound screenshot-capture rows; <c>welcome.captureArea</c> is Capture
    /// Area's keys label.
    /// </summary>
    private void BuildShortcuts(HotkeyBindings bindings)
    {
        var rows = HotkeyCheatSheet.Rows(bindings);
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(16) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (int r = 0; r < rows.Count; r++)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var keys = new TextBlock
            {
                Text = rows[r].Keys,
                FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"), FontWeight = FontWeights.SemiBold,
                Foreground = (System.Windows.Media.Brush)FindResource("Theme.TextBrush"),
                HorizontalAlignment = System.Windows.HorizontalAlignment.Right, Margin = new Thickness(0, 3, 0, 3),
            };
            var text = new TextBlock
            {
                Text = rows[r].Description, Margin = new Thickness(0, 3, 0, 3),
                Foreground = (System.Windows.Media.Brush)FindResource("Theme.SecondaryTextBrush"),
            };
            Grid.SetRow(keys, r);
            Grid.SetRow(text, r);
            Grid.SetColumn(text, 2);
            grid.Children.Add(keys);
            grid.Children.Add(text);
            if (rows[r].Action == HotkeyAction.CaptureArea) TourAnchors.Set(keys, "welcome.captureArea");
        }
        int first = rows.ToList().FindIndex(x => x.IsScreenshotCapture), last = rows.ToList().FindLastIndex(x => x.IsScreenshotCapture);
        if (first >= 0)
        {
            var outline = new Border { Background = System.Windows.Media.Brushes.Transparent, IsHitTestVisible = false };
            Grid.SetRow(outline, first);
            Grid.SetRowSpan(outline, last - first + 1);
            Grid.SetColumnSpan(outline, 3);
            grid.Children.Add(outline);
            TourAnchors.Set(outline, "welcome.shortcuts");
        }
        grid.HorizontalAlignment = System.Windows.HorizontalAlignment.Center;
        ShortcutRows.Children.Add(grid);
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
        // One page size (§4.7 O2, round 3 #11): the window keeps its height as the question goes, instead of jumping
        // shorter just as the tour starts pointing into it; the content centres in the space.
        SizeToContent = SizeToContent.Manual;
        SetAsking(false);
        UpdateLayout(); // re-render first, so the tour's anchors are the final views
        Answered?.Invoke(true);
    }

    private void NoThanks_Click(object sender, RoutedEventArgs e) => Close();

    /// <summary>Set when the app is quitting, so the window closing with it isn't taken as "No Thanks" — the
    /// question is asked again next launch (review round 2 #21).</summary>
    public static bool AppIsQuitting { get; set; }

    protected override void OnClosing(CancelEventArgs e)
    {
        base.OnClosing(e);
        if (!e.Cancel && _asking && !AppIsQuitting)
        {
            _asking = false;
            Answered?.Invoke(false);
        }
    }
}
