namespace BetterScreenshot.Capture;

/// <summary>
/// Pure Capture-Text tuning rules (Mac v2.10.0, <c>TextRecognizer.recognitionLanguages</c> / <c>upscaleFactor</c>).
/// </summary>
public static class OcrTuning
{
    /// <summary>Maps the user's preferred languages (e.g. <c>en-RO</c>, <c>ro-RO</c>) onto the languages the OCR
    /// engine supports, by exact tag first then by language code, keeping order and dropping duplicates; falls back
    /// to <c>en-US</c>. Explicit languages replace auto-detection, which leaked CJK punctuation into Latin text.</summary>
    public static IReadOnlyList<string> RecognitionLanguages(IEnumerable<string> preferred, IReadOnlyList<string> supported)
    {
        var result = new List<string>();
        foreach (var lang in preferred)
        {
            string code = LanguageCode(lang);
            string? match = supported.FirstOrDefault(s => string.Equals(s, lang, StringComparison.OrdinalIgnoreCase))
                            ?? supported.FirstOrDefault(s => string.Equals(LanguageCode(s), code, StringComparison.OrdinalIgnoreCase));
            if (match != null && !result.Contains(match)) result.Add(match);
        }
        return result.Count == 0 ? new[] { "en-US" } : result;
    }

    /// <summary>Scale that brings a capture to 2× pixel density (pixels per DIP); 1 when it already is. At 1× the
    /// OCR fragments lines and misreads small text.</summary>
    public static double UpscaleFactor(int pixelWidth, double dipWidth)
    {
        if (pixelWidth <= 0 || dipWidth <= 0) return 1;
        return Math.Max(1, dipWidth * 2 / pixelWidth);
    }

    /// <summary><paramref name="factor"/> reduced so neither upscaled side exceeds <paramref name="maxDimension"/>
    /// (never below 1).</summary>
    public static double ClampToMaxDimension(double factor, int pixelWidth, int pixelHeight, int maxDimension)
    {
        int longest = Math.Max(pixelWidth, pixelHeight);
        if (longest <= 0 || maxDimension <= 0) return 1;
        return Math.Max(1, Math.Min(factor, (double)maxDimension / longest));
    }

    /// <summary>Romanian letters with a comma below (v3 §8.2): engines return the cedilla forms <c>ş ţ</c>; mapped
    /// when Romanian is the recognition language.</summary>
    public static string RomanianCommaBelow(string text, string languageTag) =>
        !LanguageCode(languageTag).Equals("ro", StringComparison.OrdinalIgnoreCase) ? text
            : text.Replace('ş', 'ș').Replace('ţ', 'ț').Replace('Ş', 'Ș').Replace('Ţ', 'Ț');

    private static string LanguageCode(string tag)
    {
        int i = tag.IndexOfAny(new[] { '-', '_' });
        return i < 0 ? tag : tag[..i];
    }
}
