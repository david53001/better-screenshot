using System.Text.RegularExpressions;
using BetterScreenshot.Core;

namespace BetterScreenshot.Capture;

/// <summary>
/// Rebuilds paragraphs from the individual visual lines the OCR returns, so a bullet that wraps over five lines on
/// a slide comes out as one line of text (port of the Mac v2.11.0 <c>CaptureKit/TextReflow.swift</c>). Pure geometry.
/// <para>A line continues the block above it only when all of these hold:
/// 1. it sits in the same column (its x-range overlaps the block's);
/// 2. the vertical spacing matches the block's rhythm (no blank-line gap, no pitch jump, no font-size change);
/// 3. it doesn't start with a list marker (<c>•</c>, <c>-</c>, <c>1.</c>, <c>a)</c> …);
/// 4. the previous line actually wrapped: its width plus the next line's first word would overflow the column's
///    right edge — which keeps short code lines apart (a line that stopped well short had room and ended on purpose).</para>
/// <para>Known limit: the longest line of a code block merges with its follower. Boxes use a top-left origin, in any
/// unit (normalised 0..1 or pixels) — every rule is a ratio.</para>
/// </summary>
public static class TextReflow
{
    public readonly record struct Line(string Text, PxRect Box);

    /// <summary>Gap above which two lines are never one paragraph, as a multiple of the taller line's height.</summary>
    internal const double MaxGapRatio = 1.0;
    /// <summary>Pitch above which a line breaks the block's rhythm, relative to its median pitch (slide: jitter ≤ 1.07×, break 1.33×).</summary>
    internal const double MaxPitchRatio = 1.25;
    /// <summary>Height ratio between adjacent lines that reads as a font-size change.</summary>
    internal const double MaxHeightRatio = 1.5;
    /// <summary>Same-row fragments closer than this many character widths join with a space.</summary>
    internal const double SameRowJoinChars = 2;

    private static readonly Regex ListMarker = new(@"^(?:[•\-–—*]|\(?\d{1,3}[.)]|\(?[a-zA-Z][.)])\s", RegexOptions.Compiled);
    private static readonly HashSet<char> BulletLookalikes = new() { '·', '●', '◦', '▪', '‣' };

    public static List<string> Paragraphs(IEnumerable<Line> lines)
    {
        var cleaned = lines
            .Select(l => new Line(Normalize(l.Text), l.Box))
            .Where(l => l.Text.Length > 0)
            .OrderBy(l => l.Box.Y).ThenBy(l => l.Box.X)
            .ToList();

        var blocks = new List<Block>();
        foreach (var line in cleaned)
        {
            double columnRight = cleaned.Where(o => OverlapsHorizontally(o.Box, line.Box)).Select(o => o.Box.Right)
                .DefaultIfEmpty(line.Box.Right).Max();
            // The OCR sometimes splits one visual row into fragments; glue those back first, and never treat a
            // row-mate as a wrapped continuation.
            int same = blocks.FindLastIndex(b => IsSameRow(b.Last.Box, line.Box) && IsAdjacent(b.Last.Box, line.Box));
            if (same >= 0) { blocks[same].AppendToLastLine(line); continue; }
            int idx = blocks.FindLastIndex(b => OverlapsHorizontally(b.XRange, line.Box));
            if (idx >= 0 && !IsSameRow(blocks[idx].Last.Box, line.Box) && Continues(blocks[idx], line, columnRight))
            {
                blocks[idx].Append(line);
                continue;
            }
            blocks.Add(new Block(line));
        }
        return blocks.OrderBy(b => b.Top).ThenBy(b => b.XRange.X).Select(b => b.Text).ToList();
    }

    private static bool Continues(Block block, Line line, double columnRight)
    {
        var prev = block.Last.Box;
        double tallest = Math.Max(prev.Height, line.Box.Height);
        double gap = line.Box.Y - prev.Bottom;
        if (gap > MaxGapRatio * tallest) return false;
        if (tallest / Math.Max(Math.Min(prev.Height, line.Box.Height), 1e-6) > MaxHeightRatio) return false;
        if (block.MedianPitch is { } pitch && line.Box.Y - prev.Y > MaxPitchRatio * pitch) return false;
        if (StartsWithListMarker(line.Text)) return false;
        return Wrapped(block.Last, line, columnRight);
    }

    /// <summary>Would the next line's first word have fit on the previous line?</summary>
    private static bool Wrapped(Line prev, Line next, double columnRight)
    {
        double charWidth = prev.Box.Width / Math.Max(prev.Text.Length, 1);
        int firstWord = next.Text.TakeWhile(c => !char.IsWhiteSpace(c)).Count();
        double needed = (firstWord + 1) * charWidth;
        return prev.Box.Right + needed > columnRight - 0.5 * charWidth;
    }

    internal static bool StartsWithListMarker(string text) => ListMarker.IsMatch(text);

    private static bool OverlapsHorizontally(PxRect a, PxRect b) =>
        Math.Min(a.Right, b.Right) - Math.Max(a.X, b.X) > 0.5 * Math.Min(a.Width, b.Width);

    private static bool IsSameRow(PxRect a, PxRect b) =>
        Math.Min(a.Bottom, b.Bottom) - Math.Max(a.Y, b.Y) > 0.5 * Math.Min(a.Height, b.Height);

    private static bool IsAdjacent(PxRect a, PxRect b)
    {
        double charWidth = Math.Min(a.Height, b.Height) * 0.6;
        double gap = Math.Max(a.X, b.X) - Math.Min(a.Right, b.Right);
        return gap < SameRowJoinChars * charWidth;
    }

    private static string Normalize(string raw)
    {
        string text = raw.Trim();
        if (text.Length > 0 && BulletLookalikes.Contains(text[0])) text = "•" + text[1..];
        return text;
    }

    private static PxRect Union(PxRect a, PxRect b) =>
        PxRect.FromLtrb(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Max(a.Right, b.Right), Math.Max(a.Bottom, b.Bottom));

    private sealed class Block
    {
        private readonly List<Line> _lines = new();
        public PxRect XRange { get; private set; }
        public double Top => _lines[0].Box.Y;
        public Line Last => _lines[^1];

        public Block(Line line) { _lines.Add(line); XRange = line.Box; }

        public void Append(Line line) { _lines.Add(line); XRange = Union(XRange, line.Box); }

        /// <summary>Two fragments of one visual row become one line.</summary>
        public void AppendToLastLine(Line fragment)
        {
            var merged = _lines[^1];
            _lines[^1] = new Line(merged.Text + " " + fragment.Text, Union(merged.Box, fragment.Box));
            XRange = Union(XRange, fragment.Box);
        }

        public double? MedianPitch
        {
            get
            {
                if (_lines.Count < 2) return null;
                var pitches = _lines.Zip(_lines.Skip(1), (a, b) => b.Box.Y - a.Box.Y).OrderBy(p => p).ToList();
                int mid = pitches.Count / 2;
                return pitches.Count % 2 == 0 ? (pitches[mid - 1] + pitches[mid]) / 2 : pitches[mid];
            }
        }

        public string Text => _lines.Skip(1).Aggregate(_lines[0].Text, (acc, line) =>
            acc.EndsWith('-') && !acc.EndsWith("--") && line.Text.Length > 0 && char.IsLower(line.Text[0])
                ? acc[..^1] + line.Text
                : acc + " " + line.Text);
    }
}
