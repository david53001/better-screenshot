using System.Windows.Media;
using Color = System.Windows.Media.Color;

namespace BetterScreenshot.App.Controls;

/// <summary>The user's Windows accent colour (Settings → Personalisation → Colours), for the native look's
/// selected states (v3 Part 9: "native controls with the system accent"). Falls back to the macOS dark-mode blue.</summary>
public static class SystemAccent
{
    private static Color? _color;

    public static Color Color
    {
        get
        {
            if (_color is { } c) return c;
            try
            {
                var ui = new Windows.UI.ViewManagement.UISettings();
                var a = ui.GetColorValue(Windows.UI.ViewManagement.UIColorType.Accent);
                _color = Color.FromArgb(255, a.R, a.G, a.B);
            }
            catch (Exception ex) when (ex is System.Runtime.InteropServices.COMException or InvalidCastException or TypeLoadException)
            {
                _color = Color.FromRgb(0x0A, 0x84, 0xFF);
            }
            return _color.Value;
        }
    }

    public static SolidColorBrush Brush
    {
        get
        {
            var b = new SolidColorBrush(Color);
            b.Freeze();
            return b;
        }
    }

    /// <summary>Forget the cached colour (the user changed it).</summary>
    public static void Invalidate() => _color = null;
}
