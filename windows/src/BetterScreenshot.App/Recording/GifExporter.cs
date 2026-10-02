using System.IO;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;

namespace BetterScreenshot.App.Recording;

/// <summary>Converts a recorded MP4 to a looping GIF via ffmpeg in two passes (palette, then frames — args from
/// <see cref="FfmpegArgs.BuildGifPalette"/> / <see cref="FfmpegArgs.BuildGifConversion"/>). No timeout: a long GIF
/// takes as long as it takes (review round 1 #17 — the old 5-minute limit killed long exports).</summary>
public static class GifExporter
{
    /// <summary>Returns the .gif path on success (the source MP4 is deleted), or null on failure (the MP4 is kept so
    /// nothing is lost). <paramref name="progress"/> gets 0…1 as the frames are written.</summary>
    public static async Task<string?> ConvertAsync(string mp4Path, string gifPath, Action<double>? progress = null)
    {
        string palette = Path.Combine(Path.GetTempPath(), $"bs-palette-{Guid.NewGuid():N}.png");
        try
        {
            var (paletteOk, _) = await FfmpegRunner.RunWithProgressAsync(FfmpegArgs.BuildGifPalette(mp4Path, palette), _ => { });
            if (!paletteOk || !File.Exists(palette)) return null;
            progress?.Invoke(0.2);

            double seconds = Duration(mp4Path);
            void OnLine(string line)
            {
                if (seconds > 0 && FfmpegArgs.ProgressFraction(line, seconds) is { } f) progress?.Invoke(0.2 + 0.8 * f);
            }
            var (ok, _) = await FfmpegRunner.RunWithProgressAsync(FfmpegArgs.BuildGifConversion(mp4Path, palette, gifPath), OnLine);
            if (!ok || !File.Exists(gifPath)) return null;
            try { File.Delete(mp4Path); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { /* leave the mp4 if it can't be removed */ }
            return gifPath;
        }
        finally
        {
            try { File.Delete(palette); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { /* a temp file; Windows cleans %TEMP% */ }
        }
    }

    private static double Duration(string mp4Path)
    {
        try
        {
            using var fs = File.OpenRead(mp4Path);
            return BetterScreenshot.History.MediaInfo.Mp4Duration(fs)?.TotalSeconds ?? 0;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or OverflowException)
        {
            return 0;
        }
    }
}
