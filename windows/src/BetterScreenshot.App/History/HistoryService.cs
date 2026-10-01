using System.Diagnostics;
using System.IO;
using System.Windows.Media.Imaging;
using BetterScreenshot.History;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App.History;

/// <summary>
/// App-facing facade over <see cref="HistoryStore"/> (persistence) and <see cref="RestoreStack"/> (recently-closed
/// LIFO). Records captures, restores recently-closed cards, and exposes copy / reveal / delete / clear-all plus
/// image/thumb/saved-file getters for the History window and Quick Access flow. When history is disabled via
/// settings, record calls are no-ops (return null) so nothing is written to disk.
/// </summary>
public sealed class HistoryService
{
    private readonly HistoryStore _store;
    private readonly RestoreStack _restore = new();
    private readonly Func<int> _cap;
    private readonly Func<bool> _enabled;

    public HistoryService(string directory, Func<int> capProvider, Func<bool> enabledProvider)
    {
        _cap = capProvider;
        _enabled = enabledProvider;
        _store = new HistoryStore(directory, capProvider());
    }

    /// <summary>Default history location: <c>%APPDATA%\BetterScreenshot\History\</c>.</summary>
    public static string DefaultDirectory => Path.Combine(SettingsStore.DefaultDirectory, "History");

    /// <summary>Production factory: reads the cap + enabled flag live from settings on each use.</summary>
    public static HistoryService ForSettings(SettingsStore settings) =>
        new(DefaultDirectory, () => settings.Capture.HistoryCap, () => settings.Capture.HistoryEnabled);

    public IReadOnlyList<HistoryEntry> Entries => _store.Index.Entries;
    public bool Enabled => _enabled();

    /// <summary>Records a screenshot (history-owned PNG copy + thumbnail). Returns its id, or null if disabled/failed.</summary>
    public Guid? RecordScreenshot(BitmapSource image, DateTime? date = null)
    {
        if (!_enabled()) return null;
        return _store.AddScreenshot(ImageIo.EncodePng(image), _cap(), date)?.Id;
    }

    /// <summary>Records a recording by reference (thumbnail owned; the saved file is never copied nor deleted).</summary>
    public Guid? RecordRecording(string filePath, BitmapSource thumbnailSource, DateTime? date = null)
    {
        if (!_enabled()) return null;
        return _store.AddRecording(filePath, ImageIo.EncodePng(thumbnailSource), _cap(), date)?.Id;
    }

    /// <summary>Marks a card id as ✕-closed / evicted so it can be brought back via Restore Recently Closed.</summary>
    public void NoteClosed(Guid id) => _restore.Push(id);

    /// <summary>Pops the newest still-existing recently-closed entry (skips ones deleted since), or null.</summary>
    public HistoryEntry? PopRestorable()
    {
        var id = _restore.PopRestorable(x => _store.Entry(x) != null);
        return id is { } g ? _store.Entry(g) : null;
    }

    public HistoryEntry? Entry(Guid id) => _store.Entry(id);
    public void Delete(Guid id) => _store.Remove(id);
    public void ClearAll() => _store.ClearAll();

    public string ThumbPath(HistoryEntry e) => _store.ThumbPath(e);
    public string? ImagePath(HistoryEntry e) => _store.ImagePath(e);
    public string? SavedFilePath(HistoryEntry e) => _store.SavedFilePath(e);
    public bool SavedFileExists(HistoryEntry e) => _store.SavedFileExists(e);

    /// <summary>Loads the history-owned screenshot as a decoded bitmap (for annotate / pin / restore-card). Null for recordings or IO failure.</summary>
    public BitmapSource? LoadImage(HistoryEntry e)
    {
        var path = _store.ImagePath(e);
        if (path is null || !File.Exists(path)) return null;
        try
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.CreateOptions = BitmapCreateOptions.PreservePixelFormat;
            bmp.UriSource = new Uri(path);
            bmp.EndInit();
            bmp.Freeze();
            return bmp;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>The file on disk behind an entry — the history-owned PNG for a screenshot, the saved file for a
    /// recording — or null when it's gone. What drag-out, multi-Copy and Show in Explorer hand to the shell.</summary>
    public string? FileFor(HistoryEntry e)
    {
        var path = e.Kind == HistoryKind.Screenshot ? ImagePath(e) : SavedFilePath(e);
        return path is not null && File.Exists(path) ? path : null;
    }

    /// <summary>Copies an entry to the clipboard: screenshot → image, recording → its saved file (best-effort).</summary>
    public void CopyToClipboard(HistoryEntry e)
    {
        if (e.Kind == HistoryKind.Screenshot)
        {
            var image = LoadImage(e);
            if (image != null) ClipboardService.SetImage(image);
        }
        else if (SavedFileExists(e))
        {
            ClipboardService.SetFile(e.FilePath!);
        }
    }

    /// <summary>Copies a selection: one entry as above; several as one file-drop of their files (v3 §4.4).</summary>
    public void CopyToClipboard(IReadOnlyList<HistoryEntry> entries)
    {
        if (entries.Count == 1) { CopyToClipboard(entries[0]); return; }
        try { ClipboardService.SetFiles(entries.Select(FileFor).OfType<string>()); }
        catch (System.Runtime.InteropServices.ExternalException) { /* clipboard busy: best-effort */ }
    }

    /// <summary>Opens Explorer with the entry's underlying file selected (screenshot copy or saved recording).</summary>
    public void RevealInExplorer(HistoryEntry e)
    {
        if (FileFor(e) is not { } path) return;
        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", ExplorerSelectArgs(path)) { UseShellExecute = true });
        }
        catch
        {
            // Best-effort; never crash on a shell failure.
        }
    }

    /// <summary>Show in Explorer for a selection: one Explorer window per folder with all of that folder's files
    /// selected (<c>SHOpenFolderAndSelectItems</c>); a single entry uses the plain <c>/select</c> path.</summary>
    public void RevealInExplorer(IReadOnlyList<HistoryEntry> entries)
    {
        if (entries.Count == 1) { RevealInExplorer(entries[0]); return; }
        foreach (var group in RevealGroups(entries.Select(FileFor).OfType<string>()))
            ShellReveal.SelectInFolder(group.Key, group.ToList());
    }

    /// <summary>Groups paths by containing folder, case-insensitively, in first-seen order (pure; unit-tested).</summary>
    public static IEnumerable<IGrouping<string, string>> RevealGroups(IEnumerable<string> paths) =>
        paths.GroupBy(p => Path.GetDirectoryName(p) ?? "", StringComparer.OrdinalIgnoreCase);

    /// <summary>Builds the <c>explorer.exe /select,"path"</c> argument string (pure; unit-tested).</summary>
    public static string ExplorerSelectArgs(string path) => $"/select,\"{path}\"";
}
