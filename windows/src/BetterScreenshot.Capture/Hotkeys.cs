namespace BetterScreenshot.Capture;

/// <summary>Hotkey modifier flags. Values equal the Win32 MOD_* constants for direct use with RegisterHotKey.</summary>
[Flags]
public enum HotkeyModifiers
{
    None = 0,
    Alt = 0x0001,     // MOD_ALT
    Control = 0x0002, // MOD_CONTROL
    Shift = 0x0004,   // MOD_SHIFT
    Win = 0x0008,     // MOD_WIN
}

/// <summary>The user-bindable global commands.</summary>
public enum HotkeyAction
{
    CaptureArea,
    CaptureWindow,
    CaptureFullscreen,
    CaptureText,
    PinFromClipboard,
    Record,
    OpenHistory,
    RestoreRecentlyClosed,
    PauseResumeRecording,
}

public static class HotkeyActionInfo
{
    public static IReadOnlyList<HotkeyAction> All { get; } = Enum.GetValues<HotkeyAction>();

    public static string Title(this HotkeyAction a) => a switch
    {
        HotkeyAction.CaptureArea => "Capture Area",
        HotkeyAction.CaptureWindow => "Capture Window",
        HotkeyAction.CaptureFullscreen => "Capture Full Screen",
        HotkeyAction.CaptureText => "Capture Text",
        HotkeyAction.PinFromClipboard => "Pin from Clipboard",
        HotkeyAction.Record => "Record Screen",
        HotkeyAction.OpenHistory => "Open History",
        HotkeyAction.RestoreRecentlyClosed => "Restore Recently Closed",
        HotkeyAction.PauseResumeRecording => "Pause / Resume Recording",
        _ => a.ToString(),
    };

    /// <summary>Windows default bindings (Cmd→Ctrl from the macOS app): Ctrl+Shift+4/8/6/7/5; the rest unbound.</summary>
    public static HotkeyCombo? DefaultCombo(this HotkeyAction a)
    {
        const HotkeyModifiers cs = HotkeyModifiers.Control | HotkeyModifiers.Shift;
        return a switch
        {
            HotkeyAction.CaptureArea => new HotkeyCombo(0x34, cs),       // '4'
            HotkeyAction.CaptureWindow => new HotkeyCombo(0x38, cs),     // '8'
            HotkeyAction.CaptureFullscreen => new HotkeyCombo(0x36, cs), // '6'
            HotkeyAction.CaptureText => new HotkeyCombo(0x37, cs),       // '7'
            HotkeyAction.Record => new HotkeyCombo(0x35, cs),            // '5'
            _ => null,
        };
    }
}

/// <summary>A global hotkey: a Windows virtual-key code plus modifier flags.</summary>
public readonly record struct HotkeyCombo(uint Vk, HotkeyModifiers Modifiers)
{
    /// <summary>A usable global hotkey needs a non-Shift modifier (Ctrl/Alt/Win) so it does not shadow typing.</summary>
    public bool IsValid => (Modifiers & (HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.Win)) != 0;

    public string DisplayString
    {
        get
        {
            var parts = new List<string>(5);
            if (Modifiers.HasFlag(HotkeyModifiers.Control)) parts.Add("Ctrl");
            if (Modifiers.HasFlag(HotkeyModifiers.Alt)) parts.Add("Alt");
            if (Modifiers.HasFlag(HotkeyModifiers.Shift)) parts.Add("Shift");
            if (Modifiers.HasFlag(HotkeyModifiers.Win)) parts.Add("Win");
            parts.Add(KeyName(Vk));
            return string.Join("+", parts);
        }
    }

    public string ToPersisted() => $"{Vk},{(int)Modifiers}";

    /// <summary>Parses "vk,modifiers"; returns null on malformed input. The "unbound" sentinel is handled by the caller.</summary>
    public static HotkeyCombo? FromPersisted(string s)
    {
        var parts = s.Split(',');
        if (parts.Length != 2) return null;
        if (!uint.TryParse(parts[0], out var vk)) return null;
        if (!int.TryParse(parts[1], out var mods)) return null;
        return new HotkeyCombo(vk, (HotkeyModifiers)mods);
    }

    public static string KeyName(uint vk) => vk switch
    {
        >= 0x30 and <= 0x39 => ((char)vk).ToString(),  // 0-9
        >= 0x41 and <= 0x5A => ((char)vk).ToString(),  // A-Z
        >= 0x70 and <= 0x7B => $"F{vk - 0x6F}",         // F1-F12
        >= 0x60 and <= 0x69 => $"Num{vk - 0x60}",       // numpad digits
        0x20 => "Space",
        0x0D => "Enter",
        0x1B => "Esc",
        0x08 => "Backspace",
        0x09 => "Tab",
        0x25 => "←", // left
        0x26 => "↑", // up
        0x27 => "→", // right
        0x28 => "↓", // down
        0x21 => "PgUp",
        0x22 => "PgDn",
        0x23 => "End",
        0x24 => "Home",
        0x2C => "PrtSc",
        0x2D => "Ins",
        0x2E => "Del",
        0x13 => "Pause",
        0x6A => "Num*",
        0x6B => "Num+",
        0x6D => "Num-",
        0x6E => "Num.",
        0x6F => "Num/",
        // OEM punctuation (VK_OEM_1..VK_OEM_7) — US-layout labels; the recorder stores raw VKs.
        0xBA => ";",
        0xBB => "=",
        0xBC => ",",
        0xBD => "-",
        0xBE => ".",
        0xBF => "/",
        0xC0 => "`",
        0xDB => "[",
        0xDC => "\\",
        0xDD => "]",
        0xDE => "'",
        _ => $"(vk {vk})",
    };
}

/// <summary>The user's action→combo map, with conflict detection and dictionary persistence.</summary>
public sealed class HotkeyBindings
{
    private readonly Dictionary<HotkeyAction, HotkeyCombo?> _map;

    public HotkeyBindings(IDictionary<HotkeyAction, HotkeyCombo?>? map = null)
        => _map = map is null ? new Dictionary<HotkeyAction, HotkeyCombo?>() : new Dictionary<HotkeyAction, HotkeyCombo?>(map);

    public static HotkeyBindings Defaults()
    {
        var m = new Dictionary<HotkeyAction, HotkeyCombo?>();
        foreach (var a in HotkeyActionInfo.All) m[a] = a.DefaultCombo();
        return new HotkeyBindings(m);
    }

    public HotkeyCombo? Combo(HotkeyAction a) => _map.TryGetValue(a, out var c) ? c : null;
    public void Set(HotkeyAction a, HotkeyCombo combo) => _map[a] = combo;
    public void Clear(HotkeyAction a) => _map[a] = null;

    /// <summary>Returns the action already bound to <paramref name="combo"/> (other than <paramref name="excluding"/>), or null.</summary>
    public HotkeyAction? ConflictingAction(HotkeyCombo combo, HotkeyAction excluding)
    {
        foreach (var a in HotkeyActionInfo.All)
        {
            if (a == excluding) continue;
            if (_map.TryGetValue(a, out var c) && c is { } existing && existing == combo) return a;
        }
        return null;
    }

    /// <summary>Bound (action, combo) pairs in enum order, excluding unbound actions.</summary>
    public IReadOnlyList<(HotkeyAction Action, HotkeyCombo Combo)> Bound
    {
        get
        {
            var list = new List<(HotkeyAction, HotkeyCombo)>();
            foreach (var a in HotkeyActionInfo.All)
            {
                if (_map.TryGetValue(a, out var c) && c is { } combo) list.Add((a, combo));
            }
            return list;
        }
    }

    public Dictionary<string, string> ToDictionary()
    {
        var d = new Dictionary<string, string>();
        foreach (var a in HotkeyActionInfo.All)
        {
            var c = Combo(a);
            d[a.ToString()] = c is { } combo ? combo.ToPersisted() : "unbound";
        }
        return d;
    }

    public static HotkeyBindings FromDictionary(IReadOnlyDictionary<string, string> d)
    {
        var m = new Dictionary<HotkeyAction, HotkeyCombo?>();
        foreach (var a in HotkeyActionInfo.All)
        {
            if (d.TryGetValue(a.ToString(), out var v))
            {
                m[a] = v == "unbound" ? null : HotkeyCombo.FromPersisted(v) ?? a.DefaultCombo();
            }
            else
            {
                m[a] = a.DefaultCombo(); // missing key → use default (migration path)
            }
        }
        return new HotkeyBindings(m);
    }
}
