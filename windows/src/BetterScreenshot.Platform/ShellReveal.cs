using System.Diagnostics;
using System.Runtime.InteropServices;

namespace BetterScreenshot.Platform;

/// <summary>
/// Opens one Explorer window on <c>folder</c> with several of its files selected (<c>SHOpenFolderAndSelectItems</c>),
/// which <c>explorer.exe /select</c> can't do for more than one file. Best-effort: falls back to selecting the first
/// file with <c>/select</c> if the shell call fails.
/// </summary>
public static class ShellReveal
{
    public static void SelectInFolder(string folder, IReadOnlyList<string> files)
    {
        if (files.Count == 0) return;
        IntPtr parent = IntPtr.Zero;
        var children = new List<IntPtr>();
        try
        {
            parent = ILCreateFromPathW(folder);
            foreach (var f in files)
            {
                var pidl = ILCreateFromPathW(f);
                if (pidl != IntPtr.Zero) children.Add(pidl);
            }
            if (parent == IntPtr.Zero || children.Count == 0
                || SHOpenFolderAndSelectItems(parent, (uint)children.Count, children.ToArray(), 0) != 0)
                Fallback(files[0]);
        }
        catch (Exception ex) when (ex is COMException or DllNotFoundException or EntryPointNotFoundException)
        {
            Fallback(files[0]);
        }
        finally
        {
            foreach (var c in children) ILFree(c);
            if (parent != IntPtr.Zero) ILFree(parent);
        }
    }

    private static void Fallback(string file)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{file}\"") { UseShellExecute = true }); }
        catch { /* best-effort */ }
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr ILCreateFromPathW(string path);

    [DllImport("shell32.dll")]
    private static extern void ILFree(IntPtr pidl);

    [DllImport("shell32.dll")]
    private static extern int SHOpenFolderAndSelectItems(IntPtr pidlFolder, uint cidl, IntPtr[] apidl, uint flags);
}
