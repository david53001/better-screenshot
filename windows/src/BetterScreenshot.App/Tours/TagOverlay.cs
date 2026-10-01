using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using BetterScreenshot.App.Controls;
using BetterScreenshot.Tours;
using Border = System.Windows.Controls.Border;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using FontFamily = System.Windows.Media.FontFamily;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using Orientation = System.Windows.Controls.Orientation;
using Point = System.Windows.Point;
using Rectangle = System.Windows.Shapes.Rectangle;
using Size = System.Windows.Size;
using VerticalAlignment = System.Windows.VerticalAlignment;

namespace BetterScreenshot.App.Tours;

/// <summary>
/// The tour tag (Mac v3 §7.3): a red outline box around the step's control, a dim over the rest of the host window, a
/// leader line, and the red bubble with title, body, "n of m", Skip Tour and Next/Done/Skip Step. Two borderless
/// windows owned by the host (decor = click-through dim/box/line; tag = the bubble, takes clicks but never activates
/// or takes focus), both kept out of screenshots and recordings. Follows the host and the control every 100 ms.
/// </summary>
public sealed class TagOverlay : ITourTagPresenter
{
    public static readonly Color TourRed = Color.FromRgb(TagColors.Red.R, TagColors.Red.G, TagColors.Red.B);
    private static readonly Brush RedBrush = Frozen(new SolidColorBrush(TourRed));
    private static readonly Brush White90 = Frozen(new SolidColorBrush(Color.FromArgb(0xE6, 0xFF, 0xFF, 0xFF)));
    private static readonly FontFamily UiFont = new("Segoe UI Variable Text, Segoe UI");
    private const double ShadowMargin = 14;

    public Action? OnNext { get; set; }
    public Action? OnSkipStep { get; set; }
    public Action? OnSkipTour { get; set; }

    private Window? _host;
    private DecorWindow? _decor;
    private TagWindow? _tag;
    private readonly DispatcherTimer _follow;
    private TourStep? _step;
    private string _body = "";
    private int _number, _total;
    private bool _isLast;
    private bool _done;
    private string _lastLayoutKey = "";

    public TagOverlay()
    {
        _follow = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(100) };
        _follow.Tick += (_, _) => Layout(force: false);
    }

    public bool IsShowing => _step is not null;
    public bool IsDone => _done;
    /// <summary>For the 0.5 s check and the preview renderer: the tag's last placement (null while hidden).</summary>
    public TagPlacementResult? LastPlacement { get; private set; }

    public void Show(Window host, TourStep step, string body, int number, int total, bool isLast)
    {
        if (!ReferenceEquals(host, _host)) Detach();
        _host = host;
        _step = step;
        _body = body;
        _number = number;
        _total = total;
        _isLast = isLast;
        _done = false;
        Attach();
        _tag!.Build(step, body, number, total, isLast, done: false);
        Layout(force: true);
        Announce($"{step.Title}. {body} Step {number} of {total}.");
    }

    public void ShowCompleted()
    {
        if (_step is null || _tag is null) return;
        _done = true;
        _tag.Build(_step, _body, _number, _total, _isLast, done: true);
        Layout(force: true);
        Announce("Done");
    }

    public void UpdateProgress(int number, int total, bool isLast)
    {
        if (_step is null || _tag is null || _done || (number == _number && total == _total && isLast == _isLast)) return;
        _number = number;
        _total = total;
        _isLast = isLast;
        _tag.Build(_step, _body, number, total, isLast, done: false);
        Layout(force: true);
    }

    public void Hide()
    {
        _step = null;
        _done = false;
        _follow.Stop();
        _decor?.Hide();
        _tag?.Hide();
        LastPlacement = null;
    }

    /// <summary>Hides and forgets the host (its window closed).</summary>
    public void Detach()
    {
        Hide();
        if (_host is not null)
        {
            _host.PreviewKeyDown -= HostKeyDown;
            _host.LocationChanged -= HostMoved;
            _host.SizeChanged -= HostMoved;
            _host.StateChanged -= HostMoved;
        }
        try { _tag?.Close(); } catch (InvalidOperationException) { }
        try { _decor?.Close(); } catch (InvalidOperationException) { }
        _tag = null;
        _decor = null;
        _host = null;
    }

    private void Attach()
    {
        if (_host is null) return;
        if (_decor is null)
        {
            _host.PreviewKeyDown += HostKeyDown;
            _host.LocationChanged += HostMoved;
            _host.SizeChanged += HostMoved;
            _host.StateChanged += HostMoved;
            _decor = new DecorWindow();
            _tag = new TagWindow(this);
        }
        _follow.Start();
    }

    private void HostMoved(object? sender, EventArgs e) => Layout(force: true);

    private void HostKeyDown(object sender, KeyEventArgs e)
    {
        if (_step is null || _host is null) return;
        var key = e.Key switch { Key.Enter => TagKey.Enter, Key.Escape => TagKey.Escape, _ => TagKey.Other };
        if (key == TagKey.Other) return;
        var mods = Keyboard.Modifiers != ModifierKeys.None;
        var claims = _host as ITourHost;
        var action = TagKeys.Action(key, mods, e.IsRepeat, TourAnchors.IsEditable(Keyboard.FocusedElement), !_step.IsTry, _done,
            claims?.ClaimsTourEscape ?? false, claims?.ClaimsTourKeys ?? false);
        if (action == TagKeyAction.None) return;
        e.Handled = true;
        if (action == TagKeyAction.Next) OnNext?.Invoke();
        else OnSkipTour?.Invoke();
    }

    private void Layout(bool force)
    {
        if (_step is null || _host is null || _decor is null || _tag is null) return;
        var anchor = TourAnchors.Find(_host, _step.Anchor);
        var hostFrame = TourAnchors.WindowRect(_host);
        if (anchor is null || hostFrame is null || TourAnchors.ScreenRect(anchor) is not { } control)
        {
            _decor.Hide();
            _tag.Hide();
            _lastLayoutKey = "";
            return;
        }

        var shape = (_host as ITourHost)?.TourShape;
        var hostRect = shape?.Frame ?? hostFrame.Value;
        bool titled = _host.WindowStyle != WindowStyle.None;
        var work = WorkArea(control);
        var tagSize = _tag.BubbleSize;
        string key = $"{control}|{hostRect}|{tagSize}|{work}";
        if (!force && key == _lastLayoutKey && _decor.IsVisible) return;
        _lastLayoutKey = key;

        var keepOut = shape?.KeepOut ?? (titled ? (Rect?)null : hostRect);
        var input = new TagLayoutInput(
            ToTag(control), tagSize.Width, tagSize.Height, ToTag(work),
            Host: ToTag(hostRect),
            KeepOut: keepOut is { } k ? ToTag(k) : null,
            VerticalFirst: TourAnchors.ParentIsBar(anchor),
            Placement: _step.Placement);
        var placed = TagLayout.Place(input);
        LastPlacement = placed;

        double controlRadius = TourAnchors.CornerRadius(anchor);
        double boxRadius = controlRadius > 0 ? Math.Min(controlRadius + TagLayout.BoxGrow, placed.Box.Height / 2) : 6;
        double hostRadius = shape?.CornerRadius ?? (titled ? (Environment.OSVersion.Version.Build >= 22000 ? 8 : 0) : 12);
        _decor.Render(hostRect, hostRadius, ToRect(placed.Box), boxRadius, placed, ToRect(placed.Tag));

        // The tag window carries a shadow margin around the bubble.
        _tag.Place(placed.Tag.X - ShadowMargin, placed.Tag.Y - ShadowMargin);
        if (!_decor.IsVisible) ShowOwned(_decor, _host);
        if (!_tag.IsVisible) ShowOwned(_tag, _decor);
    }

    private static void ShowOwned(Window w, Window owner)
    {
        try
        {
            if (!ReferenceEquals(w.Owner, owner)) w.Owner = owner;
        }
        catch (InvalidOperationException) { }
        w.Show();
    }

    private Rect WorkArea(Rect control)
    {
        var src = PresentationSource.FromVisual(_host!);
        var toDevice = src?.CompositionTarget?.TransformToDevice ?? Matrix.Identity;
        var fromDevice = src?.CompositionTarget?.TransformFromDevice ?? Matrix.Identity;
        var c = toDevice.Transform(new Point(control.X + control.Width / 2, control.Y + control.Height / 2));
        var wa = System.Windows.Forms.Screen.FromPoint(new System.Drawing.Point((int)c.X, (int)c.Y)).WorkingArea;
        return new Rect(fromDevice.Transform(new Point(wa.Left, wa.Top)), fromDevice.Transform(new Point(wa.Right, wa.Bottom)));
    }

    private void Announce(string text)
    {
        if (_tag?.Bubble is not { } bubble) return;
        try
        {
            var peer = UIElementAutomationPeer.FromElement(bubble) ?? UIElementAutomationPeer.CreatePeerForElement(bubble);
            peer?.RaiseNotificationEvent(AutomationNotificationKind.Other, AutomationNotificationProcessing.ImportantMostRecent, text, "TourTag");
        }
        catch (Exception) { /* no screen reader listening */ }
    }

    /// <summary>Off-screen preview (<c>--render-previews</c>): a tag window built for one step, not shown.</summary>
    internal static Window PreviewTag(TourStep step, string body, int number, int total, bool isLast, bool done)
    {
        var w = new TagWindow(new TagOverlay());
        w.Build(step, body, number, total, isLast, done);
        w.Background = new SolidColorBrush(Color.FromRgb(0x2B, 0x2B, 0x2E)); // a dark host behind it, for the shot
        return w;
    }

    private static TagRect ToTag(Rect r) => new(r.X, r.Y, r.Width, r.Height);
    private static Rect ToRect(TagRect r) => new(r.X, r.Y, Math.Max(0, r.Width), Math.Max(0, r.Height));
    private static T Frozen<T>(T f) where T : Freezable { f.Freeze(); return f; }

    // ------------------------------------------------------------------ windows

    private static void MakeOverlayWindow(Window w)
    {
        w.WindowStyle = WindowStyle.None;
        w.AllowsTransparency = true;
        w.Background = Brushes.Transparent;
        w.ShowInTaskbar = false;
        w.ShowActivated = false;
        w.Focusable = false;
        w.ResizeMode = ResizeMode.NoResize;
        w.WindowStartupLocation = WindowStartupLocation.Manual;
    }

    /// <summary>The dim, the outline box and the leader line. Ignores the mouse entirely.</summary>
    private sealed class DecorWindow : Window
    {
        private readonly Canvas _canvas = new() { IsHitTestVisible = false };

        public DecorWindow()
        {
            MakeOverlayWindow(this);
            IsHitTestVisible = false;
            Content = _canvas;
            SourceInitialized += (_, _) =>
            {
                FloatingPanel.MakeNonActivating(this, clickThrough: true);
                FloatingPanel.ExcludeFromCapture(this, true);
            };
        }

        public void Render(Rect host, double hostRadius, Rect box, double boxRadius, TagPlacementResult placed, Rect tag)
        {
            var bounds = Rect.Union(Rect.Union(host, Grow(box, 3)), tag);
            bounds = Grow(bounds, 2);
            Left = bounds.X;
            Top = bounds.Y;
            Width = bounds.Width;
            Height = bounds.Height;
            Vector o = new(-bounds.X, -bounds.Y);
            _canvas.Children.Clear();

            // Dim: the host's rounded outline minus a hole at the box's outer edge. Every surface here is dark → 35 %.
            var outer = Grow(box, 2);
            var dim = new CombinedGeometry(GeometryCombineMode.Exclude,
                new RectangleGeometry(Offset(host, o), hostRadius, hostRadius),
                new RectangleGeometry(Offset(outer, o), boxRadius + 2, boxRadius + 2));
            _canvas.Children.Add(new Path { Data = dim, Fill = new SolidColorBrush(Color.FromArgb((byte)(0.35 * 255), 0, 0, 0)) });

            // Box: a 2-thick stroke drawn outside the box's edge (centre line 1 out).
            var stroke = Grow(box, 1);
            var r = new Rectangle
            {
                Width = stroke.Width, Height = stroke.Height, RadiusX = boxRadius + 1, RadiusY = boxRadius + 1,
                Stroke = RedBrush, StrokeThickness = 2,
            };
            Canvas.SetLeft(r, stroke.X + o.X);
            Canvas.SetTop(r, stroke.Y + o.Y);
            _canvas.Children.Add(r);

            if (placed.Leader is { } leader)
                _canvas.Children.Add(new Line
                {
                    X1 = leader.From.X + o.X, Y1 = leader.From.Y + o.Y, X2 = leader.To.X + o.X, Y2 = leader.To.Y + o.Y,
                    Stroke = RedBrush, StrokeThickness = 2, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
                });
        }

        private static Rect Grow(Rect r, double d) { r.Inflate(d, d); return r; }
        private static Rect Offset(Rect r, Vector v) { r.Offset(v); return r; }
    }

    /// <summary>The red bubble. Takes clicks, never activates or takes focus.</summary>
    private sealed class TagWindow : Window
    {
        private readonly TagOverlay _owner;
        private readonly Border _bubble;
        public Border Bubble => _bubble;
        public Size BubbleSize { get; private set; } = new(200, 80);

        public TagWindow(TagOverlay owner)
        {
            _owner = owner;
            MakeOverlayWindow(this);
            SizeToContent = SizeToContent.WidthAndHeight;
            _bubble = new Border
            {
                Background = RedBrush,
                CornerRadius = new CornerRadius(12),
                Padding = new Thickness(12, 10, 12, 10),
                Margin = new Thickness(ShadowMargin),
                Effect = new DropShadowEffect { BlurRadius = 12, ShadowDepth = 3, Direction = 270, Opacity = 0.35 },
                Focusable = false,
            };
            Content = _bubble;
            SourceInitialized += (_, _) =>
            {
                FloatingPanel.MakeNonActivating(this);
                FloatingPanel.ExcludeFromCapture(this, true);
            };
        }

        public void Place(double x, double y)
        {
            Left = Math.Round(x);
            Top = Math.Round(y);
        }

        public void Build(TourStep step, string body, int number, int total, bool isLast, bool done)
        {
            AutomationProperties.SetName(_bubble, "Tour: " + step.Title);
            var title = Text(step.Title, 13, FontWeights.SemiBold, Brushes.White);
            title.TextTrimming = TextTrimming.CharacterEllipsis;
            var bodyText = Text(body, 12, FontWeights.Normal, Brushes.White);
            bodyText.Margin = new Thickness(0, 2, 0, 0);

            var footer = new DockPanel { Height = 20, Margin = new Thickness(0, 8, 0, 0), LastChildFill = false };
            if (done)
            {
                var check = new Grid { Width = 16, Height = 16, VerticalAlignment = VerticalAlignment.Center };
                check.Children.Add(new Ellipse { Width = 13, Height = 13, Stroke = Brushes.White, StrokeThickness = 1.4 });
                check.Children.Add(new Path
                {
                    Data = Geometry.Parse("M 4.6,8.2 L 7,10.4 L 11.4,5.8"), Stroke = Brushes.White, StrokeThickness = 1.5,
                    StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round,
                });
                footer.Children.Add(check);
                var doneLabel = Text("Done", 11, FontWeights.SemiBold, Brushes.White);
                doneLabel.Margin = new Thickness(4, 0, 0, 0);
                doneLabel.VerticalAlignment = VerticalAlignment.Center;
                footer.Children.Add(doneLabel);
            }
            else
            {
                var counter = Text($"{number} of {total}", 11, FontWeights.Medium, White90);
                counter.VerticalAlignment = VerticalAlignment.Center;
                DockPanel.SetDock(counter, Dock.Left);
                footer.Children.Add(counter);

                var right = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
                DockPanel.SetDock(right, Dock.Right);
                bool lastExplain = isLast && !step.IsTry;
                if (!lastExplain)
                {
                    var skipTour = Text("Skip Tour", 11, FontWeights.SemiBold, White90);
                    skipTour.VerticalAlignment = VerticalAlignment.Center;
                    var link = new Border { Child = skipTour, Background = Brushes.Transparent, Padding = new Thickness(2, 0, 2, 0) };
                    Pressable(link, () => _owner.OnSkipTour?.Invoke(), "Skip Tour");
                    right.Children.Add(link);
                }
                string label = step.IsTry ? "Skip Step" : isLast ? "Done" : "Next";
                var primaryText = Text(label, 11, FontWeights.SemiBold, step.IsTry ? Brushes.White : RedBrush);
                primaryText.VerticalAlignment = VerticalAlignment.Center;
                var primary = new Border
                {
                    Height = 20, CornerRadius = new CornerRadius(10), Padding = new Thickness(8, 0, 8, 0), Margin = new Thickness(4, 0, 0, 0),
                    Background = step.IsTry ? Brushes.Transparent : Brushes.White,
                    BorderBrush = Brushes.White, BorderThickness = new Thickness(step.IsTry ? 1 : 0),
                    Child = primaryText,
                };
                Pressable(primary, step.IsTry ? () => _owner.OnSkipStep?.Invoke() : () => _owner.OnNext?.Invoke(), label);
                right.Children.Add(primary);
                footer.Children.Add(right);
            }

            // Width = widest of (title, body on one line, footer) + 24, clamped to 200…260.
            title.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            var oneLine = Text(body, 12, FontWeights.Normal, Brushes.White);
            oneLine.TextWrapping = TextWrapping.NoWrap;
            oneLine.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            footer.Measure(new Size(double.PositiveInfinity, 20));
            double content = Math.Max(title.DesiredSize.Width, Math.Max(oneLine.DesiredSize.Width, footer.DesiredSize.Width));
            double width = Math.Clamp(Math.Ceiling(content) + 24, 200, 260);

            bodyText.TextTrimming = TextTrimming.CharacterEllipsis;
            bodyText.MaxHeight = Math.Ceiling(bodyText.FontSize * bodyText.FontFamily.LineSpacing * 2) + 1; // at most 2 lines

            var stack = new StackPanel();
            stack.Children.Add(title);
            stack.Children.Add(bodyText);
            stack.Children.Add(footer);
            _bubble.Width = width;
            _bubble.Child = stack;
            _bubble.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            BubbleSize = new Size(width, Math.Ceiling(_bubble.DesiredSize.Height - 2 * ShadowMargin));
        }

        private static TextBlock Text(string s, double size, FontWeight weight, Brush fg) => new()
        {
            Text = s, FontSize = size, FontWeight = weight, Foreground = fg, FontFamily = UiFont, TextWrapping = TextWrapping.Wrap,
        };

        private static void Pressable(Border b, Action onClick, string name)
        {
            b.Cursor = Cursors.Hand;
            b.Focusable = false;
            AutomationProperties.SetName(b, name);
            b.MouseLeftButtonDown += (_, e) => { b.Opacity = 0.7; b.CaptureMouse(); e.Handled = true; };
            b.MouseLeftButtonUp += (_, e) =>
            {
                var at = e.GetPosition(b);
                bool inside = at.X >= 0 && at.Y >= 0 && at.X <= b.ActualWidth && at.Y <= b.ActualHeight;
                b.Opacity = 1;
                b.ReleaseMouseCapture();
                e.Handled = true;
                if (inside) onClick();
            };
            b.LostMouseCapture += (_, _) => b.Opacity = 1;
        }
    }
}
