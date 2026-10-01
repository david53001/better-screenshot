using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.Capture;
using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

[Collection("WordList")]
public class TextRecognizerServiceTests
{
    [Fact]
    public void Windows_spell_checker_is_an_offline_English_word_list()
    {
        if (SpellWordList.Create() is not { } isWord) return; // no English dictionary on this machine
        Assert.True(isWord("reaction"));
        Assert.True(isWord("portfolio"));
        Assert.False(isWord("lightdependent"));
        Assert.False(isWord("12ab"));
    }

    private static BitmapSource MatrixToBitmap(ZXing.Common.BitMatrix matrix)
    {
        int w = matrix.Width, h = matrix.Height, stride = w * 4;
        var px = new byte[h * stride];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                byte v = matrix[x, y] ? (byte)0 : (byte)255; // set module = black
                int i = y * stride + x * 4;
                px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 255;
            }
        return BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, stride);
    }

    [Fact]
    [Trait("category", "hardware")]
    public async Task DecodesQrPayloadAndQrWinsOverText()
    {
        const string payload = "https://github.com/david53001/BetterScreenshot";
        var matrix = new ZXing.QrCode.QRCodeWriter().encode(payload, ZXing.BarcodeFormat.QR_CODE, 260, 260);
        var image = MatrixToBitmap(matrix);

        var result = await TextRecognizerService.RecognizeAsync(image);

        Assert.Equal(RecognitionKind.Qr, result.Kind);
        Assert.Equal(payload, result.Value);
    }

    /// <summary>Renders lines of text (one per entry, left-aligned, fixed pitch) like a slide at 1× density.</summary>
    internal static BitmapSource RenderLines(int width, double fontSize, params string[] lines)
    {
        var visual = new DrawingVisual();
        double pitch = fontSize * 1.35;
        using (var dc = visual.RenderOpen())
        {
            dc.DrawRectangle(Brushes.White, null, new System.Windows.Rect(0, 0, width, 40 + pitch * lines.Length));
            var face = new Typeface("Segoe UI");
            for (int i = 0; i < lines.Length; i++)
                dc.DrawText(new FormattedText(lines[i], System.Globalization.CultureInfo.InvariantCulture,
                    System.Windows.FlowDirection.LeftToRight, face, fontSize, Brushes.Black, 1.0),
                    new System.Windows.Point(20, 20 + i * pitch));
        }
        var bmp = new RenderTargetBitmap(width, (int)(40 + pitch * lines.Length), 96, 96, PixelFormats.Pbgra32);
        bmp.Render(visual);
        bmp.Freeze();
        return bmp;
    }

    [Fact]
    [Trait("category", "hardware")]
    public async Task WrappedParagraphPastesAsOneLine_andBulletsStaySeparate()
    {
        // Two wrapped bullets: each wraps onto a second visual line that must join its bullet.
        var image = RenderLines(560, 22,
            "• The Boston Consulting Group matrix is",
            "a planning tool for product portfolios.",
            "• It looks at market growth and the",
            "market share of each business unit.");

        var result = await TextRecognizerService.RecognizeAsync(image);

        Assert.Equal(RecognitionKind.Text, result.Kind);
        var paragraphs = result.Value.Split('\n');
        Assert.Equal(2, paragraphs.Length);
        Assert.StartsWith("• The Boston", paragraphs[0]);
        Assert.EndsWith("portfolios.", paragraphs[0]);
        Assert.StartsWith("• It looks", paragraphs[1]);
    }

    /// <summary>Renders a grid of cells (rows × columns) at fixed column x positions, optionally with grid lines.</summary>
    internal static BitmapSource RenderTable(string[][] rows, double[] columnX, bool gridLines, double fontSize = 22)
    {
        var visual = new DrawingVisual();
        double pitch = fontSize * 1.9, width = columnX[^1] + 200, height = 30 + pitch * rows.Length;
        using (var dc = visual.RenderOpen())
        {
            dc.DrawRectangle(Brushes.White, null, new System.Windows.Rect(0, 0, width, height));
            var face = new Typeface("Segoe UI");
            for (int r = 0; r < rows.Length; r++)
                for (int c = 0; c < rows[r].Length; c++)
                    if (rows[r][c].Length > 0)
                        dc.DrawText(new FormattedText(rows[r][c], System.Globalization.CultureInfo.InvariantCulture,
                            System.Windows.FlowDirection.LeftToRight, face, fontSize, Brushes.Black, 1.0),
                            new System.Windows.Point(columnX[c], 20 + r * pitch));
            if (gridLines)
            {
                var pen = new Pen(new SolidColorBrush(Color.FromRgb(0xC8, 0xC8, 0xC8)), 1);
                foreach (double x in columnX.Skip(1)) dc.DrawLine(pen, new System.Windows.Point(x - 12.5, 8), new System.Windows.Point(x - 12.5, height - 4));
            }
        }
        var bmp = new RenderTargetBitmap((int)width, (int)height, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(visual);
        bmp.Freeze();
        return bmp;
    }

    [Theory]
    [Trait("category", "hardware")]
    [InlineData(false)]
    [InlineData(true)]
    public async Task A_table_pastes_as_tab_separated_rows(bool gridLines)
    {
        var image = RenderTable(new[]
        {
            new[] { "Country", "Capital", "Population" },
            new[] { "Romania", "Bucharest", "19.0" },
            new[] { "France", "Paris", "68.2" },
            new[] { "Total", "", "87.2" },
        }, new[] { 20.0, 220, 420 }, gridLines);

        var result = await TextRecognizerService.RecognizeAsync(image);

        Assert.Equal(RecognitionKind.Text, result.Kind);
        Assert.Equal("Country\tCapital\tPopulation\nRomania\tBucharest\t19.0\nFrance\tParis\t68.2\nTotal\t\t87.2", result.Value);
    }
}
