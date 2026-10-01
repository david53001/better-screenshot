using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace BetterScreenshot.Editor;

/// <summary>An sRGB color with straight (non-premultiplied) alpha, each channel in [0,1]. JSON-serializable.</summary>
public readonly record struct RGBAColor(double R, double G, double B, double A)
{
    public static RGBAColor FromBytes(byte r, byte g, byte b, byte a = 255) =>
        new(r / 255.0, g / 255.0, b / 255.0, a / 255.0);

    public RGBAColor WithAlpha(double alpha) => this with { A = alpha };

    /// <summary>Equal at 8-bit precision (what a user can tell apart).</summary>
    public bool SameAs(RGBAColor o) =>
        Q(R) == Q(o.R) && Q(G) == Q(o.G) && Q(B) == Q(o.B) && Q(A) == Q(o.A);

    private static int Q(double v) => (int)Math.Round(v * 255, MidpointRounding.AwayFromZero);

    public static readonly RGBAColor White = new(1, 1, 1, 1);
    public static readonly RGBAColor Black = new(0, 0, 0, 1);
}

/// <summary>Horizontal alignment of a text annotation's lines within its box.</summary>
public enum TextAlign { Left, Center, Right }

/// <summary>What sits behind a text: nothing, a box in <see cref="AnnotationStyle.TextBackgroundColor"/>, or the
/// auto-contrast box (dark or light, whichever stands out against the text colour — <see cref="TextChip"/>).</summary>
public enum TextBackgroundMode { None, Solid, Auto }

/// <summary>A redaction's look (v3 Part 3).</summary>
public enum RedactionMode { Blur, Pixelate, Blackout }

/// <summary>Spotlight hole shape (Alt-drag always draws an ellipse).</summary>
public enum SpotlightShape { Rectangle, Ellipse }

/// <summary>The Highlighter tool's own sticky colour / width / opacity (v3 Part 3).</summary>
public sealed record HighlighterPen(RGBAColor Color, double Width, double Opacity)
{
    public static readonly HighlighterPen Default = new(new RGBAColor(1, 0.84, 0.04, 1), 20, 0.4);
    public const double MinWidth = 4, MaxWidth = 48;
    public static readonly double[] WidthPresets = { 12, 20, 32 };

    public HighlighterPen Clamped() =>
        this with { Width = Math.Clamp(Width, MinWidth, MaxWidth), Opacity = Math.Clamp(Opacity, AnnotationStyle.MinOpacity, 1) };
}

/// <summary>Text font presets (persisted names) — mapped to Windows faces by the renderer.</summary>
public static class TextFont
{
    public const string System = "System";
    public const string Rounded = "System Rounded";
    public const string Serif = "System Serif";
    public const string Mono = "System Mono";

    public static readonly (string Family, string Label)[] Presets =
    {
        (System, "System"), (Rounded, "Rounded"), (Serif, "Serif"), (Mono, "Mono"),
    };

    public static bool IsPreset(string family) => Presets.Any(p => p.Family == family);
}

/// <summary>
/// The style of annotation objects, also the editor's sticky default (persisted as JSON under
/// <c>editorDefaultStyle</c>). Every field added after v1 is optional when decoding and defaults to the old look;
/// ranges are clamped on decode (see <see cref="Normalized"/>). Port of the Mac <c>AnnotationStyle</c> (v3 A.1,
/// Parts 1–3).
/// </summary>
[JsonConverter(typeof(AnnotationStyleJsonConverter))]
public sealed record AnnotationStyle
{
    public RGBAColor StrokeColor { get; init; }
    public RGBAColor FillColor { get; init; }
    public double LineWidth { get; init; }
    public double FontSize { get; init; }

    // ---- A.1 text font
    /// <summary>A <see cref="TextFont"/> preset ("System", "System Rounded", …) or an installed family name.</summary>
    public string FontFamily { get; init; } = TextFont.System;
    /// <summary>Semibold for the presets (the historical look), Bold for named families.</summary>
    public bool FontBold { get; init; } = true;
    public bool FontItalic { get; init; }
    public TextAlign TextAlignment { get; init; } = TextAlign.Left;

    // ---- Part 1
    /// <summary>Whole-object opacity 0.1…1, applied as one layer per object.</summary>
    public double Opacity { get; init; } = 1;
    public const double MinOpacity = 0.1;

    // ---- Part 2 text v2
    public TextBackgroundMode TextBackgroundMode { get; init; } = TextBackgroundMode.None;
    public RGBAColor TextBackgroundColor { get; init; } = new(0, 0, 0, 0.8);
    public double TextBackgroundPadding { get; init; } = 6;
    public double TextBackgroundCornerRadius { get; init; } = 4;
    public bool TextUnderline { get; init; }
    public bool TextStrikethrough { get; init; }
    public bool TextOutline { get; init; }
    public RGBAColor TextOutlineColor { get; init; } = RGBAColor.White;
    public double TextOutlineWidth { get; init; } = 3;
    public bool TextShadow { get; init; }
    public const double MaxBoxPadding = 40, MaxBoxRadius = 40, MinOutlineWidth = 1, MaxOutlineWidth = 20;

    // ---- Part 3
    public RedactionMode RedactionMode { get; init; } = RedactionMode.Blur;
    public double BlurRadius { get; init; } = 12;
    public double PixelSize { get; init; } = 12;
    public HighlighterPen HighlighterPen { get; init; } = HighlighterPen.Default;
    public SpotlightShape SpotlightShape { get; init; } = SpotlightShape.Rectangle;
    public double SpotlightDim { get; init; } = 0.6;
    public const double MinBlurRadius = 2, MaxBlurRadius = 40, MinPixelSize = 4, MaxPixelSize = 48;
    public const double MinSpotlightDim = 0.1, MaxSpotlightDim = 0.9;

    /// <summary>Blur radius or pixel size for the current mode (0 for black-out).</summary>
    public double RedactionStrength => RedactionMode switch
    {
        RedactionMode.Blur => BlurRadius,
        RedactionMode.Pixelate => PixelSize,
        _ => 0,
    };

    /// <summary>The default colour: exactly the panel's Red preset swatch (and the Callout box).</summary>
    public static readonly RGBAColor DefaultRed = new(1, 0.27, 0.23, 1);

    /// <summary>Red stroke, a 25%-alpha fill of the same hue, 4 px line, 24 pt font, opaque.</summary>
    public static AnnotationStyle Default { get; } = new()
    {
        StrokeColor = DefaultRed,
        FillColor = DefaultRed.WithAlpha(0.25),
        LineWidth = 4,
        FontSize = 24,
    };

    /// <summary>This style with every ranged field clamped (opacity, box padding/radius, outline width,
    /// redaction strengths, highlighter pen, spotlight dim).</summary>
    public AnnotationStyle Normalized() => this with
    {
        Opacity = Math.Clamp(double.IsNaN(Opacity) ? 1 : Opacity, MinOpacity, 1),
        TextBackgroundPadding = Math.Clamp(TextBackgroundPadding, 0, MaxBoxPadding),
        TextBackgroundCornerRadius = Math.Clamp(TextBackgroundCornerRadius, 0, MaxBoxRadius),
        TextOutlineWidth = Math.Clamp(TextOutlineWidth, MinOutlineWidth, MaxOutlineWidth),
        BlurRadius = Math.Clamp(BlurRadius, MinBlurRadius, MaxBlurRadius),
        PixelSize = Math.Clamp(PixelSize, MinPixelSize, MaxPixelSize),
        HighlighterPen = (HighlighterPen ?? HighlighterPen.Default).Clamped(),
        SpotlightDim = Math.Clamp(SpotlightDim, MinSpotlightDim, MaxSpotlightDim),
    };

    /// <summary>This style with <paramref name="other"/>'s redaction, highlighter-pen and spotlight settings —
    /// when an old object's style becomes the default (editing a text), those stay the user's current ones.</summary>
    public AnnotationStyle KeepingToolDefaults(AnnotationStyle other) => this with
    {
        RedactionMode = other.RedactionMode,
        BlurRadius = other.BlurRadius,
        PixelSize = other.PixelSize,
        HighlighterPen = other.HighlighterPen,
        SpotlightShape = other.SpotlightShape,
        SpotlightDim = other.SpotlightDim,
    };

    /// <summary>The style a highlighter stroke is drawn with: the pen's colour, width and opacity.</summary>
    public AnnotationStyle WithHighlighterPen() => this with
    {
        StrokeColor = HighlighterPen.Color,
        FillColor = HighlighterPen.Color.WithAlpha(0.25),
        LineWidth = HighlighterPen.Width,
        Opacity = HighlighterPen.Opacity,
    };

    /// <summary>Stores <paramref name="penStyle"/>'s colour/width/opacity as the highlighter pen.</summary>
    public AnnotationStyle RememberingHighlighterPen(AnnotationStyle penStyle) => this with
    {
        HighlighterPen = new HighlighterPen(penStyle.StrokeColor, penStyle.LineWidth, penStyle.Opacity).Clamped(),
    };

    /// <summary>The old default red (1, 0.23, 0.19) at any alpha → <see cref="DefaultRed"/> at that alpha, so an
    /// untouched sticky default shows the Red swatch as selected.</summary>
    public static RGBAColor MigratingOldDefaultRed(RGBAColor c) =>
        c.SameAs(new RGBAColor(1, 0.23, 0.19, c.A)) ? DefaultRed.WithAlpha(c.A) : c;

    public string ToJson() => JsonSerializer.Serialize(this);

    public static AnnotationStyle FromJson(string json) =>
        JsonSerializer.Deserialize<AnnotationStyle>(json) ?? throw new JsonException("null annotation style");
}

/// <summary>Explicit JSON shape for <see cref="AnnotationStyle"/> (camelCase keys, enums as lower-case strings)
/// with the legacy / clamping rules of v3 §1.5, §2.3 and §3.4. Unknown enum strings fall back to defaults.</summary>
public sealed class AnnotationStyleJsonConverter : JsonConverter<AnnotationStyle>
{
    public override AnnotationStyle Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        using var doc = JsonDocument.ParseValue(ref reader);
        var o = doc.RootElement;
        if (o.ValueKind != JsonValueKind.Object) throw new JsonException("style must be an object");
        var d = AnnotationStyle.Default;

        RGBAColor? legacyChip = Color(o, "textBackground");
        var modeRaw = Lower(o, "textBackgroundMode");
        TextBackgroundMode mode = modeRaw switch
        {
            "none" => TextBackgroundMode.None,
            "solid" => TextBackgroundMode.Solid,
            "auto" => TextBackgroundMode.Auto,
            // Missing or unknown → the legacy chip: the Windows port's `textBackground` colour (or the Mac Bool).
            _ => legacyChip is not null || Bool(o, "textBackground") == true ? TextBackgroundMode.Auto : TextBackgroundMode.None,
        };

        var style = new AnnotationStyle
        {
            StrokeColor = AnnotationStyle.MigratingOldDefaultRed(Color(o, "strokeColor") ?? d.StrokeColor),
            FillColor = AnnotationStyle.MigratingOldDefaultRed(Color(o, "fillColor") ?? d.FillColor),
            LineWidth = Num(o, "lineWidth") ?? d.LineWidth,
            FontSize = Num(o, "fontSize") ?? d.FontSize,
            FontFamily = Str(o, "fontFamily") is { Length: > 0 } fam ? fam : TextFont.System,
            FontBold = Bool(o, "fontBold") ?? true,
            FontItalic = Bool(o, "fontItalic") ?? false,
            TextAlignment = Lower(o, "textAlignment") switch { "center" => TextAlign.Center, "right" => TextAlign.Right, _ => TextAlign.Left },
            Opacity = Num(o, "opacity") ?? 1,
            TextBackgroundMode = mode,
            TextBackgroundColor = Color(o, "textBackgroundColor") ?? d.TextBackgroundColor,
            TextBackgroundPadding = Num(o, "textBackgroundPadding") ?? d.TextBackgroundPadding,
            TextBackgroundCornerRadius = Num(o, "textBackgroundCornerRadius") ?? d.TextBackgroundCornerRadius,
            TextUnderline = Bool(o, "textUnderline") ?? false,
            TextStrikethrough = Bool(o, "textStrikethrough") ?? false,
            TextOutline = Bool(o, "textOutline") ?? false,
            TextOutlineColor = Color(o, "textOutlineColor") ?? d.TextOutlineColor,
            TextOutlineWidth = Num(o, "textOutlineWidth") ?? d.TextOutlineWidth,
            TextShadow = Bool(o, "textShadow") ?? false,
            RedactionMode = Lower(o, "redactionMode") switch { "pixelate" => RedactionMode.Pixelate, "blackout" => RedactionMode.Blackout, _ => RedactionMode.Blur },
            BlurRadius = Num(o, "blurRadius") ?? d.BlurRadius,
            PixelSize = Num(o, "pixelSize") ?? d.PixelSize,
            HighlighterPen = Pen(o) ?? HighlighterPen.Default,
            SpotlightShape = Lower(o, "spotlightShape") == "ellipse" ? SpotlightShape.Ellipse : SpotlightShape.Rectangle,
            SpotlightDim = Num(o, "spotlightDim") ?? d.SpotlightDim,
        };
        return style.Normalized();
    }

    public override void Write(Utf8JsonWriter w, AnnotationStyle s, JsonSerializerOptions options)
    {
        w.WriteStartObject();
        WriteColor(w, "strokeColor", s.StrokeColor);
        WriteColor(w, "fillColor", s.FillColor);
        w.WriteNumber("lineWidth", s.LineWidth);
        w.WriteNumber("fontSize", s.FontSize);
        w.WriteString("fontFamily", s.FontFamily);
        w.WriteBoolean("fontBold", s.FontBold);
        w.WriteBoolean("fontItalic", s.FontItalic);
        w.WriteString("textAlignment", s.TextAlignment.ToString().ToLowerInvariant());
        w.WriteNumber("opacity", s.Opacity);
        w.WriteString("textBackgroundMode", s.TextBackgroundMode.ToString().ToLowerInvariant());
        WriteColor(w, "textBackgroundColor", s.TextBackgroundColor);
        w.WriteNumber("textBackgroundPadding", s.TextBackgroundPadding);
        w.WriteNumber("textBackgroundCornerRadius", s.TextBackgroundCornerRadius);
        w.WriteBoolean("textUnderline", s.TextUnderline);
        w.WriteBoolean("textStrikethrough", s.TextStrikethrough);
        w.WriteBoolean("textOutline", s.TextOutline);
        WriteColor(w, "textOutlineColor", s.TextOutlineColor);
        w.WriteNumber("textOutlineWidth", s.TextOutlineWidth);
        w.WriteBoolean("textShadow", s.TextShadow);
        w.WriteString("redactionMode", s.RedactionMode.ToString().ToLowerInvariant());
        w.WriteNumber("blurRadius", s.BlurRadius);
        w.WriteNumber("pixelSize", s.PixelSize);
        w.WriteStartObject("highlighterPen");
        WriteColor(w, "color", s.HighlighterPen.Color);
        w.WriteNumber("width", s.HighlighterPen.Width);
        w.WriteNumber("opacity", s.HighlighterPen.Opacity);
        w.WriteEndObject();
        w.WriteString("spotlightShape", s.SpotlightShape.ToString().ToLowerInvariant());
        w.WriteNumber("spotlightDim", s.SpotlightDim);
        w.WriteEndObject();
    }

    private static void WriteColor(Utf8JsonWriter w, string name, RGBAColor c)
    {
        w.WriteStartObject(name);
        w.WriteNumber("r", c.R); w.WriteNumber("g", c.G); w.WriteNumber("b", c.B); w.WriteNumber("a", c.A);
        w.WriteEndObject();
    }

    private static JsonElement? Prop(JsonElement o, string name)
    {
        foreach (var p in o.EnumerateObject())
            if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase)) return p.Value;
        return null;
    }

    private static double? Num(JsonElement o, string name) =>
        Prop(o, name) is { } v && v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out var d) && double.IsFinite(d) ? d : null;

    private static bool? Bool(JsonElement o, string name) =>
        Prop(o, name) is { } v ? v.ValueKind switch { JsonValueKind.True => true, JsonValueKind.False => false, _ => null } : null;

    private static string? Str(JsonElement o, string name) =>
        Prop(o, name) is { ValueKind: JsonValueKind.String } v ? v.GetString() : null;

    private static string? Lower(JsonElement o, string name) => Str(o, name)?.ToLower(CultureInfo.InvariantCulture);

    private static RGBAColor? Color(JsonElement o, string name)
    {
        if (Prop(o, name) is not { ValueKind: JsonValueKind.Object } c) return null;
        double? r = Num(c, "r"), g = Num(c, "g"), b = Num(c, "b"), a = Num(c, "a");
        return r is null || g is null || b is null ? null : new RGBAColor(r.Value, g.Value, b.Value, a ?? 1);
    }

    private static HighlighterPen? Pen(JsonElement o)
    {
        if (Prop(o, "highlighterPen") is not { ValueKind: JsonValueKind.Object } p) return null;
        var color = Color(p, "color");
        double? width = Num(p, "width"), opacity = Num(p, "opacity");
        if (color is null || width is null || opacity is null) return null;
        return new HighlighterPen(color.Value, width.Value, opacity.Value).Clamped();
    }
}
