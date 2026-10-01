using BetterScreenshot.Core;

namespace BetterScreenshot.Editor;

/// <summary>A titled group in the editor's side panel. Declaration order = top-to-bottom panel order.</summary>
public enum InspectorSection
{
    Styles, Colour, Stroke, HighlighterStroke, Font, Background, Effects, Redaction, Strength,
    SpotlightShape, SpotlightDim, Opacity, Arrange,
    /// <summary>Explanatory text only — the Crop tool and Select with nothing selected.</summary>
    CropHelp, SelectHelp,
}

/// <summary>What the side panel shows: a heading plus its sections, in order.</summary>
public sealed record InspectorContent(string Title, IReadOnlyList<InspectorSection> Sections)
{
    public bool Equals(InspectorContent? o) => o is not null && Title == o.Title && Sections.SequenceEqual(o.Sections);
    public override int GetHashCode() => Title.GetHashCode();
}

/// <summary>Pure rules for the side panel and the hint line (port of <c>InspectorModel.swift</c>, v3 Parts 1–3).
/// A selected object is described by the tool that draws it.</summary>
public static class InspectorModel
{
    public static string? Title(this InspectorSection s) => s switch
    {
        InspectorSection.Styles => "Styles",
        InspectorSection.Colour => "Colour",
        InspectorSection.Stroke or InspectorSection.HighlighterStroke => "Stroke",
        InspectorSection.Font => "Font",
        InspectorSection.Background => "Background",
        InspectorSection.Effects => "Effects",
        InspectorSection.Redaction => "Redaction",
        InspectorSection.Opacity => "Opacity",
        InspectorSection.Arrange => "Arrange",
        InspectorSection.Strength => "Strength",
        InspectorSection.SpotlightShape => "Shape",
        InspectorSection.SpotlightDim => "Dim outside",
        _ => null,
    };

    public static string? Note(this InspectorSection s) => s switch
    {
        InspectorSection.CropHelp => "Drag over the part of the image you want to keep. Undo (Ctrl+Z) brings the rest back.",
        InspectorSection.SelectHelp => "Click an object on the image to change it here. Drag across empty space to select several.",
        _ => null,
    };

    /// <summary>Style sections an object drawn by <paramref name="tool"/> exposes.</summary>
    public static IReadOnlyList<InspectorSection> ObjectSections(EditorTool tool) => tool switch
    {
        EditorTool.Arrow or EditorTool.Line or EditorTool.Rectangle or EditorTool.Ellipse =>
            new[] { InspectorSection.Colour, InspectorSection.Stroke, InspectorSection.Opacity },
        EditorTool.FilledRectangle or EditorTool.Counter => new[] { InspectorSection.Colour, InspectorSection.Opacity },
        EditorTool.Text => new[] { InspectorSection.Styles, InspectorSection.Colour, InspectorSection.Font, InspectorSection.Background, InspectorSection.Effects, InspectorSection.Opacity },
        EditorTool.Blur or EditorTool.Pixelate => new[] { InspectorSection.Redaction, InspectorSection.Strength },
        EditorTool.Blackout => new[] { InspectorSection.Redaction },
        EditorTool.Highlighter => new[] { InspectorSection.Colour, InspectorSection.HighlighterStroke, InspectorSection.Opacity },
        EditorTool.Spotlight => new[] { InspectorSection.SpotlightShape, InspectorSection.SpotlightDim },
        _ => Array.Empty<InspectorSection>(),
    };

    public static IReadOnlyList<InspectorSection> ToolSections(EditorTool tool) => tool switch
    {
        EditorTool.Crop => new[] { InspectorSection.CropHelp },
        EditorTool.Select => new[] { InspectorSection.SelectHelp },
        _ => ObjectSections(tool),
    };

    /// <summary>A drawing tool shows its own sections; Select shows the selection's SHARED sections + Arrange.</summary>
    public static InspectorContent Content(EditorTool tool, IReadOnlyList<EditorTool> selection)
    {
        if (tool != EditorTool.Select) return new InspectorContent(tool.DisplayName(), ToolSections(tool));
        if (selection.Count == 0) return new InspectorContent("Nothing selected", new[] { InspectorSection.SelectHelp });
        var shared = Enum.GetValues<InspectorSection>()
            .Where(s => s != InspectorSection.Arrange && s != InspectorSection.CropHelp && s != InspectorSection.SelectHelp)
            .Where(s => selection.All(t => ObjectSections(t).Contains(s))
                        // One Strength slider can't show a blur radius and a pixel size at once.
                        && (s != InspectorSection.Strength || selection.Distinct().Count() == 1))
            .ToList();
        shared.Add(InspectorSection.Arrange);
        string title = selection.Count == 1 ? selection[0].DisplayName() : $"{selection.Count} objects";
        return new InspectorContent(title, shared);
    }

    /// <summary>One plain sentence for the hint line (Windows key names).</summary>
    public static string Hint(EditorTool tool, IReadOnlyList<EditorTool> selection, bool editingText)
    {
        if (editingText) return "Type your text — Enter or Esc finishes it, Shift+Enter starts a new line.";
        return tool switch
        {
            EditorTool.Select when selection.Count > 1 => "Drag to move them together, or press Delete to remove them.",
            EditorTool.Select when selection.Count == 0 => "Click an object to select it, or drag across empty space to select several.",
            EditorTool.Select => selection[0] switch
            {
                EditorTool.Text => "Drag to move it, drag a corner to resize the text, drag a side to change the box width, or double-click to edit.",
                EditorTool.Rectangle or EditorTool.FilledRectangle or EditorTool.Ellipse or EditorTool.Blur
                    or EditorTool.Pixelate or EditorTool.Blackout or EditorTool.Spotlight =>
                    "Drag to move it, drag a handle to resize it, or press Delete to remove it.",
                _ => "Drag to move it, or press Delete to remove it.",
            },
            EditorTool.Arrow => "Drag to draw an arrow — it points to where you let go.",
            EditorTool.Line => "Drag to draw a straight line.",
            EditorTool.Rectangle => "Drag to draw a rectangle outline.",
            EditorTool.FilledRectangle => "Drag to draw a solid rectangle that covers what's under it.",
            EditorTool.Ellipse => "Drag to draw an ellipse.",
            EditorTool.Text => "Click to type a label, drag to make a text box, or click existing text to edit it.",
            EditorTool.Counter => "Click to place the next numbered step.",
            EditorTool.Blur => "Drag over anything you want to hide — it's blurred when you let go.",
            EditorTool.Pixelate => "Drag over anything you want to hide — it's pixelated when you let go.",
            EditorTool.Blackout => "Drag over anything you want to hide — it's covered in solid black when you let go.",
            EditorTool.Highlighter => "Drag to highlight, like a marker pen — hold Shift for a straight line.",
            EditorTool.Spotlight => "Drag over what matters — everything else is dimmed. Hold Alt for an ellipse.",
            EditorTool.Crop => "Drag over the area to keep — everything outside is cut away (Ctrl+Z undoes it).",
            _ => "",
        };
    }

    /// <summary>Redaction-mode note under the Redaction switch.</summary>
    public static string RedactionNote(RedactionMode m) => m switch
    {
        RedactionMode.Blur => "Softens what's underneath. Raise the strength until it can't be read.",
        RedactionMode.Pixelate => "Turns what's underneath into blocks. Bigger blocks hide more.",
        _ => "Covers it with solid black — the safest choice, nothing can be recovered.",
    };
}

/// <summary>
/// Canvas zoom maths (port of <c>ZoomMath.swift</c>). Magnification m = DIPs per image pixel. Percent is per
/// SCREEN pixel: 100% = one image pixel per device pixel, i.e. m × dpiScale = 1.
/// </summary>
public static class ZoomMath
{
    public const double MaxPercent = 800;
    public static readonly double[] Stops = { 10, 25, 50, 75, 100, 150, 200, 300, 400, 600, 800 };

    public static double Percent(double m, double backingScale) => m * backingScale * 100;

    public static double Magnification(double percent, double backingScale) => percent / 100 / Math.Max(backingScale, 1);

    /// <summary>Fit: the whole image inside <paramref name="available"/>, never larger than 100%.</summary>
    public static double FitMagnification(PxSize imageSize, PxSize available, double backingScale)
    {
        if (imageSize.Width <= 0 || imageSize.Height <= 0) return 1;
        double m = Math.Min(Math.Min(available.Width / imageSize.Width, available.Height / imageSize.Height),
            Magnification(100, backingScale));
        return Math.Max(m, 0.01);
    }

    /// <summary>The image's size at 100%, in DIPs.</summary>
    public static PxSize PointSize(PxSize pixels, double backingScale)
    {
        double s = Math.Max(backingScale, 1);
        return new PxSize(pixels.Width / s, pixels.Height / s);
    }

    /// <summary>Allowed range: from fit (or 100% if fit is larger) up to 800%.</summary>
    public static double Clamp(double m, double fit, double backingScale)
    {
        double lo = Math.Min(fit, Magnification(100, backingScale));
        double hi = Magnification(MaxPercent, backingScale);
        return Math.Min(Math.Max(m, lo), hi);
    }

    /// <summary>Next stop from the percent the label SHOWS (a 99.8% fit reads "100%", so + goes to 150%).</summary>
    public static double SteppedPercent(double percent, bool zoomIn)
    {
        double shown = Math.Round(percent);
        return zoomIn
            ? Stops.Cast<double?>().FirstOrDefault(s => s > shown) ?? MaxPercent
            : Stops.Cast<double?>().LastOrDefault(s => s < shown) ?? Stops[0];
    }

    public static bool IsFit(double m, double fit) => Math.Abs(m - fit) <= fit * 0.005;

    /// <summary>New scroll origin that keeps <paramref name="anchor"/> (document coordinates at the old
    /// magnification) on the same spot of the screen after zooming from <paramref name="old"/> to <paramref name="next"/>.</summary>
    public static PxPoint AnchoredOrigin(PxPoint anchor, PxPoint visibleOrigin, double old, double next)
    {
        double k = next / old;
        return new PxPoint(anchor.X * k - (anchor.X - visibleOrigin.X), anchor.Y * k - (anchor.Y - visibleOrigin.Y));
    }

    /// <summary>"Fit · 57%" in fit mode, else "150%".</summary>
    public static string Label(double percent, bool isFit)
    {
        string p = $"{(int)Math.Round(percent, MidpointRounding.AwayFromZero)}%";
        return isFit ? $"Fit · {p}" : p;
    }
}

/// <summary>The editor's Recent colours: most recent first, no duplicates (8-bit), at most 6. Shared by all tools.</summary>
public sealed class RecentColors
{
    public const int Capacity = 6;
    private readonly List<RGBAColor> _colors = new();
    public IReadOnlyList<RGBAColor> Colors => _colors;

    public RecentColors(IEnumerable<RGBAColor>? colors = null)
    {
        if (colors != null) foreach (var c in colors.Reverse()) Add(c);
    }

    /// <summary>Puts <paramref name="color"/> first. <paramref name="replacingFront"/> swaps out the current first
    /// entry instead (one colour-picker session adds one entry).</summary>
    public void Add(RGBAColor color, bool replacingFront = false)
    {
        if (replacingFront && _colors.Count > 0) _colors.RemoveAt(0);
        _colors.RemoveAll(c => c.SameAs(color));
        _colors.Insert(0, color);
        if (_colors.Count > Capacity) _colors.RemoveRange(Capacity, _colors.Count - Capacity);
    }
}

/// <summary>The editor's colour presets (Part 1 Colour section; Part 2's box palette differs only in Black 80%).</summary>
public static class ColorPresets
{
    public static readonly (string Name, RGBAColor Color)[] Swatches =
    {
        ("Red", new RGBAColor(1.00, 0.27, 0.23, 1)), ("Orange", new RGBAColor(1.00, 0.62, 0.04, 1)),
        ("Yellow", new RGBAColor(1.00, 0.84, 0.04, 1)), ("Green", new RGBAColor(0.19, 0.82, 0.35, 1)),
        ("Blue", new RGBAColor(0.04, 0.52, 1.00, 1)), ("Purple", new RGBAColor(0.75, 0.35, 0.95, 1)),
        ("White", new RGBAColor(1, 1, 1, 1)), ("Black", new RGBAColor(0, 0, 0, 1)),
    };

    public static readonly (string Name, RGBAColor Color)[] BoxSwatches =
        Swatches.Take(7).Append(("Black (80%)", new RGBAColor(0, 0, 0, 0.8))).ToArray();

    public static readonly double[] StrokePresets = { 2, 4, 7 };
    public static readonly double[] FontSizes = { 12, 14, 18, 24, 30, 36, 48, 64, 96 };
}

/// <summary>
/// Style edits on the selection (v3 §1.4): an edit is applied to the default style AND every selected object.
/// Pure — the window owns undo grouping. Highlighter strokes route through the pen; redactions stay opaque; a
/// Dim change reaches every spotlight in the document.
/// </summary>
public static class StyleEdits
{
    /// <summary>True when the panel's Colour/Stroke/Opacity sections edit the highlighter pen: the Highlighter tool
    /// is active, or under Select only highlighter strokes are selected.</summary>
    public static bool EditsPen(EditorTool tool, IReadOnlyList<EditorTool> selection) =>
        tool == EditorTool.Highlighter || (tool == EditorTool.Select && selection.Count > 0 && selection.All(t => t == EditorTool.Highlighter));

    /// <summary>The style the panel shows: the back-most selected object's, else the default (the pen's look while
    /// <see cref="EditsPen"/>).</summary>
    public static AnnotationStyle Shown(AnnotationStyle defaults, IAnnotation? backMostSelected, bool editsPen)
    {
        if (backMostSelected is not null) return backMostSelected.Style;
        return editsPen ? defaults.WithHighlighterPen() : defaults;
    }

    /// <summary>Applies <paramref name="edit"/> to the default style (routing pen edits into the pen) and returns it.</summary>
    public static AnnotationStyle ApplyToDefault(AnnotationStyle defaults, Func<AnnotationStyle, AnnotationStyle> edit, bool editsPen)
    {
        if (!editsPen) return edit(defaults).Normalized();
        var penStyle = edit(defaults.WithHighlighterPen());
        return defaults.RememberingHighlighterPen(penStyle).Normalized();
    }

    /// <summary>The document with <paramref name="edit"/> applied to every selected object (and, when
    /// <paramref name="dimEdit"/>, the new dim copied onto every spotlight). Returns null when nothing changed.</summary>
    public static EditorDocument? ApplyToDocument(EditorDocument doc, IReadOnlyCollection<Guid> selection,
        Func<AnnotationStyle, AnnotationStyle> edit, bool dimEdit, double? newDim)
    {
        bool changed = false;
        var list = new List<IAnnotation>(doc.Annotations.Count);
        foreach (var a in doc.Annotations)
        {
            var next = a;
            if (selection.Contains(a.Id)) next = a.WithStyle(edit(a.Style).Normalized());
            if (dimEdit && newDim is { } dim && next is SpotlightAnnotation s && Math.Abs(s.Style.SpotlightDim - dim) > 1e-9)
                next = s.WithStyle(s.Style with { SpotlightDim = dim });
            if (!ReferenceEquals(next, a) && !Equals(next, a)) changed = true;
            list.Add(next);
        }
        return changed ? new EditorDocument(doc.Size, list) : null;
    }
}
