using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.Capture;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Storage.Streams;

namespace BetterScreenshot.Platform;

/// <summary>
/// Capture-Text recognition: decodes QR codes (ZXing) and on-device text (Windows.Media.Ocr), then applies the
/// pure <see cref="RecognitionResolver"/> rule (QR wins over text). Everything runs locally — no network.
/// </summary>
public static class TextRecognizerService
{
    public static async Task<RecognitionResult> RecognizeAsync(BitmapSource image)
    {
        byte[] bgra = GetBgra(image, out int width, out int height);
        var (qr, coverage) = DecodeQr(bgra, width, height);
        var lines = await OcrLinesAsync(image, UpscaleFor(image));
        return RecognitionResolver.Resolve(qr, lines, qrDominant: coverage >= RecognitionResolver.DominantQrArea);
    }

    /// <summary>Upscale (Mac v2.10.0) to 2× pixel density before OCR. Our captures are device pixels at the
    /// image's own DPI (96 = 1×), so most Windows monitors get 2×; capped by the engine's max dimension.
    /// Measured on Windows.Media.Ocr: see windows/docs/PROGRESS.md (2026-10-02 #9).</summary>
    internal static double UpscaleFor(BitmapSource image)
    {
        double dipWidth = image.PixelWidth * 96.0 / (image.DpiX > 0 ? image.DpiX : 96.0);
        double f = OcrTuning.UpscaleFactor(image.PixelWidth, dipWidth);
        return OcrTuning.ClampToMaxDimension(f, image.PixelWidth, image.PixelHeight, (int)OcrEngine.MaxImageDimension);
    }

    // ---- One engine for the app's lifetime, created for an explicit language (never auto-detect).
    private static OcrEngine? _engine;
    private static bool _engineTried;
    private static readonly object EngineLock = new();

    internal static OcrEngine? Engine()
    {
        lock (EngineLock)
        {
            if (_engineTried) return _engine;
            _engineTried = true;
            try
            {
                var supported = OcrEngine.AvailableRecognizerLanguages.Select(l => l.LanguageTag).ToList();
                var preferred = Windows.System.UserProfile.GlobalizationPreferences.Languages;
                foreach (var tag in OcrTuning.RecognitionLanguages(preferred, supported))
                {
                    var lang = new Windows.Globalization.Language(tag);
                    if (OcrEngine.IsLanguageSupported(lang) && OcrEngine.TryCreateFromLanguage(lang) is { } e) { _engine = e; break; }
                }
                _engine ??= OcrEngine.TryCreateFromUserProfileLanguages();
            }
            catch (Exception ex) when (ex is ArgumentException or System.Runtime.InteropServices.COMException)
            {
                _engine = null; // no OCR language pack installed; Capture Text then reports "no text"
            }
            return _engine;
        }
    }

    private static DateTime _lastUse = DateTime.MinValue;

    /// <summary>One recognition at a time on the shared engine (the warm-up can still be running when the user
    /// finishes a quick drag; concurrent RecognizeAsync calls on one OcrEngine returned empty results in tests).</summary>
    private static readonly SemaphoreSlim Gate = new(1, 1);

    /// <summary>Loads the OCR model while the user drags (Mac: cold start 0.5–1 s, unloaded after ~20 s idle).
    /// Runs one tiny recognition of a real word off the UI thread; a blank image doesn't load the model.
    /// Skipped when the engine was used in the last 15 s.</summary>
    public static void WarmUp()
    {
        if ((DateTime.UtcNow - _lastUse).TotalSeconds < 15) return;
        _lastUse = DateTime.UtcNow;
        var word = WarmUpBitmap(); // built on the calling (UI) thread — WPF rendering
        _ = Task.Run(async () =>
        {
            try
            {
                if (Engine() is not { } engine) return;
                using var sb = SoftwareBitmap.CreateCopyFromBuffer(word.Pixels.AsBuffer(), BitmapPixelFormat.Bgra8,
                    word.Width, word.Height, BitmapAlphaMode.Premultiplied);
                await Gate.WaitAsync();
                try { await engine.RecognizeAsync(sb); }
                finally { Gate.Release(); }
            }
            catch (Exception ex) when (ex is not OutOfMemoryException)
            {
                System.Diagnostics.Debug.WriteLine("OCR warm-up failed: " + ex.Message); // a cold first capture is the only cost
            }
        });
    }

    private static (byte[] Pixels, int Width, int Height) WarmUpBitmap()
    {
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.DrawRectangle(Brushes.White, null, new System.Windows.Rect(0, 0, 160, 48));
            dc.DrawText(new FormattedText("Warm up", System.Globalization.CultureInfo.InvariantCulture,
                System.Windows.FlowDirection.LeftToRight, new Typeface("Segoe UI"), 24, Brushes.Black, 1.0),
                new System.Windows.Point(10, 8));
        }
        var rtb = new RenderTargetBitmap(160, 48, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(visual);
        var px = new byte[160 * 48 * 4];
        rtb.CopyPixels(px, 160 * 4, 0);
        return (px, 160, 48);
    }

    /// <summary>The QR payload (if any) and the share of the selection the code covers.</summary>
    private static (List<string> Payloads, double Coverage) DecodeQr(byte[] bgra, int width, int height)
    {
        var found = new List<string>();
        double coverage = 0;
        try
        {
            var luminance = new ZXing.RGBLuminanceSource(bgra, width, height, ZXing.RGBLuminanceSource.BitmapFormat.BGRA32);
            var bitmap = new ZXing.BinaryBitmap(new ZXing.Common.HybridBinarizer(luminance));
            var reader = new ZXing.QrCode.QRCodeReader();
            var hints = new Dictionary<ZXing.DecodeHintType, object> { { ZXing.DecodeHintType.TRY_HARDER, true } };
            var result = reader.decode(bitmap, hints);
            if (result?.Text is { Length: > 0 } text)
            {
                found.Add(text);
                var finders = result.ResultPoints.OfType<ZXing.QrCode.Internal.FinderPattern>().ToList();
                double module = finders.Count > 0 ? finders.Average(f => f.EstimatedModuleSize) : 0;
                coverage = RecognitionResolver.QrCoverage(finders.Select(f => ((double)f.X, (double)f.Y)).ToList(), module, width, height);
            }
        }
        catch
        {
            // No QR code present (or undecodable) — fall through to OCR.
        }
        return (found, coverage);
    }

    internal static async Task<List<string>> OcrLinesAsync(BitmapSource image, double upscale)
    {
        _lastUse = DateTime.UtcNow;
        if (Engine() is not { } engine) return new List<string>();

        using var software = await ToSoftwareBitmapAsync(image, upscale);
        OcrResult result;
        await Gate.WaitAsync();
        try { result = await engine.RecognizeAsync(software); }
        finally { Gate.Release(); }
        int w = software.PixelWidth, h = software.PixelHeight;
        string language = engine.RecognizerLanguage?.LanguageTag ?? "";
        // Vertical grid lines are measured only when the layout asks (a table with two or more multi-cell rows).
        var grid = new Lazy<GridLines>(() =>
        {
            var px = new byte[w * h * 4];
            software.CopyToBuffer(px.AsBuffer());
            return GridLines.FromBgra(px, w, h);
        });
        WordList.Lookup ??= SpellWordList.Create();
        var lines = result.Lines.Select(l => ToReflowLine(l, w, h, language)).Where(l => l.Text.Length > 0).ToList();
        return TextReflow.Paragraphs(lines, new Core.PxSize(w, h), r => grid.Value.Vertical(r)).ToList();
    }

    /// <summary>An OCR line for <see cref="TextReflow"/>: its text, its box = the union of its words' boxes, and each
    /// word's box — normalised to the <paramref name="width"/>×<paramref name="height"/> bitmap, top-left origin.</summary>
    internal static TextReflow.Line ToReflowLine(OcrLine line, int width, int height, string language = "")
    {
        double l = double.MaxValue, t = double.MaxValue, r = double.MinValue, b = double.MinValue;
        var words = new List<Core.PxRect>(line.Words.Count);
        foreach (var w in line.Words)
        {
            var box = w.BoundingRect;
            l = Math.Min(l, box.X); t = Math.Min(t, box.Y);
            r = Math.Max(r, box.X + box.Width); b = Math.Max(b, box.Y + box.Height);
            words.Add(new Core.PxRect(box.X / width, box.Y / height, box.Width / width, box.Height / height));
        }
        var rect = line.Words.Count == 0 ? default : Core.PxRect.FromLtrb(l / width, t / height, r / width, b / height);
        // Windows.Media.Ocr joins words with spaces for Latin scripts; the word boxes line up with them.
        string text = OcrTuning.RomanianCommaBelow(line.Text, language);
        return new TextReflow.Line(text, rect, WordBoxes: words);
    }

    private static async Task<SoftwareBitmap> ToSoftwareBitmapAsync(BitmapSource image, double upscale)
    {
        byte[] png = ImageIo.EncodePng(image);
        var stream = new InMemoryRandomAccessStream();
        var writer = new DataWriter(stream);
        writer.WriteBytes(png);
        await writer.StoreAsync();
        await writer.FlushAsync();
        writer.DetachStream();
        stream.Seek(0);

        var decoder = await Windows.Graphics.Imaging.BitmapDecoder.CreateAsync(stream);
        SoftwareBitmap sb;
        if (upscale > 1.001)
        {
            var transform = new BitmapTransform
            {
                ScaledWidth = (uint)Math.Round(decoder.PixelWidth * upscale),
                ScaledHeight = (uint)Math.Round(decoder.PixelHeight * upscale),
                InterpolationMode = BitmapInterpolationMode.Cubic,
            };
            sb = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, transform,
                ExifOrientationMode.IgnoreExifOrientation, ColorManagementMode.DoNotColorManage);
        }
        else sb = await decoder.GetSoftwareBitmapAsync();
        if (sb.BitmapPixelFormat != BitmapPixelFormat.Bgra8 || sb.BitmapAlphaMode == BitmapAlphaMode.Straight)
            sb = SoftwareBitmap.Convert(sb, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
        return sb;
    }

    private static byte[] GetBgra(BitmapSource source, out int width, out int height)
    {
        BitmapSource src = source.Format == PixelFormats.Bgra32
            ? source
            : new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        width = src.PixelWidth;
        height = src.PixelHeight;
        int stride = width * 4;
        var bytes = new byte[height * stride];
        src.CopyPixels(bytes, stride, 0);
        return bytes;
    }
}
