using System.IO;

namespace BetterScreenshot.Platform;

/// <summary>
/// A small append-only error log (<c>error.log</c> beside settings.json) for failures the app survives — the global
/// exception handlers and best-effort saves write here instead of swallowing silently. Kept under 1 MB (rolled to
/// <c>error.log.1</c>). Never throws.
/// </summary>
public static class ErrorLog
{
    private const long MaxBytes = 1024 * 1024;
    private static readonly object Gate = new();

    public static string FilePath => Path.Combine(SettingsStore.DefaultDirectory, "error.log");

    public static void Write(string context, Exception? ex = null)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(SettingsStore.DefaultDirectory);
                var info = new FileInfo(FilePath);
                if (info.Exists && info.Length > MaxBytes) File.Move(FilePath, FilePath + ".1", overwrite: true);
                File.AppendAllText(FilePath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}  {context}{(ex is null ? "" : Environment.NewLine + ex)}{Environment.NewLine}");
            }
        }
        catch (Exception)
        {
            // The log is the last resort; nothing further to report to.
        }
    }
}
