namespace BetterScreenshot.Capture;

/// <summary>
/// The Welcome page's shortcut grid (review O1–O2, Mac <c>HotkeyCheatSheet</c>): the user's live bindings in tray-menu
/// order — the three screenshot captures, Capture Text, then Record — each with a plain description. Unbound actions
/// are left out. Pure.
/// </summary>
public static class HotkeyCheatSheet
{
    public sealed record Row(HotkeyAction Action, string Keys, string Description)
    {
        /// <summary>One of the three screenshot captures (the rows the Welcome tour's "Capture shortcuts" step outlines).</summary>
        public bool IsScreenshotCapture => Action is HotkeyAction.CaptureArea or HotkeyAction.CaptureWindow or HotkeyAction.CaptureFullscreen;
    }

    private static readonly (HotkeyAction Action, string Description)[] Order =
    {
        (HotkeyAction.CaptureArea, "Capture an area"),
        (HotkeyAction.CaptureWindow, "Capture a window"),
        (HotkeyAction.CaptureFullscreen, "Capture the full screen"),
        (HotkeyAction.CaptureText, "Copy text from the screen"),
        (HotkeyAction.Record, "Record the screen"),
    };

    public static IReadOnlyList<Row> Rows(HotkeyBindings bindings) =>
        Order.Where(o => bindings.Combo(o.Action) is not null)
            .Select(o => new Row(o.Action, bindings.Combo(o.Action)!.Value.DisplayString, o.Description))
            .ToList();
}
