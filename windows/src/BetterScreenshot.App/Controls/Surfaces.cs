using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using BetterScreenshot.Core;
using Application = System.Windows.Application;
using Color = System.Windows.Media.Color;

namespace BetterScreenshot.App.Controls;

/// <summary>
/// The native look (v3 Part 9) + the live Opacity setting (§4.9). One app-wide value; every surface reads its brush
/// through a DynamicResource, so moving the Settings slider updates open windows and a running recording's pill at
/// once:
/// <list type="bullet">
/// <item><c>Hud.SurfaceBrush</c> — floating HUDs (pill, hint, strip, toast, countdown, keystrokes, chips): always dark.</item>
/// <item><c>Panel.SurfaceBrush</c> — docked panels on the editor's dark backdrop (tool pill, inspector, video card).</item>
/// <item><c>Window.LayerBrush</c> — the background colour layer over the Mica material of Settings / History / editors.</item>
/// <item><c>Card.FillBrush</c> — Settings cards (the text colour at 3–5 %).</item>
/// </list>
/// Main windows get Mica (DWMSBT_MAINWINDOW) when Windows supports it; otherwise their layer is solid.
/// </summary>
public static class Surfaces
{
    private const int DwmwaUseImmersiveDarkMode = 20;
    private const int DwmwaSystemBackdropType = 38;
    private const int DwmsbtMainWindow = 2;

    private static double _value = UiOpacity.Default;
    private static bool? _micaSupported;

    public static double Value => _value;

    /// <summary>Sets the app-wide opacity (0 = Transparent … 1 = Opaque) and refreshes every surface brush.</summary>
    public static void Set(double value)
    {
        _value = double.IsFinite(value) ? Math.Clamp(value, 0, 1) : UiOpacity.Default;
        var res = Application.Current?.Resources;
        if (res is null) return;
        var hud = UiOpacity.HudIsSolid(_value)
            ? Color.FromRgb(UiOpacity.SolidColor.R, UiOpacity.SolidColor.G, UiOpacity.SolidColor.B)
            : Color.FromArgb(A(UiOpacity.HudAlpha(_value)), UiOpacity.HudColor.R, UiOpacity.HudColor.G, UiOpacity.HudColor.B);
        res["Hud.SurfaceBrush"] = Frozen(hud);
        res["Panel.SurfaceBrush"] = Frozen(UiOpacity.HudIsSolid(_value)
            ? Color.FromRgb(0x2A, 0x2A, 0x2D)
            : Color.FromArgb(A(UiOpacity.PanelAlpha(_value)), 0x2A, 0x2A, 0x2D));
        double layer = MicaSupported ? UiOpacity.WindowLayerAlpha(_value) : 1;
        res["Window.LayerBrush"] = Frozen(Color.FromArgb(A(layer), 0x1C, 0x1C, 0x1E));
        res["Editor.LayerBrush"] = Frozen(Color.FromArgb(A(layer), 0x1C, 0x1C, 0x1E));
        res["Card.FillBrush"] = Frozen(Color.FromArgb(A(UiOpacity.CardFillAlpha(_value)), 0xFF, 0xFF, 0xFF));
        SystemTheme.Refresh(); // light-mode windows carry their own layer + card brushes
    }

    /// <summary>
    /// A system-theme follower's surfaces (<see cref="SystemTheme"/>): in light mode its own resources shadow the app's
    /// dark <c>Window.LayerBrush</c> / <c>Card.FillBrush</c> with the light layer (#F3F3F3 at the same alpha) and the
    /// text colour (black) at the card alpha; the title bar follows. Dark removes the shadows.
    /// </summary>
    internal static void ApplyMode(Window window, bool light)
    {
        var res = window.Resources;
        if (light)
        {
            double layer = MicaSupported ? UiOpacity.WindowLayerAlpha(_value) : 1;
            res["Window.LayerBrush"] = Frozen(Color.FromArgb(A(layer), 0xF3, 0xF3, 0xF3));
            res["Card.FillBrush"] = Frozen(Color.FromArgb(A(UiOpacity.CardFillAlpha(_value)), 0x00, 0x00, 0x00));
        }
        else
        {
            res.Remove("Window.LayerBrush");
            res.Remove("Card.FillBrush");
        }
        void Title()
        {
            var hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero) return;
            int dark = light ? 0 : 1;
            try { _ = DwmSetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, ref dark, sizeof(int)); }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }
        }
        if (new WindowInteropHelper(window).Handle != IntPtr.Zero) Title();
        else window.SourceInitialized += (_, _) => Title();
    }

    /// <summary>Windows 11 22H2+ (build 22621) can put a system backdrop behind a window.</summary>
    public static bool MicaSupported => _micaSupported ??= Environment.OSVersion.Version.Build >= 22621;

    /// <summary>
    /// Dark title bar + Mica behind the client area: the WPF surface is cleared to transparent and the frame extended
    /// into the client so the material shows through the window's <c>Window.LayerBrush</c> background. A no-op
    /// (solid layer) where unsupported. Call before the window is shown.
    /// </summary>
    public static void UseMica(Window window)
    {
        window.SetResourceReference(Window.BackgroundProperty, "Window.LayerBrush");
        if (!MicaSupported)
        {
            WindowThemer.ApplyDark(window);
            return;
        }
        void Apply()
        {
            var hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero) return;
            try
            {
                if (HwndSource.FromHwnd(hwnd) is { CompositionTarget: { } target }) target.BackgroundColor = Colors.Transparent;
                int dark = 1, backdrop = DwmsbtMainWindow;
                _ = DwmSetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, ref dark, sizeof(int));
                var margins = new Margins { Left = -1, Right = -1, Top = -1, Bottom = -1 };
                _ = DwmExtendFrameIntoClientArea(hwnd, ref margins);
                _ = DwmSetWindowAttribute(hwnd, DwmwaSystemBackdropType, ref backdrop, sizeof(int));
            }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }
        }
        if (new WindowInteropHelper(window).Handle != IntPtr.Zero) Apply();
        else window.SourceInitialized += (_, _) => Apply();
    }

    private static byte A(double alpha) => (byte)Math.Round(Math.Clamp(alpha, 0, 1) * 255);

    private static SolidColorBrush Frozen(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Margins { public int Left, Right, Top, Bottom; }

    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref Margins margins);
}
