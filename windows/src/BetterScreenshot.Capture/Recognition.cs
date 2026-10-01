namespace BetterScreenshot.Capture;

public enum RecognitionKind
{
    None,
    Qr,
    Text,
}

/// <summary>Result of a Capture-Text run: a decoded QR payload, recognized text, or nothing.</summary>
public readonly struct RecognitionResult : IEquatable<RecognitionResult>
{
    public RecognitionKind Kind { get; }
    public string Value { get; }

    private RecognitionResult(RecognitionKind kind, string value)
    {
        Kind = kind;
        Value = value;
    }

    public static readonly RecognitionResult None = new(RecognitionKind.None, string.Empty);
    public static RecognitionResult Qr(string payload) => new(RecognitionKind.Qr, payload);
    public static RecognitionResult Text(string text) => new(RecognitionKind.Text, text);

    public string? ClipboardString => Kind == RecognitionKind.None ? null : Value;

    public string HudMessage => Kind switch
    {
        RecognitionKind.Qr => "QR code copied",
        RecognitionKind.Text => $"Text copied — {Value.Length} characters",
        _ => "No text found",
    };

    public bool Equals(RecognitionResult other) => Kind == other.Kind && Value == other.Value;
    public override bool Equals(object? obj) => obj is RecognitionResult r && Equals(r);
    public override int GetHashCode() => HashCode.Combine(Kind, Value);
    public static bool operator ==(RecognitionResult a, RecognitionResult b) => a.Equals(b);
    public static bool operator !=(RecognitionResult a, RecognitionResult b) => !a.Equals(b);
}

/// <summary>
/// Pure decision rule for Capture Text (Mac <c>RecognitionResolver</c>, v3 §8.2). Text lines (one per paragraph, table
/// row or code block after <see cref="TextReflow"/>) join with newlines; blank ones drop. A QR code that fills the
/// selection (<see cref="DominantQrArea"/>) is what the user was after, so its payload wins; a small one on a poster
/// or slide is appended to the text instead of replacing it (unless the text already prints it).
/// </summary>
public static class RecognitionResolver
{
    /// <summary>A QR code covering this share of the selection is what the user was after.</summary>
    public const double DominantQrArea = 0.2;

    public static RecognitionResult Resolve(IReadOnlyList<string> qrPayloads, IReadOnlyList<string> textLines, bool qrDominant = false)
    {
        var qrs = qrPayloads.Where(q => !string.IsNullOrEmpty(q)).ToList();
        var kept = textLines.Where(l => !string.IsNullOrEmpty(l)).ToList();
        if (qrs.Count > 0 && (qrDominant || kept.Count == 0)) return RecognitionResult.Qr(qrs[0]);
        if (kept.Count == 0) return RecognitionResult.None;
        string text = string.Join("\n", kept);
        return RecognitionResult.Text(string.Join("\n", new[] { text }.Concat(qrs.Where(q => !text.Contains(q, StringComparison.Ordinal)))));
    }

    /// <summary>The share of a <paramref name="width"/>×<paramref name="height"/> selection a QR code covers, from its
    /// finder-pattern centres (ZXing's result points) and module size: each centre sits 3.5 modules in from its corner.</summary>
    public static double QrCoverage(IReadOnlyList<(double X, double Y)> finderCentres, double moduleSize, int width, int height)
    {
        if (finderCentres.Count < 3 || width <= 0 || height <= 0) return 0;
        double w = finderCentres.Max(p => p.X) - finderCentres.Min(p => p.X) + 7 * moduleSize;
        double h = finderCentres.Max(p => p.Y) - finderCentres.Min(p => p.Y) + 7 * moduleSize;
        return Math.Clamp(w * h / ((double)width * height), 0, 1);
    }
}
