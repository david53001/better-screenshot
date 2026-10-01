using BetterScreenshot.Capture;

namespace BetterScreenshot.Tests;

/// <summary>Port of the Mac FocusRestoreTests + the remember/restore rules of CaptureCoordinator (v2.8.0).</summary>
public class FocusRestoreTests
{
    private const int Own = 100;

    [Fact] public void Restores_another_app() => Assert.True(FocusRestore.ShouldRestore(42, Own));
    [Fact] public void Never_restores_ourselves() => Assert.False(FocusRestore.ShouldRestore(Own, Own));
    [Fact] public void Nothing_remembered_means_no_restore() => Assert.False(FocusRestore.ShouldRestore(null, Own));

    [Fact]
    public void Records_the_foreground_app_and_returns_it()
    {
        var m = new FocusMemory<long>();
        m.Record(7, 42, Own, selectionActive: false);
        Assert.Equal(7, m.RestoreTarget(Own));
    }

    [Fact]
    public void Second_hotkey_during_open_selection_keeps_the_real_target()
    {
        var m = new FocusMemory<long>();
        m.Record(7, 42, Own, selectionActive: false);   // browser had focus
        m.Record(9, Own, Own, selectionActive: true);   // our overlay is foreground now
        Assert.Equal(7, m.RestoreTarget(Own));
    }

    [Fact]
    public void Capture_started_from_our_own_window_clears_the_target()
    {
        var m = new FocusMemory<long>();
        m.Record(7, 42, Own, selectionActive: false);
        m.Record(9, Own, Own, selectionActive: false);  // started from e.g. our History window
        Assert.Null(m.RestoreTarget(Own));
    }

    [Fact]
    public void Restore_does_not_clear_the_memory()
    {
        var m = new FocusMemory<long>();
        m.Record(7, 42, Own, selectionActive: false);
        Assert.Equal(7, m.RestoreTarget(Own));
        Assert.Equal(7, m.RestoreTarget(Own));
    }

    [Fact]
    public void A_newer_foreign_app_replaces_the_old_one()
    {
        var m = new FocusMemory<long>();
        m.Record(7, 42, Own, selectionActive: false);
        m.Record(8, 43, Own, selectionActive: false);
        Assert.Equal(8, m.RestoreTarget(Own));
    }
}
