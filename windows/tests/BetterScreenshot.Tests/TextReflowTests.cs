using BetterScreenshot.Capture;
using BetterScreenshot.Core;

namespace BetterScreenshot.Tests;

/// <summary>Port of the Mac TextReflowTests (v2.11.0). Normalised geometry with a top-left origin.</summary>
public class TextReflowTests
{
    private static TextReflow.Line L(string text, double top, double left, double right, double height = 0.05) =>
        new(text, new PxRect(left, top, right - left, height));

    private static void Is(IEnumerable<TextReflow.Line> lines, params string[] expected) =>
        Assert.Equal(expected, TextReflow.Paragraphs(lines));

    [Fact] public void Empty_input_is_empty() => Is(Array.Empty<TextReflow.Line>());

    [Fact]
    public void Wrapped_lines_join_into_one_paragraph() => Is(new[]
    {
        L("The quick brown fox jumps", 0.10, 0.1, 0.6),
        L("over the lazy dog", 0.16, 0.1, 0.44),
    }, "The quick brown fox jumps over the lazy dog");

    [Fact]
    public void Short_line_ends_paragraph() => Is(new[]
    {
        L("let x = 1", 0.10, 0.1, 0.28),
        L("let y = 2", 0.16, 0.1, 0.28),
        L("return veryLongExpression(with: lots, of: arguments)", 0.22, 0.1, 1.0),
    }, "let x = 1", "let y = 2", "return veryLongExpression(with: lots, of: arguments)");

    [Fact]
    public void Bullet_marker_starts_new_paragraph() => Is(new[]
    {
        L("• The Boston Consulting Group", 0.10, 0.1, 0.7),
        L("matrix is a planning tool.", 0.16, 0.14, 0.66),
        L("• It looks at market growth", 0.24, 0.1, 0.64),
        L("and market share.", 0.30, 0.14, 0.48),
    }, "• The Boston Consulting Group matrix is a planning tool.", "• It looks at market growth and market share.");

    [Fact]
    public void Numbered_marker_starts_new_paragraph() => Is(new[]
    {
        L("1. First item that wraps onto", 0.10, 0.1, 0.7),
        L("a second line", 0.16, 0.14, 0.4),
        L("2. Second item", 0.22, 0.1, 0.38),
    }, "1. First item that wraps onto a second line", "2. Second item");

    [Fact]
    public void Large_gap_starts_new_paragraph() => Is(new[]
    {
        L("A full width line of prose that reaches", 0.10, 0.1, 0.9),
        L("Next paragraph here", 0.21, 0.1, 0.5),
    }, "A full width line of prose that reaches", "Next paragraph here");

    [Fact]
    public void Pitch_jump_starts_new_paragraph() => Is(new[]
    {
        L("first line of the block here", 0.10, 0.1, 0.66),
        L("second line of the block too", 0.16, 0.1, 0.66),
        L("third line of the block ends", 0.22, 0.1, 0.66),
        L("fourth line after a paragraph", 0.31, 0.1, 0.68),
    }, "first line of the block here second line of the block too third line of the block ends", "fourth line after a paragraph");

    [Fact]
    public void Font_size_change_starts_new_paragraph() => Is(new[]
    {
        L("Big heading here", 0.10, 0.1, 0.6, 0.08),
        L("body text that is long enough", 0.19, 0.1, 0.6, 0.04),
    }, "Big heading here", "body text that is long enough");

    [Fact]
    public void Columns_stay_separate() => Is(new[]
    {
        L("left column first", 0.10, 0.05, 0.45),
        L("right column first", 0.10, 0.55, 0.95),
        L("wrapped", 0.16, 0.05, 0.2),
        L("wrapped too", 0.16, 0.55, 0.78),
    }, "left column first wrapped", "right column first wrapped too");

    [Fact]
    public void Same_row_fragments_join_when_adjacent() => Is(new[]
    {
        L("Hello", 0.10, 0.10, 0.20),
        L("world", 0.10, 0.21, 0.31),
    }, "Hello world");

    [Fact]
    public void Same_row_distant_fragments_stay_separate() => Is(new[]
    {
        L("Name", 0.10, 0.1, 0.2),
        L("Value", 0.10, 0.6, 0.7),
    }, "Name", "Value");

    [Fact]
    public void Lines_are_sorted_top_to_bottom() => Is(new[]
    {
        L("over the lazy dog", 0.16, 0.1, 0.44),
        L("The quick brown fox jumps", 0.10, 0.1, 0.6),
    }, "The quick brown fox jumps over the lazy dog");

    [Fact]
    public void Hyphenated_break_joins_without_space() => Is(new[]
    {
        L("a tool for product portfo-", 0.10, 0.1, 0.62),
        L("lio analysis", 0.16, 0.1, 0.34),
    }, "a tool for product portfolio analysis");

    [Fact]
    public void Bullet_glyphs_normalize_and_whitespace_trims() => Is(new[]
    {
        L("  · first thing ", 0.10, 0.1, 0.4),
        L("● second thing", 0.18, 0.1, 0.4),
    }, "• first thing", "• second thing");

    [Fact]
    public void Works_in_pixel_units_too() => Is(new[]
    {
        L("The quick brown fox jumps", 100, 100, 600, 50),
        L("over the lazy dog", 160, 100, 440, 50),
    }, "The quick brown fox jumps over the lazy dog");
}
