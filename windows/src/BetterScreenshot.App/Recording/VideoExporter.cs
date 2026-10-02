using System.IO;
using System.Windows.Media.Imaging;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// Runs the video editor's exports with ffmpeg (v3 A.3 + Part 6): a plain start/end trim at 1× is a lossless stream
/// copy; anything else is re-encoded (h264_nvenc when it works, else libx264). The original is never touched
/// unless an export fully succeeds: copies go to a new name, Replace Original renders to a temp file in the same
/// folder and then swaps it in.
/// </summary>
public static class VideoExporter
{
    public static async Task<MediaInfo?> ProbeAsync(string path)
    {
        if (!File.Exists(path)) return null;
        var (_, stderr) = await FfmpegRunner.RunAsync(new[] { "-hide_banner", "-i", path }, 15000);
        return MediaInfo.Parse(stderr) is { HasVideo: true, Duration: > 0 } info ? info : null;
    }

    /// <summary>Renders the edit to <paramref name="output"/>. Progress: null = indeterminate (passthrough), else 0…1.</summary>
    public static async Task<bool> RenderAsync(string source, CutList cuts, MediaInfo info, bool muteAll, string output,
        Action<double?> progress)
    {
        if (cuts.Passthrough is { } p)
        {
            progress(null);
            var (ok, _) = await FfmpegRunner.RunWithProgressAsync(
                FfmpegArgs.BuildPassthroughTrim(source, p.Start, p.End, muteAll || p.Muted, output), _ => { });
            return ok && File.Exists(output);
        }

        double outSeconds = cuts.KeptDuration;
        void OnLine(string line) { if (FfmpegArgs.ProgressFraction(line, outSeconds) is { } f) progress(f); }
        bool nvenc = await FfmpegRunner.HasNvencAsync();
        var (done, _) = await FfmpegRunner.RunWithProgressAsync(
            FfmpegArgs.BuildCutExport(source, cuts, info.AudioTracks, muteAll, info.Fps, nvenc, output), OnLine);
        if (!done && nvenc)
            (done, _) = await FfmpegRunner.RunWithProgressAsync(
                FfmpegArgs.BuildCutExport(source, cuts, info.AudioTracks, muteAll, info.Fps, nvenc: false, output), OnLine);
        return done && File.Exists(output);
    }

    /// <summary>Save as Copy → "&lt;stem&gt; (trimmed).mp4" next to the original (" 2", " 3"… on collision); null on failure.</summary>
    public static async Task<string?> SaveCopyAsync(string source, CutList cuts, MediaInfo info, bool muteAll, Action<double?> progress)
    {
        string target = TrimmedFileName.Unique(source, File.Exists);
        if (await RenderAsync(source, cuts, info, muteAll, target, progress)) return target;
        TryDelete(target);
        return null;
    }

    /// <summary>Export as GIF → "&lt;stem&gt; (edited).gif": render the edit without sound to a temp MP4 (first half of
    /// the progress), then the GIF converter (10 fps, ≤ 960 px, loops); null on failure, no temp file left.</summary>
    public static async Task<string?> ExportGifAsync(string source, CutList cuts, MediaInfo info, Action<double?> progress)
    {
        string temp = Path.Combine(Path.GetTempPath(), $"bs-gif-{Guid.NewGuid():N}.mp4");
        string target = TrimmedFileName.Unique(source, File.Exists, "edited", "gif");
        try
        {
            if (!await RenderAsync(source, cuts, info, muteAll: true, temp, f => progress(f is { } v ? v / 2 : 0.25))) return null;
            progress(0.5);
            var gif = await GifExporter.ConvertAsync(temp, target, f => progress(0.5 + f / 2));
            progress(1);
            return gif;
        }
        finally
        {
            TryDelete(temp);
        }
    }

    /// <summary>Replace Original: render to a temp file in the same folder, check it's a playable video, then swap it
    /// in atomically. The original's bytes are unchanged on any failure.</summary>
    public static async Task<bool> ReplaceAsync(string source, CutList cuts, MediaInfo info, bool muteAll, Action<double?> progress)
    {
        string dir = Path.GetDirectoryName(source) ?? Path.GetTempPath();
        string temp = Path.Combine(dir, $".{Path.GetFileNameWithoutExtension(source)}.bs-edit-{Guid.NewGuid():N}.mp4");
        try
        {
            if (!await RenderAsync(source, cuts, info, muteAll, temp, progress)) return false;
            if (await ProbeAsync(temp) is null) return false;
            File.Move(temp, source, overwrite: true); // MoveFileEx(MOVEFILE_REPLACE_EXISTING) on the same volume
            return true;
        }
        catch
        {
            return false;
        }
        finally
        {
            TryDelete(temp);
        }
    }

    /// <summary>The file's first frame (≤ 640 px wide) for a restored Quick Access card; null if it can't be read.</summary>
    public static async Task<BitmapSource?> FirstFrameAsync(string path)
    {
        string png = Path.Combine(Path.GetTempPath(), $"bs-frame-{Guid.NewGuid():N}.png");
        try
        {
            var (ok, _) = await FfmpegRunner.RunAsync(new[] { "-v", "error", "-i", path, "-frames:v", "1", "-vf", "scale='min(640,iw)':-2", "-y", png }, 20000);
            if (!ok || !File.Exists(png)) return null;
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.UriSource = new Uri(png);
            bmp.EndInit();
            bmp.Freeze();
            return bmp;
        }
        catch
        {
            return null;
        }
        finally
        {
            TryDelete(png);
        }
    }

    /// <summary>Extracts <paramref name="count"/> filmstrip thumbnails (100 px tall) into a temp folder; returns the files in time order.</summary>
    public static async Task<IReadOnlyList<string>> FilmstripAsync(string path, double duration, int count, string folder)
    {
        Directory.CreateDirectory(folder);
        var (ok, _) = await FfmpegRunner.RunAsync(FfmpegArgs.BuildFilmstrip(path, duration, count, Path.Combine(folder, "f%04d.jpg")), 180000);
        return ok ? Directory.GetFiles(folder, "f*.jpg").OrderBy(f => f, StringComparer.Ordinal).ToList() : Array.Empty<string>();
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { /* best-effort */ }
    }
}
