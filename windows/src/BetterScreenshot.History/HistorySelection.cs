namespace BetterScreenshot.History;

/// <summary>Which modifier a History click carried: none, Ctrl (the Mac's ⌘ — toggle), or Shift (range).</summary>
public enum HistoryClickModifier { None, Toggle, Range }

/// <summary>
/// The History grid's selection (v3 §4.4; Mac <c>HistoryKit/HistorySelection.swift</c>, ported 1:1): a set of entry ids
/// and the anchor a Shift-click ranges from. <c>order</c> is always the displayed order (newest first). Pure.
/// </summary>
public sealed record HistorySelectionState(IReadOnlySet<Guid> Selected, Guid? Anchor)
{
    public static readonly HistorySelectionState Empty = new(new HashSet<Guid>(), null);

    public bool IsSelected(Guid id) => Selected.Contains(id);

    /// <summary>The selected ids in displayed order (what Copy / drag / Delete act on).</summary>
    public IReadOnlyList<Guid> InOrder(IReadOnlyList<Guid> order) => order.Where(Selected.Contains).ToList();
}

public static class HistorySelection
{
    /// <summary>
    /// none → just <paramref name="id"/>, anchored there; toggle → add/remove <paramref name="id"/>, anchored there;
    /// range → everything between the anchor and <paramref name="id"/> in display order, anchor unchanged — or, when
    /// the anchor is missing or was deleted, the same as a plain click.
    /// </summary>
    public static HistorySelectionState Click(HistorySelectionState state, Guid id, HistoryClickModifier modifier, IReadOnlyList<Guid> order)
    {
        switch (modifier)
        {
            case HistoryClickModifier.Toggle:
            {
                var set = new HashSet<Guid>(state.Selected);
                if (!set.Remove(id)) set.Add(id);
                return new HistorySelectionState(set, id);
            }
            case HistoryClickModifier.Range when state.Anchor is { } anchor:
            {
                int a = IndexOf(order, anchor), i = IndexOf(order, id);
                if (a < 0 || i < 0) goto default;
                int lo = Math.Min(a, i), hi = Math.Max(a, i);
                return new HistorySelectionState(new HashSet<Guid>(order.Skip(lo).Take(hi - lo + 1)), anchor);
            }
            default:
                return new HistorySelectionState(new HashSet<Guid> { id }, id);
        }
    }

    /// <summary>A drag starting on <paramref name="id"/>: an already-selected item drags the whole selection; otherwise
    /// the item is plain-clicked first. Returns the new state and the ids to drag, in displayed order.</summary>
    public static (HistorySelectionState State, IReadOnlyList<Guid> Dragged) DragStart(HistorySelectionState state, Guid id, IReadOnlyList<Guid> order)
    {
        var s = state.IsSelected(id) ? state : Click(state, id, HistoryClickModifier.None, order);
        return (s, s.InOrder(order));
    }

    /// <summary>Drops ids that are no longer listed (deleted, or pruned by the cap); a gone anchor becomes null.</summary>
    public static HistorySelectionState Prune(HistorySelectionState state, IReadOnlyList<Guid> order)
    {
        var live = new HashSet<Guid>(order);
        var kept = state.Selected.Where(live.Contains).ToHashSet();
        Guid? anchor = state.Anchor is { } a && live.Contains(a) ? a : null;
        return kept.Count == state.Selected.Count && anchor == state.Anchor ? state : new HistorySelectionState(kept, anchor);
    }

    /// <summary>Plain clicks apply on mouse-UP, so a mouse-down on a selected item can start a multi-item drag without
    /// collapsing the selection; modifier clicks apply on mouse-down as usual.</summary>
    public static bool AppliesOnMouseUp(HistorySelectionState state, Guid id, HistoryClickModifier modifier) =>
        modifier == HistoryClickModifier.None && state.IsSelected(id) && state.Selected.Count > 1;

    private static int IndexOf(IReadOnlyList<Guid> order, Guid id)
    {
        for (int i = 0; i < order.Count; i++) if (order[i] == id) return i;
        return -1;
    }
}
