namespace BetterScreenshot.App.Overlays;

public enum QuickAccessKind { Screenshot, Recording }

/// <summary>Why a Quick Access card went away (Closed/Evicted are restorable; ActionTaken is not).</summary>
public enum DismissReason { Closed, Evicted, ActionTaken }

/// <summary>Callbacks the Quick Access card invokes for each action button.</summary>
public sealed class QuickAccessActions
{
    public Action OnCopy { get; init; } = () => { };
    public Action OnSave { get; init; } = () => { };
    public Action OnEdit { get; init; } = () => { };
    public Action OnOpen { get; init; } = () => { };
    public Action OnReveal { get; init; } = () => { };
}
