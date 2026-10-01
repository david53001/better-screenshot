using BetterScreenshot.Core;

namespace BetterScreenshot.Editor;

/// <summary>
/// Buffer-based redaction (v3 Part 3): a pixelated or blurred patch for a region of a base image, at a given
/// strength. Headless (<see cref="ArgbImage"/>) so it is unit-testable; the renderer calls it for a redaction's
/// CURRENT frame and caches the result. Returns null if the region is smaller than 2×2.
/// </summary>
public static class Redactor
{
    /// <summary>Mosaic of <paramref name="blockSize"/>-px squares, each its average colour, using only the
    /// region's own pixels; the grid is centred on the region's centre (partial blocks at the edges).</summary>
    public static ArgbImage? Pixelate(ArgbImage source, PxRect region, int blockSize = 12)
    {
        if (TryRegion(region, source) is not (var x0, var y0, var w, var h)) return null;
        int b = Math.Max(1, blockSize);
        var patch = source.Crop(x0, y0, w, h);
        int startX = GridStart(w, b), startY = GridStart(h, b);

        for (int by = startY; by < h; by += b)
        {
            int ya = Math.Max(0, by), yb = Math.Min(h, by + b);
            for (int bx = startX; bx < w; bx += b)
            {
                int xa = Math.Max(0, bx), xb = Math.Min(w, bx + b);
                long sr = 0, sg = 0, sb = 0, sa = 0;
                int count = (xb - xa) * (yb - ya);
                if (count <= 0) continue;
                for (int y = ya; y < yb; y++)
                    for (int x = xa; x < xb; x++)
                    {
                        var (pr, pg, pb, pa) = patch.Get(x, y);
                        sr += pr; sg += pg; sb += pb; sa += pa;
                    }
                byte ar = (byte)(sr / count), ag = (byte)(sg / count), ab = (byte)(sb / count), aa = (byte)(sa / count);
                for (int y = ya; y < yb; y++)
                    for (int x = xa; x < xb; x++)
                        patch.Set(x, y, ar, ag, ab, aa);
            }
        }
        return patch;
    }

    /// <summary>First block's left edge so the block grid is centred on the region's centre (≤ 0).</summary>
    internal static int GridStart(int length, int block)
    {
        double centre = length / 2.0;
        // A block boundary sits centre ± block/2 (the centre block straddles the centre).
        double first = centre - block / 2.0;
        first -= Math.Ceiling(first / block) * block;
        return (int)Math.Floor(first);
    }

    /// <summary>Gaussian-like blur with σ = <paramref name="radius"/> (three running-sum box passes per axis),
    /// reading up to ceil(3 × radius) px of the REAL image around the region (clamped at the image edges only),
    /// then keeping only the region.</summary>
    public static ArgbImage? Blur(ArgbImage source, PxRect region, int radius = 12)
    {
        if (TryRegion(region, source) is not (var x0, var y0, var w, var h)) return null;
        int margin = (int)Math.Ceiling(3.0 * Math.Max(1, radius));
        int ex0 = Math.Max(0, x0 - margin), ey0 = Math.Max(0, y0 - margin);
        int ex1 = Math.Min(source.Width, x0 + w + margin), ey1 = Math.Min(source.Height, y0 + h + margin);
        int ew = ex1 - ex0, eh = ey1 - ey0;
        var work = source.Crop(ex0, ey0, ew, eh).Pixels;
        var tmp = new byte[work.Length];

        int boxR = BoxRadius(radius);
        for (int pass = 0; pass < 3; pass++)
        {
            BoxPass(work, tmp, ew, eh, boxR, horizontal: true);
            BoxPass(tmp, work, ew, eh, boxR, horizontal: false);
        }
        var expanded = new ArgbImage(ew, eh, work);
        return expanded.Crop(x0 - ex0, y0 - ey0, w, h);
    }

    /// <summary>Box radius whose three passes approximate a Gaussian of σ = <paramref name="sigma"/>.</summary>
    internal static int BoxRadius(double sigma) =>
        Math.Max(1, (int)Math.Round((Math.Sqrt(12 * sigma * sigma / 3 + 1) - 1) / 2, MidpointRounding.AwayFromZero));

    private static (int X, int Y, int W, int H)? TryRegion(PxRect region, ArgbImage source)
    {
        int x = Math.Clamp((int)Math.Floor(region.X), 0, source.Width);
        int y = Math.Clamp((int)Math.Floor(region.Y), 0, source.Height);
        int w = Math.Min((int)Math.Ceiling(region.Right) - x, source.Width - x);
        int h = Math.Min((int)Math.Ceiling(region.Bottom) - y, source.Height - y);
        if (w < 2 || h < 2) return null;
        return (x, y, w, h);
    }

    /// <summary>One running-sum box pass (O(1) per pixel), edge-clamped.</summary>
    private static void BoxPass(byte[] src, byte[] dst, int w, int h, int r, bool horizontal)
    {
        int lines = horizontal ? h : w, len = horizontal ? w : h;
        int span = 2 * r + 1;
        for (int line = 0; line < lines; line++)
        {
            int Index(int i) => horizontal ? (line * w + Math.Clamp(i, 0, len - 1)) * 4 : (Math.Clamp(i, 0, len - 1) * w + line) * 4;
            long s0 = 0, s1 = 0, s2 = 0, s3 = 0;
            for (int k = -r; k <= r; k++)
            {
                int j = Index(k);
                s0 += src[j]; s1 += src[j + 1]; s2 += src[j + 2]; s3 += src[j + 3];
            }
            for (int i = 0; i < len; i++)
            {
                int o = horizontal ? (line * w + i) * 4 : (i * w + line) * 4;
                dst[o] = (byte)(s0 / span); dst[o + 1] = (byte)(s1 / span); dst[o + 2] = (byte)(s2 / span); dst[o + 3] = (byte)(s3 / span);
                int add = Index(i + r + 1), rem = Index(i - r);
                s0 += src[add] - src[rem]; s1 += src[add + 1] - src[rem + 1];
                s2 += src[add + 2] - src[rem + 2]; s3 += src[add + 3] - src[rem + 3];
            }
        }
    }
}
