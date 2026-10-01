using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>Section 4.11 smoke test: the probe finds the desktop in view (off-screen, nothing moves).</summary>
public class VirtualDesktopsTests
{
    [Fact]
    [Trait("category", "hardware")]
    public void The_desktop_in_view_has_an_id_and_a_window_already_here_is_not_moved()
    {
        Exception? failure = null;
        var thread = new Thread(() => { try { RunChecks(); } catch (Exception ex) { failure = ex; } });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null) throw failure;
    }

    private static void RunChecks()
    {
        var id = VirtualDesktops.CurrentDesktopId();
        Assert.NotNull(id);
        Assert.NotEqual(Guid.Empty, id!.Value);
        var parameters = new System.Windows.Interop.HwndSourceParameters("test", 1, 1)
        {
            PositionX = -32000, PositionY = -32000, WindowStyle = unchecked((int)0x90000000), ExtendedWindowStyle = 0x08000000,
        };
        using var here = new System.Windows.Interop.HwndSource(parameters);
        Assert.False(VirtualDesktops.BringToCurrent(here.Handle));
    }
}
