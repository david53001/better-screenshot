using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Canvas = System.Windows.Controls.Canvas;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using Ellipse = System.Windows.Shapes.Ellipse;
using Keyboard = System.Windows.Input.Keyboard;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Point = System.Windows.Point;
using Rectangle = System.Windows.Shapes.Rectangle;
using TextBox = System.Windows.Controls.TextBox;

namespace BetterScreenshot.App.Editor;

/// <summary>Canvas interaction: drawing, selection (click / Shift-click / marquee), moving, the 8 box handles, the
/// text handles (corner scale + side width), the in-place text editor (v3 A.1), highlighter and spotlight drags.
/// All maths in image pixels; chrome (handles, outlines) sized in screen points (÷ magnification).</summary>
public partial class EditorWindow
{
    private enum DragKind { None, Draw, Redact, Crop, Marquee, Move, Resize, TextScale, TextSide, TextBox, Highlight, Spotlight }

    private DragKind _drag;
    private PxPoint _dragStart;
    private Point _downView;
    private EditorState? _beforeDrag;
    private bool _dragChanged;
    private List<IAnnotation> _moveOriginals = new();
    private BitmapSource? _moveBackground;
    private bool _moveFullRender;
    private IAnnotation? _handleOriginal;
    private int _handle;
    private readonly List<PxPoint> _hlPoints = new();
    private BitmapSource? _spotBackground;
    private Rectangle? _marquee;
    private readonly List<UIElement> _preview = new();
    private readonly List<UIElement> _overlay = new();

    private static readonly Brush SelectionBlue = Frozen(Color.FromRgb(0x0A, 0x84, 0xFF));

    private static Brush Frozen(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }

    private double View(double points) => points / Math.Max(_magnification, 0.01);

    private PxPoint Pos(MouseEventArgs e, bool clamp = true)
    {
        var p = e.GetPosition(InteractionLayer);
        return clamp
            ? new PxPoint(Math.Clamp(p.X, 0, _baseImage.PixelWidth), Math.Clamp(p.Y, 0, _baseImage.PixelHeight))
            : new PxPoint(p.X, p.Y);
    }

    // ------------------------------------------------------------------ mouse down

    private void OnDown(object sender, MouseButtonEventArgs e)
    {
        Focus();
        // A click while a text is open just finishes that text (it does NOT also start a new one).
        if (_textEdit != null) { CommitText(); e.Handled = true; return; }

        var p = Pos(e);
        _dragStart = p;
        _downView = e.GetPosition(Scroller);
        _beforeDrag = Snapshot();
        _dragChanged = false;
        bool shift = (Keyboard.Modifiers & ModifierKeys.Shift) != 0;

        switch (_tool)
        {
            case EditorTool.Select:
                if (TryStartHandleDrag(p)) break;
                if (_document.TopmostHit(p, View(AnnotationExtensions.HitSlop)) is { } hit)
                {
                    if (e.ClickCount == 2 && _document.Find(hit) is TextAnnotation text) { BeginTextEdit(text.Origin, text.WrapWidth, text); return; }
                    if (shift)
                    {
                        if (!_selection.Remove(hit)) _selection.Add(hit);
                        RefreshChrome();
                        return;
                    }
                    if (!_selection.Contains(hit)) { _selection.Clear(); _selection.Add(hit); }
                    StartMove();
                }
                else
                {
                    if (!shift) _selection.Clear();
                    _drag = DragKind.Marquee;
                    BeginMarquee(p, select: true);
                }
                break;
            case EditorTool.Counter:
                PushUndo();
                var counter = CounterAnnotation.Centered(p, _document.NextCounterNumber(), _style);
                _document.Add(counter);
                PostAdded(EditorTool.Counter);
                _selection.Clear();
                _selection.Add(counter.Id); // a Counter click selects the new badge too
                Redraw();
                return;
            case EditorTool.Text:
                if (_document.TopmostHit(p, View(2)) is { } id && _document.Find(id) is TextAnnotation existing)
                {
                    BeginTextEdit(existing.Origin, existing.WrapWidth, existing);
                    return;
                }
                _drag = DragKind.TextBox;
                break;
            case EditorTool.Blur:
            case EditorTool.Pixelate:
            case EditorTool.Blackout:
                _drag = DragKind.Redact;
                BeginMarquee(p, select: false);
                break;
            case EditorTool.Crop:
                _drag = DragKind.Crop;
                BeginMarquee(p, select: false);
                break;
            case EditorTool.Highlighter:
                _drag = DragKind.Highlight;
                _hlPoints.Clear();
                _hlPoints.Add(p);
                break;
            case EditorTool.Spotlight:
                _drag = DragKind.Spotlight;
                var withoutSpots = new EditorDocument(_document.Size, _document.Annotations.Where(a => a is not SpotlightAnnotation));
                _spotBackground = DocumentRenderer.Render(withoutSpots, _baseImage);
                break;
            default:
                _drag = DragKind.Draw;
                break;
        }
        InteractionLayer.CaptureMouse();
        e.Handled = true;
    }

    private bool TryStartHandleDrag(PxPoint p)
    {
        if (_selection.Count != 1 || _document.Find(_selection[0]) is not { } a) return false;
        if (a is TextAnnotation t)
        {
            var rects = TextHandleRects(t);
            // Corners first, then the side bars (with a wider hit area).
            foreach (int i in TextHandles.Corners)
                if (rects.TryGetValue(i, out var r) && Inflate(r, View(2)).Contains(p)) { StartHandle(a, i, DragKind.TextScale); return true; }
            foreach (int i in TextHandles.Sides)
                if (rects.TryGetValue(i, out var r) && Inflate(WidenTo(r, View(10)), View(2)).Contains(p)) { StartHandle(a, i, DragKind.TextSide); return true; }
            return false;
        }
        if (a is IFramedAnnotation f)
        {
            for (int i = 0; i < 8; i++)
            {
                var c = FrameResize.HandleCenter(f.Frame, i);
                double half = View(4) + View(2);
                if (Math.Abs(p.X - c.X) <= half && Math.Abs(p.Y - c.Y) <= half) { StartHandle(a, i, DragKind.Resize); return true; }
            }
        }
        return false;
    }

    private void StartHandle(IAnnotation a, int handle, DragKind kind)
    {
        _handleOriginal = a;
        _handle = handle;
        _drag = kind;
    }

    private void StartMove()
    {
        _drag = DragKind.Move;
        _moveOriginals = _document.Annotations.Where(a => _selection.Contains(a.Id)).ToList();
        // Spotlights and highlighters can't be composited over a cached background (the dim layer / multiply
        // depend on everything) — full render per tick then. Otherwise flatten the rest once.
        _moveFullRender = _document.Annotations.Any(a => a is SpotlightAnnotation) || _moveOriginals.Any(a => a is HighlighterAnnotation);
        if (!_moveFullRender)
        {
            var rest = new EditorDocument(_document.Size, _document.Annotations.Where(a => !_selection.Contains(a.Id)));
            _moveBackground = DocumentRenderer.Render(rest, _baseImage);
        }
    }

    // ------------------------------------------------------------------ mouse move

    private void OnMove(object sender, MouseEventArgs e)
    {
        if (_drag == DragKind.None)
        {
            UpdateHoverCursor(Pos(e));
            return;
        }
        if (e.LeftButton != MouseButtonState.Pressed) return;
        var p = Pos(e);
        double dx = p.X - _dragStart.X, dy = p.Y - _dragStart.Y;

        switch (_drag)
        {
            case DragKind.Marquee:
            case DragKind.Redact:
            case DragKind.Crop:
                UpdateMarquee(p);
                break;
            case DragKind.Draw:
                ShowPreview(AnnotationFactory.CreateDrag(_tool, _dragStart, p, _style) is { } shape ? PreviewElements(shape) : Array.Empty<UIElement>());
                break;
            case DragKind.TextBox:
                UpdateMarquee(p, create: true);
                break;
            case DragKind.Highlight:
            {
                bool straight = (Keyboard.Modifiers & ModifierKeys.Shift) != 0;
                if (straight) { _hlPoints.RemoveRange(1, _hlPoints.Count - 1); _hlPoints.Add(p); }
                else if (Dist(_hlPoints[^1], p) >= 0.5) _hlPoints.Add(p);
                var pen = _style.WithHighlighterPen();
                ShowPreview(new UIElement[]
                {
                    new Polyline
                    {
                        Points = new PointCollection(_hlPoints.Select(q => new Point(q.X, q.Y))), Stroke = DocumentRenderer.Solid(pen.StrokeColor),
                        StrokeThickness = pen.LineWidth, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
                        StrokeLineJoin = PenLineJoin.Round, Opacity = pen.Opacity, IsHitTestVisible = false,
                    },
                });
                break;
            }
            case DragKind.Spotlight:
            {
                var spot = SpotlightFromDrag(p);
                var spots = _document.Annotations.OfType<SpotlightAnnotation>().Append(spot).ToList();
                CanvasImage.Source = _spotBackground;
                var dimPath = new Path
                {
                    Data = DocumentRenderer.DimGeometry(spots, _baseImage.PixelWidth, _baseImage.PixelHeight),
                    Fill = new SolidColorBrush(Color.FromArgb((byte)Math.Round(spot.Style.SpotlightDim * 255), 0, 0, 0)),
                    IsHitTestVisible = false,
                };
                ShowPreview(new UIElement[] { dimPath });
                break;
            }
            case DragKind.Move:
            {
                var (cdx, cdy) = FrameResize.ClampDelta(_moveOriginals.Select(a => a.BoundingBox()), dx, dy, _document.Size);
                var moved = _moveOriginals.Select(a => a.MovedBy(cdx, cdy)).ToList();
                if (_moveFullRender)
                {
                    var doc = new EditorDocument(_document.Size, _document.Annotations.Select(a => moved.FirstOrDefault(m => m.Id == a.Id) ?? a));
                    CanvasImage.Source = DocumentRenderer.Render(doc, _baseImage);
                }
                else if (_moveBackground != null)
                {
                    CanvasImage.Source = DocumentRenderer.Render(new EditorDocument(_document.Size, moved), _moveBackground, patchSource: _baseImage);
                }
                _dragChanged = Math.Abs(cdx) > 0.01 || Math.Abs(cdy) > 0.01;
                DrawSelectionChrome(moved);
                break;
            }
            case DragKind.Resize when _handleOriginal is IFramedAnnotation f:
            {
                var frame = FrameResize.Resize(f.Frame, _handle, dx, dy);
                ReplaceLive(f.WithFrame(frame));
                break;
            }
            case DragKind.TextScale when _handleOriginal is TextAnnotation t:
            {
                var scaled = t.Scaled(TextHandles.CornerOf(_handle), Pos(e, clamp: false).X - _dragStart.X, Pos(e, clamp: false).Y - _dragStart.Y);
                ReplaceLive(scaled);
                break;
            }
            case DragKind.TextSide when _handleOriginal is TextAnnotation t:
            {
                var box = t.BoundingBox();
                double left = box.X, right = box.Right;
                if (_handle == 3) left += dx; else right += dx;
                ReplaceLive(t.WithBoxSpan(left, right));
                break;
            }
        }
    }

    /// <summary>Live handle drag: the document holds the dragged object; one undo step is pushed on mouse-up.</summary>
    private void ReplaceLive(IAnnotation next)
    {
        _document.Replace(next.Id, next);
        _dragChanged = true;
        CanvasImage.Source = DocumentRenderer.Render(_document, _baseImage);
        RefreshOverlay();
        if (next is TextAnnotation) RefreshChrome(); // the size pop-up follows the scale live
    }

    // ------------------------------------------------------------------ mouse up

    private void OnUp(object sender, MouseButtonEventArgs e)
    {
        InteractionLayer.ReleaseMouseCapture();
        var kind = _drag;
        _drag = DragKind.None;
        var p = Pos(e);
        var frame = SelectionMath.Normalize(_dragStart, p);
        var before = _beforeDrag;
        _beforeDrag = null;
        ClearPreview();

        switch (kind)
        {
            case DragKind.Marquee:
                EndMarquee();
                if (frame.Width > View(2) || frame.Height > View(2))
                    foreach (var id in _document.IdsIntersecting(frame)) if (!_selection.Contains(id)) _selection.Add(id);
                RefreshChrome();
                break;
            case DragKind.Crop:
                EndMarquee();
                if (frame.Width >= 4 && frame.Height >= 4) { PushUndo(); ApplyCrop(frame); }
                Redraw();
                break;
            case DragKind.Redact:
                EndMarquee();
                if (frame.Width >= 2 && frame.Height >= 2)
                {
                    PushUndo();
                    var mode = _tool.RedactionModeOf() ?? RedactionMode.Blur;
                    var clipped = frame.Intersection(new PxRect(0, 0, _baseImage.PixelWidth, _baseImage.PixelHeight));
                    var r = new RedactionAnnotation(Guid.NewGuid(), _style with { RedactionMode = mode }, clipped);
                    _document.Add(r);
                    SelectOnly(r.Id);
                    PostAdded(_tool);
                    Tours.TourEvents.Post(BetterScreenshot.Tours.TourEvent.Action("editor.redactionAdded"));
                }
                Redraw();
                break;
            case DragKind.Draw:
                if (frame.Width >= 2 || frame.Height >= 2)
                {
                    if (AnnotationFactory.CreateDrag(_tool, _dragStart, p, _style) is { } shape)
                    {
                        PushUndo();
                        _document.Add(shape);
                        SelectOnly(shape.Id);
                        PostAdded(_tool);
                    }
                }
                Redraw();
                break;
            case DragKind.TextBox:
            {
                EndMarquee();
                double viewWidth = Math.Abs(e.GetPosition(Scroller).X - _downView.X);
                if (viewWidth >= 12)
                    BeginTextEdit(new PxPoint(frame.X, frame.Y), Math.Max(_style.FontSize, frame.Width), null);
                else
                    BeginTextEdit(_dragStart, null, null);
                return;
            }
            case DragKind.Highlight:
                if (_hlPoints.Count >= 2 && _hlPoints.Any(q => Dist(q, _hlPoints[0]) > 0.5))
                {
                    PushUndo();
                    var hl = new HighlighterAnnotation(Guid.NewGuid(), _style.WithHighlighterPen(), _hlPoints.ToList());
                    _document.Add(hl);
                    SelectOnly(hl.Id);
                    PostAdded(EditorTool.Highlighter);
                }
                _hlPoints.Clear();
                Redraw();
                break;
            case DragKind.Spotlight:
            {
                var spot = SpotlightFromDrag(p);
                _spotBackground = null;
                if (spot.Frame.Width >= 4 && spot.Frame.Height >= 4)
                {
                    PushUndo();
                    _document.Add(spot);
                    SelectOnly(spot.Id);
                    PostAdded(EditorTool.Spotlight);
                }
                Redraw();
                break;
            }
            case DragKind.Move:
                if (_dragChanged && before != null)
                {
                    var (cdx, cdy) = FrameResize.ClampDelta(_moveOriginals.Select(a => a.BoundingBox()), p.X - _dragStart.X, p.Y - _dragStart.Y, _document.Size);
                    _history.Push(before);
                    foreach (var a in _moveOriginals) _document.Replace(a.Id, a.MovedBy(cdx, cdy));
                }
                _moveOriginals.Clear();
                _moveBackground = null;
                Redraw();
                break;
            case DragKind.Resize:
            case DragKind.TextScale:
            case DragKind.TextSide:
                if (_dragChanged && before != null) _history.Push(before);
                if (_dragChanged && kind == DragKind.TextScale) Tours.TourEvents.Post(BetterScreenshot.Tours.TourEvent.Action("editor.textScaled"));
                _handleOriginal = null;
                Redraw();
                break;
        }
        _dragChanged = false;
    }

    private void CancelDrag()
    {
        InteractionLayer.ReleaseMouseCapture();
        if (_beforeDrag != null && _drag is DragKind.Resize or DragKind.TextScale or DragKind.TextSide)
        {
            _document = _beforeDrag.Document;
        }
        _drag = DragKind.None;
        _beforeDrag = null;
        _moveOriginals.Clear();
        _moveBackground = null;
        _spotBackground = null;
        ClearPreview();
        EndMarquee();
        Redraw();
    }

    private void SelectOnly(Guid id)
    {
        _selection.Clear();
        _selection.Add(id);
    }

    private SpotlightAnnotation SpotlightFromDrag(PxPoint p)
    {
        bool alt = (Keyboard.Modifiers & ModifierKeys.Alt) != 0;
        var style = alt ? _style with { SpotlightShape = SpotlightShape.Ellipse } : _style;
        return new SpotlightAnnotation(Guid.NewGuid(), style, SelectionMath.Normalize(_dragStart, p));
    }

    private void ApplyCrop(PxRect frame)
    {
        int x = Math.Clamp((int)Math.Round(frame.X), 0, _baseImage.PixelWidth);
        int y = Math.Clamp((int)Math.Round(frame.Y), 0, _baseImage.PixelHeight);
        int w = Math.Min((int)Math.Round(frame.Width), _baseImage.PixelWidth - x);
        int h = Math.Min((int)Math.Round(frame.Height), _baseImage.PixelHeight - y);
        if (w < 1 || h < 1) return;
        _document = _document.Cropped(new PxRect(x, y, w, h));
        var cropped = new WriteableBitmap(new CroppedBitmap(_baseImage, new Int32Rect(x, y, w, h)));
        cropped.Freeze();
        _baseImage = cropped;
        _selection.Clear();
        ResizeStage();
        if (_fitMode) Dispatcher.BeginInvoke(new Action(ApplyFit), System.Windows.Threading.DispatcherPriority.Loaded);
    }

    private static double Dist(PxPoint a, PxPoint b) => Math.Sqrt((a.X - b.X) * (a.X - b.X) + (a.Y - b.Y) * (a.Y - b.Y));

    // ------------------------------------------------------------------ marquee + previews

    private void BeginMarquee(PxPoint start, bool select)
    {
        _marquee = new Rectangle
        {
            Stroke = select ? SelectionBlue : Brushes.White,
            StrokeThickness = View(1),
            StrokeDashArray = new DoubleCollection { 4, 3 },
            Fill = new SolidColorBrush(select ? Color.FromArgb(0x1F, 0x0A, 0x84, 0xFF) : Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF)),
            IsHitTestVisible = false,
        };
        Canvas.SetLeft(_marquee, start.X);
        Canvas.SetTop(_marquee, start.Y);
        InteractionLayer.Children.Add(_marquee);
    }

    private void UpdateMarquee(PxPoint p, bool create = false)
    {
        if (_marquee == null)
        {
            if (!create) return;
            BeginMarquee(_dragStart, select: false);
        }
        var rect = SelectionMath.Normalize(_dragStart, p);
        Canvas.SetLeft(_marquee!, rect.X);
        Canvas.SetTop(_marquee!, rect.Y);
        _marquee!.Width = rect.Width;
        _marquee.Height = rect.Height;
    }

    private void EndMarquee()
    {
        if (_marquee != null) InteractionLayer.Children.Remove(_marquee);
        _marquee = null;
    }

    private void ShowPreview(IEnumerable<UIElement> elements)
    {
        ClearPreview();
        foreach (var el in elements)
        {
            InteractionLayer.Children.Add(el);
            _preview.Add(el);
        }
    }

    private void ClearPreview()
    {
        foreach (var el in _preview) InteractionLayer.Children.Remove(el);
        _preview.Clear();
    }

    /// <summary>The in-progress shape drawn as one WPF visual (rendered by the same renderer → exact match).</summary>
    private static UIElement[] PreviewElements(IAnnotation shape)
    {
        var drawing = new DrawingGroup();
        using (var dc = drawing.Open()) DocumentRenderer.Draw(dc, shape);
        var image = new System.Windows.Controls.Image { Source = new DrawingImage(drawing), IsHitTestVisible = false, Opacity = shape.Style.Opacity, Stretch = Stretch.None };
        var b = drawing.Bounds;
        if (b.IsEmpty) return Array.Empty<UIElement>();
        Canvas.SetLeft(image, b.X);
        Canvas.SetTop(image, b.Y);
        return new UIElement[] { image };
    }

    // ------------------------------------------------------------------ selection chrome

    private void RefreshOverlay()
    {
        if (_drag == DragKind.Move) return;
        DrawSelectionChrome(_document.Annotations.Where(a => _selection.Contains(a.Id)).ToList());
    }

    private void DrawSelectionChrome(IReadOnlyList<IAnnotation> selected)
    {
        foreach (var el in _overlay) InteractionLayer.Children.Remove(el);
        _overlay.Clear();
        if (_textEdit != null) return;
        foreach (var a in selected)
        {
            var box = a.BoundingBox();
            var outline = new Rectangle
            {
                Width = box.Width + View(4), Height = box.Height + View(4), Stroke = SelectionBlue, StrokeThickness = View(1),
                StrokeDashArray = new DoubleCollection { 4, 3 }, IsHitTestVisible = false,
            };
            Canvas.SetLeft(outline, box.X - View(2));
            Canvas.SetTop(outline, box.Y - View(2));
            AddOverlay(outline);
        }
        if (selected.Count != 1) return;
        var only = selected[0];
        if (only is TextAnnotation t)
        {
            foreach (var (i, r) in TextHandleRects(t))
            {
                Shape handle = TextHandles.Corners.Contains(i)
                    ? new Ellipse { Width = r.Width, Height = r.Height }
                    : new Rectangle { Width = r.Width, Height = r.Height, RadiusX = r.Width / 2, RadiusY = r.Width / 2 };
                handle.Fill = Brushes.White;
                handle.Stroke = SelectionBlue;
                handle.StrokeThickness = View(1);
                handle.IsHitTestVisible = false;
                Canvas.SetLeft(handle, r.X);
                Canvas.SetTop(handle, r.Y);
                AddOverlay(handle);
            }
        }
        else if (only is IFramedAnnotation f)
        {
            for (int i = 0; i < 8; i++)
            {
                var c = FrameResize.HandleCenter(f.Frame, i);
                var h = new Rectangle { Width = View(8), Height = View(8), Fill = Brushes.White, Stroke = SelectionBlue, StrokeThickness = View(1), IsHitTestVisible = false };
                Canvas.SetLeft(h, c.X - View(4));
                Canvas.SetTop(h, c.Y - View(4));
                AddOverlay(h);
            }
        }
    }

    private void AddOverlay(UIElement el)
    {
        InteractionLayer.Children.Add(el);
        _overlay.Add(el);
    }

    /// <summary>Text handle rects in image px: <see cref="TextHandles"/> works in view points, so map through the zoom.</summary>
    private Dictionary<int, PxRect> TextHandleRects(TextAnnotation t)
    {
        double m = Math.Max(_magnification, 0.01);
        var box = t.BoundingBox();
        var viewBox = new PxRect(box.X * m, box.Y * m, box.Width * m, box.Height * m);
        return TextHandles.Rects(viewBox).ToDictionary(kv => kv.Key, kv => new PxRect(kv.Value.X / m, kv.Value.Y / m, kv.Value.Width / m, kv.Value.Height / m));
    }

    private static PxRect Inflate(PxRect r, double d) => new(r.X - d, r.Y - d, r.Width + 2 * d, r.Height + 2 * d);

    private static PxRect WidenTo(PxRect r, double minWidth) =>
        r.Width >= minWidth ? r : new PxRect(r.X - (minWidth - r.Width) / 2, r.Y, minWidth, r.Height);

    private void UpdateHoverCursor(PxPoint p)
    {
        if (_tool != EditorTool.Select || _selection.Count != 1 || _document.Find(_selection[0]) is not { } a) { InteractionLayer.Cursor = _tool == EditorTool.Select ? null : Cursors.Cross; return; }
        System.Windows.Input.Cursor? c = null;
        if (a is TextAnnotation t)
        {
            foreach (var (i, r) in TextHandleRects(t))
                if (Inflate(WidenTo(r, View(10)), View(2)).Contains(p))
                    c = TextHandles.Corners.Contains(i) ? (i is 0 or 7 ? Cursors.SizeNWSE : Cursors.SizeNESW) : Cursors.SizeWE;
        }
        else if (a is IFramedAnnotation f)
        {
            for (int i = 0; i < 8; i++)
            {
                var hc = FrameResize.HandleCenter(f.Frame, i);
                if (Math.Abs(p.X - hc.X) <= View(6) && Math.Abs(p.Y - hc.Y) <= View(6))
                    c = i switch { 0 or 7 => Cursors.SizeNWSE, 2 or 5 => Cursors.SizeNESW, 1 or 6 => Cursors.SizeNS, _ => Cursors.SizeWE };
            }
        }
        InteractionLayer.Cursor = c;
    }

    // ------------------------------------------------------------------ in-place text editing (v3 A.1)

    private sealed class TextEditSession
    {
        public required TextBox Box { get; init; }
        public required Border Host { get; init; }
        public required Rectangle Frame { get; init; }
        public required PxPoint Origin { get; init; }
        public double? WrapWidth { get; set; }
        public Guid? ExistingId { get; init; }
        public TextAnnotation? Original { get; init; }
        public required AnnotationStyle Style { get; set; }
    }

    private TextEditSession? _textEdit;

    private void BeginTextEdit(PxPoint origin, double? wrapWidth, TextAnnotation? existing)
    {
        var style = existing?.Style ?? _style;
        if (existing != null) _style = style.KeepingToolDefaults(_style); // the text's look loads into the panel
        var box = new TextBox
        {
            Text = existing?.Text ?? "",
            AcceptsReturn = false,
            TextWrapping = TextWrapping.Wrap,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0),
            Background = Brushes.Transparent,
            Template = BareTextBoxTemplate(),
        };
        var host = new Border { Child = box };
        var frame = new Rectangle { Stroke = SelectionBlue, StrokeDashArray = new DoubleCollection { 4, 3 }, IsHitTestVisible = false };
        _textEdit = new TextEditSession
        {
            Box = box, Host = host, Frame = frame, Origin = origin, WrapWidth = wrapWidth, ExistingId = existing?.Id, Original = existing, Style = style,
        };
        _selection.Clear();
        InteractionLayer.Children.Add(frame);
        InteractionLayer.Children.Add(host);
        ApplyTextEditLook();
        box.PreviewKeyDown += TextBoxKeyDown;
        box.TextChanged += (_, _) => PositionTextEditor();
        box.LostKeyboardFocus += (_, e) =>
        {
            if (!ReferenceEquals(_textEdit?.Box, box)) return;
            if (KeepsTextEditOpen(e.NewFocus)) return; // restyling from the inspector / a colour picker (round 2 #8)
            CommitText();
        };
        box.CaretIndex = box.Text.Length;
        CanvasImage.Source = DocumentRenderer.Render(HiddenWhileEditing(), _baseImage);
        RefreshChrome();
        Dispatcher.BeginInvoke(new Action(() => { box.Focus(); Keyboard.Focus(box); }), System.Windows.Threading.DispatcherPriority.Input);
    }

    /// <summary>A colour dialog or eyedropper session is open on behalf of the live text.</summary>
    private bool _pickerOpen;

    /// <summary>Focus moving to the inspector (a font or size list, its drop-down) or to a picker session restyles the
    /// text being typed (v3 §1.4: restyle the live text, commit as one step) — it must not commit it.</summary>
    private bool KeepsTextEditOpen(IInputElement? newFocus)
    {
        if (_pickerOpen) return true;
        for (var d = newFocus as DependencyObject; d is not null; d = UpTree(d))
            if (ReferenceEquals(d, _panel)) return true;
        return false;
    }

    /// <summary>Up the visual tree, across a popup (a ComboBox drop-down) to the element that owns it.</summary>
    private static DependencyObject? UpTree(DependencyObject d)
    {
        if (d is System.Windows.Controls.Primitives.Popup popup) return popup.PlacementTarget ?? popup.Parent;
        var up = d is Visual or System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(d) : null;
        return up ?? LogicalTreeHelper.GetParent(d) ?? (d as FrameworkElement)?.TemplatedParent;
    }

    /// <summary>Hands the keyboard back to the live text after a restyle, so typing carries on.</summary>
    private void RefocusTextEdit()
    {
        if (_textEdit?.Box is not { } box) return;
        Dispatcher.BeginInvoke(new Action(() =>
        {
            if (ReferenceEquals(_textEdit?.Box, box)) { box.Focus(); Keyboard.Focus(box); }
        }), System.Windows.Threading.DispatcherPriority.Input);
    }

    private static ControlTemplate BareTextBoxTemplate()
    {
        var host = new FrameworkElementFactory(typeof(ScrollViewer), "PART_ContentHost");
        host.SetValue(ScrollViewer.HorizontalScrollBarVisibilityProperty, ScrollBarVisibility.Disabled);
        host.SetValue(ScrollViewer.VerticalScrollBarVisibilityProperty, ScrollBarVisibility.Disabled);
        host.SetValue(MarginProperty, new Thickness(0));
        host.SetValue(PaddingProperty, new Thickness(0));
        return new ControlTemplate(typeof(TextBox)) { VisualTree = host };
    }

    /// <summary>Font, colour, decorations, box and opacity of the live editor = the session style.</summary>
    private void ApplyTextEditLook()
    {
        if (_textEdit is not { } s) return;
        var st = s.Style;
        var tf = TextRendering.Typeface(st);
        var box = s.Box;
        box.FontFamily = tf.FontFamily;
        box.FontWeight = tf.Weight;
        box.FontStyle = tf.Style;
        box.FontSize = st.FontSize;
        box.Foreground = DocumentRenderer.Solid(st.StrokeColor);
        box.CaretBrush = DocumentRenderer.Solid(st.StrokeColor);
        box.TextAlignment = TextRendering.Alignment(st.TextAlignment);
        var deco = new TextDecorationCollection();
        if (st.TextUnderline) deco.Add(TextDecorations.Underline);
        if (st.TextStrikethrough) deco.Add(TextDecorations.Strikethrough);
        box.TextDecorations = deco;
        bool hasBox = st.TextBackgroundMode != TextBackgroundMode.None;
        var inset = TextChip.Insets(st.TextBackgroundPadding);
        s.Host.Padding = hasBox ? new Thickness(inset.Width, inset.Height, inset.Width, inset.Height) : new Thickness(0);
        s.Host.Background = hasBox ? DocumentRenderer.Solid(st.TextBackgroundMode == TextBackgroundMode.Auto ? TextChip.AutoColor(st.StrokeColor) : st.TextBackgroundColor) : Brushes.Transparent;
        s.Host.CornerRadius = new CornerRadius(hasBox ? st.TextBackgroundCornerRadius : 0);
        s.Host.Opacity = st.Opacity;
        PositionTextEditor();
    }

    /// <summary>A free label grows to the right up to the canvas edge, then wraps and grows down; a text box keeps
    /// its width and grows down. Earlier lines never scroll out of view.</summary>
    private void PositionTextEditor()
    {
        if (_textEdit is not { } s) return;
        var st = s.Style;
        bool hasBox = st.TextBackgroundMode != TextBackgroundMode.None;
        var inset = hasBox ? TextChip.Insets(st.TextBackgroundPadding) : new PxSize(0, 0);
        double room = Math.Max(st.FontSize, _baseImage.PixelWidth - s.Origin.X);
        if (s.WrapWidth is { } w) { s.Box.Width = w; s.Box.MaxWidth = double.PositiveInfinity; }
        else
        {
            var natural = TextRendering.Measure(s.Box.Text, st, null);
            s.Box.Width = Math.Max(st.FontSize * 0.6, Math.Min(room, Math.Ceiling(natural.Width) + 2));
        }
        Canvas.SetLeft(s.Host, s.Origin.X - inset.Width);
        Canvas.SetTop(s.Host, s.Origin.Y - inset.Height);
        s.Host.UpdateLayout();
        double gap = View(3);
        s.Frame.StrokeThickness = View(1);
        s.Frame.Width = s.Host.ActualWidth + 2 * gap;
        s.Frame.Height = s.Host.ActualHeight + 2 * gap;
        Canvas.SetLeft(s.Frame, s.Origin.X - inset.Width - gap);
        Canvas.SetTop(s.Frame, s.Origin.Y - inset.Height - gap);
    }

    private void TextBoxKeyDown(object sender, KeyEventArgs e)
    {
        if (_textEdit is not { } s) return;
        bool shift = (Keyboard.Modifiers & ModifierKeys.Shift) != 0;
        if (e.Key == Key.Enter && shift)
        {
            int caret = s.Box.CaretIndex;
            s.Box.SelectedText = "\n";
            s.Box.CaretIndex = caret + 1;
            s.Box.SelectionLength = 0;
            e.Handled = true;
        }
        else if (e.Key is Key.Enter or Key.Escape)
        {
            e.Handled = true;
            CommitText();
        }
    }

    /// <summary>Commits the live text: same id when editing (one undo step; unchanged = no step; emptied = deleted).</summary>
    private void CommitText()
    {
        if (_textEdit is not { } s) return;
        _textEdit = null;
        string text = s.Box.Text.Replace("\r\n", "\n");
        InteractionLayer.Children.Remove(s.Host);
        InteractionLayer.Children.Remove(s.Frame);

        double? wrap = s.WrapWidth;
        if (wrap is null)
        {
            // A free label that wrapped at the canvas edge is stored with the room it had.
            double room = Math.Max(s.Style.FontSize, _baseImage.PixelWidth - s.Origin.X);
            if (TextRendering.Measure(text, s.Style, null).Width > room) wrap = room;
        }

        if (s.Original is { } original)
        {
            if (string.IsNullOrWhiteSpace(text)) { PushUndo(); _document.Remove(original.Id); }
            else
            {
                var updated = original with { Text = text, Style = s.Style, WrapWidth = wrap };
                if (updated != original) { PushUndo(); _document.Replace(original.Id, updated); }
                SelectOnly(original.Id);
            }
        }
        else if (!string.IsNullOrWhiteSpace(text))
        {
            PushUndo();
            var t = new TextAnnotation(Guid.NewGuid(), s.Style, text, s.Origin, wrap);
            _document.Add(t);
            SelectOnly(t.Id);
            PostAdded(EditorTool.Text);
        }
        Redraw();
        Focus();
    }
}
