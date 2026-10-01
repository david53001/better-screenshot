using BetterScreenshot.Core;

namespace BetterScreenshot.Capture;

/// <summary>
/// A table's vertical grid lines, from the pixels (Mac <c>GridLines.swift</c>): a thin stripe darker (or, on a dark
/// theme, lighter) than the pixels a few columns to either side, unbroken down a row. Compared locally rather than
/// binarised — a spreadsheet's faint #e2e2e2 lines fall below any threshold tuned for text, and zebra or header
/// shading changes the background per row. Pure over a grey buffer.
/// </summary>
public sealed class GridLines
{
    /// <summary>Pixels either side a line is compared with: a 1–4 px line is narrower than twice this.</summary>
    public const int Side = 3;
    /// <summary>Grey levels a line must differ from both sides by.</summary>
    public const int Contrast = 8;
    /// <summary>Share of the rows a line must cross (anti-aliasing may nick one).</summary>
    public const double Coverage = 0.9;

    private readonly int _width, _height;
    private readonly byte[] _gray;

    /// <summary>Row-major grey levels, top row first.</summary>
    public GridLines(int width, int height, byte[] gray)
    {
        _width = width;
        _height = height;
        _gray = gray;
    }

    /// <summary>Grey levels from a top-down BGRA buffer (ITU-R 601 luma).</summary>
    public static GridLines FromBgra(byte[] bgra, int width, int height)
    {
        var gray = new byte[width * height];
        for (int i = 0, p = 0; i < gray.Length; i++, p += 4)
            gray[i] = (byte)((bgra[p] * 114 + bgra[p + 1] * 587 + bgra[p + 2] * 299) / 1000);
        return new GridLines(width, height, gray);
    }

    /// <summary>x positions (pixel centres) of the vertical lines crossing all of <paramref name="rect"/> (top-left
    /// pixel coordinates).</summary>
    public IReadOnlyList<double> Vertical(PxRect rect)
    {
        int y0 = Math.Max(0, (int)Math.Floor(rect.Y)), y1 = Math.Min(_height, (int)Math.Ceiling(rect.Bottom));
        int x0 = Math.Max(Side, (int)Math.Floor(rect.X)), x1 = Math.Min(_width - Side, (int)Math.Ceiling(rect.Right));
        if (y1 - y0 < 3 || x1 <= x0) return Array.Empty<double>();
        var hits = new int[x1 - x0];
        for (int y = y0; y < y1; y++)
        {
            int row = y * _width;
            for (int x = x0; x < x1; x++)
            {
                int c = _gray[row + x], l = _gray[row + x - Side], r = _gray[row + x + Side];
                if ((l - c >= Contrast && r - c >= Contrast) || (c - l >= Contrast && c - r >= Contrast)) hits[x - x0]++;
            }
        }
        int need = (int)Math.Ceiling(Coverage * (y1 - y0));
        var lines = new List<double>();
        int? start = null;
        for (int dx = 0; dx <= hits.Length; dx++)
        {
            if (dx < hits.Length && hits[dx] >= need)
            {
                start ??= dx;
            }
            else if (start is { } s)
            {
                lines.Add(x0 + (s + dx) / 2.0);
                start = null;
            }
        }
        return lines;
    }
}
