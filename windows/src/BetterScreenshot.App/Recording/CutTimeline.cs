using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.Recording;
using Application = System.Windows.Application;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using FlowDirection = System.Windows.FlowDirection;
using FontFamily = System.Windows.Media.FontFamily;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Pen = System.Windows.Media.Pen;
using Point = System.Windows.Point;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// The video editor's filmstrip timeline (Mac v3 Part 6 drawing spec): a time ruler over the kept segments, kept
/// segments at their output length filled with the filmstrip, cuts dimmed + hatched at their source length,
/// speed / mute badges, the yellow selection with edge handles, and the playhead. Mouse: click/scrub, edge drag
/// (scale frozen while dragging, one commit on release), right-click for the segment menu. The host owns the
/// model and the undo history; this control reports gestures through its events.
/// </summary>
public sealed class CutTimeline : FrameworkElement
{
    public const double ViewHeight = 74;
    private const double Inset = 12;
    private const double TrackTop = 18;
    private const double EdgeReach = 7;

    private static readonly Typeface RulerFace = new(new FontFamily("Cascadia Mono, Consolas"), FontStyles.Normal, FontWeights.Medium, FontStretches.Normal);
    private static readonly Typeface BadgeFace = new(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);
    private static readonly Brush Yellow = Frozen(Color.FromRgb(0xFF, 0xD6, 0x0A));
    private static readonly Brush TrackBack = Frozen(Color.FromArgb(0x59, 0, 0, 0));
    private static readonly Brush CutDim = Frozen(Color.FromArgb(0xA8, 0, 0, 0));
    private static readonly Brush Placeholder = Frozen(Color.FromArgb(0x38, 0xFF, 0xFF, 0xFF));
    private static readonly Brush BadgeBack = Frozen(Color.FromArgb(0xB3, 0, 0, 0));
    private static readonly Brush Grip = Frozen(Color.FromArgb(0x8C, 0, 0, 0));
    private static readonly Brush LabelBrush = Frozen(Color.FromArgb(0x8C, 0xFF, 0xFF, 0xFF));
    private static readonly Pen KeptBorder = FrozenPen(Color.FromArgb(0x38, 0xFF, 0xFF, 0xFF), 1);
    private static readonly Pen Hatch = FrozenPen(Color.FromArgb(0x17, 0xFF, 0xFF, 0xFF), 1.5);
    private static readonly Pen MajorTick = FrozenPen(Color.FromArgb(0x4D, 0xFF, 0xFF, 0xFF), 1);
    private static readonly Pen MinorTick = FrozenPen(Color.FromArgb(0x2E, 0xFF, 0xFF, 0xFF), 1);
    private static readonly Pen SelectionPen = new(Yellow, 2.5);
    private static readonly Pen PlayheadShadow = FrozenPen(Color.FromArgb(0x99, 0, 0, 0), 4);

    private CutList _cuts = new(1);
    private int _selected;
    private double _playhead;
    private IReadOnlyList<BitmapSource?> _frames = Array.Empty<BitmapSource?>();
    private double _aspect = 16.0 / 9;

    // drag state
    private enum Drag { None, Scrub, Edge }
    private Drag _drag;
    private int _dragIndex;
    private bool _dragStart;
    private double _frozenScale;
    private IReadOnlyList<TimelineItem>? _frozenItems;
    private CutList? _dragBase;

    /// <summary>The user clicked / scrubbed: move the playhead to this output time (and select <c>Selected</c>).</summary>
    public event Action<double, int>? Seek;
    /// <summary>An edge drag moved: the working cut list and the source time to preview.</summary>
    public event Action<CutList, double>? EdgeDragging;
    /// <summary>An edge drag ended: the final cut list (commit once), the segment, and whether it was the start edge.</summary>
    public event Action<CutList, int, bool>? EdgeDragged;
    /// <summary>Right-click on a kept segment (already selected).</summary>
    public event Action<int>? SegmentMenu;

    public CutTimeline()
    {
        Height = ViewHeight;
        ClipToBounds = true;
        ToolTip = "Click to move the playhead and pick a segment · drag a yellow edge to trim · right-click for speed and mute";
        Focusable = false;
    }

    public CutList Cuts { get => _cuts; set { _cuts = value; InvalidateVisual(); } }
    public int Selected { get => _selected; set { _selected = value; InvalidateVisual(); } }
    public double Playhead { get => _playhead; set { _playhead = value; InvalidateVisual(); } }
    public double Aspect { get => _aspect; set { _aspect = value > 0 ? value : 16.0 / 9; InvalidateVisual(); } }
    public bool IsDraggingEdge => _drag == Drag.Edge;

    public IReadOnlyList<BitmapSource?> Frames { get => _frames; set { _frames = value; InvalidateVisual(); } }

    /// <summary>Points per timeline second at the current width.</summary>
    public double Scale => _drag == Drag.Edge ? _frozenScale : (ActualWidth - 2 * Inset) / Math.Max(0.001, _cuts.TimelineLength);

    public double XForTimeline(double t) => Inset + t * Scale;
    public double TimelineAt(double x) => Math.Clamp((x - Inset) / Scale, 0, _cuts.TimelineLength);
    public double PlayheadX => XForTimeline(_cuts.TimelinePositionForOutput(_playhead));

    // ------------------------------------------------------------------ drawing

    protected override void OnRender(DrawingContext dc)
    {
        double w = ActualWidth, h = ActualHeight;
        if (w <= 2 * Inset || _cuts.Duration <= 0) return;
        double scale = Scale, trackBottom = h - 6, trackH = trackBottom - TrackTop;
        var items = _cuts.Timeline;

        dc.DrawRoundedRectangle(TrackBack, null, new Rect(2, TrackTop - 3, w - 4, trackH + 6), 8, 8);
        DrawRuler(dc, items, scale, w);

        foreach (var it in items)
        {
            double x0 = Inset + it.DisplayStart * scale, x1 = Inset + it.DisplayEnd * scale;
            if (it.Kept)
            {
                var r = new Rect(x0 + 1, TrackTop, Math.Max(0, x1 - x0 - 2), trackH);
                var clip = new RectangleGeometry(r, 6, 6);
                dc.PushClip(clip);
                DrawFilmstrip(dc, r, scale);
                dc.Pop();
                dc.DrawRoundedRectangle(null, KeptBorder, r, 6, 6);
                DrawBadges(dc, r, _cuts.Segments[it.Index]);
            }
            else
            {
                var r = new Rect(x0 + 1, TrackTop + 4, Math.Max(0, x1 - x0 - 2), trackH - 8);
                dc.PushClip(new RectangleGeometry(r, 4, 4));
                DrawFilmstrip(dc, r, scale);
                dc.DrawRectangle(CutDim, null, r);
                for (double hx = r.Left - r.Height; hx < r.Right; hx += 7)
                    dc.DrawLine(Hatch, new Point(hx, r.Bottom), new Point(hx + r.Height, r.Top));
                dc.Pop();
                if (r.Width >= 22) DrawScissors(dc, new Point(r.Left + r.Width / 2, r.Top + r.Height / 2));
            }
        }

        // Selection: 2.5 pt yellow border + two solid handles with grips.
        if (items.FirstOrDefault(i => i.Kept && i.Index == _selected) is { Kept: true } sel)
        {
            double x0 = Inset + sel.DisplayStart * scale, x1 = Inset + sel.DisplayEnd * scale;
            var r = new Rect(x0 + 1, TrackTop, Math.Max(0, x1 - x0 - 2), trackH);
            dc.DrawRoundedRectangle(null, SelectionPen, r, 6, 6);
            double hw = Math.Min(10, r.Width / 3);
            foreach (var hx in new[] { r.Left, r.Right - hw })
            {
                var hr = new Rect(hx, r.Top, hw, r.Height);
                dc.DrawRoundedRectangle(Yellow, null, hr, 4, 4);
                dc.DrawRectangle(Grip, null, new Rect(hr.Left + hw / 2 - 1, hr.Top + hr.Height / 2 - 7, 2, 14));
            }
        }

        // Playhead: 8 pt knob at y 9.5 + 2 pt line to the bottom, soft shadow.
        double px = Inset + _cuts.TimelinePositionForOutput(_playhead) * scale;
        dc.DrawLine(PlayheadShadow, new Point(px, 9.5), new Point(px, h));
        dc.DrawLine(new Pen(System.Windows.Media.Brushes.White, 2), new Point(px, 9.5), new Point(px, h));
        dc.DrawEllipse(System.Windows.Media.Brushes.White, null, new Point(px, 9.5), 4, 4);
    }

    private void DrawRuler(DrawingContext dc, IReadOnlyList<TimelineItem> items, double scale, double width)
    {
        double dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var spans = items.Where(i => i.Kept)
            .Select(i => new TimeRuler.Span(Inset + i.DisplayStart * scale, i.DisplayLength * scale, _cuts.OutputStart(i.Index)))
            .ToList();
        double Width(string s) => new FormattedText(s, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, RulerFace, 9, LabelBrush, dpi).Width;
        foreach (var tick in TimeRuler.Ticks(spans, scale, width, Width))
        {
            if (tick.Major) dc.DrawLine(MajorTick, new Point(tick.X, 1), new Point(tick.X, 14));
            else dc.DrawLine(MinorTick, new Point(tick.X, 11), new Point(tick.X, 14));
            if (tick.Label is { } label)
                dc.DrawText(new FormattedText(label, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, RulerFace, 9, LabelBrush, dpi),
                    new Point(tick.X + 3, 0));
        }
    }

    /// <summary>Tiles track-height × aspect wide, each aspect-filling the thumbnail nearest the source time at its centre.</summary>
    private void DrawFilmstrip(DrawingContext dc, Rect r, double scale)
    {
        double tile = Math.Clamp(r.Height * _aspect, 24, 160);
        for (double x = r.Left; x < r.Right; x += tile)
        {
            var cell = new Rect(x, r.Top, tile, r.Height);
            double t = _cuts.SourceTimeForTimelinePosition(Math.Max(0, (x + tile / 2 - Inset) / scale));
            var frame = Nearest(t);
            if (frame is null) { dc.DrawRectangle(Placeholder, null, cell); continue; }
            double fa = frame.PixelWidth / (double)Math.Max(1, frame.PixelHeight);
            Rect img = fa > tile / r.Height
                ? new Rect(cell.Left - (r.Height * fa - tile) / 2, cell.Top, r.Height * fa, r.Height)
                : new Rect(cell.Left, cell.Top - (tile / fa - r.Height) / 2, tile, tile / fa);
            dc.PushClip(new RectangleGeometry(cell));
            dc.DrawImage(frame, img);
            dc.Pop();
        }
    }

    private BitmapSource? Nearest(double sourceTime)
    {
        int n = _frames.Count;
        if (n == 0) return null;
        int k = Math.Clamp((int)Math.Floor(sourceTime / Math.Max(1e-6, _cuts.Duration) * n), 0, n - 1);
        for (int d = 0; d < n; d++)
        {
            if (k - d >= 0 && _frames[k - d] is { } a) return a;
            if (k + d < n && _frames[k + d] is { } b) return b;
        }
        return null;
    }

    private void DrawBadges(DrawingContext dc, Rect r, CutSegment s)
    {
        double dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        double x = r.Left + 5, y = r.Top + 4;
        if (Math.Abs(s.Speed - 1) > 1e-9)
        {
            var ft = new FormattedText(FormatSpeed(s.Speed), CultureInfo.InvariantCulture, FlowDirection.LeftToRight, BadgeFace, 10, System.Windows.Media.Brushes.White, dpi);
            double bw = ft.Width + 10;
            if (x + bw <= r.Right - 2)
            {
                dc.DrawRoundedRectangle(BadgeBack, null, new Rect(x, y, bw, 16), 8, 8);
                dc.DrawText(ft, new Point(x + 5, y + (16 - ft.Height) / 2));
                x += bw + 4;
            }
        }
        if (s.Muted && x + 22 <= r.Right - 2)
        {
            dc.DrawRoundedRectangle(BadgeBack, null, new Rect(x, y, 22, 16), 8, 8);
            if (Application.Current?.TryFindResource("icon-speaker-slash") is Geometry g)
            {
                dc.PushTransform(new TranslateTransform(x + 5, y + 2));
                dc.PushTransform(new ScaleTransform(12 / 24.0, 12 / 24.0));
                dc.DrawGeometry(null, new Pen(System.Windows.Media.Brushes.White, 2.6) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, g);
                dc.Pop();
                dc.Pop();
            }
        }
    }

    private static void DrawScissors(DrawingContext dc, Point c)
    {
        if (Application.Current?.TryFindResource("icon-scissors") is not Geometry g) return;
        dc.PushTransform(new TranslateTransform(c.X - 6, c.Y - 6));
        dc.PushTransform(new ScaleTransform(12 / 24.0, 12 / 24.0));
        dc.DrawGeometry(null, new Pen(new SolidColorBrush(Color.FromArgb(0x73, 0xFF, 0xFF, 0xFF)), 2.4), g);
        dc.Pop();
        dc.Pop();
    }

    public static string FormatSpeed(double speed) => speed.ToString("0.#", CultureInfo.InvariantCulture) + "×";

    // ------------------------------------------------------------------ mouse

    /// <summary>The kept-segment edge within reach of <paramref name="x"/>: the selected segment's wins, otherwise the
    /// one on the pointer's side of a shared boundary.</summary>
    private (int Index, bool Start)? EdgeAt(double x)
    {
        double scale = Scale;
        (int, bool)? best = null;
        double bestDist = double.MaxValue;
        foreach (var it in _cuts.Timeline.Where(i => i.Kept))
        {
            foreach (var (ex, start) in new[] { (Inset + it.DisplayStart * scale, true), (Inset + it.DisplayEnd * scale, false) })
            {
                double d = Math.Abs(x - ex);
                if (d > EdgeReach) continue;
                bool onSide = start ? x >= ex : x <= ex;
                double rank = it.Index == _selected ? -1 : onSide ? d : d + EdgeReach;
                if (rank < bestDist) { bestDist = rank; best = (it.Index, start); }
            }
        }
        return best;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        var p = e.GetPosition(this);
        switch (_drag)
        {
            case Drag.Scrub:
                SeekTo(p.X, select: false);
                break;
            case Drag.Edge:
                DragEdge(p.X);
                break;
            default:
                Cursor = EdgeAt(p.X) is not null ? Cursors.SizeWE : null;
                break;
        }
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        var p = e.GetPosition(this);
        if (EdgeAt(p.X) is { } edge)
        {
            _drag = Drag.Edge;
            _dragIndex = edge.Index;
            _dragStart = edge.Start;
            _frozenScale = (ActualWidth - 2 * Inset) / Math.Max(0.001, _cuts.TimelineLength);
            _frozenItems = _cuts.Timeline;
            _dragBase = _cuts.Clone();
            _selected = edge.Index;
            DragEdge(p.X);
        }
        else
        {
            _drag = Drag.Scrub;
            SeekTo(p.X, select: true);
        }
        CaptureMouse();
        e.Handled = true;
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        EndDrag();
        ReleaseMouseCapture();
        e.Handled = true;
    }

    /// <summary>Alt+Tab or a dialog mid-drag takes the capture away: finish the drag there, or the timeline would stay
    /// in edge-drag mode with nothing holding the mouse (review round 1 #20).</summary>
    protected override void OnLostMouseCapture(MouseEventArgs e)
    {
        base.OnLostMouseCapture(e);
        EndDrag();
    }

    private void EndDrag()
    {
        if (_drag == Drag.Edge && _dragBase is not null)
        {
            var final = _cuts;
            _drag = Drag.None;
            _frozenItems = null;
            EdgeDragged?.Invoke(final, _dragIndex, _dragStart);
        }
        _drag = Drag.None;
    }

    protected override void OnMouseRightButtonUp(MouseButtonEventArgs e)
    {
        double t = TimelineAt(e.GetPosition(this).X);
        var it = _cuts.Timeline.FirstOrDefault(i => i.Kept && t >= i.DisplayStart && t <= i.DisplayEnd);
        if (it.Kept)
        {
            Seek?.Invoke(_cuts.OutputTimeForTimelinePosition(t), it.Index);
            SegmentMenu?.Invoke(it.Index);
        }
        e.Handled = true;
    }

    private void SeekTo(double x, bool select)
    {
        double t = TimelineAt(x);
        double output = _cuts.OutputTimeForTimelinePosition(t);
        int index = select && _cuts.Timeline.FirstOrDefault(i => i.Kept && t >= i.DisplayStart && t < i.DisplayEnd) is { Kept: true } hit
            ? hit.Index
            : select ? _cuts.SegmentIndexAtOutput(output) : _selected;
        Seek?.Invoke(output, index);
    }

    /// <summary>Scale frozen: start edge → previous kept end (or 0) + distance from the cut's display start; end edge →
    /// start + distance from the segment's display start × speed; clamped by the cut list.</summary>
    private void DragEdge(double x)
    {
        if (_dragBase is null || _frozenItems is null) return;
        double pointer = (x - Inset) / _frozenScale;
        var work = _dragBase.Clone();
        var seg = _dragBase.Segments[_dragIndex];
        int k = _frozenItems.ToList().FindIndex(i => i.Kept && i.Index == _dragIndex);
        double preview;
        if (_dragStart)
        {
            double anchorSource = _dragIndex > 0 ? _dragBase.Segments[_dragIndex - 1].End : 0;
            double anchorDisplay = k > 0 && !_frozenItems[k - 1].Kept ? _frozenItems[k - 1].DisplayStart : _frozenItems[k].DisplayStart;
            if (k > 0 && _frozenItems[k - 1].Kept) anchorSource = seg.Start;
            work.SetStart(anchorSource + (pointer - anchorDisplay), _dragIndex);
            preview = work.Segments[_dragIndex].Start;
        }
        else
        {
            work.SetEnd(seg.Start + (pointer - _frozenItems[k].DisplayStart) * seg.Speed, _dragIndex);
            preview = Math.Max(work.Segments[_dragIndex].Start, work.Segments[_dragIndex].End - 1.0 / 60);
        }
        _cuts = work;
        InvalidateVisual();
        EdgeDragging?.Invoke(work, preview);
    }

    private static SolidColorBrush Frozen(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }

    private static Pen FrozenPen(Color c, double w)
    {
        var p = new Pen(Frozen(c), w);
        p.Freeze();
        return p;
    }
}
