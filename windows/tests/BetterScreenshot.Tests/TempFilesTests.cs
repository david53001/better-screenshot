using System.IO;
using BetterScreenshot.Capture;
using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

public class TempFilesTests
{
    [Fact]
    public void PayloadLifetimeDefaultsToFiveMinutes()
    {
        // Untouched settings must behave exactly as before the setting existed: a 5-minute temp lifetime.
        RestoreDefaultRetention();
        Assert.Equal(TimeSpan.FromMinutes(5), TempFiles.PayloadLifetime);
        Assert.Equal(5, TempFiles.RetentionMinutes);
    }

    [Theory]
    [InlineData(5, 5)]
    [InlineData(12, 12)]
    [InlineData(30, 30)]
    [InlineData(1, 5)]    // out-of-range values are clamped to the bar's 5..30 range, never honored raw
    [InlineData(0, 5)]
    [InlineData(90, 30)]
    public void ConfigureSetsTheClampedLifetime(int minutes, int expected)
    {
        try
        {
            TempFiles.Configure(minutes);
            Assert.Equal(expected, TempFiles.RetentionMinutes);
            Assert.Equal(TimeSpan.FromMinutes(expected), TempFiles.PayloadLifetime);
        }
        finally
        {
            RestoreDefaultRetention();
        }
    }

    private static void RestoreDefaultRetention() => TempFiles.Configure(TempRetentionScale.DefaultMinutes);

    [Fact]
    public async Task ScheduleDeleteRemovesContainingDirAfterDelay()
    {
        var dir = Path.Combine(Path.GetTempPath(), "bs-tf-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var file = Path.Combine(dir, "payload.png");
        File.WriteAllText(file, "x");

        TempFiles.ScheduleDeleteContainingDir(file, TimeSpan.FromMilliseconds(150));
        Assert.True(Directory.Exists(dir)); // still present immediately — outlives an in-flight drag

        await Task.Delay(900);
        Assert.False(Directory.Exists(dir)); // and auto-removed once the delay elapses
    }

    [Fact]
    public async Task ScheduleDeleteLeavesSiblingDirsUntouched()
    {
        // Each payload PNG owns its own guid subdir, so deleting one must not touch a sibling
        // (e.g. a capture's separate History copy lives elsewhere entirely and is never in scope).
        var keep = Path.Combine(Path.GetTempPath(), "bs-tf-keep-" + Guid.NewGuid().ToString("N"));
        var drop = Path.Combine(Path.GetTempPath(), "bs-tf-drop-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(keep);
        Directory.CreateDirectory(drop);
        File.WriteAllText(Path.Combine(keep, "history.png"), "keep");
        var dropFile = Path.Combine(drop, "payload.png");
        File.WriteAllText(dropFile, "drop");

        try
        {
            TempFiles.ScheduleDeleteContainingDir(dropFile, TimeSpan.FromMilliseconds(150));
            await Task.Delay(900);

            Assert.False(Directory.Exists(drop)); // the temp payload dir is gone
            Assert.True(Directory.Exists(keep));  // the unrelated dir survives
        }
        finally
        {
            if (Directory.Exists(keep)) Directory.Delete(keep, true);
            if (Directory.Exists(drop)) Directory.Delete(drop, true);
        }
    }

    [Fact]
    public void ScheduleDeleteWithNullOrEmptyIsNoOp()
    {
        // Must not throw for a missing drag file (e.g. a card with no temp payload).
        TempFiles.ScheduleDeleteContainingDir(null, TimeSpan.FromMilliseconds(10));
        TempFiles.ScheduleDeleteContainingDir("", TimeSpan.FromMilliseconds(10));
    }
}
