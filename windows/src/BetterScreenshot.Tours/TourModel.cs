namespace BetterScreenshot.Tours;

/// <summary>Persisted tour ids (Mac v3 §7.2 <c>TourID</c>) — the raw values are stored in settings; never rename.</summary>
public enum TourId { Welcome, QuickAccess, Editor, Text, Redaction, Highlighter, Spotlight, FirstRecording, RecordingPill, VideoEditor, Settings, History }

/// <summary>A window a tour runs on.</summary>
public enum TourSurface { Welcome, QuickAccess, Editor, RecordStrip, RecordingPill, VideoEditor, Settings, History }

/// <summary>Where a step's tag goes (§7.3 Placement); <see cref="Automatic"/> lets the layout decide.</summary>
public enum TagPlacement { Automatic, Left, Right, Above, Below, InsideCorner }

public enum TourEventKind { CaptureTaken, ToolSelected, AnnotationAdded, StyleChanged, MenuOpened, ChoiceMade, Action }

/// <summary>Something the user did. Two events are equal only if kind and name match exactly.</summary>
public readonly record struct TourEvent(TourEventKind Kind, string Name = "")
{
    public static TourEvent CaptureTaken => new(TourEventKind.CaptureTaken);
    public static TourEvent ToolSelected(string tool) => new(TourEventKind.ToolSelected, tool);
    public static TourEvent AnnotationAdded(string tool) => new(TourEventKind.AnnotationAdded, tool);
    public static TourEvent StyleChanged(string field) => new(TourEventKind.StyleChanged, field);
    public static TourEvent MenuOpened(string anchor) => new(TourEventKind.MenuOpened, anchor);
    public static TourEvent ChoiceMade(string anchor) => new(TourEventKind.ChoiceMade, anchor);
    public static TourEvent Action(string name) => new(TourEventKind.Action, name);
}

/// <summary>An Explain step advances on Next; a Try step advances when <see cref="AdvanceOn"/> is posted (or Skip Step).</summary>
public sealed record TourStep(string Anchor, string Title, string Body, TourEvent? AdvanceOn = null,
    TourEvent? Requires = null, TagPlacement Placement = TagPlacement.Automatic)
{
    public bool IsTry => AdvanceOn is not null;
}

public enum TriggerKind { SurfaceShown, Event, StartedByApp }

public readonly record struct TourTrigger(TriggerKind Kind, TourSurface Surface = default, TourEvent Event = default)
{
    public static TourTrigger Shown(TourSurface s) => new(TriggerKind.SurfaceShown, s);
    public static TourTrigger On(TourEvent e) => new(TriggerKind.Event, Event: e);
    public static TourTrigger ByApp => new(TriggerKind.StartedByApp);
}

public sealed record Tour(TourId Id, TourSurface Surface, TourTrigger Trigger, IReadOnlyList<TourStep> Steps,
    TourId? HandsOverTo = null, int Version = 1);

public static class TourIds
{
    /// <summary>The persisted raw value ("welcome", "quickAccess", …).</summary>
    public static string Raw(this TourId id) => char.ToLowerInvariant(id.ToString()[0]) + id.ToString()[1..];

    public static TourId? Parse(string raw) =>
        Enum.GetValues<TourId>().FirstOrDefault(t => t.Raw() == raw) is var t && t.Raw() == raw ? t : null;

    /// <summary>Help &amp; Tours menu title (Mac <c>TourID.menuTitle</c>).</summary>
    public static string MenuTitle(this TourId id) => id switch
    {
        TourId.Welcome => "Take the Welcome Tour",
        TourId.QuickAccess => "Quick Access Tour",
        TourId.Editor => "Editor Tour",
        TourId.Text => "Text Tool Tour",
        TourId.Redaction => "Blur & Pixelate Tour",
        TourId.Highlighter => "Highlighter Tour",
        TourId.Spotlight => "Spotlight Tour",
        TourId.FirstRecording => "Recording Setup Tour",
        TourId.RecordingPill => "Recording Controls Tour",
        TourId.VideoEditor => "Video Editor Tour",
        TourId.Settings => "Settings Tour",
        _ => "History Tour",
    };
}
