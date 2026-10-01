using System.Drawing;
using BetterScreenshot.App.Branding;
using BetterScreenshot.Capture;
using BetterScreenshot.Tours;
using WF = System.Windows.Forms;

namespace BetterScreenshot.App.Tray;

/// <summary>
/// The system-tray presence (macOS menu-bar equivalent): a WinForms <see cref="WF.NotifyIcon"/> with the full
/// context menu. Swaps to a red icon + elapsed tooltip while recording, and toggles the Record/Pause menu items.
/// </summary>
public sealed class TrayIcon : IDisposable
{
    private readonly WF.NotifyIcon _notify;
    private readonly Icon _normalIcon;
    private readonly Icon _recordingIcon;
    private readonly WF.ToolStripMenuItem _recordItem;
    private readonly WF.ToolStripMenuItem _pauseResumeItem;
    private readonly Dictionary<HotkeyAction, WF.ToolStripMenuItem> _actionItems = new();
    private readonly WF.ContextMenuStrip _menu;
    private readonly WF.ToolStripMenuItem _settingsItem;

    public TrayIcon(IAppCommands commands, HotkeyBindings bindings)
    {
        _normalIcon = AppIconFactory.CreateTrayIcon(recording: false);
        _recordingIcon = AppIconFactory.CreateTrayIcon(recording: true);

        _recordItem = Item("Record Screen…", bindings.Combo(HotkeyAction.Record)?.DisplayString, commands.ToggleRecording, HotkeyAction.Record, "record-circle");
        _pauseResumeItem = Item("Pause Recording", bindings.Combo(HotkeyAction.PauseResumeRecording)?.DisplayString, commands.PauseResumeRecording, HotkeyAction.PauseResumeRecording, "pause");
        _pauseResumeItem.Visible = false;

        _settingsItem = Item("Settings…", null, commands.OpenSettings, icon: "gear");
        var menu = _menu = new WF.ContextMenuStrip();
        menu.Renderer = new DarkMenuRenderer();
        // Review X6: an icon on every item, so the titles line up (Record/Stop and Pause/Resume swap theirs).
        int side = MenuIcons.SidePx;
        menu.ImageScalingSize = new Size(side, side);
        menu.Items.AddRange(new WF.ToolStripItem[]
        {
            Item("Capture Area", bindings.Combo(HotkeyAction.CaptureArea)?.DisplayString, commands.CaptureArea, HotkeyAction.CaptureArea, "rect-dashed"),
            Item("Capture Window", bindings.Combo(HotkeyAction.CaptureWindow)?.DisplayString, commands.CaptureWindow, HotkeyAction.CaptureWindow, "window"),
            Item("Capture Full Screen", bindings.Combo(HotkeyAction.CaptureFullscreen)?.DisplayString, commands.CaptureFullscreen, HotkeyAction.CaptureFullscreen, "display"),
            Item("Capture Text", bindings.Combo(HotkeyAction.CaptureText)?.DisplayString, commands.CaptureText, HotkeyAction.CaptureText, "text"),
            new WF.ToolStripSeparator(),
            _recordItem,
            _pauseResumeItem,
            new WF.ToolStripSeparator(),
            Item("Pin from Clipboard", bindings.Combo(HotkeyAction.PinFromClipboard)?.DisplayString, commands.PinFromClipboard, HotkeyAction.PinFromClipboard, "pin"),
            new WF.ToolStripSeparator(),
            Item("History…", bindings.Combo(HotkeyAction.OpenHistory)?.DisplayString, commands.OpenHistory, HotkeyAction.OpenHistory, "photo"),
            Item("Restore Recently Closed", bindings.Combo(HotkeyAction.RestoreRecentlyClosed)?.DisplayString, commands.RestoreRecentlyClosed, HotkeyAction.RestoreRecentlyClosed, "undo"),
            new WF.ToolStripSeparator(),
            _settingsItem,
            Item("Quit", null, commands.Quit, icon: "close"),
        });

        _notify = new WF.NotifyIcon
        {
            Icon = _normalIcon,
            Visible = true,
            Text = "BetterScreenshot",
            ContextMenuStrip = menu,
        };
        // Left-click opens the menu too (like the macOS menu-bar item).
        _notify.MouseClick += (_, e) =>
        {
            if (e.Button == WF.MouseButtons.Left) ShowMenu(menu);
        };
    }

    /// <summary>
    /// Help &amp; Tours ▸ (Mac v3 §7.8), right above Settings…: Take the Welcome Tour · each tour · Reset All Tours.
    /// </summary>
    public void AddHelpMenu(Action<TourId> replay, Action resetAll)
    {
        var help = new WF.ToolStripMenuItem("Help && Tours") { Image = MenuIcons.Get("info") }; // && = a literal ampersand (WinForms mnemonics)
        var drop = (WF.ToolStripDropDownMenu)help.DropDown;
        drop.Renderer = new DarkMenuRenderer();
        drop.ShowImageMargin = false;
        help.DropDownItems.Add(Item("Take the Welcome Tour", null, () => replay(TourId.Welcome)));
        help.DropDownItems.Add(new WF.ToolStripSeparator());
        foreach (var id in Enum.GetValues<TourId>().Where(t => t != TourId.Welcome))
        {
            var tour = id;
            help.DropDownItems.Add(Item(id.MenuTitle().Replace("&", "&&"), null, () => replay(tour)));
        }
        help.DropDownItems.Add(new WF.ToolStripSeparator());
        help.DropDownItems.Add(Item("Reset All Tours", null, resetAll));
        _menu.Items.Insert(_menu.Items.IndexOf(_settingsItem), help);
    }

    public void SetRecordingState(bool recording, string? elapsed)
    {
        _notify.Icon = recording ? _recordingIcon : _normalIcon;
        _notify.Text = recording ? Trim($"BetterScreenshot — {elapsed}") : "BetterScreenshot";
        _recordItem.Text = recording ? "Stop Recording" : "Record Screen…";
        _recordItem.Image = MenuIcons.Get(recording ? "stop-circle" : "record-circle");
        _pauseResumeItem.Visible = recording;
    }

    /// <summary>Reflects pause state on the Pause/Resume menu item: visible while a session is active, text flips.</summary>
    public void SetPauseState(bool active, bool paused)
    {
        _pauseResumeItem.Visible = active;
        _pauseResumeItem.Text = paused ? "Resume Recording" : "Pause Recording";
        _pauseResumeItem.Image = MenuIcons.Get(paused ? "play" : "pause");
    }

    /// <summary>Refreshes the shortcut hints after a rebind in Settings (the menu is long-lived).</summary>
    public void UpdateShortcuts(HotkeyBindings bindings)
    {
        foreach (var (action, item) in _actionItems)
            item.ShortcutKeyDisplayString = bindings.Combo(action)?.DisplayString ?? string.Empty;
    }

    private static void ShowMenu(WF.ContextMenuStrip menu)
    {
        menu.Show(WF.Cursor.Position);
    }

    private WF.ToolStripMenuItem Item(string text, string? shortcut, Action onClick, HotkeyAction? action = null, string? icon = null)
    {
        var item = new WF.ToolStripMenuItem(text) { Image = icon is null ? null : MenuIcons.Get(icon) };
        if (!string.IsNullOrEmpty(shortcut)) item.ShortcutKeyDisplayString = shortcut;
        item.Click += (_, _) => onClick();
        if (action is { } a) _actionItems[a] = item;
        return item;
    }

    // NotifyIcon.Text has a 63-char limit.
    private static string Trim(string s) => s.Length <= 63 ? s : s[..63];

    public void Dispose()
    {
        _notify.Visible = false;
        _notify.Dispose();
        _normalIcon.Dispose();
        _recordingIcon.Dispose();
    }
}
