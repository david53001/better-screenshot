using System.Collections.Specialized;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using BetterScreenshot.App.Controls;
using Brush = System.Windows.Media.Brush;
using Button = System.Windows.Controls.Button;
using DataObject = System.Windows.DataObject;
using DragDrop = System.Windows.DragDrop;
using DragDropEffects = System.Windows.DragDropEffects;
using MouseButtonState = System.Windows.Input.MouseButtonState;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Point = System.Windows.Point;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// Post-capture floating card. The captured image fills the whole rounded block edge-to-edge; the action
/// buttons overlay the bottom of the image on an auto-contrasting scrim (see <see cref="ContrastPalette"/>).
/// Drag the card to export the file.
/// </summary>
public partial class QuickAccessWindow : Window
{
    private const double ContentWidth = 210;      // image (card) width in DIPs; height derives from the image aspect
    private const double MinContentHeight = 150;  // widest card ~= 210/150 = 1.40:1 — a mild rectangle, not a 16:9 sliver,
                                                  // so the button row hugs the width instead of floating in bare image
    private const double MaxContentHeight = 280;
    private const double CornerRadiusPx = 14;     // must match the Hairline CornerRadius in the XAML
    private const double ShadowMargin = 6;        // must match the shadow-host Border Margin in the XAML
    private const double ButtonWidth = 32, ButtonHeight = 30, ButtonGap = 2, RowBottomMargin = 9;

    private readonly string? _dragFile;
    private readonly int _autoDismissSeconds;
    private DispatcherTimer? _dismissTimer;
    private Point _dragStart;
    private bool _done;

    public event Action<DismissReason>? Dismissed;

    public QuickAccessWindow(BitmapSource image, QuickAccessKind kind, QuickAccessActions actions, string? dragFile,
        int autoDismissSeconds = 0)
    {
        InitializeComponent();
        Thumb.Source = image;
        _dragFile = dragFile;
        _autoDismissSeconds = autoDismissSeconds;

        // Size the card to the image so it fills the whole rounded block with no letterbox. Extreme aspect
        // ratios clamp; UniformToFill then crops the long side to keep the image full-bleed.
        double aspect = image.PixelHeight > 0 ? (double)image.PixelWidth / image.PixelHeight : 16.0 / 9.0;
        double contentHeight = Math.Clamp(ContentWidth / aspect, MinContentHeight, MaxContentHeight);
        Width = ContentWidth + 2 * ShadowMargin;
        Height = contentHeight + 2 * ShadowMargin;

        Root.Clip = RoundedClip(ContentWidth, contentHeight);
        Root.SizeChanged += (_, _) => Root.Clip = RoundedClip(Root.ActualWidth, Root.ActualHeight);

        // Guaranteed contrast (Mac v2.9.0): lay the button row out FIRST so the sampled rect is the row's final
        // on-screen frame, sample the pixels aspect-fill actually draws there at device resolution, then hold the
        // planned scrim alpha flat from the row's top edge to the card's bottom.
        var specs = kind == QuickAccessKind.Screenshot
            ? new (string Key, string Tip, Action Click)[]
            {
                ("copy", "Copy", actions.OnCopy),
                ("edit", "Edit", () => { actions.OnEdit(); Dismiss(DismissReason.ActionTaken); }),
                ("pin", "Pin to screen", () => { actions.OnPin(); Dismiss(DismissReason.ActionTaken); }),
                ("save", "Save", () => { actions.OnSave(); Dismiss(DismissReason.ActionTaken); }),
                ("close", "Close", () => Dismiss(DismissReason.Closed)),
            }
            : new (string Key, string Tip, Action Click)[]
            {
                ("copy", "Copy file", actions.OnCopy),
                ("play", "Open", () => { actions.OnOpen(); Dismiss(DismissReason.ActionTaken); }),
                ("folder", "Show in folder", () => { actions.OnReveal(); Dismiss(DismissReason.ActionTaken); }),
                ("close", "Close", () => Dismiss(DismissReason.Closed)),
            };
        double rowWidth = specs.Length * (ButtonWidth + 2 * ButtonGap);
        double rowTop = contentHeight - RowBottomMargin - ButtonHeight;
        var rowRect = new Rect((ContentWidth - rowWidth) / 2, rowTop, rowWidth, ButtonHeight);
        double scrimHeight = contentHeight - rowTop + ContrastPalette.FadeAbove;
        Scrim.Height = scrimHeight;
        ButtonRow.Margin = new Thickness(0, 0, 0, RowBottomMargin);
        var palette = ContrastPalette.ForButtonRow(image, new System.Windows.Size(ContentWidth, contentHeight), rowRect,
            VisualTreeHelper.GetDpi(this).DpiScaleX, scrimHeight);
        Scrim.Fill = palette.Scrim;
        Resources["QA.HoverBrush"] = palette.Hover;
        Resources["QA.PressedBrush"] = palette.Pressed;

        foreach (var (key, tip, click) in specs)
            ButtonRow.Children.Add(MakeButton(key, tip, palette.Glyph, click));

        DragSurface.MouseLeftButtonDown += (_, e) => _dragStart = e.GetPosition(this);
        DragSurface.MouseMove += DragSurface_MouseMove;

        Loaded += (_, _) => StartAutoDismiss();
    }

    /// <summary>Auto-dismiss the card after the configured number of seconds (0 = never — the card stays until
    /// the user acts). Hovering the card pauses the countdown, and moving the pointer away restarts it, so a card
    /// you are actively using never vanishes out from under you. An auto-dismissed card is treated as
    /// <see cref="DismissReason.Closed"/> so it remains restorable via "Restore Recently Closed".</summary>
    private void StartAutoDismiss()
    {
        if (_autoDismissSeconds <= 0 || _done) return;

        _dismissTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(_autoDismissSeconds) };
        _dismissTimer.Tick += (_, _) =>
        {
            _dismissTimer!.Stop();
            Dismiss(DismissReason.Closed);
        };

        MouseEnter += (_, _) => _dismissTimer?.Stop();
        MouseLeave += (_, _) =>
        {
            if (_done) return;
            _dismissTimer?.Stop();
            _dismissTimer?.Start(); // restart the full countdown once the pointer leaves
        };

        if (!IsMouseOver) _dismissTimer.Start();
    }

    public void MoveTo(double left, double top)
    {
        Left = left;
        Top = top;
    }

    public void ForceDismiss(DismissReason reason) => Dismiss(reason);

    private static RectangleGeometry RoundedClip(double w, double h) =>
        new(new Rect(0, 0, w, h), CornerRadiusPx, CornerRadiusPx);

    private void DragSurface_MouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || _dragFile is null) return;
        var p = e.GetPosition(this);
        if (Math.Abs(p.X - _dragStart.X) < 4 && Math.Abs(p.Y - _dragStart.Y) < 4) return;

        var data = new DataObject();
        data.SetFileDropList(new StringCollection { _dragFile });
        var result = DragDrop.DoDragDrop(DragSurface, data, DragDropEffects.Copy);
        if (result != DragDropEffects.None) Dismiss(DismissReason.ActionTaken); // Esc-cancel keeps the card
    }

    private void Dismiss(DismissReason reason)
    {
        if (_done) return;
        _done = true;
        _dismissTimer?.Stop();
        Dismissed?.Invoke(reason);
        Close();
    }

    private Button MakeButton(string iconKey, string tip, Brush glyph, Action onClick)
    {
        var button = new Button
        {
            Content = new IconPresenter { IconKey = iconKey, Brush = glyph, Width = 17, Height = 17 },
            Width = ButtonWidth,
            Height = ButtonHeight,
            Margin = new Thickness(ButtonGap, 0, ButtonGap, 0),
            ToolTip = tip,
            Style = (Style)FindResource("QA.IconButton"),
        };
        System.Windows.Automation.AutomationProperties.SetName(button, tip); // accessible name for an icon-only button
        button.Click += (_, _) => onClick();
        return button;
    }
}
