using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Overlays;
using BetterScreenshot.Editor;
using BetterScreenshot.Platform;
using Brushes = System.Windows.Media.Brushes;
using Canvas = System.Windows.Controls.Canvas;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using Image = System.Windows.Controls.Image;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Point = System.Windows.Point;
using TextBlock = System.Windows.Controls.TextBlock;

namespace BetterScreenshot.App.Editor;

/// <summary>
/// Screen colour picker (v3 §1.8 — Windows has no system sampler): every monitor is frozen into a still and shown
/// full-screen with a magnifier loupe by the cursor; a click takes that pixel's colour, Esc cancels.
/// </summary>
public static class Eyedropper
{
    public static void Pick(Action<RGBAColor?> done)
    {
        var frozen = FrozenScreen.Capture();
        var windows = new List<Window>();
        bool finished = false;
        void Finish(RGBAColor? c)
        {
            if (finished) return;
            finished = true;
            foreach (var w in windows) w.Close();
            done(c);
        }
        foreach (var m in Screens.All())
        {
            if (frozen.For(m) is not { } still) continue;
            var w = new LoupeWindow(m, still, Finish);
            windows.Add(w);
            w.Show();
        }
        if (windows.Count == 0) { done(null); return; }
        var cursor = OverlayHelpers.MonitorUnderCursor();
        (windows.OfType<LoupeWindow>().FirstOrDefault(w => w.Monitor.DeviceName == cursor.DeviceName) ?? windows[0]).Activate();
    }

    private sealed class LoupeWindow : Window
    {
        private const int Cells = 11, Zoom = 10;
        public MonitorInfo Monitor { get; }
        private readonly BitmapSource _still;
        private readonly Action<RGBAColor?> _finish;
        private readonly Border _loupe;
        private readonly Image _zoomed = new() { Width = Cells * Zoom, Height = Cells * Zoom, Stretch = Stretch.Fill };
        private readonly TextBlock _hex = new() { Foreground = Brushes.White, FontSize = 11, HorizontalAlignment = System.Windows.HorizontalAlignment.Center, Margin = new Thickness(0, 4, 0, 0) };
        private readonly Canvas _canvas = new();

        public LoupeWindow(MonitorInfo monitor, BitmapSource still, Action<RGBAColor?> finish)
        {
            Monitor = monitor;
            _still = still;
            _finish = finish;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            Topmost = true;
            Cursor = Cursors.Cross;
            Background = Brushes.Black;
            RenderOptions.SetBitmapScalingMode(_zoomed, BitmapScalingMode.NearestNeighbor);

            var root = new Grid();
            root.Children.Add(new Image
            {
                Source = still, Width = still.PixelWidth / monitor.DpiScale, Height = still.PixelHeight / monitor.DpiScale,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top, Stretch = Stretch.Fill,
            });
            var frame = new Grid();
            frame.Children.Add(_zoomed);
            frame.Children.Add(new Border
            {
                Width = Zoom + 2, Height = Zoom + 2, BorderBrush = Brushes.White, BorderThickness = new Thickness(1),
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            });
            var stack = new StackPanel();
            stack.Children.Add(new Border { Child = frame, CornerRadius = new CornerRadius(6), ClipToBounds = true });
            stack.Children.Add(_hex);
            _loupe = new Border
            {
                Child = stack, Padding = new Thickness(6), CornerRadius = new CornerRadius(10),
                Background = new SolidColorBrush(Color.FromArgb(0xE6, 0x1C, 0x1C, 0x1E)), BorderBrush = new SolidColorBrush(Color.FromArgb(0x33, 255, 255, 255)),
                BorderThickness = new Thickness(1), IsHitTestVisible = false,
            };
            _canvas.Children.Add(_loupe);
            root.Children.Add(_canvas);
            Content = root;

            SourceInitialized += (_, _) =>
            {
                var b = monitor.Bounds;
                MoveWindow(new WindowInteropHelper(this).Handle, (int)b.X, (int)b.Y, (int)b.Width, (int)b.Height, true);
            };
            MouseMove += OnMove;
            MouseLeftButtonDown += (_, e) => _finish(Sample(e.GetPosition(this)));
            MouseRightButtonDown += (_, _) => _finish(null);
            KeyDown += (_, e) => { if (e.Key == Key.Escape) _finish(null); };
        }

        private (int X, int Y) Pixel(Point p) =>
            (Math.Clamp((int)(p.X * Monitor.DpiScale), 0, _still.PixelWidth - 1), Math.Clamp((int)(p.Y * Monitor.DpiScale), 0, _still.PixelHeight - 1));

        private RGBAColor Sample(Point p)
        {
            var (x, y) = Pixel(p);
            var px = new byte[4];
            new FormatConvertedBitmap(new CroppedBitmap(_still, new Int32Rect(x, y, 1, 1)), PixelFormats.Bgra32, null, 0).CopyPixels(px, 4, 0);
            return RGBAColor.FromBytes(px[2], px[1], px[0]);
        }

        private void OnMove(object sender, MouseEventArgs e)
        {
            var p = e.GetPosition(this);
            var (x, y) = Pixel(p);
            int half = Cells / 2;
            int x0 = Math.Clamp(x - half, 0, Math.Max(0, _still.PixelWidth - Cells)), y0 = Math.Clamp(y - half, 0, Math.Max(0, _still.PixelHeight - Cells));
            int w = Math.Min(Cells, _still.PixelWidth), h = Math.Min(Cells, _still.PixelHeight);
            _zoomed.Source = new CroppedBitmap(_still, new Int32Rect(x0, y0, w, h));
            var c = Sample(p);
            _hex.Text = $"#{(int)Math.Round(c.R * 255):X2}{(int)Math.Round(c.G * 255):X2}{(int)Math.Round(c.B * 255):X2}";
            double lx = p.X + 24, ly = p.Y + 24;
            if (lx + 140 > ActualWidth) lx = p.X - 24 - 124;
            if (ly + 150 > ActualHeight) ly = p.Y - 24 - 140;
            Canvas.SetLeft(_loupe, lx);
            Canvas.SetTop(_loupe, ly);
        }

        [DllImport("user32.dll")]
        private static extern bool MoveWindow(IntPtr hWnd, int x, int y, int w, int h, bool repaint);
    }
}
