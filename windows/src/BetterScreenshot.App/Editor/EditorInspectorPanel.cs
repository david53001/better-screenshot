using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Threading;
using BetterScreenshot.App.Controls;
using BetterScreenshot.Editor;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Button = System.Windows.Controls.Button;
using CheckBox = System.Windows.Controls.CheckBox;
using Color = System.Windows.Media.Color;
using ComboBox = System.Windows.Controls.ComboBox;
using FontFamily = System.Windows.Media.FontFamily;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Orientation = System.Windows.Controls.Orientation;
using ScrollViewer = System.Windows.Controls.ScrollViewer;
using Slider = System.Windows.Controls.Slider;
using TextBlock = System.Windows.Controls.TextBlock;

namespace BetterScreenshot.App.Editor;

/// <summary>Which colour a colour well / eyedropper edits.</summary>
public enum ColorTarget { Stroke, Box, Outline }

/// <summary>
/// The editor's 264-px dark side panel (v3 Parts 1–3): a heading plus the sections <see cref="InspectorModel"/>
/// lists for the active tool / selection, and the Arrange footer pinned to the bottom. Every control raises a
/// style edit (a function of the style) that the window applies to the default style and the selection; slider
/// drags and colour-picker sessions carry a group key so they merge into one undo step.
/// </summary>
internal sealed class EditorInspectorPanel : Border
{
    private const double ContentWidth = 230, LabelWidth = 56, ValueWidth = 40; // 264 − 2×16 padding − 2×1 border

    public event Action<Func<AnnotationStyle, AnnotationStyle>, string?>? Edit;
    public event Action? EndGroup;
    public event Action<TextStylePreset>? Preset;
    public event Action<RedactionMode>? RedactionSwitch;
    public event Action? BringToFront, SendToBack, DeleteSelection;
    public event Action<ColorTarget>? OpenColorWell;
    public event Action<ColorTarget>? Eyedropper;
    public event Action<RGBAColor>? RecentPicked;
    public event Action<double>? DimEdit;

    private readonly TextBlock _heading;
    private readonly ScrollViewer _scroll;
    private readonly StackPanel _sections;
    private readonly Border _footer;

    private InspectorContent _content = new("", Array.Empty<InspectorSection>());
    private AnnotationStyle _style = AnnotationStyle.Default;
    private IReadOnlyList<RGBAColor> _recent = Array.Empty<RGBAColor>();
    private bool _dragging;
    private bool _rebuildQueued;

    public EditorInspectorPanel()
    {
        Width = 264;
        CornerRadius = new CornerRadius(12);
        SetResourceReference(BackgroundProperty, "Panel.SurfaceBrush"); // docked panel, live with Opacity
        BorderBrush = Res("Ed.HairlineBrush");
        BorderThickness = new Thickness(1);
        SnapsToDevicePixels = true;

        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        _heading = new TextBlock
        {
            FontSize = 13, FontWeight = FontWeights.SemiBold, Foreground = Res("Ed.TextBrush"),
            Margin = new Thickness(16, 14, 16, 0), TextTrimming = TextTrimming.CharacterEllipsis,
        };
        grid.Children.Add(_heading);

        _sections = new StackPanel { Margin = new Thickness(0, 10, 0, 0) };
        _scroll = new ScrollViewer
        {
            Content = _sections, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Focusable = false,
        };
        Grid.SetRow(_scroll, 1);
        grid.Children.Add(_scroll);

        _footer = new Border { Visibility = Visibility.Collapsed };
        Grid.SetRow(_footer, 2);
        grid.Children.Add(_footer);
        Child = grid;
    }

    public InspectorContent Content => _content;

    /// <summary>Shows <paramref name="content"/> with values from <paramref name="shown"/>. Rebuilds are coalesced
    /// and skipped while a slider is being dragged (the slider is the source of the change).</summary>
    public void Show(InspectorContent content, AnnotationStyle shown, IReadOnlyList<RGBAColor> recent)
    {
        bool structural = !content.Equals(_content);
        _content = content;
        _style = shown;
        _recent = recent;
        if (_dragging && !structural) return;
        if (_rebuildQueued) return;
        _rebuildQueued = true;
        Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(Rebuild));
    }

    /// <summary>Synchronous rebuild (tests, previews).</summary>
    public void RebuildNow() { _rebuildQueued = true; Rebuild(); }

    private void Rebuild()
    {
        if (!_rebuildQueued) return;
        _rebuildQueued = false;
        double offset = _scroll.VerticalOffset;
        _heading.Text = _content.Title;
        _sections.Children.Clear();
        bool first = true;
        foreach (var section in _content.Sections)
        {
            if (section == InspectorSection.Arrange) continue;
            var built = Build(section);
            if (built is null) continue;
            if (!first) _sections.Children.Add(Hairline());
            first = false;
            _sections.Children.Add(built);
        }
        BuildFooter(_content.Sections.Contains(InspectorSection.Arrange));
        _scroll.ScrollToVerticalOffset(offset);
    }

    // ---------------------------------------------------------------- sections

    private FrameworkElement? Build(InspectorSection s)
    {
        var panel = new StackPanel { Margin = new Thickness(16, 12, 16, 14) };
        if (s.Title() is { } title && s is not (InspectorSection.Opacity or InspectorSection.Strength or InspectorSection.SpotlightDim))
            panel.Children.Add(Caption(title));
        void Row(UIElement e) { if (panel.Children.Count > 0 && e is FrameworkElement fe) fe.Margin = new Thickness(0, 8, 0, 0); panel.Children.Add(e); }

        switch (s)
        {
            case InspectorSection.Styles:
            {
                var grid = new UniformGrid { Columns = 3, Width = ContentWidth + 8, Margin = new Thickness(-4, 0, -4, 0) };
                foreach (var p in Enum.GetValues<TextStylePreset>()) grid.Children.Add(PresetChip(p));
                Row(grid);
                break;
            }
            case InspectorSection.Colour:
                Row(SwatchGrid(ColorPresets.Swatches, _style.StrokeColor, c => Edit?.Invoke(st => WithStroke(st, c), null)));
                if (_recent.Count > 0) Row(RecentRow());
                Row(CustomRow(ColorTarget.Stroke, _style.StrokeColor, "Custom colour — opens the colour picker"));
                break;
            case InspectorSection.Stroke:
                Row(SliderRow("Width", 1, 24, _style.LineWidth, v => $"{v:0} px", "stroke",
                    (st, v) => st with { LineWidth = Math.Round(v) }, null));
                Row(Segmented(ColorPresets.StrokePresets.Select(w => (Label: Name(w), Tip: $"{w:0} px", On: Math.Abs(_style.LineWidth - w) < 0.01,
                    Click: (Action)(() => Edit?.Invoke(st => st with { LineWidth = w }, null)))).ToArray()));
                break;
            case InspectorSection.HighlighterStroke:
                Row(SliderRow("Width", HighlighterPen.MinWidth, HighlighterPen.MaxWidth, _style.LineWidth, v => $"{v:0} px", "stroke",
                    (st, v) => st with { LineWidth = Math.Round(v) }, null));
                Row(Segmented(HighlighterPen.WidthPresets.Select(w => (Label: Name(w == 12 ? 2 : w == 20 ? 4 : 7), Tip: $"{w:0} px",
                    On: Math.Abs(_style.LineWidth - w) < 0.01, Click: (Action)(() => Edit?.Invoke(st => st with { LineWidth = w }, null)))).ToArray()));
                break;
            case InspectorSection.Font:
                Row(FontRow());
                Row(EmphasisRow());
                break;
            case InspectorSection.Background:
                Row(Segmented(new[]
                {
                    ("None", "No box behind the text", _style.TextBackgroundMode == TextBackgroundMode.None,
                        (Action)(() => Edit?.Invoke(st => st with { TextBackgroundMode = TextBackgroundMode.None }, null))),
                    ("Solid", "A box in the colour you pick below", _style.TextBackgroundMode == TextBackgroundMode.Solid,
                        () => Edit?.Invoke(st => st with { TextBackgroundMode = TextBackgroundMode.Solid }, null)),
                    ("Auto", "A dark or light box, whichever stands out against the text colour", _style.TextBackgroundMode == TextBackgroundMode.Auto,
                        () => Edit?.Invoke(st => st with { TextBackgroundMode = TextBackgroundMode.Auto }, null)),
                }));
                if (_style.TextBackgroundMode == TextBackgroundMode.Solid)
                {
                    Row(SwatchGrid(ColorPresets.BoxSwatches, _style.TextBackgroundColor, c => Edit?.Invoke(st => st with { TextBackgroundColor = c }, null)));
                    Row(CustomRow(ColorTarget.Box, _style.TextBackgroundColor, "Custom box colour — opens the colour picker"));
                }
                if (_style.TextBackgroundMode == TextBackgroundMode.Auto)
                    Row(Note("Dark or light — whichever stands out against the text colour."));
                if (_style.TextBackgroundMode != TextBackgroundMode.None)
                {
                    Row(SliderRow("Padding", 0, AnnotationStyle.MaxBoxPadding, _style.TextBackgroundPadding, v => $"{v:0} px", "padding",
                        (st, v) => st with { TextBackgroundPadding = Math.Round(v) }, "Space between the text and the edge of the box"));
                    Row(SliderRow("Corners", 0, AnnotationStyle.MaxBoxRadius, _style.TextBackgroundCornerRadius, v => $"{v:0} px", "corners",
                        (st, v) => st with { TextBackgroundCornerRadius = Math.Round(v) }, "How rounded the box's corners are"));
                }
                break;
            case InspectorSection.Effects:
            {
                var row = new DockPanel { Width = ContentWidth, LastChildFill = false };
                var outline = Check("Outline", _style.TextOutline, "An edge around every letter — keeps text readable on busy screenshots",
                    on => Edit?.Invoke(st => st with { TextOutline = on, TextOutlineColor = on ? TextChip.OutlineColor(st.TextOutlineColor, st.StrokeColor) : st.TextOutlineColor }, null));
                row.Children.Add(outline);
                var well = Well(ColorTarget.Outline, _style.TextOutlineColor, "Outline colour — picking one turns the outline on");
                well.Margin = new Thickness(6, 0, 0, 0);
                row.Children.Add(well);
                var shadow = Check("Shadow", _style.TextShadow, "A soft drop shadow under the text (and its box)",
                    on => Edit?.Invoke(st => st with { TextShadow = on }, null));
                DockPanel.SetDock(shadow, Dock.Right);
                row.Children.Insert(0, shadow);
                Row(row);
                if (_style.TextOutline)
                    Row(SliderRow("Width", AnnotationStyle.MinOutlineWidth, AnnotationStyle.MaxOutlineWidth, _style.TextOutlineWidth, v => $"{v:0} px", "outline",
                        (st, v) => st with { TextOutlineWidth = Math.Round(v) }, "Outline thickness in image pixels"));
                break;
            }
            case InspectorSection.Redaction:
                Row(Segmented(new[]
                {
                    ("Blur", "Blur (B)", _style.RedactionMode == RedactionMode.Blur, (Action)(() => RedactionSwitch?.Invoke(RedactionMode.Blur))),
                    ("Pixelate", "Pixelate (P)", _style.RedactionMode == RedactionMode.Pixelate, () => RedactionSwitch?.Invoke(RedactionMode.Pixelate)),
                    ("Black-out", "Black-out (X)", _style.RedactionMode == RedactionMode.Blackout, () => RedactionSwitch?.Invoke(RedactionMode.Blackout)),
                }));
                Row(Note(InspectorModel.RedactionNote(_style.RedactionMode)));
                break;
            case InspectorSection.Strength:
                if (_style.RedactionMode == RedactionMode.Pixelate)
                    Row(SliderRow("Strength", AnnotationStyle.MinPixelSize, AnnotationStyle.MaxPixelSize, _style.PixelSize, v => $"{v:0} px", "strength",
                        (st, v) => st with { PixelSize = Math.Round(v) }, "Size of each block, in image pixels", "How strongly it hides what's underneath"));
                else
                    Row(SliderRow("Strength", AnnotationStyle.MinBlurRadius, AnnotationStyle.MaxBlurRadius, _style.BlurRadius, v => $"{v:0} px", "strength",
                        (st, v) => st with { BlurRadius = Math.Round(v) }, "Blur radius, in image pixels", "How strongly it hides what's underneath"));
                break;
            case InspectorSection.SpotlightShape:
                Row(Segmented(new[]
                {
                    ("Rectangle", "Rectangle", _style.SpotlightShape == SpotlightShape.Rectangle,
                        (Action)(() => Edit?.Invoke(st => st with { SpotlightShape = SpotlightShape.Rectangle }, null))),
                    ("Ellipse", "Ellipse — or hold Alt while dragging", _style.SpotlightShape == SpotlightShape.Ellipse,
                        () => Edit?.Invoke(st => st with { SpotlightShape = SpotlightShape.Ellipse }, null)),
                }, new[] { "rect", "ellipse" }));
                break;
            case InspectorSection.SpotlightDim:
                Row(SliderRow("Dim", 10, 90, _style.SpotlightDim * 100, v => $"{v:0}%", "dim",
                    (st, v) => st with { SpotlightDim = Math.Round(v) / 100 }, "How dark everything outside the spotlights gets", "How dark everything outside the spotlights gets",
                    v => DimEdit?.Invoke(Math.Round(v) / 100)));
                break;
            case InspectorSection.Opacity:
                Row(SliderRow("Opacity", 10, 100, _style.Opacity * 100, v => $"{v:0}%", "opacity",
                    (st, v) => st with { Opacity = Math.Round(v) / 100 }, "How see-through the object is"));
                break;
            case InspectorSection.CropHelp:
            case InspectorSection.SelectHelp:
                panel.Children.Add(Note(s.Note()!));
                break;
            default:
                return null;
        }
        return panel;
    }

    private static string Name(double w) => w switch { 2 => "Thin", 4 => "Medium", _ => "Thick" };

    private static AnnotationStyle WithStroke(AnnotationStyle st, RGBAColor c)
    {
        var s = st with { StrokeColor = c, FillColor = c.WithAlpha(0.25) };
        // The outline follows the text colour while it's on (keeps ≥ 3:1 contrast).
        return s.TextOutline ? s with { TextOutlineColor = TextChip.OutlineColor(s.TextOutlineColor, c) } : s;
    }

    private void BuildFooter(bool show)
    {
        _footer.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        if (!show) { _footer.Child = null; return; }
        var stack = new StackPanel();
        stack.Children.Add(Hairline());
        var grid = new UniformGrid { Columns = 3, Margin = new Thickness(16, 10, 16, 12) };
        grid.Children.Add(IconTextButton("bring-front", "Front", "Bring to front ( ] )", () => BringToFront?.Invoke(), new Thickness(0, 0, 4, 0)));
        grid.Children.Add(IconTextButton("send-back", "Back", "Send to back ( [ )", () => SendToBack?.Invoke(), new Thickness(2, 0, 2, 0)));
        grid.Children.Add(IconTextButton("trash", "Delete", "Delete (Del)", () => DeleteSelection?.Invoke(), new Thickness(4, 0, 0, 0)));
        stack.Children.Add(grid);
        _footer.Child = stack;
    }

    // ---------------------------------------------------------------- rows

    private FrameworkElement SwatchGrid((string Name, RGBAColor Color)[] swatches, RGBAColor current, Action<RGBAColor> pick)
    {
        var grid = new UniformGrid { Columns = 8, Width = ContentWidth };
        foreach (var (name, color) in swatches)
            grid.Children.Add(Swatch(color, name, color.SameAs(current), () => pick(color)));
        return grid;
    }

    private FrameworkElement RecentRow()
    {
        var grid = EightColumns();
        var cap = Caption("Recent");
        cap.VerticalAlignment = VerticalAlignment.Center;
        cap.Margin = new Thickness(0);
        Grid.SetColumnSpan(cap, 2);
        grid.Children.Add(cap);
        for (int i = 0; i < _recent.Count && i < 6; i++)
        {
            var c = _recent[i];
            var sw = Swatch(c, "Recent colour", c.SameAs(_style.StrokeColor), () => RecentPicked?.Invoke(c));
            Grid.SetColumn(sw, 2 + i);
            grid.Children.Add(sw);
        }
        return grid;
    }

    private FrameworkElement CustomRow(ColorTarget target, RGBAColor current, string wellTip)
    {
        var grid = new Grid { Width = ContentWidth };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(ContentWidth / 4) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var cap = Caption("Custom");
        cap.VerticalAlignment = VerticalAlignment.Center;
        cap.Margin = new Thickness(0);
        grid.Children.Add(cap);
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(Well(target, current, wellTip));
        var pick = IconTextButton("eyedropper", "Pick from Screen", "Eyedropper — click anywhere on screen to use that colour",
            () => Eyedropper?.Invoke(target), new Thickness(6, 0, 0, 0));
        row.Children.Add(pick);
        Grid.SetColumn(row, 1);
        grid.Children.Add(row);
        return grid;
    }

    private Button Well(ColorTarget target, RGBAColor color, string tip)
    {
        var b = new Button { Style = (Style)FindRes("Ed.ColorWell"), Background = DocumentRenderer.Solid(color), ToolTip = tip };
        System.Windows.Automation.AutomationProperties.SetName(b, tip);
        b.Click += (_, _) => OpenColorWell?.Invoke(target);
        return b;
    }

    private FrameworkElement FontRow()
    {
        var grid = new Grid { Width = ContentWidth };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(84) });

        var family = new ComboBox { ToolTip = "Font", Height = 24, FontSize = 12, IsEditable = false, MaxDropDownHeight = 360 };
        family.SetValue(VirtualizingPanel.IsVirtualizingProperty, true);
        family.ItemsPanel = new ItemsPanelTemplate(new FrameworkElementFactory(typeof(VirtualizingStackPanel)));
        int selected = -1;
        foreach (var (fam, label) in TextFont.Presets)
        {
            if (fam == _style.FontFamily) selected = family.Items.Count;
            family.Items.Add(new ComboBoxItem { Content = label, Tag = fam, FontFamily = TextRendering.Family(fam) });
        }
        family.Items.Add(new Separator());
        foreach (var name in TextRendering.InstalledFamilies)
        {
            if (selected < 0 && string.Equals(name, _style.FontFamily, StringComparison.OrdinalIgnoreCase)) selected = family.Items.Count;
            family.Items.Add(new ComboBoxItem { Content = name, Tag = name });
        }
        family.SelectedIndex = Math.Max(0, selected);
        family.SelectionChanged += (_, _) =>
        {
            if (family.SelectedItem is ComboBoxItem { Tag: string f } && f != _style.FontFamily)
                Edit?.Invoke(st => st with { FontFamily = f }, null);
        };
        grid.Children.Add(family);

        var size = new ComboBox { ToolTip = "Font size", Height = 24, FontSize = 12 };
        var sizes = ColorPresets.FontSizes.ToList();
        if (!sizes.Any(v => Math.Abs(v - _style.FontSize) < 0.01)) sizes.Add(Math.Round(_style.FontSize));
        sizes.Sort();
        foreach (var v in sizes) size.Items.Add(new ComboBoxItem { Content = $"{v:0} pt", Tag = v });
        size.SelectedIndex = sizes.FindIndex(v => Math.Abs(v - Math.Round(_style.FontSize)) < 0.01);
        size.SelectionChanged += (_, _) =>
        {
            if (size.SelectedItem is ComboBoxItem { Tag: double v } && Math.Abs(v - _style.FontSize) > 0.01)
                Edit?.Invoke(st => st with { FontSize = v }, null);
        };
        Grid.SetColumn(size, 2);
        grid.Children.Add(size);
        return grid;
    }

    private FrameworkElement EmphasisRow()
    {
        var dock = new DockPanel { Width = ContentWidth, LastChildFill = false };
        var emph = SegmentHost(4, 28);
        emph.Children.Add(IconToggle("bold", "Bold", _style.FontBold, () => Edit?.Invoke(st => st with { FontBold = !st.FontBold }, null)));
        emph.Children.Add(IconToggle("italic", "Italic", _style.FontItalic, () => Edit?.Invoke(st => st with { FontItalic = !st.FontItalic }, null)));
        emph.Children.Add(IconToggle("underline", "Underline", _style.TextUnderline, () => Edit?.Invoke(st => st with { TextUnderline = !st.TextUnderline }, null)));
        emph.Children.Add(IconToggle("strikethrough", "Strikethrough", _style.TextStrikethrough, () => Edit?.Invoke(st => st with { TextStrikethrough = !st.TextStrikethrough }, null)));
        dock.Children.Add(Track(emph));
        var align = SegmentHost(3, 28);
        align.Children.Add(IconToggle("align-left", "Align left", _style.TextAlignment == TextAlign.Left, () => Edit?.Invoke(st => st with { TextAlignment = TextAlign.Left }, null)));
        align.Children.Add(IconToggle("align-center", "Align centre", _style.TextAlignment == TextAlign.Center, () => Edit?.Invoke(st => st with { TextAlignment = TextAlign.Center }, null)));
        align.Children.Add(IconToggle("align-right", "Align right", _style.TextAlignment == TextAlign.Right, () => Edit?.Invoke(st => st with { TextAlignment = TextAlign.Right }, null)));
        var alignTrack = Track(align);
        DockPanel.SetDock(alignTrack, Dock.Right);
        dock.Children.Insert(0, alignTrack);
        return dock;
    }

    /// <summary>"Label" (56 px column) · slider · value (40 px, right-aligned). The drag is one undo group.</summary>
    private FrameworkElement SliderRow(string label, double min, double max, double value, Func<double, string> format, string group,
        Func<AnnotationStyle, double, AnnotationStyle> apply, string? tip, string? labelTip = null, Action<double>? special = null)
    {
        var grid = new Grid { Width = ContentWidth, Height = 24 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(LabelWidth) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(ValueWidth) });
        var name = new TextBlock { Text = label, FontSize = 12, Foreground = Res("Ed.LabelBrush"), VerticalAlignment = VerticalAlignment.Center, ToolTip = labelTip ?? tip };
        grid.Children.Add(name);
        var slider = new Slider
        {
            Minimum = min, Maximum = max, Value = Math.Clamp(value, min, max), IsSnapToTickEnabled = true, TickFrequency = 1,
            VerticalAlignment = VerticalAlignment.Center, Focusable = false, ToolTip = tip, Margin = new Thickness(0, 0, 6, 0),
        };
        if (TryFindResource("Theme.Slider") is Style ss) slider.Style = ss;
        System.Windows.Automation.AutomationProperties.SetName(slider, label);
        Grid.SetColumn(slider, 1);
        grid.Children.Add(slider);
        var readout = new TextBlock
        {
            Text = format(value), FontSize = 11.5, Foreground = Res("Ed.SecondaryBrush"), HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center, FontFamily = new FontFamily("Segoe UI"),
            Typography = { NumeralAlignment = FontNumeralAlignment.Tabular },
        };
        Grid.SetColumn(readout, 2);
        grid.Children.Add(readout);

        slider.AddHandler(Thumb.DragStartedEvent, new DragStartedEventHandler((_, _) => _dragging = true));
        slider.AddHandler(Thumb.DragCompletedEvent, new DragCompletedEventHandler((_, _) =>
        {
            _dragging = false;
            EndGroup?.Invoke();
        }));
        slider.ValueChanged += (_, e) =>
        {
            readout.Text = format(e.NewValue);
            double v = e.NewValue;
            if (special != null) special(v);
            else Edit?.Invoke(st => apply(st, v), _dragging ? group : null);
        };
        return grid;
    }

    private FrameworkElement Segmented((string Label, string Tip, bool On, Action Click)[] items, string[]? icons = null)
    {
        var host = SegmentHost(items.Length, 0);
        for (int i = 0; i < items.Length; i++)
        {
            var (label, tip, on, click) = items[i];
            object content = label;
            if (icons != null)
            {
                var sp = new StackPanel { Orientation = Orientation.Horizontal };
                sp.Children.Add(new IconPresenter { IconKey = icons[i], Brush = Res("Ed.LabelBrush"), Width = 13, Height = 13, Margin = new Thickness(0, 0, 5, 0) });
                sp.Children.Add(new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center });
                content = sp;
            }
            var b = new ToggleButton { Content = content, ToolTip = tip, IsChecked = on, Style = (Style)FindRes("Ed.Segment") };
            System.Windows.Automation.AutomationProperties.SetName(b, label);
            b.Click += (_, _) => { b.IsChecked = on; click(); };
            host.Children.Add(b);
        }
        var track = Track(host);
        track.Width = ContentWidth;
        return track;
    }

    private static UniformGrid SegmentHost(int columns, double cellWidth) =>
        cellWidth > 0 ? new UniformGrid { Columns = columns, Width = columns * cellWidth + 2 } : new UniformGrid { Columns = columns };

    private Border Track(UIElement child) => new()
    {
        Child = child, Background = Res("Ed.ControlBrush"), CornerRadius = new CornerRadius(6), Padding = new Thickness(1),
    };

    private ToggleButton IconToggle(string icon, string tip, bool on, Action click)
    {
        var b = new ToggleButton
        {
            Content = new IconPresenter { IconKey = icon, Brush = Res("Ed.LabelBrush"), Width = 14, Height = 14 },
            ToolTip = tip, IsChecked = on, Style = (Style)FindRes("Ed.Segment"),
        };
        System.Windows.Automation.AutomationProperties.SetName(b, tip);
        b.Click += (_, _) => { b.IsChecked = on; click(); };
        return b;
    }

    private ToggleButton Swatch(RGBAColor c, string tip, bool on, Action click)
    {
        var b = new ToggleButton
        {
            Style = (Style)FindRes("Ed.Swatch"), Background = DocumentRenderer.Solid(c), ToolTip = tip, IsChecked = on,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        System.Windows.Automation.AutomationProperties.SetName(b, tip);
        b.Click += (_, _) => { b.IsChecked = on; click(); };
        return b;
    }

    private CheckBox Check(string text, bool on, string tip, Action<bool> changed)
    {
        var c = new CheckBox { Content = text, IsChecked = on, ToolTip = tip, Style = (Style)FindRes("Ed.CheckBox"), VerticalAlignment = VerticalAlignment.Center };
        c.Click += (_, _) => changed(c.IsChecked == true);
        return c;
    }

    private Button IconTextButton(string icon, string text, string tip, Action click, Thickness margin)
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal };
        sp.Children.Add(new IconPresenter { IconKey = icon, Brush = Res("Ed.LabelBrush"), Width = 14, Height = 14, Margin = new Thickness(0, 0, 5, 0) });
        sp.Children.Add(new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center });
        var b = new Button { Content = sp, ToolTip = tip, Style = (Style)FindRes("Ed.SmallButton"), Margin = margin };
        System.Windows.Automation.AutomationProperties.SetName(b, text);
        b.Click += (_, _) => click();
        return b;
    }

    private FrameworkElement PresetChip(TextStylePreset p)
    {
        var look = p.Look();
        var textColor = look.Color ?? new RGBAColor(1, 1, 1, 0.92);
        var label = new TextBlock
        {
            Text = p.DisplayName(), FontSize = p == TextStylePreset.Title ? 15 : 12,
            FontFamily = TextRendering.Family(look.Family), FontWeight = look.Bold ? FontWeights.SemiBold : FontWeights.Normal,
            Foreground = DocumentRenderer.Solid(textColor), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        };
        bool active = p.IsApplied(_style);
        var chip = new Border
        {
            Height = 28, Margin = new Thickness(4, 0, 4, p <= TextStylePreset.Note ? 8 : 0),
            CornerRadius = new CornerRadius(6),
            Background = look.Box is { } box ? DocumentRenderer.Solid(box.Color) : new SolidColorBrush(Color.FromArgb(0x0F, 255, 255, 255)),
            BorderBrush = active ? Res("Ed.AccentBrush") : new SolidColorBrush(Color.FromArgb(0x29, 255, 255, 255)),
            BorderThickness = new Thickness(active ? 2 : 1),
            Child = label, Cursor = System.Windows.Input.Cursors.Hand, ToolTip = p.Tooltip(),
        };
        System.Windows.Automation.AutomationProperties.SetName(chip, p.DisplayName());
        chip.MouseLeftButtonUp += (_, _) => Preset?.Invoke(p);
        return chip;
    }

    private Grid EightColumns()
    {
        var g = new Grid { Width = ContentWidth };
        for (int i = 0; i < 8; i++) g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        return g;
    }

    private TextBlock Caption(string title) => new()
    {
        Text = title.ToUpperInvariant(), FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = Res("Ed.CaptionBrush"),
        Margin = new Thickness(0, 0, 0, 0),
    };

    private TextBlock Note(string text) => new()
    {
        Text = text, FontSize = 12, Foreground = new SolidColorBrush(Color.FromArgb(0x9E, 255, 255, 255)),
        TextWrapping = TextWrapping.Wrap, Width = ContentWidth,
    };

    private Border Hairline() => new() { Height = 1, Background = Res("Ed.HairlineBrush"), Margin = new Thickness(16, 0, 16, 0) };

    private Brush Res(string key) => (Brush)FindRes(key);

    private object FindRes(string key) => TryFindResource(key) ?? System.Windows.Application.Current.TryFindResource(key)
        ?? throw new InvalidOperationException("missing resource " + key);
}
