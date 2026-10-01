using BetterScreenshot.Core;

namespace BetterScreenshot.Editor;

/// <summary>The box behind a text annotation (port of the Mac <c>TextChip</c>).</summary>
public static class TextChip
{
    public static readonly RGBAColor DarkChip = new(0x18 / 255.0, 0x18 / 255.0, 0x1A / 255.0, 1);
    public static readonly RGBAColor LightChip = new(0xF4 / 255.0, 0xF4 / 255.0, 0xF6 / 255.0, 1);

    /// <summary>Below this an outline doesn't separate from its letters (WCAG's minimum for graphics).</summary>
    public const double MinOutlineContrast = 3.0;

    /// <summary>The Auto box colour for <paramref name="text"/>: #18181A behind light text, #F4F4F6 behind dark.</summary>
    public static RGBAColor AutoColor(RGBAColor text) =>
        0.2126 * text.R + 0.7152 * text.G + 0.0722 * text.B > 0.5 ? DarkChip : LightChip;

    /// <summary>WCAG 2.x contrast ratio between two colours, ignoring alpha.</summary>
    public static double ContrastRatio(RGBAColor a, RGBAColor b)
    {
        static double L(RGBAColor c) =>
            0.2126 * Srgb.Expand(Math.Clamp(c.R, 0, 1)) + 0.7152 * Srgb.Expand(Math.Clamp(c.G, 0, 1)) + 0.0722 * Srgb.Expand(Math.Clamp(c.B, 0, 1));
        return Srgb.ContrastRatio(L(a), L(b));
    }

    /// <summary>The outline for <paramref name="text"/>: <paramref name="current"/> when it contrasts ≥ 3:1 with
    /// the letters, else black or white, whichever contrasts more.</summary>
    public static RGBAColor OutlineColor(RGBAColor current, RGBAColor text)
    {
        if (ContrastRatio(current, text) >= MinOutlineContrast) return current;
        return ContrastRatio(RGBAColor.Black, text) >= ContrastRatio(RGBAColor.White, text) ? RGBAColor.Black : RGBAColor.White;
    }

    /// <summary>How far the box extends past the text's line box: padding left/right, half of it top/bottom.</summary>
    public static PxSize Insets(double padding) => new(padding, padding / 2);

    /// <summary>The fixed drop shadow for a text of <paramref name="fontSize"/>: offset straight down, blur radius.</summary>
    public static (double Offset, double Blur) Shadow(double fontSize) => (Math.Max(1, 0.05 * fontSize), Math.Max(2, 0.15 * fontSize));
}

/// <summary>
/// Corner-handle scaling of a text (port of <c>TextScale.swift</c>): font size, box width, padding, corner radius
/// and outline width scale together while the corner opposite the dragged one stays put.
/// </summary>
public static class TextScale
{
    public const double MinFontSize = 8, MaxFontSize = 400;

    public enum Corner { TopLeft, TopRight, BottomLeft, BottomRight }

    public static PxPoint Point(Corner c, PxRect box) => c switch
    {
        Corner.TopLeft => new PxPoint(box.X, box.Y),
        Corner.TopRight => new PxPoint(box.Right, box.Y),
        Corner.BottomLeft => new PxPoint(box.X, box.Bottom),
        _ => new PxPoint(box.Right, box.Bottom),
    };

    /// <summary>The corner diagonally opposite <paramref name="c"/> — the point that stays fixed.</summary>
    public static PxPoint Anchor(Corner c, PxRect box) => c switch
    {
        Corner.TopLeft => Point(Corner.BottomRight, box),
        Corner.TopRight => Point(Corner.BottomLeft, box),
        Corner.BottomLeft => Point(Corner.TopRight, box),
        _ => Point(Corner.TopLeft, box),
    };

    /// <summary>The drag projected onto the box's diagonal, relative to the diagonal (1 = unchanged).</summary>
    public static double Factor(PxRect box, Corner corner, double dx, double dy)
    {
        var a = Anchor(corner, box);
        var c = Point(corner, box);
        double ddx = c.X - a.X, ddy = c.Y - a.Y;
        double len2 = ddx * ddx + ddy * ddy;
        if (len2 <= 0) return 1;
        return ((c.X + dx - a.X) * ddx + (c.Y + dy - a.Y) * ddy) / len2;
    }

    /// <summary><paramref name="style"/> and <paramref name="wrapWidth"/> scaled: the font rounded and clamped to
    /// 8…400, everything else by the factor the font actually moved, within its range. Nil width stays nil.</summary>
    public static (AnnotationStyle Style, double? WrapWidth) Scaled(AnnotationStyle style, double? wrapWidth, double factor)
    {
        double size = Math.Clamp(Math.Round(style.FontSize * factor, MidpointRounding.AwayFromZero), MinFontSize, MaxFontSize);
        double k = size / style.FontSize;
        var s = style with
        {
            FontSize = size,
            TextBackgroundPadding = Math.Clamp(style.TextBackgroundPadding * k, 0, AnnotationStyle.MaxBoxPadding),
            TextBackgroundCornerRadius = Math.Clamp(style.TextBackgroundCornerRadius * k, 0, AnnotationStyle.MaxBoxRadius),
            TextOutlineWidth = Math.Clamp(style.TextOutlineWidth * k, AnnotationStyle.MinOutlineWidth, AnnotationStyle.MaxOutlineWidth),
        };
        return (s, wrapWidth * k);
    }

    /// <summary>A rect of <paramref name="size"/> whose corner opposite <paramref name="corner"/> sits at <paramref name="anchor"/>.</summary>
    public static PxRect Placed(PxSize size, PxPoint anchor, Corner corner)
    {
        double x = corner is Corner.TopLeft or Corner.BottomLeft ? anchor.X - size.Width : anchor.X;
        double y = corner is Corner.TopLeft or Corner.TopRight ? anchor.Y - size.Height : anchor.Y;
        return new PxRect(x, y, size.Width, size.Height);
    }
}

/// <summary>Where a selected text's handles go, in view points (port of <c>TextHandles.swift</c>): round corner
/// handles just outside the box (scale) and thin side bars (box width) that disappear when they'd hit the corners.</summary>
public static class TextHandles
{
    public const double CornerDiameter = 9, Outset = 4, BarWidth = 4, MaxBarHeight = 16, MinBarHeight = 6, Clearance = 2;
    /// <summary>Handle indices: 0 top-left, 2 top-right, 5 bottom-left, 7 bottom-right; 3 middle-left, 4 middle-right.</summary>
    public static readonly int[] Corners = { 0, 2, 5, 7 };
    public static readonly int[] Sides = { 3, 4 };

    public static Dictionary<int, PxRect> Rects(PxRect box)
    {
        double r = CornerDiameter / 2;
        double left = box.X - Outset, right = box.Right + Outset, top = box.Y - Outset, bottom = box.Bottom + Outset;
        PxRect Circle(double x, double y) => new(x - r, y - r, CornerDiameter, CornerDiameter);
        var rects = new Dictionary<int, PxRect>
        {
            [0] = Circle(left, top), [2] = Circle(right, top), [5] = Circle(left, bottom), [7] = Circle(right, bottom),
        };
        double free = (bottom - r) - (top + r) - 2 * Clearance;
        double barHeight = Math.Min(MaxBarHeight, free);
        if (barHeight >= MinBarHeight)
        {
            double midY = box.Y + box.Height / 2;
            PxRect Bar(double x) => new(x - BarWidth / 2, midY - barHeight / 2, BarWidth, barHeight);
            rects[3] = Bar(left);
            rects[4] = Bar(right);
        }
        return rects;
    }

    public static TextScale.Corner CornerOf(int handle) => handle switch
    {
        0 => TextScale.Corner.TopLeft,
        2 => TextScale.Corner.TopRight,
        5 => TextScale.Corner.BottomLeft,
        _ => TextScale.Corner.BottomRight,
    };
}

/// <summary>One-click text looks (port of <c>TextStylePreset.swift</c>). A preset sets only the text look; it
/// never touches alignment, opacity, line width or the box width.</summary>
public enum TextStylePreset { Label, Callout, Note, Code, Title, Subtle }

public static class TextStylePresets
{
    public static string DisplayName(this TextStylePreset p) => p.ToString();

    public static string Tooltip(this TextStylePreset p) => p switch
    {
        TextStylePreset.Label => "Label — bold white text on a black box",
        TextStylePreset.Callout => "Callout — bold white text on a red box",
        TextStylePreset.Note => "Note — black text on a yellow box",
        TextStylePreset.Code => "Code — light monospaced text on a dark box",
        TextStylePreset.Title => "Title — 48 pt bold, no box (keeps the colour)",
        _ => "Subtle — 18 pt regular grey, no box",
    };

    /// <summary>(text colour or null = keep, size or null = keep, family, bold, box (colour, padding, radius) or null = no box).</summary>
    public static (RGBAColor? Color, double? Size, string Family, bool Bold, (RGBAColor Color, double Padding, double Radius)? Box) Look(this TextStylePreset p) => p switch
    {
        TextStylePreset.Label => (RGBAColor.White, null, TextFont.System, true, (new RGBAColor(0, 0, 0, 0.8), 6, 4)),
        TextStylePreset.Callout => (RGBAColor.White, null, TextFont.System, true, (new RGBAColor(1, 0.27, 0.23, 1), 8, 6)),
        TextStylePreset.Note => (RGBAColor.Black, null, TextFont.System, false, (new RGBAColor(1, 0.84, 0.04, 1), 8, 2)),
        TextStylePreset.Code => (new RGBAColor(0.90, 0.92, 0.95, 1), null, TextFont.Mono, false, (new RGBAColor(0.12, 0.13, 0.15, 1), 6, 4)),
        TextStylePreset.Title => (null, 48, TextFont.System, true, null),
        _ => (new RGBAColor(0.56, 0.56, 0.58, 1), 18, TextFont.System, false, null),
    };

    public static AnnotationStyle Apply(this TextStylePreset p, AnnotationStyle s)
    {
        var look = p.Look();
        if (look.Color is { } c) s = s with { StrokeColor = c, FillColor = c.WithAlpha(0.25) };
        if (look.Size is { } size) s = s with { FontSize = size };
        s = s with
        {
            FontFamily = look.Family, FontBold = look.Bold, FontItalic = false,
            TextUnderline = false, TextStrikethrough = false, TextOutline = false, TextShadow = false,
        };
        return look.Box is { } box
            ? s with { TextBackgroundMode = TextBackgroundMode.Solid, TextBackgroundColor = box.Color, TextBackgroundPadding = box.Padding, TextBackgroundCornerRadius = box.Radius }
            : s with { TextBackgroundMode = TextBackgroundMode.None };
    }

    /// <summary>True when <paramref name="s"/> already has this look (the panel rings that chip).</summary>
    public static bool IsApplied(this TextStylePreset p, AnnotationStyle s) => p.Apply(s) == s;
}
