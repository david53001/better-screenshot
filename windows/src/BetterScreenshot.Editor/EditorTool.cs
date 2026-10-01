namespace BetterScreenshot.Editor;

/// <summary>The annotation tools. Black-out has no toolbar button (it's the Redaction switch's third segment).</summary>
public enum EditorTool
{
    Select,
    Arrow,
    Line,
    Rectangle,
    FilledRectangle,
    Ellipse,
    Text,
    Counter,
    Blur,
    Pixelate,
    Crop,
    Blackout,
    Highlighter,
    Spotlight,
}

/// <summary>Per-tool metadata (Mac <c>EditorTool.swift</c>): name, icon, single-key shortcut, tooltip.</summary>
public static class ToolInfo
{
    /// <summary>Toolbar order with group breaks (v3 Part 3): Select | shapes | Text, Counter, Highlighter |
    /// Blur, Pixelate, Spotlight | Crop.</summary>
    public static readonly EditorTool[][] ToolbarGroups =
    {
        new[] { EditorTool.Select },
        new[] { EditorTool.Arrow, EditorTool.Line, EditorTool.Rectangle, EditorTool.FilledRectangle, EditorTool.Ellipse },
        new[] { EditorTool.Text, EditorTool.Counter, EditorTool.Highlighter },
        new[] { EditorTool.Blur, EditorTool.Pixelate, EditorTool.Spotlight },
        new[] { EditorTool.Crop },
    };

    public static string DisplayName(this EditorTool t) => t switch
    {
        EditorTool.Select => "Select",
        EditorTool.Arrow => "Arrow",
        EditorTool.Line => "Line",
        EditorTool.Rectangle => "Rectangle",
        EditorTool.FilledRectangle => "Filled Rectangle",
        EditorTool.Ellipse => "Ellipse",
        EditorTool.Text => "Text",
        EditorTool.Counter => "Counter",
        EditorTool.Blur => "Blur",
        EditorTool.Pixelate => "Pixelate",
        EditorTool.Crop => "Crop",
        EditorTool.Blackout => "Black-out",
        EditorTool.Highlighter => "Highlighter",
        EditorTool.Spotlight => "Spotlight",
        _ => t.ToString(),
    };

    /// <summary>Key into <c>Resources/Icons.xaml</c> (without the <c>icon-</c> prefix).</summary>
    public static string IconKey(this EditorTool t) => t switch
    {
        EditorTool.Select => "cursor",
        EditorTool.Arrow => "arrow",
        EditorTool.Line => "line",
        EditorTool.Rectangle => "rect",
        EditorTool.FilledRectangle => "rect-fill",
        EditorTool.Ellipse => "ellipse",
        EditorTool.Text => "text",
        EditorTool.Counter => "counter",
        EditorTool.Blur => "blur",
        EditorTool.Pixelate => "pixelate",
        EditorTool.Crop => "crop",
        EditorTool.Blackout => "blackout",
        EditorTool.Highlighter => "highlighter",
        EditorTool.Spotlight => "spotlight",
        _ => "cursor",
    };

    /// <summary>Single-key shortcut (lower case; typed keys match case-insensitively).</summary>
    public static char ShortcutKey(this EditorTool t) => t switch
    {
        EditorTool.Select => 'v',
        EditorTool.Arrow => 'a',
        EditorTool.Line => 'l',
        EditorTool.Rectangle => 'r',
        EditorTool.FilledRectangle => 'f',
        EditorTool.Ellipse => 'o',
        EditorTool.Text => 't',
        EditorTool.Counter => 'n',
        EditorTool.Blur => 'b',
        EditorTool.Pixelate => 'p',
        EditorTool.Crop => 'c',
        EditorTool.Blackout => 'x',
        EditorTool.Highlighter => 'h',
        EditorTool.Spotlight => 's',
        _ => '\0',
    };

    /// <summary>Toolbar tooltip, e.g. "Arrow (A)".</summary>
    public static string Tooltip(this EditorTool t) => $"{t.DisplayName()} ({char.ToUpperInvariant(t.ShortcutKey())})";

    /// <summary>The tool whose shortcut is <paramref name="characters"/> (exactly one typed character), or null.</summary>
    public static EditorTool? ForShortcut(string characters)
    {
        if (characters is not { Length: 1 }) return null;
        char c = char.ToLowerInvariant(characters[0]);
        foreach (var t in Enum.GetValues<EditorTool>())
            if (t.ShortcutKey() == c) return t;
        return null;
    }

    /// <summary>The tool that draws <paramref name="a"/> — how the inspector describes a selected object.</summary>
    public static EditorTool? MakerOf(IAnnotation a) => a switch
    {
        ArrowAnnotation => EditorTool.Arrow,
        LineAnnotation => EditorTool.Line,
        FilledRectangleAnnotation => EditorTool.FilledRectangle,
        RectangleAnnotation r => r.Filled ? EditorTool.FilledRectangle : EditorTool.Rectangle,
        EllipseAnnotation => EditorTool.Ellipse,
        TextAnnotation => EditorTool.Text,
        CounterAnnotation => EditorTool.Counter,
        RedactionAnnotation r => ToolOf(r.Style.RedactionMode),
        HighlighterAnnotation => EditorTool.Highlighter,
        SpotlightAnnotation => EditorTool.Spotlight,
        _ => null,
    };

    public static EditorTool ToolOf(RedactionMode m) => m switch
    {
        RedactionMode.Pixelate => EditorTool.Pixelate,
        RedactionMode.Blackout => EditorTool.Blackout,
        _ => EditorTool.Blur,
    };

    public static RedactionMode? RedactionModeOf(this EditorTool t) => t switch
    {
        EditorTool.Blur => RedactionMode.Blur,
        EditorTool.Pixelate => RedactionMode.Pixelate,
        EditorTool.Blackout => RedactionMode.Blackout,
        _ => null,
    };
}
