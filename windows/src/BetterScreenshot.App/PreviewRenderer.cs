using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using BetterScreenshot.App.Editor;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using BetterScreenshot.App.History;
using BetterScreenshot.App.Onboarding;
using BetterScreenshot.App.Overlays;
using BetterScreenshot.App.Recording;
using BetterScreenshot.App.Settings;
using BetterScreenshot.Platform;
using Application = System.Windows.Application;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using FontFamily = System.Windows.Media.FontFamily;
using Point = System.Windows.Point;

namespace BetterScreenshot.App;

/// <summary>
/// Headless screenshot mode: <c>BetterScreenshot.App.exe --ui-preview &lt;outDir&gt; [--scale 1.5]
/// [--settings-dir &lt;tmp&gt;]</c> opens every real window / HUD state OFF-SCREEN, saves each as a PNG via
/// <see cref="RenderTargetBitmap"/> (works with the screen locked) and exits. It never registers hotkeys, never
/// takes the single-instance mutex, and points settings + History at a throwaway directory (the real
/// <c>%APPDATA%</c> profile is never read or written).
/// </summary>
internal static class PreviewRenderer
{
    private static double _scale = 1.0;
    private static string _outDir = "";

    /// <summary>True when the first argument is a directory path rather than a gallery window name.</summary>
    public static bool IsRenderRequest(string[] args) =>
        args.Length >= 2 && args[0] == "--ui-preview" && (args[1].Contains('\\') || args[1].Contains('/') || args[1].Contains(':'));

    public static async void Run(Application app, string[] args)
    {
        _outDir = Path.GetFullPath(args[1]);
        Directory.CreateDirectory(_outDir);
        for (int i = 2; i < args.Length - 1; i++)
        {
            if (args[i] == "--scale" && double.TryParse(args[i + 1], System.Globalization.CultureInfo.InvariantCulture, out var s)) _scale = Math.Clamp(s, 0.5, 4);
            if (args[i] == "--settings-dir") Environment.SetEnvironmentVariable(SettingsStore.DirectoryOverrideVariable, args[i + 1]);
        }
        // Never touch the user's real profile from a preview.
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable(SettingsStore.DirectoryOverrideVariable)))
            Environment.SetEnvironmentVariable(SettingsStore.DirectoryOverrideVariable,
                Path.Combine(Path.GetTempPath(), "BetterScreenshot-preview-" + Environment.ProcessId));

        app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        var log = new List<string>();
        foreach (var (name, make) in Shots())
        {
            try { await Render(make(), Path.Combine(_outDir, name + ".png")); log.Add("ok   " + name); }
            catch (Exception ex) { log.Add($"FAIL {name}: {ex.GetType().Name} {ex.Message}"); }
        }
        File.WriteAllLines(Path.Combine(_outDir, "_preview-log.txt"), log);
        app.Shutdown(log.Any(l => l.StartsWith("FAIL")) ? 1 : 0);
    }

    private static IEnumerable<(string Name, Func<Window> Make)> Shots()
    {
        var commands = new UiPreview.PreviewCommands("settings");
        yield return ("settings", () => new SettingsWindow(new SettingsStore(), new HotkeyController(commands)));
        foreach (var (label, img) in QuickAccessSamples())
            yield return ("quickaccess-" + label, () => new QuickAccessWindow(img, QuickAccessKind.Screenshot, new QuickAccessActions(), null));
        yield return ("quickaccess-recording", () => new QuickAccessWindow(UiPreview.SampleImage(640, 360), QuickAccessKind.Recording, new QuickAccessActions(), null));
        foreach (var (label, setup) in EditorStates())
            yield return ("editor-" + label, () => { var w = new EditorWindow(EditorSample(), AnnotationStyle.Default); w.Loaded += (_, _) => setup(w); return w; });
        yield return ("welcome", () => new WelcomeWindow());
        yield return ("record-strip", () => new RecordStripWindow(new SettingsStore()));
        yield return ("countdown", () => new CountdownOverlayWindow());
        foreach (var (label, state) in PillStates())
            yield return ("pill-" + label, () =>
            {
                var w = new RecordingPillWindow(SystemParameters.WorkArea, null, excludeFromCapture: false);
                w.Apply(state);
                return w;
            });
        yield return ("toast", () => new HudWindow("Copied to clipboard"));
        yield return ("history-empty", () => new HistoryWindow(PreviewHistory(0), new HistoryWindowActions(_ => { }, _ => { })));
        yield return ("history-filled", () => new HistoryWindow(PreviewHistory(6), new HistoryWindowActions(_ => { }, _ => { })));
    }

    /// <summary>A screenshot-like sample for the editor: a light page with rows of text.</summary>
    private static BitmapSource EditorSample() => Draw(1200, 750, dc =>
    {
        dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0xF5, 0xF5, 0xF5)), null, new Rect(0, 0, 1200, 750));
        dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0x3E, 0x63, 0xDD)), null, new Rect(0, 0, 1200, 60));
        var face = new Typeface("Segoe UI");
        for (int i = 0; i < 8; i++)
        {
            dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0xDA, 0xDA, 0xDA)), null, new Rect(40, 90 + i * 76, 1000, 46));
            dc.DrawText(new FormattedText($"Row {i} — some screenshot text to annotate", System.Globalization.CultureInfo.InvariantCulture,
                System.Windows.FlowDirection.LeftToRight, face, 20, Brushes.Black, 1.0), new Point(56, 100 + i * 76));
        }
    });

    private static IEnumerable<(string, Action<EditorWindow>)> EditorStates()
    {
        var red = AnnotationStyle.Default;
        yield return ("arrow-tool", w =>
        {
            w.PreviewAdd(new ArrowAnnotation(Guid.NewGuid(), red, new PxPoint(700, 520), new PxPoint(470, 300)), false);
            w.PreviewUseTool(EditorTool.Arrow);
        });
        yield return ("select-text", w =>
        {
            w.PreviewUseTool(EditorTool.Select);
            var label = TextStylePreset.Callout.Apply(red) with { TextOutline = false };
            w.PreviewAdd(new TextAnnotation(Guid.NewGuid(), label, "Click here to continue", new PxPoint(640, 180)), true);
        });
        yield return ("text-tool", w => w.PreviewUseTool(EditorTool.Text));
        yield return ("text-editing", w =>
        {
            w.PreviewUseTool(EditorTool.Text);
            w.PreviewEditText(new TextAnnotation(Guid.NewGuid(), red, "", new PxPoint(120, 420)));
        });
        yield return ("blur-selected", w =>
        {
            w.PreviewUseTool(EditorTool.Select);
            w.PreviewAdd(new RedactionAnnotation(Guid.NewGuid(), red with { BlurRadius = 8 }, new PxRect(50, 165, 420, 46)), true);
        });
        yield return ("pixelate-tool", w =>
        {
            w.PreviewAdd(new RedactionAnnotation(Guid.NewGuid(), red with { RedactionMode = RedactionMode.Pixelate }, new PxRect(50, 241, 420, 46)), false);
            w.PreviewUseTool(EditorTool.Pixelate);
        });
        yield return ("highlighter", w =>
        {
            var pen = red.WithHighlighterPen();
            w.PreviewAdd(new HighlighterAnnotation(Guid.NewGuid(), pen, new[] { new PxPoint(56, 340), new PxPoint(470, 340) }), false);
            w.PreviewUseTool(EditorTool.Highlighter);
        });
        yield return ("spotlight-selected", w =>
        {
            w.PreviewUseTool(EditorTool.Select);
            w.PreviewAdd(new ArrowAnnotation(Guid.NewGuid(), red, new PxPoint(900, 650), new PxPoint(560, 560)), false);
            w.PreviewAdd(new SpotlightAnnotation(Guid.NewGuid(), red, new PxRect(40, 540, 520, 70)), true);
        });
        yield return ("multi-select", w =>
        {
            w.PreviewUseTool(EditorTool.Select);
            w.PreviewAdd(new RectangleAnnotation(Guid.NewGuid(), red, new PxRect(30, 80, 600, 70), false), true);
            w.PreviewAdd(new ArrowAnnotation(Guid.NewGuid(), red, new PxPoint(900, 300), new PxPoint(640, 120)), true);
        });
        yield return ("crop-tool", w => w.PreviewUseTool(EditorTool.Crop));
    }

    /// <summary>A throwaway History with <paramref name="n"/> sample screenshots (in the preview's temp profile).</summary>
    private static HistoryService PreviewHistory(int n)
    {
        var dir = Path.Combine(SettingsStore.DefaultDirectory, "History-" + n);
        if (Directory.Exists(dir)) Directory.Delete(dir, recursive: true);
        var history = new HistoryService(dir, () => 100, () => true);
        var samples = QuickAccessSamples().Select(s => s.Image).ToList();
        for (int i = 0; i < n; i++) history.RecordScreenshot(samples[i % samples.Count], DateTime.Now.AddMinutes(-7 * i));
        return history;
    }

    /// <summary>Quick Access backdrops that stress the contrast guarantee: white page, black page, a white
    /// headline across a dark band (bimodal), and a busy photo-like image.</summary>
    internal static IEnumerable<(string Label, BitmapSource Image)> QuickAccessSamples()
    {
        yield return ("white", Draw(800, 500, dc =>
        {
            dc.DrawRectangle(Brushes.White, null, new Rect(0, 0, 800, 500));
            for (int i = 0; i < 12; i++) dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0xDD, 0xDD, 0xDD)), null, new Rect(60, 40 + i * 36, 500 - i * 20, 14));
        }));
        yield return ("black", Draw(800, 500, dc =>
        {
            dc.DrawRectangle(Brushes.Black, null, new Rect(0, 0, 800, 500));
            for (int i = 0; i < 12; i++) dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0x2A, 0x2A, 0x2A)), null, new Rect(60, 40 + i * 36, 500 - i * 20, 14));
        }));
        yield return ("bimodal", Draw(800, 500, dc =>
        {
            dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0x06, 0x08, 0x14)), null, new Rect(0, 0, 800, 500));
            var text = new FormattedText("WHITE HEADLINE ACROSS THE BOTTOM", System.Globalization.CultureInfo.InvariantCulture,
                System.Windows.FlowDirection.LeftToRight, new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Black, FontStretches.Normal),
                54, Brushes.White, 1.0);
            dc.DrawText(text, new Point(20, 410));
            dc.DrawText(text, new Point(20, 440));
        }));
        yield return ("photo", Draw(800, 500, dc =>
        {
            var sky = new LinearGradientBrush(Color.FromRgb(0x87, 0xB8, 0xE8), Color.FromRgb(0xF5, 0xD7, 0x9E), 90);
            dc.DrawRectangle(sky, null, new Rect(0, 0, 800, 500));
            var rnd = new Random(7);
            for (int i = 0; i < 140; i++)
            {
                byte r = (byte)rnd.Next(256), g = (byte)rnd.Next(256), b = (byte)rnd.Next(256);
                dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(r, g, b)), null, new Point(rnd.Next(800), 250 + rnd.Next(250)), 10 + rnd.Next(40), 10 + rnd.Next(30));
            }
        }));
    }

    private static BitmapSource Draw(int w, int h, Action<DrawingContext> paint)
    {
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen()) paint(dc);
        var bmp = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(visual);
        bmp.Freeze();
        return bmp;
    }

    /// <summary>The v3 Part 5 snapshot states (expanded / muted / area-no-mic paused / countdown / confirm / collapsed / full screen).</summary>
    private static IEnumerable<(string, BetterScreenshot.Recording.PillState)> PillStates()
    {
        var live = new BetterScreenshot.Recording.PillState
        {
            Phase = BetterScreenshot.Recording.PillPhase.Recording, Elapsed = TimeSpan.FromSeconds(83),
            MicTrack = true, SystemTrack = true, Target = BetterScreenshot.Recording.PillTarget.Window,
        };
        yield return ("expanded", live);
        yield return ("muted", live with { MicMuted = true, SystemMuted = true, Camera = BetterScreenshot.Recording.PillCamera.Showing });
        yield return ("area-no-mic", live with
        {
            Phase = BetterScreenshot.Recording.PillPhase.Paused, MicTrack = false, Target = BetterScreenshot.Recording.PillTarget.Area,
            Elapsed = TimeSpan.FromSeconds(84),
        });
        yield return ("countdown", live with { Phase = BetterScreenshot.Recording.PillPhase.Countdown });
        yield return ("confirm-restart", live with { Elapsed = TimeSpan.FromSeconds(727), Confirm = BetterScreenshot.Recording.PillConfirm.Restart });
        yield return ("collapsed", live with { Elapsed = TimeSpan.FromSeconds(727), Collapsed = true });
        yield return ("fullscreen", live with { Target = BetterScreenshot.Recording.PillTarget.FullScreen });
    }

    /// <summary>Shows <paramref name="w"/> far off-screen, lets layout + Loaded handlers settle, renders its
    /// background + content to a PNG and closes it.</summary>
    internal static async Task Render(Window w, string path)
    {
        w.WindowStartupLocation = WindowStartupLocation.Manual;
        w.ShowActivated = false;
        w.ShowInTaskbar = false;
        w.Left = -30000;
        w.Top = -30000;
        w.Show();
        for (int i = 0; i < 3; i++) await Dispatcher.Yield(DispatcherPriority.ApplicationIdle);
        w.Left = -30000; // Loaded handlers may have centred it on a monitor
        w.Top = -30000;
        w.UpdateLayout();
        await Dispatcher.Yield(DispatcherPriority.ApplicationIdle);
        SavePng(w, path);
        w.Close();
    }

    internal static void SavePng(Window w, string path)
    {
        var content = (FrameworkElement)w.Content;
        double width = content.ActualWidth + content.Margin.Left + content.Margin.Right;
        double height = content.ActualHeight + content.Margin.Top + content.Margin.Bottom;
        if (width < 1 || height < 1) throw new InvalidOperationException("window content has no size");
        var bmp = new RenderTargetBitmap((int)Math.Ceiling(width * _scale), (int)Math.Ceiling(height * _scale),
            96 * _scale, 96 * _scale, PixelFormats.Pbgra32);
        // Windows draw their Background behind the content; the content visual alone doesn't include it.
        if (w.Background is Brush bg && !(bg is SolidColorBrush s && s.Color.A == 0))
        {
            var back = new DrawingVisual();
            using (var dc = back.RenderOpen()) dc.DrawRectangle(bg, null, new Rect(0, 0, width, height));
            bmp.Render(back);
        }
        bmp.Render(content);
        var enc = new PngBitmapEncoder();
        enc.Frames.Add(BitmapFrame.Create(bmp));
        using var fs = File.Create(path);
        enc.Save(fs);
    }
}
