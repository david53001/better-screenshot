using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using BetterScreenshot.Core;

namespace BetterScreenshot.Capture;

/// <summary>
/// Rebuilds readable text from the individual visual lines the OCR returns — port of the Mac
/// <c>CaptureKit/TextReflow.swift</c> on the <c>ocr-structure-math</c> branch (v3 Part 8 §8.2 clipboard format).
/// Pure geometry, unit-tested with the Mac's own cases.
/// <para>The engine already hands lines over in reading order (column by column on a two-column page), so that order
/// is kept; what this adds is structure:
/// • fragments of one visual line are glued back together, left to right;
/// • grids — rows of separate cells whose columns line up — become one line per row with tab-separated cells (pastes
///   into a spreadsheet as a grid), and short right-hand annotations (exam marks, page numbers) join their row;
/// • code keeps one line per line, its indentation and its blank lines (a line-number gutter is dropped);
/// • everything else is prose: wrapped lines rejoin into paragraphs, list items keep their nesting (one tab per
///   level), and a paragraph that runs into the next column joins up.</para>
/// <para>All geometry is in pixels (<c>imageSize</c>): boxes come in normalised (0…1, top-left origin) and are scaled
/// separately in x and y, so comparing a width with a height needs the aspect.</para>
/// <para>Windows port (BS #11 PARTIAL): the Mac's maths passes — stacked fractions (<c>ruleLength</c>), detached
/// scripts, super/subscript recovery — are deferred while the Mac branch is WIP; the text-only math-line tidying
/// (<see cref="MathText"/>) runs, as it does on the Mac with "Recognize math" off.</para>
/// </summary>
public static class TextReflow
{
    /// <summary>One recognised visual line. <see cref="Box"/> is normalised (0…1) with a top-left origin.</summary>
    /// <param name="RawText">The same line read without language correction (code uses it); Windows.Media.Ocr has no
    /// correction switch, so the port leaves it null.</param>
    /// <param name="Recovered">The line with scripts / math symbols rebuilt (what prose and tables show); null = <paramref name="Text"/>.</param>
    /// <param name="WordBoxes">The engine's box for each whitespace-separated word of <paramref name="Text"/>, left to
    /// right (same coordinates as <paramref name="Box"/>); lets a line that runs across table cells be cut between them.</param>
    public sealed record Line(string Text, PxRect Box, string? RawText = null, string? Recovered = null,
        IReadOnlyList<PxRect>? WordBoxes = null);

    /// <summary>Vertical gap above which two lines are never one paragraph, as a multiple of the taller line's height.</summary>
    internal const double MaxGapRatio = 1.0;
    /// <summary>Line pitch above which a line breaks a paragraph's rhythm, relative to its median pitch (slide:
    /// intra-paragraph jitter ≤ 1.07×, paragraph break 1.33×).</summary>
    internal const double MaxPitchRatio = 1.25;
    /// <summary>A font-size change needs glyph height *and* character width to jump by this much — either alone is noise.</summary>
    internal const double FontChangeRatio = 1.4;
    /// <summary>Same-row fragments closer than this many character widths are one line.</summary>
    internal const double SameRowJoinChars = 1.5;
    /// <summary>A table's vertical grid line runs past the text beside it by this much of the row's height.</summary>
    internal const double RuleReach = 0.2;
    /// <summary>Longest line <see cref="SplittingAcrossBands"/> will cut: a row of short cells, not prose.</summary>
    private const int MaxSplitWords = 8;

    /// <summary>The paragraphs / table rows / code blocks, in reading order. <paramref name="verticalRules"/> (optional)
    /// gives the x positions (pixels) of vertical lines crossing all of a pixel region; with it, a gridded table's cells
    /// are separated by its grid lines.</summary>
    public static List<string> Paragraphs(IEnumerable<Line> lines, PxSize? imageSize = null,
        Func<PxRect, IReadOnlyList<double>>? verticalRules = null) =>
        JoinedAcrossColumns(Layout(lines.ToList(), imageSize ?? new PxSize(1, 1), verticalRules)).Select(p => p.Text).ToList();

    /// <summary>True when some block reads as source code.</summary>
    public static bool ContainsCode(IEnumerable<Line> lines, PxSize? imageSize = null) =>
        Layout(lines.ToList(), imageSize ?? new PxSize(1, 1), null).Any(p => p.Kind == PieceKind.Code);

    // ------------------------------------------------------------------ layout

    internal sealed record Seg(string Text, string Shown, string? Raw, PxRect Box, int Order)
    {
        public IReadOnlyList<PxRect>? WordBoxes { get; init; }
        /// <summary>x positions of the table grid lines crossing this fragment's row.</summary>
        public IReadOnlyList<double> RowRules { get; init; } = Array.Empty<double>();
        public double CharWidth => Box.Width / Math.Max(Text.Length, 1);
        public int Words => SplitWords(Text).Length;
    }

    internal enum PieceKind { Prose, Code, Grid }

    internal sealed class Piece
    {
        public PieceKind Kind;
        public string Text = "";
        public int Order;
        public PxRect Box;
        public Seg? First, Last;
        public double ColumnRight;
        public bool OpensRun, ClosesRun;
    }

    private static List<Piece> Layout(List<Line> lines, PxSize imageSize, Func<PxRect, IReadOnlyList<double>>? verticalRules)
    {
        var segs = Segments(ColumnOrdered(lines), imageSize);
        segs = DroppingLineNumbers(segs);
        if (verticalRules != null) segs = SplittingAtRules(segs, imageSize.Width, verticalRules);
        var pieces = new List<Piece>();
        var used = new HashSet<int>();
        foreach (var grid in Grids(segs))
        {
            used.UnionWith(grid.Members);
            pieces.Add(new Piece
            {
                Kind = PieceKind.Grid, Text = grid.Text, Order = grid.Members.Min(m => segs[m].Order),
                Box = grid.Members.Skip(1).Aggregate(segs[grid.Members[0]].Box, (b, m) => b.Union(segs[m].Box)),
            });
        }
        foreach (var run in Runs(segs, used))
            pieces.AddRange(Flow(run.Select(i => segs[i]).ToList(), imageSize.Width));
        return TitlesAboveGrids(pieces.OrderBy(p => p.Order).ToList());
    }

    /// <summary>The engine reads a left column only down to a gap (a figure) and lists what is under the gap (its
    /// caption) after the whole right column: a line that follows a stack of three or more lines beside it, and sits
    /// under the line before that stack, goes back into its own column.</summary>
    public static List<Line> ColumnOrdered(IReadOnlyList<Line> input)
    {
        var lines = input.ToList();
        static bool Overlaps(PxRect a, PxRect b) => Math.Min(a.Right, b.Right) > Math.Max(a.X, b.X);
        for (int i = 1; i < lines.Count; i++)
        {
            var line = lines[i].Box;
            double gutter = 2 * line.Width / Math.Max(lines[i].Text.Length, 1);
            int start = i;
            while (start > 0 && !Overlaps(lines[start - 1].Box, line)) start--;
            var stack = lines.GetRange(start, i - start).Select(l => l.Box).ToList();
            if (start > 0 && stack.Count >= 3 && lines[i].Text.Length >= 4 && stack.All(b => b.X >= line.Right + gutter)
                && stack.Zip(stack.Skip(1)).All(p => Overlaps(p.First, p.Second) && p.Second.Y > p.First.Y)
                && stack[0].Y < line.Y && lines[start - 1].Box.Bottom <= line.Y)
            {
                var moved = lines[i];
                lines.RemoveAt(i);
                lines.Insert(start, moved);
            }
        }
        return lines;
    }

    /// <summary>A line sitting right above a grid goes before it (its title).</summary>
    private static List<Piece> TitlesAboveGrids(List<Piece> pieces)
    {
        for (int g = 0; g < pieces.Count; g++)
        {
            if (pieces[g].Kind != PieceKind.Grid) continue;
            var grid = pieces[g].Box;
            var titles = Enumerable.Range(0, pieces.Count).Where(i =>
                i > g && pieces[i].Kind == PieceKind.Prose && pieces[i].Box.Bottom <= grid.Y + 0.2 * pieces[i].Box.Height
                && pieces[i].Box.Y > grid.Y - 3 * pieces[i].Box.Height
                && Math.Min(pieces[i].Box.Right, grid.Right) - Math.Max(pieces[i].Box.X, grid.X) > 0).ToList();
            for (int k = titles.Count - 1; k >= 0; k--)
            {
                var title = pieces[titles[k]];
                pieces.RemoveAt(titles[k]);
                pieces.Insert(g, title);
            }
        }
        return pieces;
    }

    /// <summary>Converts to pixels, normalises text, and glues fragments of one visual line back together (in the
    /// engine's order).</summary>
    internal static List<Seg> Segments(IReadOnlyList<Line> lines, PxSize imageSize)
    {
        var segs = new List<Seg>();
        PxRect Pixels(PxRect b) => new(b.X * imageSize.Width, b.Y * imageSize.Height, b.Width * imageSize.Width, b.Height * imageSize.Height);
        for (int index = 0; index < lines.Count; index++)
        {
            var line = lines[index];
            string text = Normalize(line.Text);
            if (text.Length == 0) continue;
            var seg = new Seg(text, line.Recovered is { } rec ? Normalize(rec) : text, line.RawText is { } raw ? Normalize(raw) : null,
                Pixels(line.Box), index) { WordBoxes = line.WordBoxes?.Select(Pixels).ToList() };
            while (true)
            {
                var s0 = seg;
                int j = segs.FindIndex(s => IsSameRow(s.Box, s0.Box) && IsAdjacent(s, s0)
                    && Math.Abs(MidY(s.Box) - MidY(s0.Box)) <= 0.4 * Math.Max(s.Box.Height, s0.Box.Height));
                if (j < 0) break;
                var other = segs[j];
                segs.RemoveAt(j);
                seg = Joined(other, seg);
            }
            segs.Add(seg);
        }
        return segs.OrderBy(s => s.Order).ToList();
    }

    private static Seg Joined(Seg a, Seg b)
    {
        var (l, r) = a.Box.X <= b.Box.X ? (a, b) : (b, a);
        // Touching fragments join without a space only at punctuation (`printf("%d\n"` + `, *p);`).
        double gap = r.Box.X - l.Box.Right;
        bool tight = gap < 0.25 * Math.Min(l.CharWidth, r.CharWidth)
            && ((r.Text.Length > 0 && ",.;:)]}!?%".Contains(r.Text[0])) || (l.Text.Length > 0 && "([{/".Contains(l.Text[^1])));
        string sep = tight ? "" : " ";
        string? raw = l.Raw == null && r.Raw == null ? null : (l.Raw ?? l.Text) + sep + (r.Raw ?? r.Text);
        IReadOnlyList<PxRect>? words = sep.Length == 0 ? null
            : ValidWordBoxes(l) is { } lw && ValidWordBoxes(r) is { } rw ? lw.Concat(rw).ToList() : null;
        return new Seg(l.Text + sep + r.Text, l.Shown + sep + r.Shown, raw, l.Box.Union(r.Box), Math.Min(l.Order, r.Order)) { WordBoxes = words };
    }

    /// <summary>A code view's gutter (a left column of consecutive integers next to monospaced lines) is dropped. A
    /// table's rank column sits next to proportional text and stays.</summary>
    internal static List<Seg> DroppingLineNumbers(List<Seg> segs)
    {
        Seg? RightNeighbour(int i) => segs.Where(s => IsSameRow(s.Box, segs[i].Box) && s.Box.X > segs[i].Box.Right).MinBy(s => s.Box.X);
        static int? Int(string s) => int.TryParse(s, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var v) ? v : null;
        var numbers = Enumerable.Range(0, segs.Count).Where(i =>
                segs[i].Text.Length <= 5 && Int(segs[i].Text) != null
                && !segs.Any(s => IsSameRow(s.Box, segs[i].Box) && s.Box.Right <= segs[i].Box.X))
            .OrderBy(i => segs[i].Box.Y).ToList();
        var best = new List<int>();
        var current = new List<int>();
        foreach (int i in numbers)
        {
            if (current.Count > 0 && Int(segs[i].Text) == Int(segs[current[^1]].Text) + 1 && OverlapsHorizontally(segs[current[^1]].Box, segs[i].Box))
                current.Add(i);
            else
                current = new List<int> { i };
            if (current.Count > best.Count) best = current.ToList();
        }
        if (best.Count < 3) return segs;
        var code = best.Select(RightNeighbour).OfType<Seg>().ToList();
        if (!(code.Count * 3 >= best.Count * 2 && IsMonospace(code, evidence: 2))) return segs;
        var drop = best.ToHashSet();
        return Enumerable.Range(0, segs.Count).Where(i => !drop.Contains(i)).Select(i => segs[i]).ToList();
    }

    /// <summary>Consecutive (in reading order) segments stacked in one column.</summary>
    private static List<List<int>> Runs(List<Seg> segs, HashSet<int> used)
    {
        static bool BracketsOnly(Seg x) => x.Text.All(c => "{}[](),; ".Contains(c));
        var runs = new List<List<int>>();
        for (int i = 0; i < segs.Count; i++)
        {
            if (used.Contains(i)) continue;
            var s = segs[i];
            if (runs.Count > 0)
            {
                var run = runs[^1];
                var prev = segs[run[^1]];
                double left = run.Min(j => segs[j].Box.X), right = run.Max(j => segs[j].Box.Right);
                double overlap = Math.Min(right, s.Box.Right) - Math.Max(left, s.Box.X);
                // A lone `{` and the keys indented under it share a column too.
                bool nearLeft = (BracketsOnly(s) || run.All(j => BracketsOnly(segs[j])))
                    && Math.Abs(s.Box.X - left) <= 4 * Math.Max(s.CharWidth, prev.CharWidth);
                if ((overlap > 0.5 * Math.Min(s.Box.Width, right - left) || nearLeft) && s.Box.Y > MidY(prev.Box))
                {
                    run.Add(i);
                    continue;
                }
            }
            runs.Add(new List<int> { i });
        }
        return runs;
    }

    // ------------------------------------------------------------------ grids

    private sealed record Grid(List<int> Members, string Text);

    /// <summary>Visual rows, top to bottom, each left to right.</summary>
    private static List<List<int>> Rows(List<Seg> segs, ISet<int>? skipped = null)
    {
        var rows = new List<List<int>>();
        foreach (int i in Enumerable.Range(0, segs.Count).Where(i => skipped?.Contains(i) != true).OrderBy(i => MidY(segs[i].Box)))
        {
            if (rows.Count > 0 && rows[^1].Any(j => IsSameRow(segs[j].Box, segs[i].Box))) rows[^1].Add(i);
            else rows.Add(new List<int> { i });
        }
        return rows.Select(r => r.OrderBy(i => segs[i].Box.X).ToList()).ToList();
    }

    /// <summary>A table's grid lines are cell boundaries: every fragment learns its row's vertical grid lines, and one
    /// that runs across a grid line is cut there, between words. A line counts only if another row has one at the
    /// same x (a table, not a stray vertical stroke).</summary>
    private static List<Seg> SplittingAtRules(List<Seg> segs, double imageWidth, Func<PxRect, IReadOnlyList<double>> rules)
    {
        var rows = Rows(segs);
        if (rows.Count(r => r.Count >= 2) < 2) return segs;
        var found = rows.Select(row =>
        {
            var tops = row.Select(i => segs[i].Box.Y).Order().ToList();
            var bottoms = row.Select(i => segs[i].Box.Bottom).Order().ToList();
            double top = tops[tops.Count / 2], bottom = bottoms[bottoms.Count / 2];
            double reach = RuleReach * (bottom - top);
            return rules(new PxRect(0, top - reach, imageWidth, bottom - top + 2 * reach)).ToList();
        }).ToList();
        double tolerance = RuleTolerance(Enumerable.Range(0, segs.Count), segs);
        var seen = found;
        found = seen.Select((xs, r) => xs.Where(x =>
            Enumerable.Range(0, seen.Count).Any(o => o != r && seen[o].Any(y => Math.Abs(y - x) <= tolerance))).ToList()).ToList();
        if (!found.Any(f => f.Count > 0)) return segs;
        var rowOf = new Dictionary<int, int>();
        for (int r = 0; r < rows.Count; r++) foreach (int i in rows[r]) rowOf[i] = r;
        var output = new List<Seg>();
        for (int i = 0; i < segs.Count; i++)
        {
            var seg = segs[i] with { RowRules = found[rowOf[i]] };
            var cuts = new SortedSet<int>();
            if (ValidWordBoxes(seg) is { } boxes)
            {
                foreach (double x in seg.RowRules.Where(x => x > seg.Box.X && x < seg.Box.Right))
                {
                    // The word gap nearest the line, if the line lies in it.
                    double Distance(int k) => Math.Abs(x - (boxes[k - 1].Right + boxes[k].X) / 2);
                    var gaps = Enumerable.Range(1, Math.Max(0, boxes.Count - 1)).Where(k => MidX(boxes[k - 1]) < x && x < MidX(boxes[k])).ToList();
                    if (gaps.Count > 0) cuts.Add(gaps.MinBy(Distance));
                }
            }
            output.AddRange(Split(seg, cuts.ToList()) ?? new List<Seg> { seg });
        }
        return output;
    }

    /// <summary>How far apart two sightings of one grid line may be.</summary>
    private static double RuleTolerance(IEnumerable<int> indices, List<Seg> segs)
    {
        var heights = indices.Select(i => segs[i].Box.Height).Order().ToList();
        return heights.Count == 0 ? 0 : 0.3 * heights[heights.Count / 2];
    }

    /// <summary>A fragment's word boxes when they still line up with its words; a one-word fragment's box is its word's.</summary>
    private static IReadOnlyList<PxRect>? ValidWordBoxes(Seg seg)
    {
        if (seg.WordBoxes is { } boxes && boxes.Count == seg.Words) return boxes;
        return seg.Words == 1 ? new[] { seg.Box } : null;
    }

    /// <summary><paramref name="seg"/> cut into pieces before each word index in <paramref name="cuts"/>; null when the
    /// shown text no longer lines up word for word with the engine's.</summary>
    private static List<Seg>? Split(Seg seg, IReadOnlyList<int> cuts)
    {
        if (cuts.Count == 0 || ValidWordBoxes(seg) is not { } boxes) return null;
        var text = SplitWords(seg.Text);
        var shown = SplitWords(seg.Shown);
        var raw = seg.Raw is { } r ? SplitWords(r) : null;
        if (shown.Length != text.Length || !cuts.All(c => c > 0 && c < text.Length)) return null;
        var bounds = new List<int> { 0 };
        bounds.AddRange(cuts);
        bounds.Add(text.Length);
        return bounds.Zip(bounds.Skip(1)).Select(p =>
        {
            int a = p.First, b = p.Second;
            double left = boxes.Skip(a).Take(b - a).Min(x => x.X), right = boxes.Skip(a).Take(b - a).Max(x => x.Right);
            return new Seg(string.Join(' ', text[a..b]), string.Join(' ', shown[a..b]),
                raw != null && raw.Length == text.Length ? string.Join(' ', raw[a..b]) : null,
                new PxRect(left, seg.Box.Y, right - left, seg.Box.Height), seg.Order)
            { WordBoxes = boxes.Skip(a).Take(b - a).ToList(), RowRules = seg.RowRules };
        }).ToList();
    }

    /// <summary>A sidebar beside a table (Settings' General · Appearance · Wi-Fi): a column of short items at the
    /// layout's left or right edge, most of which line up with no row of what is beside it. Never part of a grid.</summary>
    private static HashSet<int> Sidebar(List<Seg> segs)
    {
        if (segs.Count < 6) return new HashSet<int>();
        double left = segs.Min(s => s.Box.X), right = segs.Max(s => s.Box.Right);
        foreach (bool edge in new[] { true, false })
        {
            var column = Enumerable.Range(0, segs.Count).Where(i =>
            {
                var b = segs[i].Box;
                double c = segs[i].CharWidth;
                return edge ? b.X - left < 1.5 * c : right - b.Right < 1.5 * c;
            }).ToList();
            if (column.Count < 3 || !column.All(i => segs[i].Words <= 3)) continue;
            double inner = column.Max(i => segs[i].Box.Right), outer = column.Min(i => segs[i].Box.X);
            var beside = Enumerable.Range(0, segs.Count).Where(i => !column.Contains(i)
                && (edge ? segs[i].Box.X > inner + 2 * segs[i].CharWidth : segs[i].Box.Right < outer - 2 * segs[i].CharWidth)).ToList();
            if (beside.Count < 3 || beside.Count + column.Count != segs.Count) continue;
            var aligned = column.Where(i => beside.Any(j =>
                Math.Abs(MidY(segs[i].Box) - MidY(segs[j].Box)) < 0.25 * Math.Min(segs[i].Box.Height, segs[j].Box.Height))).ToList();
            if (2 * aligned.Count < column.Count) return column.ToHashSet();
        }
        return new HashSet<int>();
    }

    private static List<Grid> Grids(List<Seg> segs)
    {
        var rows = Rows(segs, Sidebar(segs));
        var grids = new List<Grid>();
        int i = 0;
        while (i < rows.Count)
        {
            if (rows[i].Count < 2) { i++; continue; }
            int end = i, lastMulti = i, j = i + 1;
            while (j < rows.Count)
            {
                if (rows[j].Count >= 2) { end = j; lastMulti = j; j++; continue; }
                // A one-cell row stays in the grid when it doesn't span columns and either another multi-cell row
                // follows or it is the next line of a wrapped cell.
                int seg = rows[j][0];
                bool spans = rows[lastMulti].Count(k => OverlapWidth(segs[k].Box, segs[seg].Box) > 0) >= 2;
                bool multiFollows = j + 1 < rows.Count && rows[j + 1].Count >= 2;
                if (!spans && (multiFollows || ContinuesCell(seg, rows[j - 1], segs))) { end = j; j++; continue; }
                break;
            }
            if (MakeGrid(rows.GetRange(i, end - i + 1), segs) is { } grid) grids.Add(grid);
            i = end + 1;
        }
        return grids;
    }

    private static Grid? MakeGrid(List<List<int>> run, List<Seg> segs)
    {
        var members = run.SelectMany(r => r).ToList();
        var multi = run.Where(r => r.Count >= 2).ToList();
        if (multi.Count == 1)
        {
            // One isolated row of short pieces: a running header and its page number, a label and its value.
            if (!(run.Count == 1 && run[0].All(k => segs[k].Words <= 6))) return null;
            return new Grid(run[0], string.Join('\t', run[0].Select(k => segs[k].Shown)));
        }
        run = run.Select(r => r.ToList()).ToList();
        segs = segs.ToList();
        var ruled = RuledColumns(run, segs);
        if (ruled == null)
        {
            (run, segs) = SplittingAcrossBands(run, segs);
            multi = run.Where(r => r.Count >= 2).ToList();
        }
        var bands = ruled == null ? ColumnBands(multi, segs) : new List<(double Lo, double Hi)>();
        int bandCount = ruled?.Count ?? bands.Count;
        if (bandCount < 2) return null;
        var segsFinal = segs;
        static double Score((double Lo, double Hi) band, PxRect box)
        {
            double overlap = Math.Min(band.Hi, box.Right) - Math.Max(band.Lo, box.X);
            return overlap > 0 ? overlap : -Math.Abs(MidX(box) - (band.Lo + band.Hi) / 2);
        }
        int Band(int i) => ruled is { } rc ? rc.Column[i]
            : Enumerable.Range(0, bands.Count).MaxBy(b => Score(bands[b], segsFinal[i].Box));
        var byBand = Enumerable.Range(0, bandCount).Select(_ => new List<int>()).ToList();
        foreach (var row in run) foreach (int i in row) byBand[Band(i)].Add(i);
        var flowing = byBand.Select(b => IsFlowingText(b.Select(k => segsFinal[k]).ToList())).ToList();

        bool isTable = !flowing.Contains(true);
        if (!isTable)
        {
            // Prose on the left with short tags on the right (marks "[2]", prices, page numbers): each tag joins its
            // row. Anything else is side-by-side text columns, which the reading order already handles.
            int firstTag = flowing.IndexOf(false);
            if (firstTag < 0 || flowing.Skip(firstTag).Contains(true)
                || !byBand.Skip(firstTag).SelectMany(b => b).All(k => segsFinal[k].Words <= 3 && segsFinal[k].Text.Length <= 12))
                return null;
        }

        var lines = new List<string>();
        var cells = new SortedDictionary<int, List<int>>();
        var previous = new List<int>();
        void Flush()
        {
            if (cells.Count == 0) return;
            lines.Add(RowText(cells, byBand, isTable, segsFinal));
            cells = new SortedDictionary<int, List<int>>();
        }
        foreach (var row in run)
        {
            // The next line of wrapped cells: every text piece sits just under a cell of the row above. In a table
            // the row-label column rarely wraps together with others, so a row that fills it is a new row unless alone.
            var content = row.Where(k => flowing[Band(k)] || isTable).ToList();
            bool continuation = previous.Count > 0 && content.Count > 0
                && content.All(k => ContinuesCell(k, previous, segsFinal))
                && (!isTable || row.Count == 1 || !row.Any(k => Band(k) == 0));
            if (!continuation) Flush();
            foreach (int i in row)
            {
                if (!cells.TryGetValue(Band(i), out var list)) cells[Band(i)] = list = new List<int>();
                list.Add(i);
            }
            previous = row;
        }
        Flush();
        return new Grid(members, string.Join('\n', lines));
    }

    /// <summary>Columns from a table's vertical grid lines, when it has them; each cell goes to the column that starts
    /// at the nearest grid line left of it on its own row (a merged cell lands in the first column it spans). Null —
    /// use the text's own column bands — unless grid lines seen on two or more rows split the cells into two or more
    /// columns with no two cells of a row in one column.</summary>
    private static (int Count, Dictionary<int, int> Column)? RuledColumns(List<List<int>> run, List<Seg> segs)
    {
        double tolerance = RuleTolerance(run.SelectMany(r => r), segs);
        var sightings = new List<(double X, int Row)>();
        for (int r = 0; r < run.Count; r++)
            foreach (double x in run[r].SelectMany(k => segs[k].RowRules).Distinct()) sightings.Add((x, r));
        sightings = sightings.OrderBy(s => s.X).ToList();
        var groups = new List<List<(double X, int Row)>>();
        foreach (var s in sightings)
        {
            if (groups.Count > 0 && s.X - groups[^1][^1].X <= tolerance) groups[^1].Add(s);
            else groups.Add(new List<(double X, int Row)> { s });
        }
        var rules = groups.Where(g => g.Select(s => s.Row).Distinct().Count() >= 2).Select(g => g.Average(s => s.X)).ToList();
        if (rules.Count == 0) return null;
        var column = new Dictionary<int, int>();
        foreach (var row in run)
        {
            var own = Enumerable.Range(0, rules.Count)
                .Where(j => row.Any(k => segs[k].RowRules.Any(x => Math.Abs(x - rules[j]) <= tolerance))).ToList();
            var present = own.Count == 0 ? Enumerable.Range(0, rules.Count).ToList() : own;
            foreach (int i in row)
            {
                int last = present.FindLastIndex(j => rules[j] < MidX(segs[i].Box));
                column[i] = last >= 0 ? present[last] + 1 : 0;
            }
            if (row.Select(k => column[k]).Distinct().Count() != row.Count) return null;
        }
        var usedCols = column.Values.Distinct().Order().ToList();
        if (usedCols.Count < 2) return null;
        var index = usedCols.Select((c, n) => (c, n)).ToDictionary(p => p.c, p => p.n);
        return (usedCols.Count, column.ToDictionary(p => p.Key, p => index[p.Value]));
    }

    /// <summary>A gridless table's cells that the engine read as one line (`Gold Silver` under the Gold and Silver
    /// columns) are cut where the other rows' columns say: only a short line whose every word overlaps exactly one of
    /// those columns, left to right, into pieces of at most three words.</summary>
    private static (List<List<int>>, List<Seg>) SplittingAcrossBands(List<List<int>> run, List<Seg> segs)
    {
        for (int r = 0; r < run.Count; r++)
        {
            foreach (int i in run[r].ToList())
            {
                int words = segs[i].Words;
                if (words < 2 || words > MaxSplitWords || ValidWordBoxes(segs[i]) is not { } boxes) continue;
                var others = Enumerable.Range(0, run.Count)
                    .Select(x => x == r ? run[x].Where(k => k != i).ToList() : run[x]).Where(x => x.Count >= 2).ToList();
                var bands = ColumnBands(others, segs);
                var hits = boxes.Select(w => Enumerable.Range(0, bands.Count)
                    .Where(b => Math.Min(bands[b].Hi, w.Right) > Math.Max(bands[b].Lo, w.X)).ToList()).ToList();
                if (!hits.All(h => h.Count == 1)) continue;
                var columns = hits.Select(h => h[0]).ToList();
                if (!columns.Zip(columns.Skip(1)).All(p => p.First <= p.Second)) continue;
                var cuts = Enumerable.Range(1, columns.Count - 1).Where(k => columns[k] != columns[k - 1]).ToList();
                var bounds = new List<int> { 0 };
                bounds.AddRange(cuts);
                bounds.Add(columns.Count);
                if (!bounds.Zip(bounds.Skip(1)).All(p => p.Second - p.First <= 3) || Split(segs[i], cuts) is not { } pieces) continue;
                segs[i] = pieces[0];
                var ids = new List<int> { i };
                foreach (var piece in pieces.Skip(1)) { segs.Add(piece); ids.Add(segs.Count - 1); }
                run[r] = run[r].SelectMany(k => k == i ? ids : new List<int> { k }).ToList();
            }
        }
        return (run, segs);
    }

    /// <summary>One output line for a grid row. Within a cell, stacked lines (a wrapped cell) join with a space and
    /// side-by-side pieces with a tab. In a table, empty columns keep their tab so the row still lines up.</summary>
    private static string RowText(SortedDictionary<int, List<int>> cells, List<List<int>> byBand, bool table, List<Seg> segs)
    {
        string CellText(List<int> members)
        {
            var sorted = InsertionSorted(members, (a, b) => IsSameRow(segs[a].Box, segs[b].Box)
                ? segs[a].Box.X < segs[b].Box.X : segs[a].Box.Y < segs[b].Box.Y);
            string text = segs[sorted[0]].Shown;
            for (int k = 1; k < sorted.Count; k++)
                text = IsSameRow(segs[sorted[k - 1]].Box, segs[sorted[k]].Box) ? text + "\t" + segs[sorted[k]].Shown
                    : JoinWrapped(text, segs[sorted[k]].Shown);
            return text;
        }
        var filled = cells.Keys.ToList();
        if (filled.Count == 1 && cells[filled[0]].Count == 1) return CellText(cells[filled[0]]);
        if (!table) return string.Join('\t', filled.Select(k => CellText(cells[k])));
        // A row that doesn't start in the table's first column keeps its leading empty cells only if it actually
        // lines up with a column (not a button row sitting under the grid).
        int firstBand = filled[0];
        int first = cells[firstBand].MinBy(k => segs[k].Box.X);
        int start = IsAligned(first, byBand[firstBand], segs) ? 0 : firstBand;
        return string.Join('\t', Enumerable.Range(start, filled[^1] - start + 1)
            .Select(c => cells.TryGetValue(c, out var m) ? CellText(m) : ""));
    }

    /// <summary>Left-, right- or centre-aligned with another cell of its column.</summary>
    private static bool IsAligned(int i, List<int> column, List<Seg> segs)
    {
        var box = segs[i].Box;
        return column.Any(j =>
        {
            var other = segs[j].Box;
            return j != i && !IsSameRow(other, box)
                && (Math.Abs(other.X - box.X) < box.Height || Math.Abs(other.Right - box.Right) < box.Height
                    || Math.Abs(MidX(other) - MidX(box)) < box.Height);
        });
    }

    /// <summary>Column bands from the x-extents of multi-cell rows: x positions covered by more than one in five rows'
    /// cells (so a single spanning cell doesn't fuse two columns in a larger grid).</summary>
    private static List<(double Lo, double Hi)> ColumnBands(List<List<int>> rows, List<Seg> segs)
    {
        var edges = new List<(double X, int Delta)>();
        foreach (var row in rows)
            foreach (int i in row) { edges.Add((segs[i].Box.X, 1)); edges.Add((segs[i].Box.Right, -1)); }
        edges = edges.OrderBy(e => e.X).ThenBy(e => e.Delta).ToList();
        int threshold = rows.Count / 5;
        var bands = new List<(double Lo, double Hi)>();
        int depth = 0;
        double start = 0;
        foreach (var edge in edges)
        {
            int before = depth;
            depth += edge.Delta;
            if (before <= threshold && depth > threshold) start = edge.X;
            if (before > threshold && depth <= threshold) bands.Add((start, edge.X));
        }
        return bands;
    }

    /// <summary>Long lines or list items: the column is running text, not table cells.</summary>
    private static bool IsFlowingText(List<Seg> column)
    {
        if (column.Count < 2) return false;
        var words = column.Select(s => s.Words).Order().ToList();
        int markers = column.Count(s => StartsWithListMarker(s.Text));
        return words[words.Count / 2] >= 5 || markers * 2 >= column.Count;
    }

    /// <summary>Is <paramref name="i"/> the next line of a wrapped cell in the row above (same column, ordinary line
    /// spacing, not a new list item)?</summary>
    private static bool ContinuesCell(int i, List<int> above, List<Seg> segs)
    {
        var s = segs[i];
        return above.Any(q =>
        {
            var a = segs[q];
            return OverlapsHorizontally(a.Box, s.Box) && s.Box.Y > MidY(a.Box)
                && s.Box.Y - a.Box.Bottom <= 0.7 * Math.Max(a.Box.Height, s.Box.Height);
        }) && !StartsWithListMarker(s.Text);
    }

    // ------------------------------------------------------------------ flow (prose and code)

    private static List<Piece> Flow(List<Seg> run, double imageWidth)
    {
        // Split where a paragraph gap could be, classify each block, then merge neighbouring code blocks.
        var blocks = new List<List<Seg>>();
        foreach (var s in run)
        {
            if (blocks.Count > 0 && s.Box.Y - blocks[^1][^1].Box.Bottom <= MaxGapRatio * Math.Max(blocks[^1][^1].Box.Height, s.Box.Height))
                blocks[^1].Add(s);
            else
                blocks.Add(new List<Seg> { s });
        }
        var kinds = blocks.Select(IsCode).ToList();
        // A short plain block next to code in the same monospaced font (`import Foundation`, a lone `}`) is part of it.
        if (kinds.Contains(true))
        {
            var codeWidths = blocks.Where((_, k) => kinds[k]).SelectMany(b => b).Where(s => s.Text.Length >= 4)
                .Select(s => s.CharWidth).Order().ToList();
            if (codeWidths.Count > 0)
            {
                double median = codeWidths[codeWidths.Count / 2];
                for (int i = 0; i < blocks.Count; i++)
                {
                    if (!kinds[i] && ((i > 0 && kinds[i - 1]) || (i + 1 < blocks.Count && kinds[i + 1]))
                        && blocks[i].All(s => s.Words <= 8 && Ratio(s.CharWidth, median) <= 1.12))
                        kinds[i] = true;
                }
            }
        }
        var groups = new List<(bool Code, List<Seg> Lines)>();
        for (int i = 0; i < blocks.Count; i++)
        {
            if (groups.Count > 0 && groups[^1].Code == kinds[i]) groups[^1].Lines.AddRange(blocks[i]);
            else groups.Add((kinds[i], blocks[i].ToList()));
        }
        var pieces = new List<Piece>();
        foreach (var (code, lines) in groups)
        {
            if (code)
                pieces.Add(new Piece
                {
                    Kind = PieceKind.Code, Text = CodeText(lines), Order = lines[0].Order,
                    Box = lines.Skip(1).Aggregate(lines[0].Box, (b, s) => b.Union(s.Box)),
                });
            else
                pieces.AddRange(Prose(lines, imageWidth));
        }
        if (pieces.Count > 0 && pieces[0].Kind == PieceKind.Prose) pieces[0].OpensRun = true;
        if (pieces.Count > 0 && pieces[^1].Kind == PieceKind.Prose) pieces[^1].ClosesRun = true;
        return pieces;
    }

    // ---- code

    /// <summary>Signals only code carries: statement ends, closers, prompts, preprocessor lines, keyword +
    /// punctuation, JSON keys, code operators.</summary>
    private static readonly Regex StrongCodeSignals = new(string.Join("|", new[]
    {
        @"[;{}]\s*$",
        @"^\s*[}\])]",
        // `$ `, `% `, `>>> `, `user@host:~$ `, zsh's `user@host dir % `, `bash-3.2$ `, `PS C:\> `
        @"^(?:\$|%|>>>|[\w.-]+@[\w.-]+(?:[:\w~/.-]*| \S+)\s?[$%#]|[\w/.~-]+ \$|bash-[\d.]+\$|PS [^>]*>) ",
        @"^\s*(#include|#import|#!|// |/\*)",
        @"^\s*(def|class|import|from|return|if|elif|else|for|while|func|let|var|const|function|struct|enum|public|private|static|void|int|fn|pub|use|try|catch|except|switch|case|package|using|val|lambda|async|await)\b.*[(){}:;=\[\]]",
        @"^\s*""[^""]+""\s*:",
        @"(=>|===|!==|!=|&&|\|\||::)",
    }.Select(p => "(?:" + p + ")")), RegexOptions.Compiled);

    /// <summary>Signals prose, math and chemistry share now and then: they count only in a monospaced block or next to
    /// strong ones.</summary>
    private static readonly Regex WeakCodeSignals = new(string.Join("|", new[]
    {
        @"\b(?!(?:sin|cos|tan|cot|sec|csc|log|ln|lg|exp|lim|max|min|det|gcd|lcm|arc)\w*\()[A-Za-z_]\w{2,}\(",
        @"\b[A-Za-z_]\w+\.[A-Za-z_]\w+",
        @"[a-z0-9]_[a-z]",
        @"^\s*-?\s*[a-z][\w-]*:(\s|$)",
    }.Select(p => "(?:" + p + ")")), RegexOptions.Compiled);

    public static bool LooksLikeCode(string text) => StrongCodeSignals.IsMatch(text) || WeakCodeSignals.IsMatch(text);

    /// <summary>Character width constant across lines within 10% — only a monospaced font does that over short and
    /// long lines alike.</summary>
    internal static bool IsMonospace(IReadOnlyList<Seg> lines, int evidence = 3)
    {
        var widths = lines.Where(s => s.Text.Length >= 4).Select(s => s.CharWidth).ToList();
        if (widths.Count < evidence) return false;
        double lo = widths.Min(), hi = widths.Max();
        return lo > 0 && hi / lo <= 1.1;
    }

    private static bool IsCode(List<Seg> lines)
    {
        int strong = lines.Count(s => StrongCodeSignals.IsMatch(s.Raw ?? s.Text));
        int hits = lines.Count(s => LooksLikeCode(s.Raw ?? s.Text));
        if (lines.Count == 1) return strong == 1 && lines[0].Words >= 2;
        bool monospace = IsMonospace(lines);
        // A terminal session: one prompt line makes the monospaced output code too.
        return strong >= 1 && (hits * 2 >= lines.Count || monospace) || monospace && hits * 3 >= lines.Count;
    }

    /// <summary>One line per line, indentation rebuilt from each line's left edge on the character grid, blank lines
    /// from gaps of a whole line pitch or more.</summary>
    private static string CodeText(List<Seg> lines)
    {
        var widths = lines.Where(s => s.Text.Length >= 3).Select(s => s.CharWidth).Order().ToList();
        double charWidth = widths.Count == 0 ? lines[0].CharWidth : widths[widths.Count / 2];
        double left = lines.Min(s => s.Box.X);
        var pitches = lines.Zip(lines.Skip(1), (a, b) => MidY(b.Box) - MidY(a.Box)).Order().ToList();
        double pitch = pitches.Count == 0 ? 0 : pitches[pitches.Count / 2];
        var output = new List<string>();
        for (int index = 0; index < lines.Count; index++)
        {
            var line = lines[index];
            if (index > 0 && pitch > 0)
            {
                int steps = (int)Math.Round((MidY(line.Box) - MidY(lines[index - 1].Box)) / pitch, MidpointRounding.AwayFromZero);
                for (int k = 0; k < Math.Min(Math.Max(steps - 1, 0), 2); k++) output.Add("");
            }
            int indent = Math.Max(0, (int)Math.Round((line.Box.X - left) / charWidth, MidpointRounding.AwayFromZero));
            output.Add(new string(' ', indent) + CleanedCode(line.Raw ?? line.Text));
        }
        return string.Join('\n', output);
    }

    private static readonly Regex SpacedMemberAccess = new(@"(?<=[A-Za-z0-9_)\]])\. (?=[a-z_])", RegexOptions.Compiled);

    /// <summary>The engine's usual misreads in code fonts: the slashed zero as <c>ø</c>, angle brackets as guillemets,
    /// a space after a member-access dot, file extensions, look-alikes, hex ids, triple quotes, one unbalanced bracket.</summary>
    public static string CleanedCode(string line)
    {
        string text = line.Replace('ø', '0').Replace('Ø', '0').Replace('‹', '<').Replace('›', '>');
        text = SpacedMemberAccess.Replace(text, ".");
        text = WithFileExtensions(text);
        foreach (var (pattern, template) in CodeLookAlikes) text = pattern.Replace(text, template);
        text = WithHexDigits(text);
        text = WithTripleQuotes(text);
        return WithBalancedBrackets(text);
    }

    private static readonly Regex FileExtension = new(
        @"([A-Za-z0-9_]+)([-•·.])(py|js|jsx|ts|tsx|swift|txt|md|json|sh|c|h|cpp|java|rb|go|rs|html|css|log|csv|yml|yaml|toml|xml|sql)\b(?![-/])",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    /// <summary><c>main-py</c>, <c>README•md</c>, <c>data.CSV</c> → <c>main.py</c>, <c>README.md</c>, <c>data.csv</c>.</summary>
    public static string WithFileExtensions(string line)
    {
        string text = line;
        foreach (Match m in FileExtension.Matches(line).Reverse())
        {
            string name = m.Groups[1].Value, sep = m.Groups[2].Value, ext = m.Groups[3].Value;
            string lowered = ext == ext.ToUpperInvariant() && name.Any(char.IsLower) ? ext.ToLowerInvariant() : ext;
            if (sep == "." && lowered == ext) continue;
            text = text[..m.Index] + name + "." + lowered + text[(m.Index + m.Length)..];
        }
        return text;
    }

    /// <summary>Code look-alikes: <c>1s -1</c> at a command's start is <c>ls</c>, <c>itt)</c> is <c>i++)</c>,
    /// <c>$fres.status}</c> is <c>${res.status}</c>, and a string holding <c>${…}</c> in single or mismatched quotes is
    /// a template literal the engine can't see the backticks of.</summary>
    private static readonly (Regex, string)[] CodeLookAlikes =
    {
        (new Regex(@"(?<=^|[%$#|] |&& )1s(?= |$)", RegexOptions.Compiled), "ls"),
        (new Regex(@"(?<![A-Za-z])([a-z])tt(?=[);\s]|$)", RegexOptions.Compiled), "$1++"),
        (new Regex(@"\$f(?=[A-Za-z_][\w.]*\})", RegexOptions.Compiled), "$${"),
        (new Regex(@"'([^'""`]*\$\{[^'""`]*)['""]|""([^'""`]*\$\{[^'""`]*)'", RegexOptions.Compiled), "`$1$2`"),
    };

    /// <summary>A commit hash or hex id (<c>alb2c3d</c>): <c>l</c> is <c>1</c> and <c>O</c>/<c>o</c> is <c>0</c>.</summary>
    public static string WithHexDigits(string line)
    {
        var words = line.Split(' ');
        for (int i = 0; i < words.Length; i++)
        {
            string w = words[i];
            if (w.Length is >= 7 and <= 40 && w.All(c => char.IsAsciiHexDigit(c) || "lOo".Contains(c))
                && w.Count(char.IsNumber) >= 2 && w.Any(c => "lOo".Contains(c)))
                words[i] = new string(w.Select(c => c == 'l' ? '1' : "Oo".Contains(c) ? '0' : c).ToArray());
        }
        return string.Join(' ', words);
    }

    private static readonly Regex TripleQuote = new(@"['""‘’“”]{3,5}", RegexOptions.Compiled);

    /// <summary>A triple double quote read as a mix of single and double quotes: a line whose quote runs include a
    /// double quote gets three double quotes for each of them.</summary>
    public static string WithTripleQuotes(string line)
    {
        bool hasDouble = TripleQuote.Matches(line).Any(m => m.Value.Any(c => "\"“”".Contains(c)));
        return hasDouble ? TripleQuote.Replace(line, "\"\"\"") : line;
    }

    /// <summary>One look-alike swap that balances a line's brackets: <c>Lpush, pull]</c> → <c>[push, pull]</c>,
    /// <c>else i return 0 }</c> → <c>else { return 0 }</c>, <c>[3, 4, 51):</c> → <c>[3, 4, 5]):</c>. Nothing changes
    /// unless exactly one candidate is found and it balances the line.</summary>
    public static string WithBalancedBrackets(string line)
    {
        var chars = line.ToCharArray();
        var openerOf = new Dictionary<char, char> { [')'] = '(', [']'] = '[', ['}'] = '{' };
        (int Index, int? Open)? FirstProblem(char[] c)
        {
            var stack = new List<int>();
            char? quote = null;
            for (int i = 0; i < c.Length; i++)
            {
                char ch = c[i];
                if (quote is { } q) { if (ch == q) quote = null; continue; }
                if (ch is '"' or '\'' or '`') { quote = ch; continue; }
                if ("([{".Contains(ch)) { stack.Add(i); continue; }
                if (!openerOf.TryGetValue(ch, out char opener)) continue;
                if (stack.Count > 0)
                {
                    int top = stack[^1];
                    if (c[top] == opener) stack.RemoveAt(stack.Count - 1);
                    else return (i, top);
                }
                else if (c.Take(i).Any(x => !char.IsWhiteSpace(x) && !"})]".Contains(x)))
                {
                    return (i, null); // a closer mid-line with nothing open
                }
            }
            return null;
        }
        if (FirstProblem(chars) is not { } problem) return line;
        (int Index, char Bracket)? candidate = null;
        if (problem.Open is { } open)
        {
            char wanted = chars[open] == '[' ? ']' : chars[open] == '{' ? '}' : ')';
            int before = problem.Index - 1;
            if (before > open && "1lIJ|)".Contains(chars[before])) candidate = (before, wanted);
        }
        else if (openerOf.TryGetValue(chars[problem.Index], out char wanted))
        {
            for (int i = problem.Index - 1; i >= 0; i--)
            {
                bool startsToken = i == 0 || " (=:,".Contains(chars[i - 1]);
                char? next = i + 1 < chars.Length ? chars[i + 1] : null;
                if (wanted == '[' && startsToken && "LlI1".Contains(chars[i])
                    && next is { } n && (char.IsLetter(n) || char.IsNumber(n) || "\"'".Contains(n)))
                {
                    candidate = (i, '['); break;
                }
                if (wanted == '{' && startsToken && "il(".Contains(chars[i]) && next == ' ' && i + 2 < problem.Index
                    && chars[(i + 2)..problem.Index].Any(ch => char.IsLetter(ch) || char.IsNumber(ch)))
                {
                    candidate = (i, '{'); break;
                }
            }
        }
        if (candidate is not { } fix) return line;
        var fixedChars = (char[])chars.Clone();
        fixedChars[fix.Index] = fix.Bracket;
        return FirstProblem(fixedChars) == null ? new string(fixedChars) : line;
    }

    // ---- prose

    private static List<Piece> Prose(List<Seg> lines, double imageWidth)
    {
        var paragraphs = new List<List<Seg>>();
        foreach (var line in lines)
        {
            if (paragraphs.Count > 0 && Continues(paragraphs[^1], line, lines, imageWidth)) paragraphs[^1].Add(line);
            else paragraphs.Add(new List<Seg> { line });
        }
        var levels = ListLevels(paragraphs);
        double right = lines.Max(s => s.Box.Right);
        return paragraphs.Select((para, index) =>
        {
            string text = para.Skip(1).Aggregate(para[0].Shown, (acc, s) => JoinWrapped(acc, s.Shown));
            if (MathText.IsMath(text)) text = MathText.SpacedOperators(MathText.RepairedMathSymbols(text));
            return new Piece
            {
                Kind = PieceKind.Prose, Text = new string('\t', levels[index]) + text, Order = para[0].Order,
                Box = para.Skip(1).Aggregate(para[0].Box, (b, s) => b.Union(s.Box)),
                First = para[0], Last = para[^1], ColumnRight = right,
            };
        }).ToList();
    }

    private static bool Continues(List<Seg> para, Seg line, List<Seg> column, double imageWidth)
    {
        var prev = para[^1];
        double tallest = Math.Max(prev.Box.Height, line.Box.Height);
        if (line.Box.Y - prev.Box.Bottom > MaxGapRatio * tallest) return false;
        if (para.Count >= 2)
        {
            var pitches = para.Zip(para.Skip(1), (a, b) => MidY(b.Box) - MidY(a.Box)).Order().ToList();
            if (MidY(line.Box) - MidY(prev.Box) > MaxPitchRatio * pitches[pitches.Count / 2]) return false;
        }
        else if (EndsSentence(prev.Text))
        {
            // A one-line paragraph has no rhythm of its own: compare with the column's usual line pitch.
            var pitches = column.Zip(column.Skip(1), (a, b) => MidY(b.Box) - MidY(a.Box)).Where(p => p > 0).Order().ToList();
            if (pitches.Count >= 2 && MidY(line.Box) - MidY(prev.Box) > 1.12 * pitches[pitches.Count / 2]) return false;
            // Two lines alone: past double spacing (≈ 4.4 character widths) is a gap between paragraphs.
            if (pitches.Count < 2 && MidY(line.Box) - MidY(prev.Box) > 4.8 * Math.Min(prev.CharWidth, line.CharWidth)) return false;
        }
        if (IsFontChange(prev, line)) return false;
        if (StartsWithListMarker(line.Text)) return false;
        // A first-line indent starts a paragraph — unless this is a list item's hanging indent or centred text.
        double charWidth = prev.CharWidth;
        if (line.Box.X > prev.Box.X + 1.5 * charWidth && !StartsWithListMarker(para[0].Text)
            && Math.Abs(MidX(line.Box) - MidX(prev.Box)) > 1.5 * charWidth) return false;
        return Wrapped(prev, line, column, imageWidth);
    }

    /// <summary>Heading → body and similar. Character width is reliable once both lines have ten characters; below
    /// that, glyph height has to agree.</summary>
    private static bool IsFontChange(Seg a, Seg b)
    {
        double widthRatio = Ratio(a.CharWidth, b.CharWidth);
        if (a.Text.Length >= 10 && b.Text.Length >= 10 && widthRatio > 1.3) return true;
        return widthRatio > FontChangeRatio && Ratio(a.Box.Height, b.Box.Height) > FontChangeRatio;
    }

    /// <summary>Did <paramref name="prev"/> end because the next word didn't fit?</summary>
    private static bool Wrapped(Seg prev, Seg next, List<Seg> column, double imageWidth)
    {
        // Display equations stand alone; they don't wrap into each other.
        if (MathText.IsMath(prev.Shown) && MathText.IsMath(next.Shown)) return false;
        // A row of bare numbers (a matrix row, a score) isn't a sentence.
        if (!prev.Text.Any(char.IsLetter)) return false;
        double charWidth = prev.CharWidth;
        var inColumn = column.Where(s => OverlapsHorizontally(s.Box, prev.Box)).ToList();
        var widest = inColumn.MaxBy(s => s.Box.Right);
        double right = widest?.Box.Right ?? prev.Box.Right;
        bool nextUpper = next.Text.Length > 0 && char.IsUpper(next.Text[0]);
        // A column no wider than two words is a list of labels (a sidebar), not wrapped text.
        if ((widest ?? prev).Words <= 2 && nextUpper) return false;
        int firstWord = next.Text.TakeWhile(c => !char.IsWhiteSpace(c)).Count();
        double left = inColumn.Select(s => s.Box.X).DefaultIfEmpty(prev.Box.X).Min();
        // A selection padded evenly on both sides has its right margin mirror the left one: a line that reaches it
        // wrapped (into a line of the same font).
        double margin = imageWidth - left;
        bool reachesMargin = left >= 2 * charWidth && prev.Box.Right <= margin + charWidth
            && Ratio(charWidth, next.CharWidth) <= 1.1 && Ratio(prev.Box.Height, next.Box.Height) <= 1.1
            && prev.Box.Right + (firstWord + 1) * charWidth > margin - 0.5 * charWidth;
        // Before a capital, a wrap needs evidence: flowing text (four lines most of the way across) or two lines
        // reaching the column's edge — unless the line ends mid-phrase (`met with` / `Maria`).
        if (nextUpper)
        {
            int longLines = inColumn.Count(s => s.Box.Right - left >= 0.75 * (right - left));
            int atEdge = inColumn.Count(s => s.Box.Right >= right - 1.5 * s.CharWidth);
            if (longLines < 4 && atEdge < 2 && !EndsMidPhrase(prev.Text) && !reachesMargin) return false;
        }
        if (prev.Box.Right < right - charWidth)
            return prev.Box.Right + (firstWord + 1) * charWidth > right - 0.5 * charWidth;
        // `prev` is the column's longest line, so there's no edge to test against but the margin.
        if (reachesMargin) return true;
        if (next.Text.Length > 0 && char.IsLower(next.Text[0])) return true;
        return !EndsSentence(prev.Text);
    }

    /// <summary>A line that stops where a sentence can't: after a comma, a hyphen or a word that needs a following one.</summary>
    public static bool EndsMidPhrase(string text)
    {
        if (text.Length == 0) return false;
        if (",-–—".Contains(text[^1])) return true;
        string word = text.Split(' ', StringSplitOptions.RemoveEmptyEntries).LastOrDefault()?.ToLowerInvariant() ?? "";
        return MidPhraseWords.Contains(word);
    }

    private static readonly HashSet<string> MidPhraseWords = new()
    {
        "a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "at", "by", "for", "with", "from", "into",
        "as", "that", "which", "who", "is", "are", "was", "were", "be", "has", "have", "had", "not", "than",
        "its", "their", "his", "her", "our", "my", "your", "this", "these", "those", "de", "și", "la", "în", "cu", "pe",
    };

    /// <summary>Nesting level per paragraph: list items' left edges clustered into levels.</summary>
    private static List<int> ListLevels(List<List<Seg>> paragraphs)
    {
        var zeros = paragraphs.Select(_ => 0).ToList();
        var items = paragraphs.Where(p => StartsWithListMarker(p[0].Text)).Select(p => p[0]).ToList();
        if (items.Count < 2) return zeros;
        var widths = items.Select(s => s.CharWidth).Order().ToList();
        double tolerance = 1.5 * widths[widths.Count / 2];
        var stops = new List<double>();
        foreach (double x in items.Select(s => s.Box.X).Order())
            if (stops.Count == 0 || x - stops[^1] > tolerance) stops.Add(x);
        if (stops.Count < 2) return zeros;
        return paragraphs.Select(p =>
        {
            if (!StartsWithListMarker(p[0].Text)) return 0;
            int level = stops.FindLastIndex(s => s <= p[0].Box.X + tolerance);
            return Math.Max(level, 0);
        }).ToList();
    }

    /// <summary>A paragraph cut by a column break: the left column's last line runs to its edge mid-sentence and the
    /// next column starts in lower case.</summary>
    private static List<Piece> JoinedAcrossColumns(List<Piece> pieces)
    {
        var output = new List<Piece>();
        foreach (var piece in pieces)
        {
            if (output.Count > 0 && output[^1] is { Kind: PieceKind.Prose, ClosesRun: true, Last: { } last } prev
                && piece is { Kind: PieceKind.Prose, OpensRun: true, First: { } first }
                && first.Box.X > prev.ColumnRight - last.CharWidth && first.Box.Y < last.Box.Y
                && last.Text.Length >= 15 && !MathText.IsMath(last.Shown) && !MathText.IsMath(first.Shown)
                && !EndsSentence(last.Text) && first.Text.Length > 0 && char.IsLower(first.Text[0])
                && last.Box.Right + (first.Text.TakeWhile(c => !char.IsWhiteSpace(c)).Count() + 1) * last.CharWidth
                    > prev.ColumnRight - 0.5 * last.CharWidth)
            {
                prev.Text = JoinWrapped(prev.Text, piece.Text);
                prev.ClosesRun = piece.ClosesRun;
                prev.Last = piece.Last;
                prev.ColumnRight = piece.ColumnRight;
                continue;
            }
            output.Add(piece);
        }
        return output;
    }

    // ------------------------------------------------------------------ text helpers

    private static readonly Regex ListMarker = new(
        @"^(?:[•\-–—*☐☑☒]|\(?\d{1,3}[.)]|\(?[a-zA-Z][.)]|\(?(?:[ivx]{2,4}|[IVX]{2,4})[.)])\s", RegexOptions.Compiled);
    private static readonly HashSet<char> BulletLookalikes = new() { '·', '●', '◦', '▪', '‣' };

    public static bool StartsWithListMarker(string text) => ListMarker.IsMatch(text);

    private static bool EndsSentence(string text)
    {
        string trimmed = text.Trim('"', '\'', '”', '’', ')', ']', '»');
        return trimmed.Length > 0 && ".!?:;".Contains(trimmed[^1]);
    }

    /// <summary>Joins a wrapped line onto its paragraph: a word broken across lines rejoins (<c>infor-</c> +
    /// <c>mation</c>), a compound keeps its hyphen (<c>light-</c> + <c>dependent</c>: not in the word list), a spaced
    /// dash (<c>money —</c>) is not touched.</summary>
    public static string JoinWrapped(string text, string next)
    {
        if (text.EndsWith('-') && text.Length >= 2 && char.IsLetter(text[^2]) && next.Length > 0 && char.IsLower(next[0]))
        {
            string left = new string(text[..^1].Reverse().TakeWhile(char.IsLetter).Reverse().ToArray());
            string right = new string(next.TakeWhile(char.IsLetter).ToArray());
            return (WordList.Contains(left + right) == false ? text : text[..^1]) + next;
        }
        return text + " " + next;
    }

    private static string Normalize(string raw)
    {
        string text = raw.Trim();
        if (text.Length > 0 && BulletLookalikes.Contains(text[0])) text = "•" + text[1..];
        return text;
    }

    private static string[] SplitWords(string text) => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);

    /// <summary>Stable insertion sort with a strict "comes before" test (the cell comparator isn't transitive, so
    /// <see cref="List{T}.Sort()"/> could throw).</summary>
    private static List<int> InsertionSorted(List<int> items, Func<int, int, bool> before)
    {
        var sorted = new List<int>();
        foreach (int item in items)
        {
            int at = sorted.Count;
            while (at > 0 && before(item, sorted[at - 1])) at--;
            sorted.Insert(at, item);
        }
        return sorted;
    }

    // ------------------------------------------------------------------ geometry helpers

    private static double MidX(PxRect r) => r.X + r.Width / 2;
    private static double MidY(PxRect r) => r.Y + r.Height / 2;

    private static double OverlapWidth(PxRect a, PxRect b) => Math.Min(a.Right, b.Right) - Math.Max(a.X, b.X);

    private static bool OverlapsHorizontally(PxRect a, PxRect b) => OverlapWidth(a, b) > 0.5 * Math.Min(a.Width, b.Width);

    private static bool IsSameRow(PxRect a, PxRect b) =>
        Math.Min(a.Bottom, b.Bottom) - Math.Max(a.Y, b.Y) > 0.5 * Math.Min(a.Height, b.Height);

    private static bool IsAdjacent(Seg a, Seg b)
    {
        double gap = Math.Max(a.Box.X, b.Box.X) - Math.Min(a.Box.Right, b.Box.Right);
        return gap < SameRowJoinChars * Math.Max(a.CharWidth, b.CharWidth);
    }

    private static double Ratio(double a, double b) => Math.Max(a, b) / Math.Max(Math.Min(a, b), 1e-6);
}
