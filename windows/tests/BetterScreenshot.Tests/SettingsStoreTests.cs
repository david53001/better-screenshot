using System.IO;
using BetterScreenshot.Capture;
using BetterScreenshot.Editor;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;
using Xunit;

namespace BetterScreenshot.Tests;

public class SettingsStoreTests
{
    private static string TempPath() =>
        Path.Combine(Path.GetTempPath(), "bs-settings-" + Guid.NewGuid().ToString("N"), "settings.json");

    [Fact]
    public void RoundTripsAllFields()
    {
        var path = TempPath();
        try
        {
            var store = new SettingsStore
            {
                Capture = CaptureSettings.Default with { Format = SettingsImageFormat.Jpg, HistoryCap = 200 },
                Recording = RecordingConfig.Default with { Fps = 60, Camera = true, CountdownSeconds = 5 },
                EditorStyle = AnnotationStyle.Default with { LineWidth = 7 },
                SaveDirectory = @"C:\Shots",
                RecordingsDirectory = @"C:\Vids",
                CaptureSoundEnabled = true,
                LaunchAtLogin = true,
                FirstRunComplete = true,
            };
            store.Hotkeys.Clear(HotkeyAction.CaptureArea);
            store.Save(path);

            var loaded = SettingsStore.Load(path);
            Assert.Equal(store.Capture, loaded.Capture);
            Assert.Equal(store.Recording, loaded.Recording);
            Assert.Equal(store.EditorStyle, loaded.EditorStyle);
            Assert.Equal(@"C:\Shots", loaded.SaveDirectory);
            Assert.Equal(@"C:\Vids", loaded.RecordingsDirectory);
            Assert.True(loaded.CaptureSoundEnabled);
            Assert.True(loaded.LaunchAtLogin);
            Assert.True(loaded.FirstRunComplete);
            Assert.Equal(store.Hotkeys.ToDictionary(), loaded.Hotkeys.ToDictionary());
            Assert.Null(loaded.Hotkeys.Combo(HotkeyAction.CaptureArea)); // cleared binding persisted
        }
        finally
        {
            var dir = Path.GetDirectoryName(path);
            if (dir != null && Directory.Exists(dir)) Directory.Delete(dir, true);
        }
    }

    [Fact]
    public void MissingFileLoadsDefaults()
    {
        var loaded = SettingsStore.Load(Path.Combine(Path.GetTempPath(), "does-not-exist-" + Guid.NewGuid().ToString("N") + ".json"));
        Assert.Equal(CaptureSettings.Default, loaded.Capture);
        Assert.Equal(RecordingConfig.Default, loaded.Recording);
    }

    [Fact]
    public void CorruptFileLoadsDefaults()
    {
        var path = TempPath();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "{ this is not valid json ]");
        try
        {
            var loaded = SettingsStore.Load(path);
            Assert.Equal(CaptureSettings.Default, loaded.Capture);
        }
        finally
        {
            Directory.Delete(Path.GetDirectoryName(path)!, true);
        }
    }

    [Fact]
    public void Window_placements_round_trip_in_the_v3_shape()
    {
        var path = TempPath();
        var store = new SettingsStore();
        store.WindowPlacements["history"] = new BetterScreenshot.Core.WindowPlacementMemo(1000, 700, BetterScreenshot.Core.WindowPlacementMode.Fill);
        store.Save(path);
        string json = File.ReadAllText(path);
        Assert.Contains("\"windowPlacement\"", json);
        Assert.Contains("\"mode\": \"fill\"", json);
        var loaded = SettingsStore.Load(path);
        Assert.Equal(store.WindowPlacements["history"], loaded.WindowPlacements["history"]);
        // Nothing remembered: the key isn't written at all.
        var empty = TempPath();
        new SettingsStore().Save(empty);
        Assert.DoesNotContain("windowPlacement", File.ReadAllText(empty));
    }
}
