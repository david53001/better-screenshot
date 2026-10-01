using BetterScreenshot.Capture;
using Xunit;

namespace BetterScreenshot.Tests;

public class RecognitionResolverTests
{
    [Fact]
    public void A_QR_code_filling_the_selection_beats_text() =>
        Assert.Equal(RecognitionResult.Qr("https://example.com"),
            RecognitionResolver.Resolve(new[] { "https://example.com" }, new[] { "Scan me" }, qrDominant: true));

    [Fact]
    public void A_small_QR_code_is_appended_to_the_text() =>
        Assert.Equal(RecognitionResult.Text("hello\nworld\nhttps://example.com"),
            RecognitionResolver.Resolve(new[] { "https://example.com" }, new[] { "hello", "world" }));

    [Fact]
    public void A_QR_payload_already_printed_is_not_repeated() =>
        Assert.Equal(RecognitionResult.Text("Join at example.com/join"),
            RecognitionResolver.Resolve(new[] { "example.com/join" }, new[] { "Join at example.com/join" }));

    [Fact]
    public void A_QR_code_alone_is_the_result() =>
        Assert.Equal(RecognitionResult.Qr("x"), RecognitionResolver.Resolve(new[] { "x" }, Array.Empty<string>()));

    [Fact]
    public void QR_coverage_adds_the_finder_inset()
    {
        // A version-1 code (21 modules of 10 px) filling a 210 px square: finder centres 3.5 modules in.
        var centres = new[] { (35.0, 35.0), (175.0, 35.0), (35.0, 175.0) };
        Assert.Equal(1.0, RecognitionResolver.QrCoverage(centres, 10, 210, 210), 3);
        Assert.Equal(0.25, RecognitionResolver.QrCoverage(centres, 10, 420, 420), 3);
        Assert.Equal(0, RecognitionResolver.QrCoverage(centres.Take(2).ToList(), 10, 210, 210));
    }

    [Fact]
    public void Grid_lines_are_found_where_a_faint_stripe_crosses_every_row()
    {
        // 40×10 white with a faint (#E2) 1 px vertical line at x = 20 and a short stroke at x = 30 (half the rows).
        int w = 40, h = 10;
        var gray = Enumerable.Repeat((byte)255, w * h).ToArray();
        for (int y = 0; y < h; y++) gray[y * w + 20] = 0xE2;
        for (int y = 0; y < 5; y++) gray[y * w + 30] = 0x00;
        var lines = new GridLines(w, h, gray).Vertical(new BetterScreenshot.Core.PxRect(0, 0, w, h));
        Assert.Equal(new[] { 20.5 }, lines);
    }

    [Fact]
    public void TextLinesJoinWithNewlines()
    {
        var r = RecognitionResolver.Resolve(Array.Empty<string>(), new[] { "hello", "world" });
        Assert.Equal(RecognitionResult.Text("hello\nworld"), r);
    }

    [Fact]
    public void BlankLinesAreDropped()
    {
        var r = RecognitionResolver.Resolve(Array.Empty<string>(), new[] { "", "hello", "" });
        Assert.Equal(RecognitionResult.Text("hello"), r);
    }

    [Fact]
    public void NothingIsNone()
    {
        Assert.Equal(RecognitionResult.None, RecognitionResolver.Resolve(Array.Empty<string>(), Array.Empty<string>()));
        Assert.Equal(RecognitionResult.None, RecognitionResolver.Resolve(Array.Empty<string>(), new[] { "", "" }));
    }

    [Fact]
    public void ClipboardStrings()
    {
        Assert.Equal("x", RecognitionResult.Qr("x").ClipboardString);
        Assert.Equal("y", RecognitionResult.Text("y").ClipboardString);
        Assert.Null(RecognitionResult.None.ClipboardString);
    }

    [Fact]
    public void HudMessages()
    {
        Assert.Equal("QR code copied", RecognitionResult.Qr("x").HudMessage);
        Assert.Equal("Text copied — 4 characters", RecognitionResult.Text("abcd").HudMessage);
        Assert.Equal("No text found", RecognitionResult.None.HudMessage);
    }
}
