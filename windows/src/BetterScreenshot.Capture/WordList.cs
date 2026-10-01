namespace BetterScreenshot.Capture;

/// <summary>
/// An English word list for line-end hyphens (Mac <c>WordList</c>, which reads <c>/usr/share/dict/words</c>). Windows
/// has no such file; the app plugs in the offline Windows spell checker (<c>BetterScreenshot.Platform.SpellWordList</c>)
/// through <see cref="Lookup"/>. Null lookup = no list (a broken word then rejoins, like the Mac without one).
/// </summary>
public static class WordList
{
    /// <summary>Whether a lower-case word is a known English word. Set once at startup.</summary>
    public static Func<string, bool>? Lookup { get; set; }

    private static readonly (string Ending, string Replacement)[] Endings =
    {
        ("ies", "y"), ("ied", "y"), ("es", ""), ("s", ""), ("ed", ""), ("ed", "e"), ("d", ""), ("ing", ""), ("ing", "e"),
        ("ly", ""), ("er", ""), ("ers", ""), ("est", ""), ("ness", ""), ("ment", ""), ("ments", ""),
    };

    /// <summary>Whether <paramref name="word"/> (or its stem: <c>reactions</c> → <c>reaction</c>, <c>studied</c> →
    /// <c>study</c>) is an English word; null when there is no word list.</summary>
    public static bool? Contains(string word)
    {
        if (Lookup is not { } lookup) return null;
        string w = word.ToLowerInvariant();
        if (w.Length == 0) return false;
        if (lookup(w)) return true;
        foreach (var (ending, replacement) in Endings)
        {
            if (!w.EndsWith(ending, StringComparison.Ordinal) || w.Length <= ending.Length + 2) continue;
            string stem = w[..^ending.Length];
            if (lookup(stem + replacement)) return true;
            // A doubled consonant: `running` → `run`.
            if (stem.Length >= 2 && stem[^1] == stem[^2] && lookup(stem[..^1])) return true;
        }
        return false;
    }
}
