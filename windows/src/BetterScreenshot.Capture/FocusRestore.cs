namespace BetterScreenshot.Capture;

/// <summary>
/// Return focus to the previous app after a screenshot (Mac v2.8.0, <c>FocusRestore.shouldRestore</c> +
/// <c>CaptureCoordinator.remember/restoreFrontmostApp</c>). Showing the selection overlay activates
/// BetterScreenshot (it needs the keyboard for Esc), which leaves the user's real app unfocused afterwards.
/// </summary>
public static class FocusRestore
{
    /// <summary>Restore only when there is a previous app and it isn't BetterScreenshot itself.</summary>
    public static bool ShouldRestore(int? previousProcessId, int ownProcessId) =>
        previousProcessId is { } previous && previous != ownProcessId;
}

/// <summary>
/// Remembers who had focus when a screenshot entry point fired. Pure state machine over an opaque window handle
/// (<typeparamref name="THandle"/>) so the rules are testable without Win32:
/// <list type="number">
/// <item>Every screenshot entry point records the foreground window BEFORE anything is shown.</item>
/// <item>Our own window is never recorded. If ours is foreground while a selection is already up (a second
/// capture hotkey), the earlier, real target is kept; if ours is foreground and nothing is up (the capture
/// started from one of our own windows) the memory is cleared — there's nothing to hand back to.</item>
/// <item>Restoring never clears the memory, so a second hotkey during an open selection still has a target.</item>
/// </list>
/// </summary>
public sealed class FocusMemory<THandle> where THandle : struct
{
    public THandle? Remembered { get; private set; }
    public int? RememberedProcessId { get; private set; }

    public void Record(THandle foreground, int foregroundProcessId, int ownProcessId, bool selectionActive)
    {
        if (foregroundProcessId != ownProcessId)
        {
            Remembered = foreground;
            RememberedProcessId = foregroundProcessId;
        }
        else if (!selectionActive)
        {
            Remembered = null;
            RememberedProcessId = null;
        }
    }

    /// <summary>No foreground window at the hotkey (desktop / lock screen): an earlier target is stale, so forget it —
    /// unless our own selection is already up and the remembered window is the real one (review round 1 #19).</summary>
    public void RecordNothing(bool selectionActive)
    {
        if (selectionActive) return;
        Remembered = null;
        RememberedProcessId = null;
    }

    /// <summary>The window to reactivate, or null when <see cref="FocusRestore.ShouldRestore"/> says no.</summary>
    public THandle? RestoreTarget(int ownProcessId) =>
        FocusRestore.ShouldRestore(RememberedProcessId, ownProcessId) ? Remembered : null;
}
