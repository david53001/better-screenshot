using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using BetterScreenshot.App.Controls;
using BetterScreenshot.Core;
using BetterScreenshot.Recording;
using Border = System.Windows.Controls.Border;
using Color = System.Windows.Media.Color;
using Ellipse = System.Windows.Shapes.Ellipse;
using FontFamily = System.Windows.Media.FontFamily;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Orientation = System.Windows.Controls.Orientation;
using Point = System.Windows.Point;
using VerticalAlignment = System.Windows.VerticalAlignment;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// The floating live-recording pill (Mac v3 A.2 + Part 5 <c>RecordingControlsController</c>): dot · timer · Mic ·
/// System audio · Camera · Switch… · Restart · Discard · Pause · Stop · chevron, collapsible to dot · timer · Pause ·
/// Stop · chevron. Non-activating (clicks never steal focus from the app being recorded), topmost, draggable by its
/// background, kept out of the video unless "Show recording controls in the video" is on. Hover hints show at once
/// in a <see cref="HintBubbleWindow"/> (tooltips come late or never while the app is inactive). What each control
/// does lives in <see cref="RecordingCoordinator"/>; this window only draws <see cref="PillState"/> and reports clicks.
/// </summary>
public sealed class RecordingPillWindow : Window
{
    private const double ShadowPad = 14;
    private const double ButtonHeight = 28;
    private const double IconButtonWidth = 28;
    private const double LabelPadding = 8;
    private const double LabelIconSize = 15;
    private const double LabelIconGap = 5;
    private const double ConfirmPadding = 10;
    private const double PairSpacing = 2;

    private static readonly FontFamily UiFont = new("Segoe UI Variable Text, Segoe UI");
    private static readonly SolidColorBrush White = Frozen(Color.FromRgb(0xFF, 0xFF, 0xFF));
    private static readonly SolidColorBrush White60 = Frozen(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF));
    private static readonly SolidColorBrush White55 = Frozen(Color.FromArgb(0x8C, 0xFF, 0xFF, 0xFF));
    private static readonly SolidColorBrush White30 = Frozen(Color.FromArgb(0x4D, 0xFF, 0xFF, 0xFF));
    private static readonly SolidColorBrush Hover = Frozen(Color.FromArgb(0x1F, 0xFF, 0xFF, 0xFF));
    private static readonly SolidColorBrush Red = Frozen(Color.FromRgb(0xFF, 0x45, 0x3A));       // systemRed (dark)
    private static readonly SolidColorBrush RedChip = Frozen(Color.FromArgb(0xD9, 0xFF, 0x45, 0x3A)); // 85 %
    private static readonly SolidColorBrush RedHover = Frozen(Color.FromArgb(0xE0, 0xFF, 0x6A, 0x61)); // fill → 15 % white
    private static readonly SolidColorBrush Ring = Frozen(Color.FromArgb(0x80, 0xFF, 0xFF, 0xFF));
    private static readonly SolidColorBrush Gray = Frozen(Color.FromRgb(0x8E, 0x8E, 0x93));      // systemGray
    private static readonly SolidColorBrush SeparatorBrush = Frozen(Color.FromArgb(0x29, 0xFF, 0xFF, 0xFF));

    private readonly Border _capsule;
    private readonly StackPanel _row;
    private readonly Dictionary<PillItemId, Border> _buttons = new();
    private readonly Dictionary<PillItemId, double> _widths = new();
    private readonly Ellipse _dot = new() { Width = 10, Height = 10 };
    private readonly TextBlock _timer = new();
    private readonly TextBlock _pausedLabel = new() { Text = "Paused" };
    private readonly Border _sepAudio = Separator(), _sepSwitch = Separator(), _sepActions = Separator();
    private readonly HintBubbleWindow _hint;
    private readonly bool _excludeFromCapture;
    private readonly Rect _work;
    private PillState _state = new();
    private PillItemId? _hovered;
    private Point? _bottomRight; // capsule's bottom-right corner (DIPs) — kept fixed when the width changes
    private bool _dragging;

    /// <summary>A control was clicked (enabled ones only).</summary>
    public event Action<PillItemId>? ItemClicked;

    /// <summary>The user dragged the pill: the capsule's new bottom-right corner (DIPs, top-left origin).</summary>
    public event Action<PxPoint>? Moved;

    public RecordingPillWindow(Rect workArea, PxPoint? savedBottomRight, bool excludeFromCapture)
    {
        _work = workArea;
        _excludeFromCapture = excludeFromCapture;
        _hint = new HintBubbleWindow(excludeFromCapture);
        if (savedBottomRight is { } p && workArea.Contains(new Point(p.X - 1, p.Y - 1))) _bottomRight = new Point(p.X, p.Y);

        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = System.Windows.Media.Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        Focusable = false;
        SizeToContent = SizeToContent.WidthAndHeight;
        Title = "Recording controls";

        _timer.FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");
        _timer.FontSize = 14;
        _timer.FontWeight = FontWeights.SemiBold;
        _timer.Typography.NumeralAlignment = FontNumeralAlignment.Tabular;
        _pausedLabel.FontFamily = UiFont;
        _pausedLabel.FontSize = 10;
        _pausedLabel.FontWeight = FontWeights.SemiBold;
        _pausedLabel.Foreground = White;

        _row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(14, 0, 6, 0) };
        _capsule = new Border
        {
            Height = RecordingPillLayout.CapsuleHeight,
            CornerRadius = new CornerRadius(20),
            // The shared dark HUD + black 40 % tint (keeps white text readable on bright backdrops) + white 10 % border.
            Background = Frozen(Color.FromArgb(0xF2, 0x17, 0x17, 0x19)),
            BorderBrush = Frozen(Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(1),
            Child = _row,
            Margin = new Thickness(ShadowPad),
            Effect = new DropShadowEffect { BlurRadius = 16, ShadowDepth = 3, Direction = 270, Opacity = 0.45, Color = Colors.Black },
        };
        _capsule.MouseLeftButtonDown += OnCapsuleMouseDown;
        Content = _capsule;

        BuildRow();
        SourceInitialized += (_, _) =>
        {
            FloatingPanel.MakeNonActivating(this);
            if (excludeFromCapture) FloatingPanel.ExcludeFromCapture(this, true);
        };
        SizeChanged += (_, _) => Place();
        Closed += (_, _) => _hint.Close();
    }

    /// <summary>Redraws every control from <paramref name="state"/> (cheap — called on each timer tick).</summary>
    public void Apply(PillState state)
    {
        _state = state;
        _dot.Fill = RecordingPillModel.DotIsRed(state) ? Red : Gray;
        _timer.Text = RecordingPillModel.TimerText(state);
        _timer.Foreground = RecordingPillModel.TimerIsDim(state) ? White60 : White;
        _pausedLabel.Visibility = RecordingPillModel.ShowsPausedLabel(state) ? Visibility.Visible : Visibility.Collapsed;

        bool expanded = !state.Collapsed;
        _sepAudio.Visibility = _sepActions.Visibility = expanded ? Visibility.Visible : Visibility.Collapsed;
        _sepSwitch.Visibility = RecordingPillModel.ShowsSwitchGroup(state) ? Visibility.Visible : Visibility.Collapsed;

        foreach (var item in RecordingPillModel.Items(state)) Render(item);
        if (_hovered is { } h) ShowHint(h);
    }

    /// <summary>Positions the window (first show: bottom-centre; later: keep the bottom-right corner) — clamped inside the work area.</summary>
    private void Place()
    {
        if (_dragging || ActualWidth <= 0) return;
        double w = ActualWidth - 2 * ShadowPad, hgt = RecordingPillLayout.CapsuleHeight;
        var size = new PxSize(w, hgt);
        var work = new PxRect(_work.X, _work.Y, _work.Width, _work.Height);
        var frame = _bottomRight is { } br
            ? RecordingPillLayout.FromBottomRight(new PxPoint(br.X, br.Y), size)
            : RecordingPillLayout.DefaultFrame(size, work);
        frame = RecordingPillLayout.ClampInside(frame, work);
        _bottomRight = new Point(frame.Right, frame.Bottom);
        Left = frame.X - ShadowPad;
        Top = frame.Y - ShadowPad;
    }

    /// <summary>The capsule's on-screen rectangle (DIPs).</summary>
    private PxRect CapsuleFrame() => new(Left + ShadowPad, Top + ShadowPad, ActualWidth - 2 * ShadowPad, RecordingPillLayout.CapsuleHeight);

    // ------------------------------------------------------------------ build

    private void BuildRow()
    {
        double MeasureLabel(string s, FontWeight weight) => Measure(s, 12, weight);
        double Labelled(params string[] labels) =>
            Math.Ceiling(LabelPadding * 2 + LabelIconSize + LabelIconGap + labels.Max(l => MeasureLabel(l, FontWeights.Medium)));

        _widths[PillItemId.Mic] = Labelled("Mic");
        _widths[PillItemId.SystemAudio] = Labelled("System audio");
        _widths[PillItemId.Camera] = Labelled("Camera");
        _widths[PillItemId.Switch] = Labelled("Switch Window…", "Switch Area…");
        double pair = RecordingPillLayout.ConfirmPairButtonWidth(
            new[] { "Restart?", "Discard?" }.Select(t => MeasureLabel(t, FontWeights.SemiBold) + 2 * ConfirmPadding), PairSpacing, IconButtonWidth);
        _widths[PillItemId.Restart] = _widths[PillItemId.Discard] = pair;
        _widths[PillItemId.PauseResume] = _widths[PillItemId.Stop] = IconButtonWidth;
        _widths[PillItemId.Chevron] = 20;

        _dot.Margin = new Thickness(0, 0, 8, 0);
        _dot.VerticalAlignment = VerticalAlignment.Center;
        _row.Children.Add(_dot);
        var timerColumn = new StackPanel { Width = 46, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 10, 0) };
        timerColumn.Children.Add(_pausedLabel);
        timerColumn.Children.Add(_timer);
        _row.Children.Add(timerColumn);

        _row.Children.Add(_sepAudio);
        Add(PillItemId.Mic, 2);
        Add(PillItemId.SystemAudio, 2);
        Add(PillItemId.Camera, 10);
        _row.Children.Add(_sepSwitch);
        Add(PillItemId.Switch, 10);
        _row.Children.Add(_sepActions);
        Add(PillItemId.Restart, PairSpacing);
        Add(PillItemId.Discard, 2);
        Add(PillItemId.PauseResume, 2);
        Add(PillItemId.Stop, 6);
        Add(PillItemId.Chevron, 0);

        void Add(PillItemId id, double spacingAfter)
        {
            var b = new Border
            {
                Height = ButtonHeight,
                Width = _widths[id],
                CornerRadius = new CornerRadius(7),
                Margin = new Thickness(0, 0, spacingAfter, 0),
                Background = System.Windows.Media.Brushes.Transparent,
                VerticalAlignment = VerticalAlignment.Center,
                Tag = id,
            };
            b.MouseEnter += (_, _) => { _hovered = id; Render(RecordingPillModel.Item(_state, id)); ShowHint(id); };
            b.MouseLeave += (_, _) => { if (_hovered == id) _hovered = null; Render(RecordingPillModel.Item(_state, id)); _hint.Hide(); };
            b.MouseLeftButtonDown += (_, e) => e.Handled = true; // not a drag
            b.MouseLeftButtonUp += (_, e) =>
            {
                e.Handled = true;
                if (b.IsMouseOver && RecordingPillModel.Item(_state, id).Enabled) ItemClicked?.Invoke(id);
            };
            System.Windows.Automation.AutomationProperties.SetAutomationId(b, "pill-" + id);
            _buttons[id] = b;
            _row.Children.Add(b);
        }
    }

    private static Border Separator() => new()
    {
        Width = 1,
        Height = 18,
        Background = SeparatorBrush,
        Margin = new Thickness(0, 0, 10, 0),
        VerticalAlignment = VerticalAlignment.Center,
    };

    // ------------------------------------------------------------------ render

    private readonly Dictionary<PillItemId, (PillItem Item, bool Hover)> _rendered = new();

    private void Render(PillItem item)
    {
        var b = _buttons[item.Id];
        bool isHovered = _hovered == item.Id;
        if (_rendered.TryGetValue(item.Id, out var last) && last.Item == item && last.Hover == isHovered) return;
        _rendered[item.Id] = (item, isHovered);
        // The confirm capsule takes the Restart + Discard slot so the pill keeps its width.
        double slot = RecordingPillLayout.ConfirmSlotWidth(_widths[PillItemId.Restart], PairSpacing);
        bool confirm = item.Look == PillLook.ConfirmCapsule;
        b.Visibility = item.Visible ? Visibility.Visible : Visibility.Collapsed;
        b.Width = confirm ? slot : _widths[item.Id];
        if (item.Id == PillItemId.Restart) b.Margin = new Thickness(0, 0, confirm ? 2 : PairSpacing, 0);

        bool hover = _hovered == item.Id && item.Enabled;
        var fg = item.Look switch
        {
            PillLook.Dim => White60,
            PillLook.Disabled => White30,
            PillLook.RedGlyph => Red,
            PillLook.Chevron => White55,
            _ => White,
        };
        b.Background = item.Look switch
        {
            PillLook.RedChip => hover ? RedHover : RedChip,
            PillLook.ConfirmCapsule => hover ? RedHover : Red,
            _ => hover ? Hover : System.Windows.Media.Brushes.Transparent,
        };
        bool filled = item.Look is PillLook.RedChip or PillLook.ConfirmCapsule;
        b.BorderBrush = filled ? Ring : null;
        b.BorderThickness = new Thickness(filled ? 1 : 0);
        if (confirm) b.CornerRadius = new CornerRadius(ButtonHeight / 2);
        else b.CornerRadius = new CornerRadius(7);
        System.Windows.Automation.AutomationProperties.SetName(b, item.Label ?? item.Hint);

        if (confirm)
        {
            b.Child = new TextBlock
            {
                Text = item.Label, FontFamily = UiFont, FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = White,
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            };
            return;
        }
        double iconSize = item.Label is null ? (item.Id == PillItemId.Chevron ? 13 : 17) : LabelIconSize;
        var icon = new IconPresenter { IconKey = item.Icon, Brush = fg, Width = iconSize, Height = iconSize };
        if (item.Label is null)
        {
            icon.HorizontalAlignment = HorizontalAlignment.Center;
            icon.VerticalAlignment = VerticalAlignment.Center;
            b.Child = icon;
            return;
        }
        var sp = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        icon.Margin = new Thickness(0, 0, LabelIconGap, 0);
        sp.Children.Add(icon);
        sp.Children.Add(new TextBlock
        {
            Text = item.Label, FontFamily = UiFont, FontSize = 12, FontWeight = FontWeights.Medium, Foreground = fg,
            VerticalAlignment = VerticalAlignment.Center,
        });
        b.Child = sp;
    }

    private void ShowHint(PillItemId id)
    {
        if (!IsVisible || !_buttons.TryGetValue(id, out var b) || b.Visibility != Visibility.Visible) return;
        string text = RecordingPillModel.Item(_state, id).Hint;
        var centre = b.TranslatePoint(new Point(b.ActualWidth / 2, 0), this);
        _hint.ShowAt(text, Left + centre.X, CapsuleFrame(), new PxRect(_work.X, _work.Y, _work.Width, _work.Height));
    }

    // ------------------------------------------------------------------ drag

    private void OnCapsuleMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.Handled) return;
        _hint.Hide();
        _dragging = true;
        try { DragMove(); } catch { /* released mid-call */ }
        _dragging = false;
        var frame = RecordingPillLayout.ClampInside(CapsuleFrame(), new PxRect(_work.X, _work.Y, _work.Width, _work.Height));
        Left = frame.X - ShadowPad;
        Top = frame.Y - ShadowPad;
        _bottomRight = new Point(frame.Right, frame.Bottom);
        Moved?.Invoke(new PxPoint(frame.Right, frame.Bottom));
    }

    // ------------------------------------------------------------------ helpers

    private static double Measure(string text, double size, FontWeight weight)
    {
        var ft = new FormattedText(text, CultureInfo.CurrentUICulture, System.Windows.FlowDirection.LeftToRight,
            new Typeface(UiFont, FontStyles.Normal, weight, FontStretches.Normal), size, White, 1.0);
        return ft.WidthIncludingTrailingWhitespace;
    }

    private static SolidColorBrush Frozen(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }
}

/// <summary>
/// The pill's instant hover hint (Mac Part 5 bubble): dark HUD, radius 7, height 24, 12 pt medium white, 10 pt
/// side padding, 6 above the capsule (below when there's no room), kept 8 inside the work area and tail-truncated
/// if wider. Its own click-through, non-activating window, excluded from capture together with the pill.
/// </summary>
public sealed class HintBubbleWindow : Window
{
    private readonly TextBlock _text;
    private readonly Border _box;

    public HintBubbleWindow(bool excludeFromCapture)
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = System.Windows.Media.Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        IsHitTestVisible = false;
        Focusable = false;
        Title = "Recording hint";
        _text = new TextBlock
        {
            FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"),
            FontSize = 12,
            FontWeight = FontWeights.Medium,
            Foreground = System.Windows.Media.Brushes.White,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        _box = new Border
        {
            Height = RecordingPillLayout.HintHeight,
            CornerRadius = new CornerRadius(7),
            Background = new SolidColorBrush(Color.FromArgb(0xF2, 0x17, 0x17, 0x19)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(10, 0, 10, 0),
            Child = _text,
        };
        Content = _box;
        SourceInitialized += (_, _) =>
        {
            FloatingPanel.MakeNonActivating(this, clickThrough: true);
            if (excludeFromCapture) FloatingPanel.ExcludeFromCapture(this, true);
        };
    }

    public void ShowAt(string text, double anchorX, PxRect capsule, PxRect work)
    {
        _text.Text = text;
        var ft = new FormattedText(text, CultureInfo.CurrentUICulture, System.Windows.FlowDirection.LeftToRight,
            new Typeface(_text.FontFamily, FontStyles.Normal, FontWeights.Medium, FontStretches.Normal), 12,
            System.Windows.Media.Brushes.White, 1.0);
        double natural = Math.Ceiling(ft.WidthIncludingTrailingWhitespace) + 22;
        var frame = RecordingPillLayout.HintFrame(new PxSize(natural, RecordingPillLayout.HintHeight), anchorX, capsule, work);
        Width = frame.Width;
        Height = frame.Height;
        Left = frame.X;
        Top = frame.Y;
        if (!IsVisible) Show();
    }
}
