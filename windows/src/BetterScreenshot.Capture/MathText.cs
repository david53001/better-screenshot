using System.Text;
using System.Text.RegularExpressions;

namespace BetterScreenshot.Capture;

/// <summary>
/// The cheap, text-only tidying of math lines (Mac <c>MathLayout.spacedOperators</c> / <c>repairedMathSymbols</c> /
/// <c>spacedFunctionArguments</c> / <c>isMath</c>; v3 §8.1: these still run with "Recognize math" off). No pixels.
/// </summary>
public static class MathText
{
    /// <summary>The Unicode superscripts / subscripts of the clipboard contract (v3 §8.2).</summary>
    public const string Superscripts = "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖʳˢᵗᵘᵛʷˣʸᶻ";
    public const string Subscripts = "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ";

    private const string MathMarks = "=≤≥≠→⇒⇔±×÷∑∫√∞" + Superscripts + Subscripts;

    /// <summary>A line of mostly-math: separate display equations are separate lines.</summary>
    public static bool IsMath(string text) =>
        text.Any(c => MathMarks.Contains(c))
        && text.Split(' ').Count(w => w.Length > 3 && w.All(char.IsLetter)) <= 1;

    /// <summary>Operators on a math line spaced the way it is typeset (<c>F= ma</c> → <c>F = ma</c>): relations always,
    /// <c>+</c> and <c>-</c> only between two operands (<c>-3</c>, <c>(-x)</c>, <c>= -1</c> stay tight), never inside a
    /// word (<c>x-axis</c>, <c>Cobb-Douglas</c>).</summary>
    public static string SpacedOperators(string text)
    {
        static bool Operand(char? c) => c is { } ch
            && (char.IsLetter(ch) || char.IsNumber(ch) || ")]′'!".Contains(ch) || Superscripts.Contains(ch) || Subscripts.Contains(ch));
        static bool Opens(char? c) => c is { } ch && (char.IsLetter(ch) || char.IsNumber(ch) || "([√".Contains(ch));
        var chars = text.ToCharArray();
        var output = new StringBuilder();
        int i = 0;
        while (i < chars.Length)
        {
            char c = chars[i];
            int before = i - 1;
            while (before >= 0 && chars[before] == ' ') before--;
            int after = i + 1;
            while (after < chars.Length && chars[after] == ' ') after++;
            char? prev = before >= 0 ? chars[before] : null;
            char? next = after < chars.Length ? chars[after] : null;
            bool relation = "=≤≥≠≈→⇒⇔".Contains(c) && prev is { } p && next is { } n && !"=<>!".Contains(p) && !"=<>".Contains(n);
            bool binary = "×÷".Contains(c) && Operand(prev) && Opens(next);
            if ((c == '+' || c == '-') && Operand(prev) && Opens(next))
            {
                // Letters touching both sides, one side a word: a hyphen.
                int left = 0;
                for (int k = i - 1; k >= 0 && char.IsLetter(chars[k]); k--) left++;
                int right = 0;
                for (int k = i + 1; k < chars.Length && char.IsLetter(chars[k]); k++) right++;
                binary = !(left >= 1 && right >= 1 && Math.Max(left, right) >= 2);
            }
            if (relation || binary)
            {
                while (output.Length > 0 && output[^1] == ' ') output.Length--;
                output.Append(' ').Append(c).Append(' ');
                i = after;
            }
            else
            {
                output.Append(c);
                i++;
            }
        }
        return output.ToString();
    }

    /// <summary>Set symbols the engine reads as letters, by what surrounds them (<c>A n B</c> → <c>A ∩ B</c>,
    /// <c>x E R</c> → <c>x ∈ ℝ</c>), a stray <c>.</c> after <c>=</c>, a space after a comma between terms, <c>lal</c> →
    /// <c>|a|</c>, trig names with digit look-alikes, a dot product, a lone x between two fractions.</summary>
    public static string RepairedMathSymbols(string text)
    {
        string output = text;
        foreach (var (pattern, template) in MathRepairs) output = pattern.Replace(output, template);
        return SpacedFunctionArguments(output);
    }

    private static readonly (Regex, string)[] MathRepairs = new (string, string)[]
    {
        (@"(?<=[A-Z)] )n(?= [A-Z(])", "∩"),
        (@"(?<=[A-Z)] )U(?= [A-Z(])", "∪"),
        (@"(?<=\b[a-z] )[E€](?= [A-Z]\b)", "∈"),
        (@"(?<=∈ )N\b", "ℕ"), (@"(?<=∈ )Z\b", "ℤ"), (@"(?<=∈ )Q\b", "ℚ"), (@"(?<=∈ )R\b", "ℝ"),
        (@"= ?\.(?= |$)", "="),
        (@",(?=[^\s\d])|(?<=[^\d]),(?=\d)", ", "),
        (@"(?<![A-Za-z])l([a-zA-Z])l(?![A-Za-z])", "|$1|"),
        (@"\| ([a-zA-Z])\|", "|$1|"),
        (@"√\((\d+(?:\.\d+)?)\)", "√$1"),
        (@"(?<![A-Za-z])c[0O]s(?=[\s\dA-Za-zθ(])", "cos"),
        (@"(?<![A-Za-z])s[1l|]n(?=[\s\dA-Za-zθ(])", "sin"),
        (@"(?<=[\w)|]) ?[•·] ?(?=[\w(|])", " · "),
        (@"(?<=/[\w)]{1,12}) [xX] (?=[\w(]{1,12}/)", " × "),
    }.Select(p => (new Regex(p.Item1, RegexOptions.Compiled), p.Item2)).ToArray();

    private static readonly Regex FunctionArgument = new(
        @"(?<![A-Za-z])(sin|cos|tan|sec|csc|cot|log|ln|exp|det)(?=\d|[a-zA-Zθ](?![A-Za-z]))", RegexOptions.Compiled);

    private static readonly HashSet<string> Trig = new() { "sin", "cos", "tan", "sec", "csc", "cot" };

    /// <summary><c>cosθ</c>, <c>sinx</c>, <c>sin3x</c> → <c>cos θ</c>, <c>sin x</c>, <c>sin 3x</c> — unless the letter
    /// makes a word (<c>cost</c>, <c>sine</c>, <c>sect</c>).</summary>
    public static string SpacedFunctionArguments(string text)
    {
        var output = new StringBuilder(text);
        foreach (Match m in FunctionArgument.Matches(text).Reverse())
        {
            var name = m.Groups[1];
            int end = name.Index + name.Length;
            char next = text[end];
            if (char.IsLetter(next) && WordList.Contains(name.Value + next) == true) continue;
            if (char.IsNumber(next) && !Trig.Contains(name.Value)) continue;
            output.Insert(end, ' ');
        }
        return output.ToString();
    }
}
