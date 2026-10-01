using System.Diagnostics;
using BetterScreenshot.Platform;
using Xunit.Abstractions;

namespace BetterScreenshot.Tests;

/// <summary>
/// Measures whether the 2× pre-OCR upscale (Mac v2.10.0) helps Windows.Media.Ocr on 1× captures of small UI text.
/// Hardware-gated (real OCR engine). Asserts the upscale never makes accuracy worse.
/// </summary>
public class OcrUpscaleBenchTests
{
    private readonly ITestOutputHelper _out;
    public OcrUpscaleBenchTests(ITestOutputHelper output) => _out = output;

    private static readonly string[] Paragraph =
    {
        "Settings are saved to your profile automatically and",
        "apply right away. Capture history keeps the last fifty",
        "screenshots; older ones are removed when the limit is",
        "reached. Recording uses ffmpeg at 30 frames per second.",
    };

    private static int Distance(string a, string b)
    {
        var d = new int[a.Length + 1, b.Length + 1];
        for (int i = 0; i <= a.Length; i++) d[i, 0] = i;
        for (int j = 0; j <= b.Length; j++) d[0, j] = j;
        for (int i = 1; i <= a.Length; i++)
            for (int j = 1; j <= b.Length; j++)
                d[i, j] = Math.Min(Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1), d[i - 1, j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
        return d[a.Length, b.Length];
    }

    [Fact]
    [Trait("category", "hardware")]
    public async Task Upscale_never_hurts_small_text_accuracy()
    {
        string expected = string.Join(" ", Paragraph);
        foreach (double size in new[] { 9.0, 10.0, 11.0, 12.0, 14.0 })
        {
            var image = TextRecognizerServiceTests.RenderLines(520, size * 96 / 72, Paragraph);
            var errs = new Dictionary<double, int>();
            foreach (double f in new[] { 1.0, 2.0 })
            {
                await TextRecognizerService.OcrLinesAsync(image, f); // warm
                var sw = Stopwatch.StartNew();
                var text = string.Join(" ", await TextRecognizerService.OcrLinesAsync(image, f));
                sw.Stop();
                errs[f] = Distance(text, expected);
                _out.WriteLine($"{size,4}pt  x{f}  errors={errs[f],3}  {sw.ElapsedMilliseconds,4} ms  \"{text[..Math.Min(60, text.Length)]}\"");
            }
            Assert.True(errs[2.0] <= errs[1.0], $"upscale hurt {size}pt: {errs[2.0]} > {errs[1.0]}");
        }
    }
}
