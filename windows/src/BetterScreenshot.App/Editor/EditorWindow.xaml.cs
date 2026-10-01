using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Controls;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using Brushes = System.Windows.Media.Brushes;
using Button = System.Windows.Controls.Button;
using Color = System.Windows.Media.Color;
using ContextMenu = System.Windows.Controls.ContextMenu;
using Key = System.Windows.Input.Key;
using Keyboard = System.Windows.Input.Keyboard;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MenuItem = System.Windows.Controls.MenuItem;
using ModifierKeys = System.Windows.Input.ModifierKeys;
using MouseWheelEventArgs = System.Windows.Input.MouseWheelEventArgs;
using Orientation = System.Windows.Controls.Orientation;
using Separator = System.Windows.Controls.Separator;
using TextBlock = System.Windows.Controls.TextBlock;
using ToggleButton = System.Windows.Controls.Primitives.ToggleButton;

namespace BetterScreenshot.App.Editor;

/// <summary>
/// The annotation editor (v3 Parts 1–3 + A.1): a tool pill centred over a zoomable canvas, a 264-px inspector
/// panel on the right, and a bottom bar with the hint line and the action row. Snapshot undo/redo; every style
/// edit applies to the default style and to the selection as one undo step; the sticky default style and the
/// Recent colours are reported to the host for persistence.
/// </summary>
public partial class EditorWindow : Window
{
    private sealed record EditorState(EditorDocument Document, BitmapSource BaseImage);

    private BitmapSource _baseImage;
    private EditorDocument _document;
    private AnnotationStyle _style;
    private EditorTool _tool = EditorTool.Select;
    private readonly UndoHistory<EditorState> _history = new();
    private readonly List<Guid> _selection = new();
    private readonly RecentColors _recent;
    private string? _openGroup;
    private readonly EditorInspectorPanel _panel = new();
    private readonly Dictionary<EditorTool, ToggleButton> _toolButtons = new();
    private Button? _undoButton, _redoButton;
    private ToggleButton? _panelToggle;

    // Zoom (v3 §1.4): magnification = DIPs per image pixel; Fit by default (never above 100%).
    private double _magnification = 1;
    private bool _fitMode = true;

    public Action<BitmapSource>? OnCopy { get; set; }
    public Action<BitmapSource>? OnSave { get; set; }
    public Action<BitmapSource>? OnAddToStack { get; set; }
    public Action<AnnotationStyle>? StyleChanged { get; set; }
    public Action<IReadOnlyList<RGBAColor>>? RecentColorsChanged { get; set; }

    public EditorWindow(BitmapSource image, AnnotationStyle? defaultStyle = null, IEnumerable<RGBAColor>? recentColors = null)
    {
        TextRendering.Install();
        InitializeComponent();
        Resources["Ed.AccentBrush"] = SystemAccent.Brush;
        Surfaces.UseMica(this); // v3 Part 9: Mica + the Opacity layer (dark title bar included)
        _baseImage = image;
        _style = (defaultStyle ?? AnnotationStyle.Default).Normalized();
        _recent = new RecentColors(recentColors);
        _document = new EditorDocument(new PxSize(image.PixelWidth, image.PixelHeight));

        BuildToolbar();
        BuildTitleActions();
        PanelHost.Child = _panel;
        WirePanel();
        HintIcon.Content = new IconPresenter { IconKey = "info", Brush = new SolidColorBrush(Color.FromArgb(0x73, 255, 255, 255)), Width = 13, Height = 13 };
        CopyButton.Content = IconText("copy", "Copy");
        SaveButton.Content = IconText("save", "Save");
        StackButton.Content = IconText("stack", "Stack");

        ResizeStage();
        InteractionLayer.MouseLeftButtonDown += OnDown;
        InteractionLayer.MouseMove += OnMove;
        InteractionLayer.MouseLeftButtonUp += OnUp;
        InteractionLayer.MouseLeave += (_, _) => { if (_drag == DragKind.None) InteractionLayer.Cursor = null; };
        PreviewKeyDown += OnKeyDown;
        Scroller.PreviewMouseWheel += OnWheel;
        Scroller.SizeChanged += (_, _) => { if (_fitMode) ApplyFit(); };
        SourceInitialized += (_, _) => SizeToImage();
        Loaded += (_, _) => { ApplyFit(); Focus(); };
        Closed += (_, _) => ReleaseResources();

        SelectTool(EditorTool.Select);
        Redraw();
    }

    // ------------------------------------------------------------------ window size + chrome

    private double DpiScale => VisualTreeHelper.GetDpi(this).DpiScaleX;

    /// <summary>Initial size (v3 §1.1): the capture's real on-screen size (≤ 1200 DIPs wide) + chrome, clamped to
    /// the work area; centred on the screen in use.</summary>
    private void SizeToImage()
    {
        var size = ZoomMath.PointSize(new PxSize(_baseImage.PixelWidth, _baseImage.PixelHeight), DpiScale);
        double imgW = Math.Min(size.Width, 1200);
        double imgH = size.Width > 0 ? imgW * size.Height / size.Width : size.Height;
        var work = WindowPlacement.WorkAreaUnderCursor(this);
        Width = Math.Min(Math.Max(imgW + 48, 600) + 284 + 16, work.Width - 40);
        Height = Math.Min(Math.Max(imgH + 112 + 64 + 40, 660), work.Height - 60);
        Left = work.Left + (work.Width - Width) / 2;
        Top = work.Top + (work.Height - Height) / 2;
    }

    private void BuildToolbar()
    {
        bool firstGroup = true;
        foreach (var group in ToolInfo.ToolbarGroups)
        {
            if (!firstGroup)
                Toolbar.Children.Add(new Border { Width = 1, Height = 22, Margin = new Thickness(4, 0, 4, 0), Background = new SolidColorBrush(Color.FromArgb(0x21, 255, 255, 255)) });
            firstGroup = false;
            foreach (var tool in group)
            {
                var t = tool;
                var button = new ToggleButton
                {
                    Content = new IconPresenter { IconKey = tool.IconKey(), Brush = Brushes.White, Width = 18, Height = 18 },
                    Style = (Style)FindResource("Ed.ToolButton"),
                    ToolTip = tool.Tooltip(),
                };
                System.Windows.Automation.AutomationProperties.SetName(button, tool.DisplayName());
                button.Click += (_, _) => SelectTool(t);
                _toolButtons[tool] = button;
                Toolbar.Children.Add(button);
            }
        }
    }

    private void BuildTitleActions()
    {
        _undoButton = IconButton("undo", "Undo (Ctrl+Z)", Undo);
        _redoButton = IconButton("redo", "Redo (Ctrl+Shift+Z)", Redo);
        _panelToggle = new ToggleButton
        {
            Content = new IconPresenter { IconKey = "sidebar", Brush = Brushes.White, Width = 16, Height = 16 },
            Style = (Style)FindResource("Ed.IconButton"), IsChecked = true, Margin = new Thickness(10, 0, 0, 0),
        };
        _panelToggle.Click += (_, _) => TogglePanel();
        TitleActions.Children.Add(_undoButton);
        TitleActions.Children.Add(_redoButton);
        TitleActions.Children.Add(_panelToggle);
        UpdatePanelToggleTip();
    }

    private Button IconButton(string icon, string tip, Action click)
    {
        var b = new Button
        {
            Content = new IconPresenter { IconKey = icon, Brush = Brushes.White, Width = 16, Height = 16 },
            Style = (Style)FindResource("Ed.IconButton"), ToolTip = tip,
        };
        System.Windows.Automation.AutomationProperties.SetName(b, tip);
        b.Click += (_, _) => click();
        return b;
    }

    private static StackPanel IconText(string icon, string text)
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal };
        sp.Children.Add(new IconPresenter { IconKey = icon, Brush = Brushes.White, Width = 14, Height = 14, Margin = new Thickness(0, 0, 5, 0) });
        sp.Children.Add(new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center });
        return sp;
    }

    private bool PanelShown => _panelToggle?.IsChecked != false;

    private void TogglePanel()
    {
        bool show = PanelHost.Visibility != Visibility.Visible;
        PanelHost.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        PanelColumn.Width = new GridLength(show ? 284 : 0);
        MinWidth = show ? 884 : 600;
        if (show && Width < 884) Width = 884;
        if (_panelToggle != null) _panelToggle.IsChecked = show;
        UpdatePanelToggleTip();
        if (_fitMode) Dispatcher.BeginInvoke(new Action(ApplyFit), System.Windows.Threading.DispatcherPriority.Loaded);
    }

    private void UpdatePanelToggleTip()
    {
        if (_panelToggle != null)
            _panelToggle.ToolTip = PanelHost.Visibility == Visibility.Visible ? "Hide Inspector (Ctrl+Alt+I)" : "Show Inspector (Ctrl+Alt+I)";
    }

    // ------------------------------------------------------------------ tools

    private void SelectTool(EditorTool tool)
    {
        if (_textEdit != null) CommitText();
        // Choosing a drawing tool clears the selection; choosing Select keeps it.
        if (tool != EditorTool.Select && tool != _tool) _selection.Clear();
        _tool = tool;
        _openGroup = null;
        foreach (var (t, b) in _toolButtons) b.IsChecked = t == tool;
        InteractionLayer.Cursor = tool == EditorTool.Select ? null : System.Windows.Input.Cursors.Cross;
        RefreshChrome();
    }

    /// <summary>The selection described by the tools that draw it, in stacking order.</summary>
    private List<EditorTool> SelectionMakers() =>
        _document.Annotations.Where(a => _selection.Contains(a.Id)).Select(a => ToolInfo.MakerOf(a)).OfType<EditorTool>().ToList();

    private IAnnotation? BackMostSelected() => _document.Annotations.FirstOrDefault(a => _selection.Contains(a.Id));

    /// <summary>Panel + hint + selection chrome + undo buttons, after any state change.</summary>
    private void RefreshChrome()
    {
        var makers = SelectionMakers();
        var content = _textEdit != null
            ? InspectorModel.Content(EditorTool.Text, Array.Empty<EditorTool>())
            : InspectorModel.Content(_tool, makers);
        bool editsPen = StyleEdits.EditsPen(_tool, makers);
        var shown = _textEdit?.Style ?? StyleEdits.Shown(_style, _tool == EditorTool.Select || _selection.Count > 0 ? BackMostSelected() : null, editsPen);
        // Under a redaction tool the panel reflects the tool's mode (B / P / X), not the default style's.
        if (_tool.RedactionModeOf() is { } mode && _selection.Count == 0) shown = shown with { RedactionMode = mode };
        _panel.Show(content, shown, _recent.Colors);
        HintText.Text = InspectorModel.Hint(_tool, makers, _textEdit != null);
        HintText.ToolTip = HintText.Text;
        if (_undoButton != null) _undoButton.IsEnabled = _history.CanUndo;
        if (_redoButton != null) _redoButton.IsEnabled = _history.CanRedo;
        SizeText.Text = $"{_baseImage.PixelWidth} × {_baseImage.PixelHeight} px";
        RefreshOverlay();
    }

    // ------------------------------------------------------------------ style edits (v3 §1.4)

    private void WirePanel()
    {
        _panel.Edit += (edit, group) => ApplyEdit(edit, group);
        _panel.EndGroup += () => _openGroup = null;
        _panel.Preset += p => ApplyEdit(st => p.Apply(st), null);
        _panel.DimEdit += v => ApplyEdit(st => st with { SpotlightDim = v }, "dim", dimEdit: true);
        _panel.RedactionSwitch += SwitchRedaction;
        _panel.BringToFront += () => Arrange(front: true);
        _panel.SendToBack += () => Arrange(front: false);
        _panel.DeleteSelection += DeleteSelected;
        _panel.OpenColorWell += OpenColorWell;
        _panel.Eyedropper += PickFromScreen;
        _panel.RecentPicked += c => { _recent.Add(c); RecentColorsChanged?.Invoke(_recent.Colors); ApplyEdit(st => WithStroke(st, c), null); };
    }

    private static AnnotationStyle WithStroke(AnnotationStyle st, RGBAColor c)
    {
        var s = st with { StrokeColor = c, FillColor = c.WithAlpha(0.25) };
        return s.TextOutline ? s with { TextOutlineColor = TextChip.OutlineColor(s.TextOutlineColor, c) } : s;
    }

    /// <summary>Applies one edit to the default style and every selected object as ONE undo step (edits with the
    /// same open <paramref name="group"/> merge). While a text is being typed it restyles the live text.</summary>
    private void ApplyEdit(Func<AnnotationStyle, AnnotationStyle> edit, string? group, bool dimEdit = false)
    {
        var makers = SelectionMakers();
        bool editsPen = StyleEdits.EditsPen(_tool, makers);
        if (_textEdit != null)
        {
            _textEdit.Style = edit(_textEdit.Style).Normalized();
            ApplyTextEditLook();
        }
        _style = StyleEdits.ApplyToDefault(_style, edit, editsPen);
        StyleChanged?.Invoke(_style);

        if (_textEdit == null)
        {
            double? newDim = dimEdit ? edit(_style).SpotlightDim : null;
            var next = StyleEdits.ApplyToDocument(_document, _selection, edit, dimEdit, newDim);
            if (next != null)
            {
                if (group == null || group != _openGroup) PushUndo();
                _document = next;
                Redraw(keepGroup: true);
            }
        }
        _openGroup = group;
        RefreshChrome();
    }

    private void SwitchRedaction(RedactionMode mode)
    {
        ApplyEdit(st => st with { RedactionMode = mode }, null);
        // A redaction tool switches to that mode WITHOUT clearing the selection (the just-drawn box stays selected).
        if (_tool.RedactionModeOf() != null)
        {
            _tool = ToolInfo.ToolOf(mode);
            foreach (var (t, b) in _toolButtons) b.IsChecked = t == _tool;
            RefreshChrome();
        }
    }

    private void OpenColorWell(ColorTarget target)
    {
        var current = target switch
        {
            ColorTarget.Box => (_textEdit?.Style ?? _style).TextBackgroundColor,
            ColorTarget.Outline => (_textEdit?.Style ?? _style).TextOutlineColor,
            _ => (_textEdit?.Style ?? StyleEdits.Shown(_style, BackMostSelected(), StyleEdits.EditsPen(_tool, SelectionMakers()))).StrokeColor,
        };
        using var dialog = new System.Windows.Forms.ColorDialog
        {
            FullOpen = true, AnyColor = true,
            Color = System.Drawing.Color.FromArgb((int)Math.Round(current.R * 255), (int)Math.Round(current.G * 255), (int)Math.Round(current.B * 255)),
        };
        if (dialog.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;
        var c = RGBAColor.FromBytes(dialog.Color.R, dialog.Color.G, dialog.Color.B, (byte)Math.Round(current.A * 255));
        ApplyPickedColor(target, c);
    }

    private void PickFromScreen(ColorTarget target)
    {
        Eyedropper.Pick(c =>
        {
            Activate();
            if (c is { } color) ApplyPickedColor(target, color);
        });
    }

    /// <summary>One picker session = one Recent entry + one undo step.</summary>
    private void ApplyPickedColor(ColorTarget target, RGBAColor c)
    {
        _recent.Add(c);
        RecentColorsChanged?.Invoke(_recent.Colors);
        switch (target)
        {
            case ColorTarget.Box: ApplyEdit(st => st with { TextBackgroundColor = c }, null); break;
            case ColorTarget.Outline: ApplyEdit(st => st with { TextOutlineColor = c, TextOutline = true }, null); break;
            default: ApplyEdit(st => WithStroke(st, c), null); break;
        }
    }

    // ------------------------------------------------------------------ document ops

    private EditorState Snapshot() => new(new EditorDocument(_document.Size, _document.Annotations), _baseImage);

    private void PushUndo()
    {
        _history.Push(Snapshot());
        _openGroup = null;
    }

    private void Arrange(bool front)
    {
        if (_selection.Count == 0) return;
        PushUndo();
        var ordered = _document.Annotations.Where(a => _selection.Contains(a.Id)).Select(a => a.Id).ToList();
        if (front) foreach (var id in ordered) _document.BringToFront(id);
        else foreach (var id in Enumerable.Reverse(ordered)) _document.SendToBack(id);
        Redraw();
    }

    private void DeleteSelected()
    {
        if (_selection.Count == 0) return;
        PushUndo();
        foreach (var id in _selection) _document.Remove(id);
        _selection.Clear();
        Redraw();
    }

    private void Undo()
    {
        if (_textEdit != null) { CommitText(); }
        if (!_history.TryUndo(Snapshot(), out var prev)) return;
        Restore(prev);
    }

    private void Redo()
    {
        if (_textEdit != null) CommitText();
        if (!_history.TryRedo(Snapshot(), out var next)) return;
        Restore(next);
    }

    private void Restore(EditorState state)
    {
        bool sizeChanged = state.BaseImage.PixelWidth != _baseImage.PixelWidth || state.BaseImage.PixelHeight != _baseImage.PixelHeight;
        _document = state.Document;
        _baseImage = state.BaseImage;
        _selection.RemoveAll(id => _document.Find(id) is null);
        _openGroup = null;
        ResizeStage();
        if (sizeChanged && _fitMode) ApplyFit();
        Redraw();
    }

    private void ResizeStage()
    {
        Stage.Width = _baseImage.PixelWidth;
        Stage.Height = _baseImage.PixelHeight;
        InteractionLayer.Width = _baseImage.PixelWidth;
        InteractionLayer.Height = _baseImage.PixelHeight;
    }

    private void Redraw(bool keepGroup = false)
    {
        if (!keepGroup) _openGroup = null;
        CanvasImage.Source = DocumentRenderer.Render(HiddenWhileEditing(), _baseImage);
        RefreshChrome();
    }

    /// <summary>The document minus the text being edited in place (the live box draws it).</summary>
    private EditorDocument HiddenWhileEditing() =>
        _textEdit?.ExistingId is { } id ? new EditorDocument(_document.Size, _document.Annotations.Where(a => a.Id != id)) : _document;

    private BitmapSource Export()
    {
        if (_textEdit != null) CommitText();
        return DocumentRenderer.Render(_document, _baseImage);
    }

    private void ReleaseResources()
    {
        CanvasImage.Source = null;
        _moveBackground = null;
        _spotBackground = null;
    }

    private void Done_Click(object sender, RoutedEventArgs e) => Close();
    private void Copy_Click(object sender, RoutedEventArgs e) => OnCopy?.Invoke(Export());
    private void Save_Click(object sender, RoutedEventArgs e) { OnSave?.Invoke(Export()); Close(); }
    private void Stack_Click(object sender, RoutedEventArgs e) { OnAddToStack?.Invoke(Export()); Close(); }

    // ------------------------------------------------------------------ keys

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        var mods = Keyboard.Modifiers;
        bool ctrl = (mods & ModifierKeys.Control) != 0, shift = (mods & ModifierKeys.Shift) != 0, alt = (mods & ModifierKeys.Alt) != 0;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;

        if (_textEdit != null) return; // the live text box owns the keyboard (its own Enter/Esc handling)

        if (ctrl && alt && key == Key.I) { TogglePanel(); e.Handled = true; return; }
        if (ctrl && key == Key.Z && !shift) { Undo(); e.Handled = true; return; }
        if (ctrl && (key == Key.Y || (key == Key.Z && shift))) { Redo(); e.Handled = true; return; }
        if (ctrl && (key is Key.OemPlus or Key.Add)) { StepZoom(true); e.Handled = true; return; }
        if (ctrl && (key is Key.OemMinus or Key.Subtract)) { StepZoom(false); e.Handled = true; return; }
        if (ctrl && (key is Key.D0 or Key.NumPad0)) { ApplyFit(); e.Handled = true; return; }
        if (ctrl && (key is Key.D1 or Key.NumPad1)) { SetZoomPercent(100, null); e.Handled = true; return; }
        if (ctrl && key == Key.S) { Save_Click(this, e); e.Handled = true; return; }
        if (ctrl && key == Key.W) { Close(); e.Handled = true; return; }
        if (ctrl && key == Key.C) { Copy_Click(this, e); e.Handled = true; return; }
        if (ctrl && key == Key.A && _tool == EditorTool.Select)
        {
            _selection.Clear();
            _selection.AddRange(_document.Annotations.Select(a => a.Id));
            RefreshChrome();
            e.Handled = true;
            return;
        }
        if (ctrl || alt) return;

        switch (key)
        {
            case Key.Escape:
                if (_drag != DragKind.None) { CancelDrag(); e.Handled = true; return; }
                if (_tool != EditorTool.Select) SelectTool(EditorTool.Select);
                else { _selection.Clear(); RefreshChrome(); }
                e.Handled = true;
                return;
            case Key.Delete:
            case Key.Back:
                DeleteSelected();
                e.Handled = true;
                return;
            case Key.OemOpenBrackets:
                Arrange(front: false);
                e.Handled = true;
                return;
            case Key.OemCloseBrackets:
                Arrange(front: true);
                e.Handled = true;
                return;
        }
        // Single-key tool shortcuts (case-insensitive, no modifiers).
        if (key is >= Key.A and <= Key.Z && ToolInfo.ForShortcut(key.ToString()) is { } tool)
        {
            SelectTool(tool);
            e.Handled = true;
        }
    }

    // ------------------------------------------------------------------ zoom

    // The scroller's full size, not its viewport: the viewport shrinks while zoomed-in scrollbars show, which made
    // "fit" drift (90% on open, 97% after a zoom round-trip) and 100% mislabelled as fit.
    private PxSize AvailableForImage() => new(
        Math.Max(1, Scroller.ActualWidth - 48),
        Math.Max(1, Scroller.ActualHeight - 44));

    private double FitMagnification() =>
        ZoomMath.FitMagnification(new PxSize(_baseImage.PixelWidth, _baseImage.PixelHeight), AvailableForImage(), DpiScale);

    private void ApplyFit()
    {
        if (!IsLoaded && Scroller.ActualWidth <= 0) return;
        _fitMode = true;
        SetMagnification(FitMagnification(), null);
    }

    private void StepZoom(bool zoomIn)
    {
        double percent = ZoomMath.Percent(_magnification, DpiScale);
        SetZoomPercent(ZoomMath.SteppedPercent(percent, zoomIn), null);
    }

    private void SetZoomPercent(double percent, System.Windows.Point? anchorInViewport)
    {
        double m = ZoomMath.Clamp(ZoomMath.Magnification(percent, DpiScale), FitMagnification(), DpiScale);
        _fitMode = ZoomMath.IsFit(m, FitMagnification());
        SetMagnification(m, anchorInViewport);
    }

    private void OnWheel(object sender, MouseWheelEventArgs e)
    {
        if ((Keyboard.Modifiers & ModifierKeys.Control) == 0)
        {
            if ((Keyboard.Modifiers & ModifierKeys.Shift) != 0)
            {
                Scroller.ScrollToHorizontalOffset(Scroller.HorizontalOffset - e.Delta);
                e.Handled = true;
            }
            return;
        }
        e.Handled = true;
        // Ctrl+wheel and precision-touchpad pinch: continuous, ×e^(0.001·Δ) ≈ 13% per notch, anchored on the pointer.
        double fit = FitMagnification();
        double m = ZoomMath.Clamp(_magnification * Math.Exp(0.001 * e.Delta), fit, DpiScale);
        _fitMode = ZoomMath.IsFit(m, fit);
        SetMagnification(m, e.GetPosition(Scroller));
    }

    /// <summary>Applies <paramref name="m"/>; keeps the image point under <paramref name="anchor"/> (viewport
    /// coordinates; default = the centre of the visible area) on the same spot of the screen.</summary>
    private void SetMagnification(double m, System.Windows.Point? anchor)
    {
        var viewportAnchor = anchor ?? new System.Windows.Point(Scroller.ViewportWidth / 2, Scroller.ViewportHeight / 2);
        var imagePoint = Scroller.TranslatePoint(viewportAnchor, InteractionLayer);
        _magnification = m;
        StageScale.ScaleX = StageScale.ScaleY = m;
        double percent = ZoomMath.Percent(m, DpiScale);
        RenderOptions.SetBitmapScalingMode(CanvasImage, percent >= 300 ? BitmapScalingMode.NearestNeighbor : BitmapScalingMode.HighQuality);
        ZoomButton.Content = ZoomLabel(ZoomMath.Label(percent, _fitMode));
        Scroller.UpdateLayout();
        var now = InteractionLayer.TranslatePoint(imagePoint, Scroller);
        Scroller.ScrollToHorizontalOffset(Scroller.HorizontalOffset + now.X - viewportAnchor.X);
        Scroller.ScrollToVerticalOffset(Scroller.VerticalOffset + now.Y - viewportAnchor.Y);
        RefreshOverlay();
        if (_textEdit != null) PositionTextEditor();
    }

    private static StackPanel ZoomLabel(string text)
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal };
        sp.Children.Add(new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center, Typography = { NumeralAlignment = FontNumeralAlignment.Tabular } });
        sp.Children.Add(new IconPresenter { IconKey = "chevron-down", Brush = Brushes.White, Width = 12, Height = 12, Margin = new Thickness(6, 0, 0, 0) });
        return sp;
    }

    private void Zoom_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu { PlacementTarget = ZoomButton, Placement = System.Windows.Controls.Primitives.PlacementMode.Top };
        void Add(string header, string gesture, Action act)
        {
            var item = new MenuItem { Header = header, InputGestureText = gesture };
            item.Click += (_, _) => act();
            menu.Items.Add(item);
        }
        Add("Zoom In", "Ctrl+Plus", () => StepZoom(true));
        Add("Zoom Out", "Ctrl+Minus", () => StepZoom(false));
        menu.Items.Add(new Separator());
        Add("Fit to Window", "Ctrl+0", ApplyFit);
        Add("Actual Size (100%)", "Ctrl+1", () => SetZoomPercent(100, null));
        menu.Items.Add(new Separator());
        foreach (var p in new[] { 50, 200, 400, 800 }) { int pp = p; Add($"{pp}%", "", () => SetZoomPercent(pp, null)); }
        menu.IsOpen = true;
    }
}

public partial class EditorWindow
{
    // ---- Preview hooks (--ui-preview): stage a tool + objects without user input.
    internal void PreviewUseTool(EditorTool tool) => SelectTool(tool);

    internal void PreviewAdd(IAnnotation a, bool select)
    {
        _document.Add(a);
        if (select) _selection.Add(a.Id);
        Redraw();
    }

    internal void PreviewEditText(TextAnnotation t) => BeginTextEdit(t.Origin, t.WrapWidth, null);
}
