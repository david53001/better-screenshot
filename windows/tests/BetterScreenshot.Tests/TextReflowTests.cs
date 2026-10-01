using BetterScreenshot.Capture;
using BetterScreenshot.Core;

namespace BetterScreenshot.Tests;

/// <summary>
/// Port of the Mac <c>TextReflowTests</c> (branch <c>ocr-structure-math</c>, v3 Part 8 §8.2). Normalised geometry with
/// a top-left origin; character width ≈ (right − left) / text length, so the fixtures make "does the next word fit?"
/// unambiguous. The word list is a fixed fake (the app plugs in the Windows spell checker).
/// </summary>
[Collection("WordList")]
public class TextReflowTests
{
    public TextReflowTests() => WordList.Lookup = FakeWords.Contains;

    internal static readonly HashSet<string> FakeWords = new()
    {
        "portfolio", "reaction", "run", "information", "cost", "sine", "sect", "tacos", "using", "light", "dependent",
    };

    private static TextReflow.Line L(string text, double top, double left, double right, double height = 0.05) =>
        new(text, new PxRect(left, top, right - left, height));

    /// <summary>A line with the engine's per-word boxes, given as (left, right) per word.</summary>
    private static TextReflow.Line W(string text, double top, (double L, double R)[] spans, double height = 0.05)
    {
        var boxes = spans.Select(s => new PxRect(s.L, top, s.R - s.L, height)).ToList();
        return new TextReflow.Line(text, boxes.Skip(1).Aggregate(boxes[0], (a, b) => a.Union(b)), WordBoxes: boxes);
    }

    private static List<string> P(IEnumerable<TextReflow.Line> lines, PxSize? size = null,
        Func<PxRect, IReadOnlyList<double>>? rules = null) => TextReflow.Paragraphs(lines, size, rules);

    [Fact] public void Empty_input_is_empty() => Assert.Empty(P(Array.Empty<TextReflow.Line>()));

    [Fact]
    public void Wrapped_lines_join_into_one_paragraph() => Assert.Equal(new[] { "The quick brown fox jumps over the lazy dog" }, P(new[]
    {
        L("The quick brown fox jumps", 0.10, 0.1, 0.6),
        L("over the lazy dog", 0.16, 0.1, 0.44),
    }));

    [Fact]
    public void A_sentence_ending_at_an_evenly_padded_margin_wrapped()
    {
        const string first = "Enzymes lower the energy of a reaction without being used up.";
        const string second = "Their activity depends on temperature.";
        double cw = 0.8 / first.Length;
        Assert.Equal(new[] { first + " " + second }, P(new[]
        {
            L(first, 0.10, 0.1, 0.9),
            L(second, 0.158, 0.1, 0.1 + cw * second.Length),
        }));
        // A tight selection has no margin to go by: two sentences stay apart.
        Assert.Equal(new[] { first, second }, P(new[]
        {
            L(first, 0.10, 0.01, 0.99),
            L(second, 0.158, 0.01, 0.01 + 0.98 / first.Length * second.Length),
        }));
    }

    [Fact]
    public void Short_line_ends_paragraph() => Assert.Equal(
        "let x = 1\nlet y = 2\nreturn veryLongExpression(with: lots, of: arguments)",
        string.Join("\n", P(new[]
        {
            L("let x = 1", 0.10, 0.1, 0.28),
            L("let y = 2", 0.16, 0.1, 0.28),
            L("return veryLongExpression(with: lots, of: arguments)", 0.22, 0.1, 1.0),
        })));

    [Fact]
    public void Bullet_marker_starts_new_paragraph() => Assert.Equal(new[]
    {
        "• The Boston Consulting Group matrix is a planning tool.",
        "• It looks at market growth and market share.",
    }, P(new[]
    {
        L("• The Boston Consulting Group", 0.10, 0.1, 0.7),
        L("matrix is a planning tool.", 0.16, 0.14, 0.66),
        L("• It looks at market growth", 0.24, 0.1, 0.64),
        L("and market share.", 0.30, 0.14, 0.48),
    }));

    [Fact]
    public void Checkbox_marker_starts_new_paragraph() => Assert.Equal(new[]
    {
        "☐ Finish the history essay draft and hand it in",
        "☑ Call the dentist",
    }, P(new[]
    {
        L("☐ Finish the history essay draft and", 0.10, 0.1, 0.9),
        L("hand it in", 0.16, 0.14, 0.4),
        L("☑ Call the dentist", 0.22, 0.1, 0.5),
    }));

    [Fact]
    public void Two_lines_past_double_spacing_are_two_paragraphs()
    {
        TextReflow.Line[] Pair(double pitch) => new[]
        {
            L("It rained all day in the town, so we stayed in.", 0.1, 0.1, 0.852, 0.06),
            L("and then the sun came out, so we went for a walk.", 0.1 + pitch, 0.1, 0.9, 0.06),
        };
        Assert.Single(P(Pair(0.064)));
        Assert.Equal(2, P(Pair(0.096)).Count);
    }

    [Fact]
    public void A_caption_under_a_figure_stays_in_its_column()
    {
        var lines = new[]
        {
            L("Left column text.", 0.10, 0.05, 0.45),
            L("Right column starts here", 0.10, 0.55, 0.95),
            L("and runs on down the", 0.18, 0.55, 0.95),
            L("page past the figure.", 0.26, 0.55, 0.90),
            L("Figure 1. A caption.", 0.80, 0.05, 0.40),
        };
        Assert.Equal(new[] { "Left column text.", "Figure 1. A caption.", "Right column starts here", "and runs on down the", "page past the figure." },
            TextReflow.ColumnOrdered(lines).Select(l => l.Text));
        var table = new[]
        {
            L("Name", 0.1, 0.05, 0.2), L("Score", 0.1, 0.6, 0.8),
            L("Ana", 0.2, 0.05, 0.15), L("84", 0.2, 0.6, 0.66),
        };
        Assert.Equal(new[] { "Name", "Score", "Ana", "84" }, TextReflow.ColumnOrdered(table).Select(l => l.Text));
    }

    [Fact]
    public void A_sidebar_beside_a_table_is_a_list_of_its_own() => Assert.Equal(
        "General\nAppearance\nWi-Fi\nBluetooth\nAppearance\tAuto\nAccent colour\tMulticolour",
        string.Join("\n", P(new[]
        {
            L("General", 0.10, 0.03, 0.10, 0.055),
            L("Appearance", 0.23, 0.03, 0.14, 0.055),
            L("Wi-Fi", 0.35, 0.03, 0.08, 0.055),
            L("Bluetooth", 0.47, 0.03, 0.12, 0.055),
            L("Appearance", 0.31, 0.35, 0.46, 0.055),
            L("Accent colour", 0.44, 0.35, 0.49, 0.055),
            L("Auto", 0.31, 0.90, 0.95, 0.055),
            L("Multicolour", 0.44, 0.84, 0.95, 0.055),
        })));

    [Fact]
    public void Separate_short_lines_dont_join_without_evidence_of_wrapping()
    {
        Assert.Equal(2, P(new[]
        {
            L("p. 214, ex. 3-7 (odd)", 0.10, 0.1, 0.52),
            L("Revise: sine & cosine rules", 0.18, 0.1, 0.64),
        }).Count);
        Assert.Single(P(new[]
        {
            L("On Friday the class met with", 0.10, 0.1, 0.66),
            L("Maria and Ion from the museum.", 0.18, 0.1, 0.70),
        }));
    }

    [Fact]
    public void Two_lines_of_equal_width_are_not_enough_to_call_a_font_monospaced() => Assert.False(TextReflow.ContainsCode(new[]
    {
        L("Update to v2.11.0 from ~/Downloads/app.dmg, then", 0.10, 0.1, 0.9),
        L("write to support@example.org if it complains.", 0.18, 0.1, 0.83),
    }));

    [Fact]
    public void Zsh_and_bash_prompts_are_code()
    {
        Assert.True(TextReflow.LooksLikeCode("david@MacBook ia % ls -1"));
        Assert.True(TextReflow.LooksLikeCode("bash-3.2$ make test"));
        Assert.True(TextReflow.LooksLikeCode(@"PS C:\Users\me> dotnet test"));
    }

    [Fact]
    public void Code_look_alikes_are_repaired()
    {
        Assert.Equal("david@MacBook ia % ls -1", TextReflow.CleanedCode("david@MacBook ia % 1s -1"));
        Assert.Equal("data.csv README.md main.py", TextReflow.CleanedCode("data.CSV README•md main-py"));
        Assert.Equal("for (int i = 1; i < n; i++)", TextReflow.CleanedCode("for (int i = 1; i < n; itt)"));
        Assert.Equal("fetch(`/api/${id}/grades`);", TextReflow.CleanedCode("fetch('/api/${id}/grades\");"));
        Assert.Equal("echo \"${HOME}\"", TextReflow.CleanedCode("echo \"${HOME}\""));
        Assert.Equal("console.log(`${res.status}`)", TextReflow.CleanedCode("console.log('$fres.status}')"));
    }

    [Fact]
    public void Numbered_marker_starts_new_paragraph() => Assert.Equal(new[]
    {
        "1. First item that wraps onto a second line", "2. Second item",
    }, P(new[]
    {
        L("1. First item that wraps onto", 0.10, 0.1, 0.7),
        L("a second line", 0.16, 0.14, 0.4),
        L("2. Second item", 0.22, 0.1, 0.38),
    }));

    [Fact]
    public void Large_gap_starts_new_paragraph() => Assert.Equal(new[]
    {
        "A full width line of prose that reaches", "Next paragraph here",
    }, P(new[]
    {
        L("A full width line of prose that reaches", 0.10, 0.1, 0.9),
        L("Next paragraph here", 0.21, 0.1, 0.5),
    }));

    [Fact]
    public void Pitch_jump_starts_new_paragraph() => Assert.Equal(new[]
    {
        "first line of the block here second line of the block too third line of the block ends",
        "fourth line after a paragraph",
    }, P(new[]
    {
        L("first line of the block here", 0.10, 0.1, 0.66),
        L("second line of the block too", 0.16, 0.1, 0.66),
        L("third line of the block ends", 0.22, 0.1, 0.66),
        L("fourth line after a paragraph", 0.31, 0.1, 0.68),
    }));

    [Fact]
    public void Font_size_change_starts_new_paragraph() => Assert.Equal(new[] { "Big heading here", "body text that is long enough" }, P(new[]
    {
        L("Big heading here", 0.10, 0.1, 0.6, 0.08),
        L("body text that is long enough", 0.19, 0.1, 0.6, 0.04),
    }));

    [Fact]
    public void Columns_stay_separate() => Assert.Equal(new[]
    {
        "Water evaporates from oceans and rivers when it is heated by the Sun.",
        "Some of this water flows over the land and then returns to the sea.",
    }, P(new[]
    {
        L("Water evaporates from oceans and rivers", 0.10, 0.05, 0.45),
        L("when it is heated by the Sun.", 0.16, 0.05, 0.38),
        L("Some of this water flows over the land", 0.10, 0.55, 0.95),
        L("and then returns to the sea.", 0.16, 0.55, 0.85),
    }));

    [Fact]
    public void Same_row_fragments_join_when_adjacent() => Assert.Equal(new[] { "Hello world" }, P(new[]
    {
        L("Hello", 0.10, 0.10, 0.20),
        L("world", 0.10, 0.21, 0.31),
    }));

    [Fact]
    public void Same_row_distant_short_pieces_join_with_tab() => Assert.Equal(new[] { "Name\tValue" }, P(new[]
    {
        L("Name", 0.10, 0.1, 0.2),
        L("Value", 0.10, 0.6, 0.7),
    }));

    [Fact]
    public void Engine_column_order_is_kept() => Assert.Equal(new[]
    {
        "Advantages", "• Low carbon emissions", "Disadvantages", "• Radioactive waste",
    }, P(new[]
    {
        L("Advantages", 0.10, 0.05, 0.35),
        L("• Low carbon emissions", 0.16, 0.05, 0.40),
        L("Disadvantages", 0.10, 0.55, 0.90),
        L("• Radioactive waste", 0.16, 0.55, 0.85),
    }));

    [Fact]
    public void Hyphenated_break_joins_without_space() => Assert.Equal(new[] { "a tool for product portfolio analysis" }, P(new[]
    {
        L("a tool for product portfo-", 0.10, 0.1, 0.62),
        L("lio analysis", 0.16, 0.1, 0.34),
    }));

    [Fact]
    public void A_compound_broken_at_its_hyphen_keeps_it()
    {
        Assert.Equal(new[] { "the light-dependent reactions" }, P(new[]
        {
            L("the light-", 0.10, 0.1, 0.3),
            L("dependent reactions", 0.16, 0.1, 0.48),
        }));
        Assert.True(WordList.Contains("reactions"));
        Assert.True(WordList.Contains("running"));
        Assert.False(WordList.Contains("lightdependent"));
    }

    [Fact]
    public void Bullet_glyphs_normalize_and_whitespace_trims() => Assert.Equal(new[] { "• first thing", "• second thing" }, P(new[]
    {
        L("  · first thing ", 0.10, 0.1, 0.4),
        L("● second thing", 0.18, 0.1, 0.4),
    }));

    [Fact]
    public void Table_rows_become_tab_separated() => Assert.Equal(new[] { "Country\tCapital\tPop\nRomania\tBucharest\t19.0\nTotal\t\t19.0" }, P(new[]
    {
        L("Country", 0.10, 0.05, 0.19),
        L("Romania", 0.20, 0.05, 0.19),
        L("Total", 0.30, 0.05, 0.12),
        L("Capital", 0.10, 0.35, 0.47),
        L("Bucharest", 0.20, 0.35, 0.50),
        L("Pop", 0.10, 0.65, 0.70),
        L("19.0", 0.20, 0.65, 0.72),
        L("19.0", 0.30, 0.65, 0.72),
    }));

    [Fact]
    public void Grid_line_separates_narrow_cell_from_its_neighbour() => Assert.Equal(new[] { "Name\tPaper 2\tIA\nAna\t41\t18\nDan\t45\t22" }, P(new[]
    {
        L("Name", 0.10, 0.05, 0.15),
        L("Ana", 0.20, 0.05, 0.10),
        L("Dan", 0.30, 0.05, 0.10),
        W("Paper 2", 0.10, new[] { (0.32, 0.40), (0.41, 0.44) }),
        L("41", 0.20, 0.41, 0.44),
        L("45", 0.30, 0.41, 0.44),
        L("IA", 0.10, 0.455, 0.48),
        L("18", 0.20, 0.455, 0.48),
        L("22", 0.30, 0.455, 0.48),
    }, rules: _ => new[] { 0.25, 0.45 }));

    [Fact]
    public void Engine_line_across_grid_line_is_cut_between_words() => Assert.Equal(new[] { "Item\tBudget\t%\nRent\t1200\t48\nFood\t450" }, P(new[]
    {
        L("Item", 0.10, 0.05, 0.12),
        W("Budget %", 0.10, new[] { (0.30, 0.39), (0.41, 0.48) }),
        L("Rent", 0.20, 0.05, 0.12),
        W("1200 48", 0.20, new[] { (0.30, 0.39), (0.40, 0.48) }),
        L("Food", 0.30, 0.05, 0.12),
        L("450", 0.30, 0.33, 0.39),
    }, rules: _ => new[] { 0.2, 0.40 }));

    [Fact]
    public void Merged_cell_goes_to_first_column_it_spans() => Assert.Equal(
        new[] { "Day\tMon\tTue\tWed\n1\tMaths\tEnglish\tPhysics\nL\tLunch\n2\tArt\tFree\tTOK" }, P(new[]
        {
            L("Day", 0.10, 0.05, 0.12), L("Mon", 0.10, 0.25, 0.32), L("Tue", 0.10, 0.45, 0.52), L("Wed", 0.10, 0.65, 0.72),
            L("1", 0.20, 0.05, 0.07), L("Maths", 0.20, 0.25, 0.35), L("English", 0.20, 0.45, 0.57), L("Physics", 0.20, 0.65, 0.77),
            L("L", 0.30, 0.05, 0.07), L("Lunch", 0.30, 0.44, 0.54),
            L("2", 0.40, 0.05, 0.07), L("Art", 0.40, 0.25, 0.30), L("Free", 0.40, 0.45, 0.52), L("TOK", 0.40, 0.65, 0.71),
        }, rules: r => r.Y + r.Height / 2 is > 0.3 and < 0.35 ? new[] { 0.2 } : new[] { 0.2, 0.4, 0.6 }));

    [Fact]
    public void Stray_vertical_stroke_on_one_row_cuts_nothing() => Assert.Equal(
        new[] { "Subject\tLevel\nMaths\tMaths HL\nPhysics\tPhysics SL" }, P(new[]
        {
            L("Subject", 0.10, 0.05, 0.20), L("Level", 0.10, 0.30, 0.40),
            L("Maths", 0.20, 0.05, 0.15), W("Maths HL", 0.20, new[] { (0.30, 0.40), (0.41, 0.45) }),
            L("Physics", 0.30, 0.05, 0.17), W("Physics SL", 0.30, new[] { (0.30, 0.42), (0.43, 0.47) }),
        }, rules: r => r.Y + r.Height / 2 is > 0.2 and < 0.25 ? new[] { 0.405 } : Array.Empty<double>()));

    [Fact]
    public void Divider_beside_gridless_table_is_not_its_grid() => Assert.Equal(
        new[] { "Country\tCapital\tPop\nRomania\tBucharest\t19.0" }, P(new[]
        {
            L("Country", 0.10, 0.05, 0.19), L("Romania", 0.20, 0.05, 0.19),
            L("Capital", 0.10, 0.35, 0.47), L("Bucharest", 0.20, 0.35, 0.50),
            L("Pop", 0.10, 0.65, 0.70), L("19.0", 0.20, 0.65, 0.72),
        }, rules: _ => new[] { 0.3 }));

    [Fact]
    public void Gridless_row_read_as_one_line_is_cut_by_the_other_rows_columns() => Assert.Equal(
        new[] { "Country\tGold\tSilver\nNorway\t16\t8\nCanada\t11\t10" }, P(new[]
        {
            L("Country", 0.10, 0.05, 0.20), W("Gold Silver", 0.10, new[] { (0.30, 0.44), (0.45, 0.60) }),
            L("Norway", 0.20, 0.05, 0.18), L("16", 0.20, 0.38, 0.42), L("8", 0.20, 0.54, 0.56),
            L("Canada", 0.30, 0.05, 0.18), L("11", 0.30, 0.38, 0.42), L("10", 0.30, 0.52, 0.56),
        }));

    [Fact]
    public void Wrapped_table_cell_stays_in_its_row() => Assert.Equal(
        new[] { "Feature\tMeiosis\nDivisions\tTwo\nGenetic variation\tCrossing over and independent assortment" }, P(new[]
        {
            L("Feature", 0.10, 0.05, 0.15, 0.03),
            L("Divisions", 0.20, 0.05, 0.18, 0.03),
            L("Genetic variation", 0.30, 0.05, 0.30, 0.03),
            L("Meiosis", 0.10, 0.40, 0.52, 0.03),
            L("Two", 0.20, 0.40, 0.45, 0.03),
            L("Crossing over and", 0.30, 0.40, 0.65, 0.03),
            L("independent assortment", 0.335, 0.40, 0.70, 0.03),
        }));

    [Fact]
    public void Marks_at_the_right_join_their_question() => Assert.Equal(
        "3. A survey asked 120 students how they travel to school.\n"
        + "(a) Write down the number of students who walk to school.\t[1]\n"
        + "(b) Find the probability that a randomly chosen student travels by bus.\t[2]",
        string.Join("\n", P(new[]
        {
            L("3. A survey asked 120 students how they travel to school.", 0.05, 0.05, 0.80),
            L("(a) Write down the number of students who walk to school.", 0.15, 0.05, 0.75),
            L("[1]", 0.15, 0.90, 0.95),
            L("(b) Find the probability that a randomly chosen student travels by bus.", 0.25, 0.05, 0.85),
            L("[2]", 0.25, 0.90, 0.95),
        })));

    [Fact]
    public void Cells_of_a_wide_image_do_not_glue_together() => Assert.Equal(new[] { "Ana Ionescu\t78\t85" }, P(new[]
    {
        L("Ana Ionescu", 0.40, 0.03, 0.20, 0.08),
        L("78", 0.40, 0.40, 0.43, 0.08),
        L("85", 0.40, 0.55, 0.58, 0.08),
    }, new PxSize(1240, 282)));

    [Fact]
    public void Row_fragments_join_left_to_right() => Assert.Equal(new[] { "printf(\"%d\\n\", *p);" }, P(new[]
    {
        L(", *p);", 0.099, 0.40, 0.55),
        L("printf(\"%d\\n\"", 0.10, 0.10, 0.40),
    }));

    [Fact]
    public void Code_keeps_indentation_and_blank_lines() => Assert.Equal(
        new[] { "def grade(score):\n    if score >= 80:\n        return \"7\"\n\nprint(grade(90))" }, P(new[]
        {
            L("def grade(score):", 0.10, 0.05, 0.22, 0.04),
            L("if score >= 80:", 0.16, 0.09, 0.24, 0.04),
            L("return \"7\"", 0.22, 0.13, 0.23, 0.04),
            L("print(grade(90))", 0.34, 0.05, 0.21, 0.04),
        }));

    [Fact]
    public void Bracket_only_lines_set_the_blocks_indentation()
    {
        const double w = 560, h = 430;
        TextReflow.Line Px(string text, double x, double y, double width) => new(text, new PxRect(x / w, y / h, width / w, 27 / h));
        Assert.Equal("{\n  \"name\": \"ocr-bench\",\n  \"scripts\": {\n    \"test\": \"node --test\",\n  },\n  \"timeout\": 0.75\n}",
            string.Join("\n", P(new[]
            {
                Px("{", 37, 32, 15),
                Px("\"name\": \"ocr-bench\",", 66, 70, 312),
                Px("\"scripts\": {", 63, 175, 190),
                Px("\"test\": \"node --test\",", 98, 213, 342),
                Px("},", 69, 284, 31),
                Px("\"timeout\": 0.75", 66, 357, 236),
                Px("}", 37, 391, 15),
            }, new PxSize(w, h))));
    }

    [Fact]
    public void One_look_alike_swap_balances_a_code_lines_brackets()
    {
        Assert.Equal("on: [push, pull_request]", TextReflow.WithBalancedBrackets("on: Lpush, pull_request]"));
        Assert.Equal("guard ok else { return 0 }", TextReflow.WithBalancedBrackets("guard ok else i return 0 }"));
        Assert.Equal("print(mean([3, 4, 5]))", TextReflow.WithBalancedBrackets("print(mean([3, 4, 51))"));
        Assert.Equal("} else {", TextReflow.WithBalancedBrackets("} else {"));
        Assert.Equal("    return i }", TextReflow.WithBalancedBrackets("    return i }"));
        Assert.Equal("f(x) = [1, 2]", TextReflow.WithBalancedBrackets("f(x) = [1, 2]"));
    }

    [Fact]
    public void Code_cleanup_fixes_file_names_hashes_and_docstrings()
    {
        Assert.Equal("$ python3 main.py", TextReflow.CleanedCode("$ python3 main-py"));
        Assert.Equal("run: swift test --parallel", TextReflow.CleanedCode("run: swift test --parallel"));
        Assert.Equal("a1b2c3d Fix off-by-one", TextReflow.WithHexDigits("alb2c3d Fix off-by-one"));
        Assert.Equal("allowed deadbeef", TextReflow.WithHexDigits("allowed deadbeef"));
        Assert.Equal("\"\"\"Return the mean.\"\"\"", TextReflow.WithTripleQuotes("''\"Return the mean.''''"));
        Assert.Equal("'''raw'''", TextReflow.WithTripleQuotes("'''raw'''"));
    }

    [Fact]
    public void Code_uses_the_uncorrected_read()
    {
        var lines = new[]
        {
            new TextReflow.Line("const total = items. reduce (sum) = 0;", new PxRect(0.05, 0.1, 0.37, 0.04),
                RawText: "const total = items.reduce(sum) => 0;"),
            new TextReflow.Line("console. log (total);", new PxRect(0.05, 0.16, 0.21, 0.04), RawText: "console. log(total);"),
        };
        Assert.True(TextReflow.ContainsCode(lines));
        Assert.Equal(new[] { "const total = items.reduce(sum) => 0;\nconsole.log(total);" }, P(lines));
    }

    [Fact]
    public void Line_number_gutter_is_dropped() => Assert.Equal(new[] { "fn main() {\n    let x = 1;\n}" }, P(new[]
    {
        L("1", 0.10, 0.02, 0.03, 0.04),
        L("fn main() {", 0.10, 0.08, 0.19, 0.04),
        L("2", 0.16, 0.02, 0.03, 0.04),
        L("let x = 1;", 0.16, 0.12, 0.22, 0.04),
        L("3", 0.22, 0.02, 0.03, 0.04),
        L("}", 0.22, 0.08, 0.09, 0.04),
    }));

    [Fact]
    public void Nested_list_items_indent_by_level() => Assert.Equal(new[]
    {
        "• Fruit basket", "\t• Apples and pears", "\t\t• Conference", "• Vegetables",
    }, P(new[]
    {
        L("• Fruit basket", 0.10, 0.05, 0.25, 0.04),
        L("• Apples and pears", 0.16, 0.10, 0.30, 0.04),
        L("• Conference", 0.22, 0.15, 0.30, 0.04),
        L("• Vegetables", 0.28, 0.05, 0.20, 0.04),
    }));

    [Fact]
    public void Paragraph_continues_into_the_next_column() => Assert.Equal(new[]
    {
        "As the warm, moist air rises it cools, and the vapour condenses into tiny droplets that form clouds. When the "
        + "droplets combine and grow heavy enough, they fall back to the ground as precipitation.",
    }, P(new[]
    {
        L("As the warm, moist air rises it cools, and the", 0.10, 0.05, 0.45),
        L("vapour condenses into tiny droplets that form", 0.16, 0.05, 0.44),
        L("clouds. When the droplets combine and grow", 0.22, 0.05, 0.43),
        L("heavy enough, they fall back to the ground as", 0.10, 0.55, 0.94),
        L("precipitation.", 0.16, 0.55, 0.67),
    }));

    [Fact]
    public void Longest_line_ending_a_sentence_keeps_the_next_apart() => Assert.Equal(new[]
    {
        "Der Bär läuft über die Brücke.", "Le garçon a mangé une crème brûlée.", "El niño tiene cinco años.",
    }, P(new[]
    {
        L("Der Bär läuft über die Brücke.", 0.10, 0.05, 0.35),
        L("Le garçon a mangé une crème brûlée.", 0.16, 0.05, 0.40),
        L("El niño tiene cinco años.", 0.22, 0.05, 0.30),
    }));

    [Fact]
    public void Box_height_jitter_does_not_split_a_paragraph() => Assert.Equal(new[]
    {
        "Rivers carry these dissolved salts to the sea, where they accumulate over millions of years.",
    }, P(new[]
    {
        L("Rivers carry these dissolved salts to the sea, where they accumulate over millions of", 0.10, 0.05, 0.90, 0.069),
        L("years.", 0.17, 0.05, 0.11, 0.043),
    }));

    [Fact]
    public void Display_equations_stay_on_their_own_lines() => Assert.Equal(new[] { "2H₂ + O₂ → 2H₂O", "CO₂ + H₂O → H₂CO₃" }, P(new[]
    {
        L("2H₂ + O₂ → 2H₂O", 0.10, 0.05, 0.40),
        L("CO₂ + H₂O → H₂CO₃", 0.18, 0.05, 0.45),
    }));

    [Fact]
    public void Code_cleanup_fixes_engine_misreads()
    {
        Assert.Equal("return 0;", TextReflow.CleanedCode("return ø;"));
        Assert.Equal("File \"main.py\", in <module>", TextReflow.CleanedCode("File \"main.py\", in ‹module›"));
        Assert.Equal("console.log(label);", TextReflow.CleanedCode("console. log(label);"));
        Assert.Equal("# Done. Then run it", TextReflow.CleanedCode("# Done. Then run it"));
    }

    [Fact]
    public void Code_signals_ignore_prose_and_math()
    {
        Assert.True(TextReflow.LooksLikeCode("if (total === 0) {"));
        Assert.True(TextReflow.LooksLikeCode("runs-on: macos-15"));
        Assert.True(TextReflow.LooksLikeCode("$ python3 main.py"));
        Assert.False(TextReflow.LooksLikeCode("For example, a student who spends the evening"));
        Assert.False(TextReflow.LooksLikeCode("f(x) = x² + 1 and sin(x) = 0"));
    }

    // ------------------------------------------------------------------ math-line tidying (text only)

    [Fact]
    public void Math_lines_get_typeset_spacing_and_symbol_repairs()
    {
        Assert.Equal("F = ma", MathText.SpacedOperators("F= ma"));
        Assert.Equal("(x² - 9)", MathText.SpacedOperators("(x²-9)"));
        Assert.Equal("y = -1", MathText.SpacedOperators("y=-1"));
        Assert.Equal("x-axis", MathText.SpacedOperators("x-axis"));
        Assert.Equal("A ∩ B", MathText.RepairedMathSymbols("A n B"));
        Assert.Equal("x ∈ ℝ", MathText.RepairedMathSymbols("x E R"));
        Assert.Equal("|a|", MathText.RepairedMathSymbols("lal"));
        Assert.Equal("cos θ", MathText.RepairedMathSymbols("cosθ"));
        Assert.Equal("cost", MathText.SpacedFunctionArguments("cost")); // a word, not cos t
        Assert.True(MathText.IsMath("x² + y² = z²"));
        Assert.False(MathText.IsMath("The answer is = to the other students"));
    }

    [Fact]
    public void Word_list_is_absent_without_a_lookup()
    {
        var saved = WordList.Lookup;
        try
        {
            WordList.Lookup = null;
            Assert.Null(WordList.Contains("portfolio"));
            // No list: a broken word rejoins (like the Mac without /usr/share/dict/words).
            Assert.Equal("lightdependent", TextReflow.JoinWrapped("light-", "dependent"));
        }
        finally { WordList.Lookup = saved; }
    }
}

[CollectionDefinition("WordList", DisableParallelization = true)]
public class WordListCollection { }
