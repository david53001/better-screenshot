using System.Buffers.Binary;
using System.IO;
using BetterScreenshot.History;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>v3 §4.4: History multi-select (Mac HistorySelection, 1:1), H2 media info, H3 empty state.</summary>
public class HistorySelectionTests
{
    private static readonly Guid[] Ids = Enumerable.Range(0, 6).Select(_ => Guid.NewGuid()).ToArray(); // newest first
    private static HistorySelectionState Click(HistorySelectionState s, int i, HistoryClickModifier m = HistoryClickModifier.None) =>
        HistorySelection.Click(s, Ids[i], m, Ids);
    private static int[] Sel(HistorySelectionState s) => s.InOrder(Ids).Select(id => Array.IndexOf(Ids, id)).ToArray();

    [Fact]
    public void PlainClickSelectsOneAndAnchors()
    {
        var s = Click(HistorySelectionState.Empty, 2);
        Assert.Equal(new[] { 2 }, Sel(s));
        Assert.Equal(Ids[2], s.Anchor);
        s = Click(s, 4);
        Assert.Equal(new[] { 4 }, Sel(s));
    }

    [Fact]
    public void CtrlTogglesAndMovesTheAnchor()
    {
        var s = Click(HistorySelectionState.Empty, 1);
        s = Click(s, 3, HistoryClickModifier.Toggle);
        Assert.Equal(new[] { 1, 3 }, Sel(s));
        Assert.Equal(Ids[3], s.Anchor);
        s = Click(s, 1, HistoryClickModifier.Toggle);
        Assert.Equal(new[] { 3 }, Sel(s));
        Assert.Equal(Ids[1], s.Anchor); // anchor moves even when toggling off
    }

    [Fact]
    public void ShiftSelectsTheRangeFromTheAnchorEitherWay()
    {
        var s = Click(HistorySelectionState.Empty, 1);
        s = Click(s, 4, HistoryClickModifier.Range);
        Assert.Equal(new[] { 1, 2, 3, 4 }, Sel(s));
        Assert.Equal(Ids[1], s.Anchor); // unchanged
        s = Click(s, 0, HistoryClickModifier.Range);
        Assert.Equal(new[] { 0, 1 }, Sel(s));
    }

    [Fact]
    public void ShiftWithoutALiveAnchorIsAPlainClick()
    {
        Assert.Equal(new[] { 3 }, Sel(Click(HistorySelectionState.Empty, 3, HistoryClickModifier.Range)));
        var deleted = new HistorySelectionState(new HashSet<Guid>(), Guid.NewGuid());
        var s = Click(deleted, 2, HistoryClickModifier.Range);
        Assert.Equal(new[] { 2 }, Sel(s));
        Assert.Equal(Ids[2], s.Anchor);
    }

    [Fact]
    public void DraggingASelectedItemDragsTheWholeSelection()
    {
        var s = Click(Click(HistorySelectionState.Empty, 1), 3, HistoryClickModifier.Toggle);
        var (kept, dragged) = HistorySelection.DragStart(s, Ids[3], Ids);
        Assert.Same(s, kept);
        Assert.Equal(new[] { Ids[1], Ids[3] }, dragged); // display order
        var (other, one) = HistorySelection.DragStart(s, Ids[5], Ids);
        Assert.Equal(new[] { Ids[5] }, one);
        Assert.Equal(new[] { 5 }, Sel(other));
    }

    [Fact]
    public void PlainClickOnAMultiSelectionWaitsForMouseUp()
    {
        var s = Click(Click(HistorySelectionState.Empty, 1), 3, HistoryClickModifier.Toggle);
        Assert.True(HistorySelection.AppliesOnMouseUp(s, Ids[3], HistoryClickModifier.None));
        Assert.False(HistorySelection.AppliesOnMouseUp(s, Ids[4], HistoryClickModifier.None));
        Assert.False(HistorySelection.AppliesOnMouseUp(s, Ids[3], HistoryClickModifier.Toggle));
    }

    [Fact]
    public void PruneDropsDeletedIds()
    {
        var s = Click(Click(HistorySelectionState.Empty, 1), 3, HistoryClickModifier.Range);
        var remaining = Ids.Where((_, i) => i != 2 && i != 3).ToList();
        var p = HistorySelection.Prune(s, remaining);
        Assert.Equal(new[] { Ids[1] }, p.InOrder(remaining));
        Assert.Equal(Ids[1], p.Anchor);
        Assert.Null(HistorySelection.Prune(Click(HistorySelectionState.Empty, 2), remaining).Anchor);
        Assert.Same(s, HistorySelection.Prune(s, Ids));
    }

    // ------------------------------------------------------------------ H2: media info from headers

    private static MemoryStream Png(int w, int h)
    {
        var b = new byte[33];
        new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }.CopyTo(b, 0);
        BinaryPrimitives.WriteInt32BigEndian(b.AsSpan(8), 13);
        "IHDR"u8.CopyTo(b.AsSpan(12));
        BinaryPrimitives.WriteInt32BigEndian(b.AsSpan(16), w);
        BinaryPrimitives.WriteInt32BigEndian(b.AsSpan(20), h);
        return new MemoryStream(b);
    }

    [Fact]
    public void PngSizeComesFromTheHeader()
    {
        Assert.Equal((2560, 1440), MediaInfo.PngSize(Png(2560, 1440)));
        Assert.Null(MediaInfo.PngSize(new MemoryStream(new byte[] { 1, 2, 3 })));
        Assert.Null(MediaInfo.PngSize(new MemoryStream(new byte[40])));
    }

    private static byte[] Box(string type, params byte[][] body)
    {
        int len = 8 + body.Sum(x => x.Length);
        var b = new byte[len];
        BinaryPrimitives.WriteUInt32BigEndian(b, (uint)len);
        System.Text.Encoding.ASCII.GetBytes(type).CopyTo(b, 4);
        int o = 8;
        foreach (var x in body) { x.CopyTo(b, o); o += x.Length; }
        return b;
    }

    private static byte[] Mvhd(int version, uint timescale, ulong duration)
    {
        var body = new byte[version == 1 ? 32 : 20];
        body[0] = (byte)version;
        if (version == 1)
        {
            BinaryPrimitives.WriteUInt32BigEndian(body.AsSpan(20), timescale);
            BinaryPrimitives.WriteUInt64BigEndian(body.AsSpan(24), duration);
        }
        else
        {
            BinaryPrimitives.WriteUInt32BigEndian(body.AsSpan(12), timescale);
            BinaryPrimitives.WriteUInt32BigEndian(body.AsSpan(16), (uint)duration);
        }
        return Box("mvhd", body);
    }

    [Fact]
    public void Mp4DurationComesFromMvhdEvenAfterABigMdat()
    {
        var file = Box("ftyp", new byte[8]).Concat(Box("mdat", new byte[5000])).Concat(Box("moov", Box("trak", new byte[16]), Mvhd(0, 1000, 42_500))).ToArray();
        Assert.Equal(TimeSpan.FromSeconds(42.5), MediaInfo.Mp4Duration(new MemoryStream(file)));
        var v1 = Box("ftyp", new byte[8]).Concat(Box("moov", Mvhd(1, 600, 600UL * 3725))).ToArray();
        Assert.Equal(TimeSpan.FromSeconds(3725), MediaInfo.Mp4Duration(new MemoryStream(v1)));
        Assert.Null(MediaInfo.Mp4Duration(new MemoryStream(Box("ftyp", new byte[8]))));
        Assert.Null(MediaInfo.Mp4Duration(new MemoryStream(new byte[] { 0, 0, 0, 99, 1 })));
    }

    private static byte[] Gif(params int[] delaysHundredths)
    {
        var b = new List<byte>();
        b.AddRange("GIF89a"u8.ToArray());
        b.AddRange(new byte[] { 1, 0, 1, 0, 0x80, 0, 0 });       // 1×1, global colour table of 2
        b.AddRange(new byte[6]);
        foreach (var d in delaysHundredths)
        {
            b.AddRange(new byte[] { 0x21, 0xF9, 4, 0, (byte)(d & 0xFF), (byte)(d >> 8), 0, 0 });
            b.AddRange(new byte[] { 0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 0x4C, 0x01, 0 });
        }
        b.Add(0x3B);
        return b.ToArray();
    }

    [Fact]
    public void GifDurationSumsTheFrameDelays()
    {
        Assert.Equal(TimeSpan.FromSeconds(1.5), MediaInfo.GifDuration(new MemoryStream(Gif(50, 50, 50))));
        Assert.Equal(TimeSpan.Zero, MediaInfo.GifDuration(new MemoryStream(Gif())));
        Assert.Null(MediaInfo.GifDuration(new MemoryStream("PNG..."u8.ToArray())));
    }

    [Theory]
    [InlineData(0, "0:00")]
    [InlineData(7.4, "0:07")]
    [InlineData(102, "1:42")]
    [InlineData(3725, "1:02:05")]
    public void DurationText(double seconds, string text) => Assert.Equal(text, MediaInfoText.Duration(TimeSpan.FromSeconds(seconds)));

    [Fact]
    public void CellTexts()
    {
        Assert.Equal("1920 × 1080", MediaInfoText.PixelSize(1920, 1080));
        Assert.Equal("0:42 · MP4", MediaInfoText.Recording(TimeSpan.FromSeconds(42), ".mp4"));
        Assert.Equal("GIF", MediaInfoText.Recording(null, "gif"));
    }

    // ------------------------------------------------------------------ H3: the empty state

    [Fact]
    public void EmptyStateNamesTheLiveShortcutOrSaysHistoryIsOff()
    {
        Assert.Equal(("No captures yet", "Press Ctrl+Shift+4 to take your first screenshot. It shows up here."),
            HistoryEmptyState.Text(true, "Ctrl+Shift+4"));
        Assert.Equal("Take a screenshot from the tray icon. It shows up here.", HistoryEmptyState.Text(true, null).Detail);
        Assert.Equal("History is off", HistoryEmptyState.Text(false, "Ctrl+Shift+4").Title);
    }

    // ------------------------------------------------------------------ batch Show in Explorer

    [Fact]
    public void RevealGroupsOneWindowPerFolderCaseInsensitively()
    {
        var groups = BetterScreenshot.App.History.HistoryService.RevealGroups(new[]
        {
            @"C:\Shots.png", @"D:\Videos.mp4", @"c:\shots.png",
        }).ToList();
        Assert.Equal(2, groups.Count);
        Assert.Equal(new[] { @"C:\Shots.png", @"c:\shots.png" }, groups[0].ToArray());
        Assert.Equal(new[] { @"D:\Videos.mp4" }, groups[1].ToArray());
    }
}
