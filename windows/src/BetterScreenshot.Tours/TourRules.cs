using System.Text;
using System.Text.RegularExpressions;

namespace BetterScreenshot.Tours;

public enum TourAudienceKind { New, Existing }

/// <summary>What the first launch with tours can see (§7.1 Step 1).</summary>
public sealed record AudienceSignals(string? AppId, IReadOnlyCollection<string> PreferenceKeys, bool DataFolderHasContent, bool CapturePermissionGranted);

/// <summary>
/// Who gets tours (Mac v3 §7.1 <c>TourAudience</c>) — new users only, asked first. When in doubt: existing (a missed
/// new user loses nothing; a nagged existing user is what the owner forbade).
/// </summary>
public static class TourAudience
{
    /// <summary>The five tour keys — the only preference keys a "new" user may already have.</summary>
    public static readonly IReadOnlySet<string> TourKeys = new HashSet<string>
    {
        "tourAudience", "tourQuestionAnswered", "firstUseToursEnabled", "toursSeen", "toursPaused",
    };

    public static TourAudienceKind Classify(AudienceSignals s, string expectedAppId)
    {
        if (string.IsNullOrEmpty(s.AppId) || s.AppId != expectedAppId) return TourAudienceKind.Existing;
        if (s.PreferenceKeys.Any(k => !TourKeys.Contains(k))) return TourAudienceKind.Existing;
        if (s.DataFolderHasContent) return TourAudienceKind.Existing;
        if (s.CapturePermissionGranted) return TourAudienceKind.Existing;
        return TourAudienceKind.New;
    }

    /// <summary>Stored value: absent → not classified yet; exactly "new" → new; anything else → existing.</summary>
    public static TourAudienceKind? Parse(string? stored) =>
        stored is null ? null : stored == "new" ? TourAudienceKind.New : TourAudienceKind.Existing;

    public static string Store(TourAudienceKind kind) => kind == TourAudienceKind.New ? "new" : "existing";
}

/// <summary>When to ask, open Welcome, and start a tour by itself (Mac v3 §7.1 <c>TourRules</c>).</summary>
public static class TourRules
{
    public static bool ShouldAskQuestion(TourAudienceKind? audience, bool answered) =>
        audience == TourAudienceKind.New && !answered;

    public static bool ShouldOpenWelcomeOnLaunch(TourAudienceKind? audience, bool answered, bool permissionGranted) =>
        audience == TourAudienceKind.New && !answered && permissionGranted;

    /// <summary>Only with first-use tours on (absent = off) and this version not yet seen.</summary>
    public static bool ShouldAutoStart(Tour tour, bool? firstUseToursEnabled, int? seenVersion) =>
        firstUseToursEnabled == true && (seenVersion is null || seenVersion < tour.Version);

    public static string ResetConfirmation(bool firstUseToursEnabled) =>
        firstUseToursEnabled ? "Tours reset" : "Tours reset — turn on Tours & tips to see them again";
}

/// <summary><c>{shortcut:&lt;action&gt;}</c> placeholders in tour bodies (Mac v3 §7.2 <c>TourText</c>).</summary>
public static class TourText
{
    private static readonly Regex Placeholder = new(@"\{shortcut:([A-Za-z0-9]+)\}", RegexOptions.Compiled);

    /// <summary>Replaces each placeholder whose name <paramref name="resolve"/> knows (non-null); unknown names stay as typed.</summary>
    public static string Resolve(string body, Func<string, string?> resolve) =>
        Placeholder.Replace(body, m => resolve(m.Groups[1].Value) ?? m.Value);

    /// <summary>The placeholder names in order.</summary>
    public static IReadOnlyList<string> Names(string body) => Placeholder.Matches(body).Select(m => m.Groups[1].Value).ToList();
}
