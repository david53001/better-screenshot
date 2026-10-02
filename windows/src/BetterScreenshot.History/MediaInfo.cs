using System.Buffers.Binary;
using System.IO;

namespace BetterScreenshot.History;

/// <summary>
/// What a History cell says under its thumbnail (v3 §4.4 H2; Mac <c>MediaDuration</c> + <c>MediaInfoText</c>): a
/// screenshot's pixel size read from the PNG header only, a recording's length read from the MP4 header (<c>mvhd</c>)
/// or the GIF's frame delays — never by decoding the media. Pure readers over a stream, so they're unit-tested on
/// synthetic headers.
/// </summary>
public static class MediaInfo
{
    private static readonly byte[] PngSignature = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };

    /// <summary>Width × height from a PNG's IHDR (the first 24 bytes), or null if it isn't a PNG.</summary>
    public static (int Width, int Height)? PngSize(Stream s)
    {
        Span<byte> h = stackalloc byte[24];
        if (ReadFully(s, h) < 24 || !h[..8].SequenceEqual(PngSignature)) return null;
        if (h[12] != (byte)'I' || h[13] != (byte)'H' || h[14] != (byte)'D' || h[15] != (byte)'R') return null;
        int w = BinaryPrimitives.ReadInt32BigEndian(h[16..20]), ht = BinaryPrimitives.ReadInt32BigEndian(h[20..24]);
        return w > 0 && ht > 0 ? (w, ht) : null;
    }

    /// <summary>An MP4/MOV's duration from <c>moov/mvhd</c> (top-level boxes are skipped by size, so a big
    /// <c>mdat</c> before <c>moov</c> costs one seek), or null.</summary>
    public static TimeSpan? Mp4Duration(Stream s)
    {
        if (!s.CanSeek) return null;
        long end = s.Length;
        return FindMvhd(s, 0, end, depth: 0);
    }

    private static TimeSpan? FindMvhd(Stream s, long start, long end, int depth)
    {
        Span<byte> hdr = stackalloc byte[16];
        long pos = start;
        while (pos + 8 <= end)
        {
            s.Position = pos;
            if (ReadFully(s, hdr[..8]) < 8) return null;
            long size = BinaryPrimitives.ReadUInt32BigEndian(hdr[..4]);
            string type = System.Text.Encoding.ASCII.GetString(hdr[4..8]);
            int headerLen = 8;
            if (size == 1)
            {
                if (ReadFully(s, hdr[8..16]) < 8) return null;
                size = (long)BinaryPrimitives.ReadUInt64BigEndian(hdr[8..16]);
                headerLen = 16;
            }
            else if (size == 0) size = end - pos;
            // A 64-bit size past long.MaxValue reads negative; never let pos + size wrap (round 1 #15).
            if (size < headerLen || size > end - pos) return null;

            if (type == "moov" && depth == 0) return FindMvhd(s, pos + headerLen, pos + size, depth + 1);
            if (type == "mvhd" && depth == 1)
            {
                s.Position = pos + headerLen;
                Span<byte> body = stackalloc byte[32];
                if (ReadFully(s, body) < 20) return null;
                byte version = body[0];
                long timescale, duration;
                if (version == 1)
                {
                    timescale = BinaryPrimitives.ReadUInt32BigEndian(body[20..24]);
                    duration = (long)BinaryPrimitives.ReadUInt64BigEndian(body[24..32]);
                }
                else
                {
                    timescale = BinaryPrimitives.ReadUInt32BigEndian(body[12..16]);
                    duration = BinaryPrimitives.ReadUInt32BigEndian(body[16..20]);
                }
                if (timescale <= 0 || duration < 0) return null;
                double seconds = (double)duration / timescale;
                return seconds < TimeSpan.MaxValue.TotalSeconds / 2 ? TimeSpan.FromSeconds(seconds) : null;
            }
            pos += size;
        }
        return null;
    }

    /// <summary>A GIF's length: the sum of its Graphic Control Extension delays (hundredths of a second), or null.</summary>
    public static TimeSpan? GifDuration(Stream s)
    {
        try { return GifDurationCore(s); }
        catch (Exception ex) when (ex is IOException or ArgumentException or OverflowException) { return null; }
    }

    private static TimeSpan? GifDurationCore(Stream s)
    {
        var r = new BinaryReader(s);
        try
        {
            var sig = r.ReadBytes(6);
            if (sig.Length < 6 || sig[0] != 'G' || sig[1] != 'I' || sig[2] != 'F') return null;
            r.ReadBytes(4);                     // logical screen width/height
            byte packed = r.ReadByte();
            r.ReadBytes(2);                     // background colour, aspect
            if ((packed & 0x80) != 0) r.ReadBytes(3 * (1 << ((packed & 0x07) + 1)));
            long hundredths = 0;
            while (true)
            {
                int block = s.ReadByte();
                if (block < 0 || block == 0x3B) break;          // end / trailer
                if (block == 0x21)                               // extension
                {
                    int label = r.ReadByte();
                    if (label == 0xF9)
                    {
                        int len = r.ReadByte();
                        var gce = r.ReadBytes(len);
                        if (gce.Length >= 3) hundredths += gce[1] | (gce[2] << 8);
                    }
                    else SkipSubBlocks(r);
                    if (label == 0xF9) SkipSubBlocks(r);
                }
                else if (block == 0x2C)                          // image descriptor
                {
                    r.ReadBytes(8);
                    byte ipacked = r.ReadByte();
                    if ((ipacked & 0x80) != 0) r.ReadBytes(3 * (1 << ((ipacked & 0x07) + 1)));
                    r.ReadByte();                                // LZW minimum code size
                    SkipSubBlocks(r);
                }
                else return null;
            }
            return TimeSpan.FromMilliseconds(hundredths * 10);
        }
        catch (EndOfStreamException) { return null; }
    }

    private static void SkipSubBlocks(BinaryReader r)
    {
        while (true)
        {
            int len = r.ReadByte();
            if (len == 0) return;
            r.ReadBytes(len);
        }
    }

    private static int ReadFully(Stream s, Span<byte> buffer)
    {
        int total = 0;
        while (total < buffer.Length)
        {
            int n = s.Read(buffer[total..]);
            if (n == 0) break;
            total += n;
        }
        return total;
    }
}

/// <summary>The cell's text (Mac <c>MediaInfoText</c>): "1920 × 1080", or "0:42 · MP4".</summary>
public static class MediaInfoText
{
    public static string PixelSize(int width, int height) => $"{width} × {height}";

    /// <summary>"0:07", "1:42", "1:02:05".</summary>
    public static string Duration(TimeSpan d)
    {
        long total = (long)Math.Round(Math.Max(0, d.TotalSeconds), MidpointRounding.AwayFromZero);
        long h = total / 3600, m = total % 3600 / 60, s = total % 60;
        return h > 0 ? $"{h}:{m:00}:{s:00}" : $"{m}:{s:00}";
    }

    /// <summary>"0:42 · MP4" — the length and the container; just "MP4" when the length is unknown.</summary>
    public static string Recording(TimeSpan? duration, string extension)
    {
        string kind = extension.TrimStart('.').ToUpperInvariant();
        return duration is { } d ? $"{Duration(d)} · {kind}" : kind;
    }
}

/// <summary>The History window's empty state (v3 §4.4 H3; Mac <c>HistoryEmptyState</c>).</summary>
public static class HistoryEmptyState
{
    public static (string Title, string Detail) Text(bool historyEnabled, string? captureAreaChord) => historyEnabled
        ? ("No captures yet", captureAreaChord is { Length: > 0 } chord
            ? $"Press {chord} to take your first screenshot. It shows up here."
            : "Take a screenshot from the tray icon. It shows up here.")
        : ("History is off", "Turn on History in Settings to keep your captures here.");
}
