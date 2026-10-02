using System.Globalization;
using System.Windows;
using System.Windows.Media;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using FlowDirection = System.Windows.FlowDirection;
using FontFamily = System.Windows.Media.FontFamily;
using TextAlignment = System.Windows.TextAlignment;

namespace BetterScreenshot.App.Editor;

/// <summary>
/// WPF text layout for text annotations (v3 A.1 / Part 2): font preset → Windows face mapping, missing-face
/// fallbacks, wrap width, alignment and decorations. The same layout drives the renderer, the hit-testing
/// bounds (<see cref="TextMetrics.Measure"/>) and the live editing box, so what you type lays out exactly like
/// the committed result.
/// </summary>
public static class TextRendering
{
    private static readonly Lazy<HashSet<string>> Installed = new(() =>
        new HashSet<string>(Fonts.SystemFontFamilies.Select(f => f.Source), StringComparer.OrdinalIgnoreCase));

    /// <summary>Installed families for the font menu, sorted, no "."-names, no "@" vertical faces. Sorted once: the
    /// inspector asks for it on every rebuild (round 3 #8).</summary>
    public static IReadOnlyList<string> InstalledFamilies => SortedFamilies.Value;

    private static readonly Lazy<IReadOnlyList<string>> SortedFamilies = new(() =>
        Installed.Value.Where(n => !n.StartsWith('.') && !n.StartsWith('@')).OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToList());

    private static string FirstInstalled(params string[] names) =>
        names.FirstOrDefault(n => Installed.Value.Contains(n)) ?? "Segoe UI";

    /// <summary>The Windows family for a persisted <see cref="AnnotationStyle.FontFamily"/>. Unknown or
    /// uninstalled families fall back to the System preset so an old style still renders.</summary>
    public static FontFamily Family(string family) => family switch
    {
        TextFont.System => new FontFamily(FirstInstalled("Segoe UI Variable Text", "Segoe UI")),
        TextFont.Rounded => new FontFamily(FirstInstalled("Segoe UI Variable Display", "Arial Rounded MT Bold", "Segoe UI")),
        TextFont.Serif => new FontFamily(FirstInstalled("Georgia", "Cambria", "Times New Roman")),
        TextFont.Mono => new FontFamily(FirstInstalled("Cascadia Mono", "Consolas", "Courier New")),
        _ when Installed.Value.Contains(family) => new FontFamily(family),
        _ => Family(TextFont.System),
    };

    /// <summary>Presets: Semibold when bold (the historical look), Regular otherwise; named families: Bold.</summary>
    public static Typeface Typeface(AnnotationStyle s)
    {
        bool preset = TextFont.IsPreset(s.FontFamily) || !Installed.Value.Contains(s.FontFamily);
        var weight = s.FontBold ? (preset ? FontWeights.SemiBold : FontWeights.Bold) : FontWeights.Normal;
        return new Typeface(Family(s.FontFamily), s.FontItalic ? FontStyles.Italic : FontStyles.Normal, weight, FontStretches.Normal);
    }

    public static TextAlignment Alignment(TextAlign a) => a switch
    {
        TextAlign.Center => TextAlignment.Center,
        TextAlign.Right => TextAlignment.Right,
        _ => TextAlignment.Left,
    };

    /// <summary>Lays out <paramref name="text"/>. With a wrap width the lines wrap at it; a free label is laid out
    /// unbounded, then re-laid at its own width (+1 px slack) so alignment applies within its box.</summary>
    public static FormattedText Format(string text, AnnotationStyle s, double? wrapWidth, Brush brush)
    {
        var ft = Raw(text.Length == 0 ? " " : text, s, brush);
        double width = wrapWidth ?? Math.Ceiling(ft.WidthIncludingTrailingWhitespace) + 1;
        ft.MaxTextWidth = Math.Max(1, width);
        ft.TextAlignment = Alignment(s.TextAlignment);
        var deco = new TextDecorationCollection();
        if (s.TextUnderline) deco.Add(TextDecorations.Underline);
        if (s.TextStrikethrough) deco.Add(TextDecorations.Strikethrough);
        if (deco.Count > 0) ft.SetTextDecorations(deco);
        return ft;
    }

    private static FormattedText Raw(string text, AnnotationStyle s, Brush brush) =>
        new(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, Typeface(s), Math.Max(1, s.FontSize), brush, 1.0)
        {
            Trimming = TextTrimming.None,
        };

    /// <summary>Natural size (image px) — installed as <see cref="TextMetrics.Measure"/>.</summary>
    public static PxSize Measure(string text, AnnotationStyle s, double? wrapWidth)
    {
        var raw = Raw(text.Length == 0 ? " " : text, s, Brushes.Black);
        if (wrapWidth is { } w) raw.MaxTextWidth = Math.Max(1, w);
        return new PxSize(raw.WidthIncludingTrailingWhitespace, raw.Height);
    }

    private static int _installed;

    /// <summary>Routes the pure model's text measuring through WPF (idempotent).</summary>
    public static void Install()
    {
        if (Interlocked.Exchange(ref _installed, 1) == 1) return;
        TextMetrics.Measure = Measure;
    }
}
