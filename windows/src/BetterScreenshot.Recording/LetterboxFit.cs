using BetterScreenshot.Core;

namespace BetterScreenshot.Recording;

/// <summary>
/// Where content of one size lands when scaled to fit an output frame, aspect kept, centred with black bars
/// (Mac v3 Part 5 <c>LetterboxFit</c>). Used when Switch Window/Area re-points a recording at a target of a
/// different shape: the video keeps its first size and the new content is fitted inside it (small windows scale
/// up). The ffmpeg <c>scale=…:force_original_aspect_ratio=decrease,pad=…</c> chain in
/// <see cref="FfmpegArgs.BuildRecording"/> draws exactly this rectangle.
/// </summary>
public static class LetterboxFit
{
    /// <summary>The rectangle (output pixels, top-left origin) the content occupies; empty content → the whole output.</summary>
    public static PxRect Rect(PxSize content, PxSize output)
    {
        if (content.Width <= 0 || content.Height <= 0) return new PxRect(0, 0, output.Width, output.Height);
        double scale = Math.Min(output.Width / content.Width, output.Height / content.Height);
        double w = Math.Min(output.Width, Math.Round(content.Width * scale, MidpointRounding.AwayFromZero));
        double h = Math.Min(output.Height, Math.Round(content.Height * scale, MidpointRounding.AwayFromZero));
        return new PxRect(Math.Floor((output.Width - w) / 2), Math.Floor((output.Height - h) / 2), w, h);
    }
}
