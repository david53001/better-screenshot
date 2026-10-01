using BetterScreenshot.Capture;
using Xunit;

namespace BetterScreenshot.Tests;

public class HotkeyTests
{
    [Fact]
    public void DefaultsTable()
    {
        var b = HotkeyBindings.Defaults();
        var cs = HotkeyModifiers.Control | HotkeyModifiers.Shift;
        Assert.Equal(new HotkeyCombo(0x34, cs), b.Combo(HotkeyAction.CaptureArea));
        Assert.Equal(new HotkeyCombo(0x38, cs), b.Combo(HotkeyAction.CaptureWindow));
        Assert.Equal(new HotkeyCombo(0x36, cs), b.Combo(HotkeyAction.CaptureFullscreen));
        Assert.Equal(new HotkeyCombo(0x37, cs), b.Combo(HotkeyAction.CaptureText));
        Assert.Equal(new HotkeyCombo(0x35, cs), b.Combo(HotkeyAction.Record));
        Assert.Null(b.Combo(HotkeyAction.PinFromClipboard));
        Assert.Null(b.Combo(HotkeyAction.OpenHistory));
        Assert.Null(b.Combo(HotkeyAction.RestoreRecentlyClosed));
        Assert.Null(b.Combo(HotkeyAction.PauseResumeRecording));
    }

    [Fact]
    public void AllActionsHaveTitles()
    {
        foreach (var a in HotkeyActionInfo.All)
            Assert.False(string.IsNullOrWhiteSpace(a.Title()));
    }

    [Fact]
    public void Validity()
    {
        Assert.True(new HotkeyCombo(0x34, HotkeyModifiers.Control | HotkeyModifiers.Shift).IsValid);
        Assert.True(new HotkeyCombo(0x34, HotkeyModifiers.Alt).IsValid);
        Assert.True(new HotkeyCombo(0x34, HotkeyModifiers.Win).IsValid);
        Assert.False(new HotkeyCombo(0x34, HotkeyModifiers.Shift).IsValid);
        Assert.False(new HotkeyCombo(0x34, HotkeyModifiers.None).IsValid);
    }

    [Fact]
    public void DisplayStringOrdersModifiers()
    {
        Assert.Equal("Ctrl+Shift+4", new HotkeyCombo(0x34, HotkeyModifiers.Control | HotkeyModifiers.Shift).DisplayString);
        Assert.Equal("Ctrl+Alt+Shift+Win+A",
            new HotkeyCombo(0x41, HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.Shift | HotkeyModifiers.Win).DisplayString);
        Assert.Equal("Win+F1", new HotkeyCombo(0x70, HotkeyModifiers.Win).DisplayString);
    }

    [Fact]
    public void ConflictDetection()
    {
        var b = HotkeyBindings.Defaults();
        var areaCombo = b.Combo(HotkeyAction.CaptureArea)!.Value;
        Assert.Equal(HotkeyAction.CaptureArea, b.ConflictingAction(areaCombo, excluding: HotkeyAction.CaptureText));
        Assert.Null(b.ConflictingAction(areaCombo, excluding: HotkeyAction.CaptureArea));
    }

    [Fact]
    public void BoundReturnsBoundPairsInEnumOrder()
    {
        var bound = HotkeyBindings.Defaults().Bound;
        Assert.Equal(
            new[] { HotkeyAction.CaptureArea, HotkeyAction.CaptureWindow, HotkeyAction.CaptureFullscreen, HotkeyAction.CaptureText, HotkeyAction.Record },
            bound.Select(x => x.Action).ToArray());
    }

    [Fact]
    public void DictionaryRoundTripWithUnboundAndMissing()
    {
        var b = HotkeyBindings.Defaults();
        b.Clear(HotkeyAction.CaptureArea);
        b.Set(HotkeyAction.PinFromClipboard, new HotkeyCombo(0x50, HotkeyModifiers.Control | HotkeyModifiers.Alt)); // Ctrl+Alt+P
        var round = HotkeyBindings.FromDictionary(b.ToDictionary());
        Assert.Null(round.Combo(HotkeyAction.CaptureArea));
        Assert.Equal(new HotkeyCombo(0x50, HotkeyModifiers.Control | HotkeyModifiers.Alt), round.Combo(HotkeyAction.PinFromClipboard));
        Assert.Equal(new HotkeyCombo(0x35, HotkeyModifiers.Control | HotkeyModifiers.Shift), round.Combo(HotkeyAction.Record));
    }

    [Fact]
    public void MissingKeysFallBackToDefaults()
    {
        var round = HotkeyBindings.FromDictionary(new Dictionary<string, string>());
        Assert.Equal(HotkeyAction.CaptureArea.DefaultCombo(), round.Combo(HotkeyAction.CaptureArea));
        Assert.Null(round.Combo(HotkeyAction.OpenHistory));
    }

    [Theory]
    [InlineData(0xBAu, ";")]
    [InlineData(0xBBu, "=")]
    [InlineData(0xBCu, ",")]
    [InlineData(0xBDu, "-")]
    [InlineData(0xBEu, ".")]
    [InlineData(0xBFu, "/")]
    [InlineData(0xC0u, "`")]
    [InlineData(0xDBu, "[")]
    [InlineData(0xDCu, "\\")]
    [InlineData(0xDDu, "]")]
    [InlineData(0xDEu, "'")]
    [InlineData(0x2Cu, "PrtSc")]
    [InlineData(0x2Du, "Ins")]
    [InlineData(0x2Eu, "Del")]
    [InlineData(0x21u, "PgUp")]
    [InlineData(0x22u, "PgDn")]
    [InlineData(0x23u, "End")]
    [InlineData(0x24u, "Home")]
    [InlineData(0x13u, "Pause")]
    [InlineData(0x60u, "Num0")]
    [InlineData(0x69u, "Num9")]
    [InlineData(0x6Au, "Num*")]
    [InlineData(0x6Bu, "Num+")]
    [InlineData(0x6Du, "Num-")]
    [InlineData(0x6Eu, "Num.")]
    [InlineData(0x6Fu, "Num/")]
    public void KeyName_maps_oem_navigation_and_numpad_keys(uint vk, string expected)
        => Assert.Equal(expected, HotkeyCombo.KeyName(vk));

    [Fact]
    public void DisplayString_renders_the_users_alt_period_binding()
        => Assert.Equal("Alt+.", new HotkeyCombo(0xBE, HotkeyModifiers.Alt).DisplayString);

    [Fact]
    public void Welcome_cheat_sheet_lists_live_bindings_in_menu_order_and_skips_unbound()
    {
        var rows = HotkeyCheatSheet.Rows(HotkeyBindings.Defaults());
        Assert.Equal(new[] { HotkeyAction.CaptureArea, HotkeyAction.CaptureWindow, HotkeyAction.CaptureFullscreen,
            HotkeyAction.CaptureText, HotkeyAction.Record }, rows.Select(r => r.Action));
        Assert.Equal(HotkeyAction.CaptureArea.DefaultCombo()!.Value.DisplayString, rows[0].Keys);
        Assert.Equal(3, rows.Count(r => r.IsScreenshotCapture));

        var map = HotkeyActionInfo.All.ToDictionary(a => a, a => a.DefaultCombo());
        map[HotkeyAction.CaptureWindow] = null;
        var rebound = HotkeyCheatSheet.Rows(new HotkeyBindings(map));
        Assert.DoesNotContain(rebound, r => r.Action == HotkeyAction.CaptureWindow);
        Assert.Equal(4, rebound.Count);
    }

    [Fact]
    public void Full_screen_is_two_words_everywhere() => Assert.Equal("Capture Full Screen", HotkeyAction.CaptureFullscreen.Title());
}
