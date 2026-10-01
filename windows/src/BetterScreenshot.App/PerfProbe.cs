using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Threading;
using BetterScreenshot.App.Editor;
using BetterScreenshot.App.Overlays;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App;

/// <summary>
/// <c>--perf-probe &lt;outFile&gt; [cycles]</c> (perf harness only, REVAMP §6.1): 20 cycles of the screenshot workload — capture an
/// 800×500 area, show its Quick Access card, open the editor on it and close both — entirely off-screen, then writes
/// one line with private bytes before/after (after a full GC) and the time per cycle, and exits. A leak shows up as
/// growth past the +25 MB budget. Uses a throwaway settings folder; touches no user setting, no tray, no hotkeys.
/// </summary>
internal static class PerfProbe
{
    public const int Cycles = 20;

    public static bool IsRequest(string[] args) => args.Length >= 2 && args[0] == "--perf-probe";

    public static async void Run(System.Windows.Application app, string[] args)
    {
        app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        Environment.SetEnvironmentVariable(SettingsStore.DirectoryOverrideVariable,
            Path.Combine(Path.GetTempPath(), "BetterScreenshot-perf-" + Environment.ProcessId));
        int cycles = args.Length >= 3 && int.TryParse(args[2], out var n) && n > 0 ? n : Cycles;
        string result;
        try
        {
            await Cycle(); // warm-up: JIT, fonts, resources
            long before = PrivateAfterGc();
            var sw = Stopwatch.StartNew();
            for (int i = 0; i < cycles; i++) await Cycle();
            sw.Stop();
            long after = PrivateAfterGc();
            result = string.Format(System.Globalization.CultureInfo.InvariantCulture,
                "{0} cycles (capture 800x500 -> card -> editor open/close): {1} -> {2} MB priv ({3:+0;-0} MB), {4:N0} ms/cycle",
                cycles, before / 1048576, after / 1048576, (after - before) / 1048576.0, sw.Elapsed.TotalMilliseconds / cycles);
        }
        catch (Exception ex)
        {
            result = "FAIL " + ex.GetType().Name + ": " + ex.Message;
        }
        try { File.WriteAllText(args[1], result); }
        catch (IOException) { }
        app.Shutdown(result.StartsWith("FAIL", StringComparison.Ordinal) ? 1 : 0);
    }

    private static async Task Cycle()
    {
        var image = ScreenCapture.CaptureRegion(new PxRect(0, 0, 800, 500));
        var card = new QuickAccessWindow(image, QuickAccessKind.Screenshot, new QuickAccessActions(), null);
        await ShowOffScreen(card);
        var editor = new EditorWindow(image, AnnotationStyle.Default);
        await ShowOffScreen(editor);
        editor.Close();
        card.Close();
        await Dispatcher.Yield(DispatcherPriority.ApplicationIdle);
    }

    /// <summary>Shows a window far off-screen (re-placed after its own SourceInitialized sizing, before it's visible).</summary>
    private static async Task ShowOffScreen(Window w)
    {
        w.ShowActivated = false;
        w.ShowInTaskbar = false;
        w.WindowStartupLocation = WindowStartupLocation.Manual;
        w.SourceInitialized += (_, _) => { w.Left = -30000; w.Top = -30000; };
        w.Left = -30000;
        w.Top = -30000;
        w.Show();
        for (int i = 0; i < 3; i++) await Dispatcher.Yield(DispatcherPriority.ApplicationIdle);
    }

    private static long PrivateAfterGc()
    {
        for (int i = 0; i < 3; i++)
        {
            GC.Collect(GC.MaxGeneration, GCCollectionMode.Forced, blocking: true, compacting: true);
            GC.WaitForPendingFinalizers();
        }
        using var p = Process.GetCurrentProcess();
        p.Refresh();
        return p.PrivateMemorySize64;
    }
}
