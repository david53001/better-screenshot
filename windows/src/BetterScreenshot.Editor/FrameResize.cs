using BetterScreenshot.Core;

namespace BetterScreenshot.Editor;

/// <summary>The 8 square resize handles of a box-shaped object (indices 0 TL, 1 TM, 2 TR, 3 ML, 4 MR, 5 BL, 6 BM,
/// 7 BR) and the frame a handle drag produces. Pure.</summary>
public static class FrameResize
{
    public static PxPoint HandleCenter(PxRect f, int handle) => handle switch
    {
        0 => new(f.X, f.Y), 1 => new(f.X + f.Width / 2, f.Y), 2 => new(f.Right, f.Y),
        3 => new(f.X, f.Y + f.Height / 2), 4 => new(f.Right, f.Y + f.Height / 2),
        5 => new(f.X, f.Bottom), 6 => new(f.X + f.Width / 2, f.Bottom), _ => new(f.Right, f.Bottom),
    };

    /// <summary>The frame after dragging <paramref name="handle"/> of <paramref name="original"/> by (dx, dy):
    /// the handle's edges move, the opposite ones stay; dragging past the opposite edge flips; never below 1 px.</summary>
    public static PxRect Resize(PxRect original, int handle, double dx, double dy)
    {
        double l = original.X, t = original.Y, r = original.Right, b = original.Bottom;
        if (handle is 0 or 3 or 5) l += dx;
        if (handle is 2 or 4 or 7) r += dx;
        if (handle is 0 or 1 or 2) t += dy;
        if (handle is 5 or 6 or 7) b += dy;
        double x0 = Math.Min(l, r), x1 = Math.Max(l, r), y0 = Math.Min(t, b), y1 = Math.Max(t, b);
        return new PxRect(x0, y0, Math.Max(1, x1 - x0), Math.Max(1, y1 - y0));
    }

    /// <summary>Translates (never shrinks) <paramref name="r"/> to stay inside [0,w]×[0,h]; pinned to 0 when larger.</summary>
    public static (double Dx, double Dy) ClampDelta(IEnumerable<PxRect> boxes, double dx, double dy, PxSize image)
    {
        double minDx = double.NegativeInfinity, maxDx = double.PositiveInfinity, minDy = double.NegativeInfinity, maxDy = double.PositiveInfinity;
        foreach (var b in boxes)
        {
            minDx = Math.Max(minDx, -b.X); maxDx = Math.Min(maxDx, Math.Max(-b.X, image.Width - b.Right));
            minDy = Math.Max(minDy, -b.Y); maxDy = Math.Min(maxDy, Math.Max(-b.Y, image.Height - b.Bottom));
        }
        if (double.IsNegativeInfinity(minDx)) return (dx, dy);
        return (Math.Clamp(dx, Math.Min(minDx, maxDx), Math.Max(minDx, maxDx)), Math.Clamp(dy, Math.Min(minDy, maxDy), Math.Max(minDy, maxDy)));
    }
}
