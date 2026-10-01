using System.IO;
using BetterScreenshot.Capture;
using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>v3 §4.2: tracked payloads swept every 5 s while any exist, a launch sweep scoped to
/// <c>BetterScreenshot-{32 hex}</c>, ∞ keeps everything, and an idle app runs no timer.</summary>
[Collection("TempFiles")] // static state: never in parallel with itself
public class TempFilesTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "bs-tf-root-" + Guid.NewGuid().ToString("N"));

    public TempFilesTests()
    {
        Directory.CreateDirectory(_root);
        TempFiles.Configure(TempRetentionScale.DefaultSeconds);
        TempFiles.Sweep(DateTime.UtcNow.AddYears(10)); // clear anything a previous test tracked
    }

    public void Dispose()
    {
        TempFiles.Configure(TempRetentionScale.DefaultSeconds);
        TempFiles.Sweep(DateTime.UtcNow.AddYears(10));
        try { Directory.Delete(_root, true); } catch { }
    }

    private string Payload(string? name = null)
    {
        var dir = Path.Combine(_root, name ?? "BetterScreenshot-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var file = Path.Combine(dir, "Screenshot.png");
        File.WriteAllText(file, "x");
        return file;
    }

    [Fact]
    public void DefaultsToFiveMinutes()
    {
        Assert.Equal(300, TempFiles.RetentionSeconds);
        Assert.Equal(TimeSpan.FromMinutes(5), TempFiles.PayloadLifetime);
    }

    [Theory]
    [InlineData(12, 10)]
    [InlineData(600, 600)]
    [InlineData(0, 0)]
    public void ConfigureSnapsToAStop(int seconds, int expected)
    {
        TempFiles.Configure(seconds);
        Assert.Equal(expected, TempFiles.RetentionSeconds);
    }

    [Fact]
    public void ATrackedPayloadIsDeletedOnlyOnceExpired()
    {
        var file = Payload();
        var dir = Path.GetDirectoryName(file)!;
        TempFiles.Track(file);
        Assert.True(TempFiles.SweepRunning);
        Assert.Equal(0, TempFiles.Sweep(DateTime.UtcNow.AddMinutes(4)));
        Assert.True(Directory.Exists(dir));
        Assert.Equal(1, TempFiles.Sweep(DateTime.UtcNow.AddMinutes(5).AddSeconds(1)));
        Assert.False(Directory.Exists(dir));
        Assert.False(TempFiles.SweepRunning); // nothing tracked → no timer while idle
    }

    [Fact]
    public void InfinityKeepsPayloadsAndRunsNoTimer()
    {
        TempFiles.Configure(TempRetentionScale.NeverSeconds);
        var file = Payload();
        TempFiles.Track(file);
        Assert.False(TempFiles.SweepRunning);
        Assert.Equal(0, TempFiles.Sweep(DateTime.UtcNow.AddYears(1)));
        Assert.True(File.Exists(file));
        // Switching back to a finite stop applies to what is already tracked.
        TempFiles.Configure(10);
        Assert.True(TempFiles.SweepRunning);
        Assert.Equal(1, TempFiles.Sweep(DateTime.UtcNow.AddSeconds(11)));
        Assert.False(File.Exists(file));
    }

    [Fact]
    public void ShorteningTheSettingAppliesToTrackedPayloads()
    {
        var file = Payload();
        TempFiles.Track(file);
        TempFiles.Configure(30);
        Assert.Equal(1, TempFiles.Sweep(DateTime.UtcNow.AddSeconds(31)));
    }

    [Fact]
    public void TrackingNullOrEmptyIsANoOp()
    {
        TempFiles.Track(null);
        TempFiles.Track("");
        Assert.Equal(0, TempFiles.TrackedCount);
    }

    [Fact]
    public void LaunchSweepRemovesOnlyExpiredPayloadDirectories()
    {
        var old = Path.GetDirectoryName(Payload())!;
        var fresh = Path.GetDirectoryName(Payload())!;
        var preview = Path.GetDirectoryName(Payload("BetterScreenshot-preview-1234"))!;
        var other = Path.GetDirectoryName(Payload("SomethingElse-" + Guid.NewGuid().ToString("N")))!;
        var shortGuid = Path.GetDirectoryName(Payload("BetterScreenshot-abc"))!;
        foreach (var d in new[] { old, preview, other, shortGuid })
            Directory.SetLastWriteTimeUtc(d, DateTime.UtcNow.AddHours(-2));

        Assert.Equal(1, TempFiles.SweepOrphans(_root));
        Assert.False(Directory.Exists(old));
        Assert.True(Directory.Exists(fresh));     // younger than 5 min
        Assert.True(Directory.Exists(preview));   // not the payload name shape
        Assert.True(Directory.Exists(other));
        Assert.True(Directory.Exists(shortGuid));

        TempFiles.Configure(TempRetentionScale.NeverSeconds);
        Directory.SetLastWriteTimeUtc(fresh, DateTime.UtcNow.AddYears(-1));
        Assert.Equal(0, TempFiles.SweepOrphans(_root)); // ∞ never deletes
    }

    [Theory]
    [InlineData("BetterScreenshot-0123456789abcdef0123456789ABCDEF", true)]
    [InlineData("BetterScreenshot-preview-42", false)]
    [InlineData("BetterScreenshot-", false)]
    [InlineData("betterscreenshot-0123456789abcdef0123456789abcdef", false)]
    public void PayloadDirectoryNameShape(string name, bool matches) => Assert.Equal(matches, TempFiles.IsPayloadDirectory(name));

    [Fact]
    public void ExpiryIsAgeAgainstTheSetting()
    {
        var t = new DateTime(2026, 10, 2, 0, 0, 0, DateTimeKind.Utc);
        Assert.False(TempFiles.IsExpired(t, t.AddSeconds(9), 10));
        Assert.True(TempFiles.IsExpired(t, t.AddSeconds(10), 10));
        Assert.False(TempFiles.IsExpired(t, t.AddYears(5), 0));
    }
}
