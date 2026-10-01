using BetterScreenshot.Core;
using BetterScreenshot.Recording;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>Mac v3 Part 4 pure logic: DeviceList, RecordingConfig v2 keys + legacy rules, MicLevel, strip hints.</summary>
public class RecordStripTests
{
    private static readonly DeviceList Mics = new(new[]
    {
        new CaptureDevice("BuiltInMic", "MacBook Air Microphone"),
        new CaptureDevice("AirPods-1", "AirPods"),
        new CaptureDevice("USB-7", "USB Audio CODEC"),
    }, "BuiltInMic");

    [Fact]
    public void ResolvedIdPrefersSavedThenDefaultThenFirst()
    {
        Assert.Equal("AirPods-1", Mics.ResolvedId("AirPods-1"));
        Assert.Equal("BuiltInMic", Mics.ResolvedId("Gone-9"));
        Assert.Equal("BuiltInMic", Mics.ResolvedId(null));
        var noDefault = new DeviceList(new[] { new CaptureDevice("AirPods-1", "AirPods"), new CaptureDevice("USB-7", "USB") }, "Aggregate-3");
        Assert.Equal("AirPods-1", noDefault.ResolvedId(null));
        Assert.Null(DeviceList.Empty.ResolvedId("x"));
    }

    [Fact]
    public void ChoiceShowsWhatWillRecord()
    {
        Assert.True(Mics.Choice(false, "AirPods-1").IsOff);
        Assert.Equal("AirPods-1", Mics.Choice(true, "AirPods-1").DeviceId);
        Assert.Equal("BuiltInMic", Mics.Choice(true, null).DeviceId);
        Assert.Equal("BuiltInMic", Mics.Choice(true, "Gone-9").DeviceId);
        Assert.True(DeviceList.Empty.Choice(true, null).IsOff);
    }

    [Fact]
    public void OptionsNumberRepeatedNames()
    {
        var list = new DeviceList(new[]
        {
            new CaptureDevice("a", "MacBook Pro Microphone"), new CaptureDevice("b", "USB Audio CODEC"), new CaptureDevice("c", "USB Audio CODEC"),
        }, null);
        Assert.Equal(new[] { "Off", "MacBook Pro Microphone", "USB Audio CODEC", "USB Audio CODEC (2)" }, list.Options().Select(o => o.Title));
        Assert.Equal(new[] { "Off" }, DeviceList.Empty.Options().Select(o => o.Title));
        Assert.True(list.Options()[0].Choice.IsOff);
    }

    [Fact]
    public void ChoosingOffKeepsTheDeviceId()
    {
        var c = RecordingConfig.Default.WithMicrophone(DeviceChoice.Device("AirPods-1"));
        Assert.True(c.Microphone);
        Assert.Equal("AirPods-1", c.MicrophoneDeviceId);
        c = c.WithMicrophone(DeviceChoice.Off);
        Assert.False(c.Microphone);
        Assert.Equal("AirPods-1", c.MicrophoneDeviceId);

        var cam = RecordingConfig.Default.WithCamera(DeviceChoice.Device("Cam-2")).WithCamera(DeviceChoice.Off);
        Assert.False(cam.Camera);
        Assert.Equal("Cam-2", cam.CameraDeviceId);
    }

    [Fact]
    public void ConfigDefaultsAndRoundTrip()
    {
        var d = RecordingConfig.Default;
        Assert.Equal(SystemAudioMode.All, d.SystemAudioMode);
        Assert.Null(d.MicrophoneDeviceId);
        Assert.Null(d.CameraDeviceId);
        Assert.True(d.ShowsCursor);

        foreach (var mode in new[] { SystemAudioMode.ExcludeSelf, SystemAudioMode.Off })
        {
            var c = d with { SystemAudioMode = mode, MicrophoneDeviceId = "Mic (Yeti)", CameraDeviceId = "cam", ShowsCursor = false };
            var back = RecordingConfig.FromDictionary(c.ToDictionary());
            Assert.Equal(c, back);
        }
        Assert.False(RecordingConfig.FromDictionary(new Dictionary<string, string> { ["showsCursor"] = "false" }).ShowsCursor);
        Assert.Null(RecordingConfig.FromDictionary(new Dictionary<string, string> { ["microphoneDeviceID"] = "" }).MicrophoneDeviceId);
    }

    [Fact]
    public void LegacySystemAudioBool()
    {
        RecordingConfig From(params (string K, string V)[] kv) => RecordingConfig.FromDictionary(kv.ToDictionary(p => p.K, p => p.V));
        Assert.Equal(SystemAudioMode.All, From(("systemAudio", "true")).SystemAudioMode);
        Assert.Equal(SystemAudioMode.Off, From(("systemAudio", "false")).SystemAudioMode);
        var both = From(("microphone", "true"), ("camera", "true"));
        Assert.True(both.Microphone && both.Camera);
        Assert.Null(both.MicrophoneDeviceId);
        Assert.Equal(SystemAudioMode.ExcludeSelf, From(("systemAudio", "true"), ("systemAudioMode", "excludeSelf")).SystemAudioMode);
        Assert.Equal(SystemAudioMode.Off, From(("systemAudio", "false"), ("systemAudioMode", "bogus")).SystemAudioMode);
        Assert.Equal("true", (RecordingConfig.Default with { SystemAudioMode = SystemAudioMode.ExcludeSelf }).ToDictionary()["systemAudio"]);
        Assert.Equal("false", (RecordingConfig.Default with { SystemAudioMode = SystemAudioMode.Off }).ToDictionary()["systemAudio"]);
    }

    [Fact]
    public void SystemAudioBoolIsAViewOfTheMode()
    {
        var c = RecordingConfig.Default with { SystemAudioMode = SystemAudioMode.ExcludeSelf };
        Assert.True(c.SystemAudio);
        Assert.Equal(SystemAudioMode.ExcludeSelf, (c with { SystemAudio = true }).SystemAudioMode);
        var off = c with { SystemAudio = false };
        Assert.Equal(SystemAudioMode.Off, off.SystemAudioMode);
        Assert.Equal(SystemAudioMode.All, (off with { SystemAudio = true }).SystemAudioMode);
    }

    [Fact]
    public void MicLevelMaths()
    {
        Assert.Equal(1, MicLevel.Fraction(0));
        Assert.Equal(1, MicLevel.Fraction(6));
        Assert.Equal(0.5, MicLevel.Fraction(-30));
        Assert.Equal(0, MicLevel.Fraction(-60));
        Assert.Equal(0, MicLevel.Fraction(-72));
        Assert.Equal(0, MicLevel.Fraction(double.NegativeInfinity));
        Assert.Equal(0, MicLevel.Fraction(double.NaN));
        Assert.Equal(0.9, MicLevel.Smoothed(0.2, 0.9));
        Assert.Equal(0.84, MicLevel.Smoothed(0.9, 0.1), 10);
        Assert.Equal(0, MicLevel.Smoothed(0.03, 0));
        Assert.Equal(0, MicLevel.LitSegments(0, 12));
        Assert.Equal(6, MicLevel.LitSegments(0.5, 12));
        Assert.Equal(0, MicLevel.LitSegments(0.04, 12));
        Assert.Equal(12, MicLevel.LitSegments(1, 12));
        Assert.Equal(12, MicLevel.LitSegments(1.7, 12));
        Assert.Equal(double.NegativeInfinity, MicLevel.AveragePowerDb(new float[] { 0, 0 }));
        Assert.Equal(-6.0206, MicLevel.AveragePowerDb(new float[] { 0.5f, -0.5f }), 3);
        Assert.Equal(0, MicLevel.Band(0, 16));
        Assert.Equal(1, MicLevel.Band(12, 16));
        Assert.Equal(2, MicLevel.Band(15, 16));
    }

    [Fact]
    public void HintsAreVerbatimWithGifRules()
    {
        Assert.Equal(RecordStripHints.Idle, RecordStripHints.For(StripArea.None, RecordingFormat.Mp4));
        Assert.Equal(RecordStripHints.GifNoSound, RecordStripHints.For(StripArea.None, RecordingFormat.Gif));
        Assert.Equal(RecordStripHints.GifNoSound, RecordStripHints.For(StripArea.Microphone, RecordingFormat.Gif));
        Assert.Equal(RecordStripHints.GifNoSound, RecordStripHints.For(StripArea.SystemAudio, RecordingFormat.Gif));
        Assert.Equal("Microphone: records your voice from the selected input. Choose \"Off\" to skip it.",
            RecordStripHints.For(StripArea.Microphone, RecordingFormat.Mp4));
        Assert.Contains("your PC plays", RecordStripHints.For(StripArea.SystemAudio, RecordingFormat.Mp4));
        Assert.Equal("Full Screen: records everything on this screen.", RecordStripHints.For(StripArea.FullScreen, RecordingFormat.Gif));
        Assert.Equal("Close this strip without recording.", RecordStripHints.For(StripArea.Close, RecordingFormat.Mp4));
        Assert.Equal("The video shows no mouse cursor.", RecordStripHints.CursorTooltip(false));
    }

    [Fact]
    public void GifRecordsNoAudioAndCursorFollowsTheSetting()
    {
        Assert.False((RecordingConfig.Default with { Format = RecordingFormat.Gif }).RecordsAudio);
        var hidden = FfmpegArgs.BuildRecording(RecordingConfig.Default with { ShowsCursor = false }, new PxRect(0, 0, 64, 64), "o.mp4", AudioInputs.None).ToList();
        Assert.Equal("0", hidden[hidden.IndexOf("-draw_mouse") + 1]);
        var shown = FfmpegArgs.BuildRecording(RecordingConfig.Default, new PxRect(0, 0, 64, 64), "o.mp4", AudioInputs.None).ToList();
        Assert.Equal("1", shown[shown.IndexOf("-draw_mouse") + 1]);
    }

    [Fact]
    public void DshowNameMatching()
    {
        var names = new[] { "Microphone (Yeti Classic)", "Microphone (Razer Kraken V3)", "Microphone (Realtek(R) Audio" };
        Assert.Equal("Microphone (Yeti Classic)", DshowDeviceList.MatchName(names, "microphone (yeti classic)"));
        Assert.Equal("Microphone (Realtek(R) Audio", DshowDeviceList.MatchName(names, "Microphone (Realtek(R) Audio)"));
        Assert.Null(DshowDeviceList.MatchName(names, "Headset (Bluetooth)"));
    }
}
