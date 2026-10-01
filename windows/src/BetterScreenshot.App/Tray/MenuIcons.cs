using System.IO;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Controls;
using Bitmap = System.Drawing.Bitmap;

namespace BetterScreenshot.App.Tray;

/// <summary>
/// The app's own glyphs (<see cref="IconPresenter"/>, <c>Resources/Icons.xaml</c>) rendered as small bitmaps for the
/// WinForms tray menu (review X6: an icon on every item so the titles line up). Rendered once per key at the system
/// DPI; null when the resources aren't loaded (the item then has no image, the menu still works).
/// </summary>
internal static class MenuIcons
{
    private static readonly Dictionary<string, Bitmap?> Cache = new();

    /// <summary>Square side in device pixels for a 16-DIP menu icon at the system DPI.</summary>
    public static int SidePx
    {
        get
        {
            using var g = System.Drawing.Graphics.FromHwnd(IntPtr.Zero);
            return (int)Math.Round(16 * g.DpiX / 96.0);
        }
    }

    public static Bitmap? Get(string key)
    {
        if (Cache.TryGetValue(key, out var cached)) return cached;
        Bitmap? bitmap = null;
        try
        {
            int side = SidePx;
            var icon = new IconPresenter
            {
                IconKey = key,
                Brush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0xE6, 0xE6, 0xEA)),
                Width = side,
                Height = side,
            };
            icon.Measure(new System.Windows.Size(side, side));
            icon.Arrange(new System.Windows.Rect(0, 0, side, side));
            var rtb = new RenderTargetBitmap(side, side, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
            rtb.Render(icon);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(rtb));
            using var ms = new MemoryStream();
            encoder.Save(ms);
            ms.Position = 0;
            using var decoded = new Bitmap(ms);
            bitmap = new Bitmap(decoded); // detach from the stream
        }
        catch (Exception ex) when (ex is InvalidOperationException or ArgumentException or System.Runtime.InteropServices.ExternalException)
        {
            bitmap = null;
        }
        Cache[key] = bitmap;
        return bitmap;
    }
}
