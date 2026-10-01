using System.Linq;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;
using Windows.Graphics.Imaging;
using Windows.Media.Capture;
using Windows.Media.Capture.Frames;
using Windows.Media.MediaProperties;
using Point = System.Windows.Point;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// A circular live-camera preview shown while recording (mac <c>CameraBubbleController</c>): Ø160/240, black backing,
/// bottom-right of the recorded region + 24px, draggable, aspect-fill. Frames come from a <see cref="MediaCapture"/>
/// <see cref="MediaFrameReader"/> (BGRA8) blitted into a <see cref="WriteableBitmap"/>. Captured because it is an
/// on-screen window. Degrades silently if there is no camera or access is denied — the bubble simply never shows.
/// </summary>
public partial class CameraBubbleWindow : Window
{
    private const double EdgeMargin = 24;

    private MediaCapture? _capture;
    private MediaFrameReader? _reader;
    private WriteableBitmap? _bitmap;

    /// <summary>The camera to open (WinRT VideoCapture id); null = the first colour camera.</summary>
    public string? DeviceId { get; init; }

    public CameraBubbleWindow(double diameter, PxRect region)
    {
        InitializeComponent();
        Width = diameter;
        Height = diameter;
        Preview.Clip = new EllipseGeometry(new Point(diameter / 2, diameter / 2), diameter / 2, diameter / 2);
        PositionBottomRight(diameter, region);
        MouseLeftButtonDown += (_, _) => { try { DragMove(); } catch { /* ignore mid-drag races */ } };
    }

    private void PositionBottomRight(double diameter, PxRect region)
    {
        double scale = Math.Max(0.1, Screens.Primary().DpiScale);
        var work = SystemParameters.WorkArea; // DIPs on the primary monitor
        double left = region.Right / scale - diameter - EdgeMargin;
        double top = region.Bottom / scale - diameter - EdgeMargin;
        Left = Math.Max(work.Left, Math.Min(left, work.Right - diameter));
        Top = Math.Max(work.Top, Math.Min(top, work.Bottom - diameter));
    }

    /// <summary>What the last <see cref="StartAsync"/> found (drives the recording pill's Camera button).</summary>
    public enum StartResult { Started, NoCamera, Denied }

    /// <summary>Initialize the default camera and start previewing. Any failure degrades silently (bubble never
    /// shows) and is reported so the pill can grey its Camera button with the reason.</summary>
    public async Task<StartResult> StartAsync()
    {
        try
        {
            _capture = new MediaCapture();
            var settings = new MediaCaptureInitializationSettings
            {
                StreamingCaptureMode = StreamingCaptureMode.Video,
                MemoryPreference = MediaCaptureMemoryPreference.Cpu,
                SharingMode = MediaCaptureSharingMode.ExclusiveControl,
            };
            if (!string.IsNullOrEmpty(DeviceId)) settings.VideoDeviceId = DeviceId; // the Camera menu's choice
            await _capture.InitializeAsync(settings);

            var source = _capture.FrameSources.Values.FirstOrDefault(s =>
                             s.Info.SourceKind == MediaFrameSourceKind.Color &&
                             s.Info.MediaStreamType == MediaStreamType.VideoPreview)
                         ?? _capture.FrameSources.Values.FirstOrDefault(s => s.Info.SourceKind == MediaFrameSourceKind.Color);
            if (source is null) { Stop(); return StartResult.NoCamera; }

            _reader = await _capture.CreateFrameReaderAsync(source, MediaEncodingSubtypes.Bgra8);
            _reader.FrameArrived += OnFrameArrived;
            await _reader.StartAsync();
            Show();
            return StartResult.Started;
        }
        catch (UnauthorizedAccessException)
        {
            Stop(); // Settings › Privacy & security › Camera is off for desktop apps
            return StartResult.Denied;
        }
        catch
        {
            Stop(); // no camera or device busy — degrade
            return StartResult.NoCamera;
        }
    }

    /// <summary>
    /// Pill Camera toggle (v3 Part 5): hide the bubble where the user dragged it and stop the camera (its light goes
    /// off), or bring it back in the same spot. Returns false if the camera can't be restarted.
    /// </summary>
    public async Task<bool> SetHiddenAsync(bool hidden)
    {
        if (hidden)
        {
            StopCamera();
            Hide();
            return true;
        }
        _keepWindow = true;
        try { return await StartAsync() == StartResult.Started; }
        finally { _keepWindow = false; }
    }

    private bool _keepWindow;

    private void OnFrameArrived(MediaFrameReader sender, MediaFrameArrivedEventArgs args)
    {
        using var frame = sender.TryAcquireLatestFrame();
        var software = frame?.VideoMediaFrame?.SoftwareBitmap;
        if (software is null) return;

        SoftwareBitmap bmp = software;
        SoftwareBitmap? converted = null;
        if (bmp.BitmapPixelFormat != BitmapPixelFormat.Bgra8 || bmp.BitmapAlphaMode != BitmapAlphaMode.Premultiplied)
            bmp = converted = SoftwareBitmap.Convert(bmp, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);

        int w = bmp.PixelWidth, h = bmp.PixelHeight;
        var pixels = new byte[w * h * 4];
        bmp.CopyToBuffer(pixels.AsBuffer());
        converted?.Dispose();

        Dispatcher.BeginInvoke(() =>
        {
            if (_bitmap is null || _bitmap.PixelWidth != w || _bitmap.PixelHeight != h)
            {
                _bitmap = new WriteableBitmap(w, h, 96, 96, PixelFormats.Pbgra32, null);
                Preview.Source = _bitmap;
            }
            _bitmap.WritePixels(new Int32Rect(0, 0, w, h), pixels, w * 4, 0);
        });
    }

    public void Stop()
    {
        StopCamera();
        if (!_keepWindow) Close();
    }

    private void StopCamera()
    {
        if (_reader is not null)
        {
            _reader.FrameArrived -= OnFrameArrived;
            try { _ = _reader.StopAsync(); } catch { /* best-effort */ }
            _reader.Dispose();
            _reader = null;
        }
        _capture?.Dispose();
        _capture = null;
    }
}
