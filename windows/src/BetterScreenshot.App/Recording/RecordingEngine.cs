using System.Diagnostics;
using System.IO;
using System.Linq;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// Drives ffmpeg (via <see cref="FfmpegRunner"/>) to record a desktop region to an MP4, with gapless pause/resume
/// implemented as <b>segment-per-active-span + concat</b>: each active span is its own contiguous ffmpeg segment;
/// pausing finalizes the current segment, resuming starts a new one, and stopping concatenates them (<c>-c copy</c>,
/// all segments share identical encode settings) into the final MP4. Paused time is simply never captured, so the
/// output timeline is contiguous (the reference-sanctioned ffmpeg approach; the pure <see cref="PauseTimeline"/>
/// models the alternative PTS-retime strategy and is not needed here). One segment → just moved into place.
/// Pipes are drained in the background so a long segment never blocks on a full buffer.
/// </summary>
public sealed class RecordingEngine
{
    private readonly List<string> _segments = new();
    private Process? _process;
    private Task<string>? _stderr;
    private Task<string>? _stdout;

    private RecordingConfig _config = RecordingConfig.Default;
    private PxRect _region;
    private AudioInputs _audio = AudioInputs.None;
    private string? _finalPath;
    private string _sessionId = "";
    private PxSize _outputSize;
    private bool _muteSystem;
    private bool _muteMic;

    /// <summary>True while a recording session exists (recording or paused), from <see cref="Start"/> to <see cref="StopAsync"/>.</summary>
    public bool IsRecording => _finalPath is not null;

    /// <summary>ffmpeg's captured stderr from the most recent finished segment (written to error.log on a failure).</summary>
    public string LastStdErr { get; private set; } = "";

    /// <summary>What went wrong in this session, in words for a HUD — a segment ffmpeg that quit on its own, or why
    /// <see cref="StopAsync"/> returned no file; null when all went well. Cleared by <see cref="Start"/>.</summary>
    public string? LastFailure { get; private set; }

    /// <summary>The running segment's ffmpeg exited without being asked (a device unplugged or busy, a rejected region,
    /// a full disk — review round 2 #1). Raised on a thread-pool thread; the coordinator stops the take so the parts
    /// recorded so far are saved and says why.</summary>
    public event Action? SegmentDied;

    private readonly Dictionary<string, string> _segmentErrors = new();
    private int _startedSegments;

    /// <summary>Begin a recording session for <paramref name="region"/> → <paramref name="outputPath"/> (MP4). False if already active or ffmpeg is missing.</summary>
    public bool Start(RecordingConfig config, PxRect region, string outputPath, AudioInputs? audio = null)
    {
        if (_finalPath is not null) return false;
        LastFailure = null;
        if (!FfmpegRunner.IsAvailable()) { LastFailure = "Recording needs ffmpeg — it wasn't found"; return false; }
        // gdigrab rejects any rect past the desktop and writes nothing (round 2 #1): record the visible part.
        region = ClampToDesktop(region);
        if (region.IsEmpty) { LastFailure = "Nothing to record — that window is off-screen"; return false; }

        _config = config;
        _region = region;
        _audio = audio ?? AudioInputs.None;
        _finalPath = outputPath;
        _sessionId = Guid.NewGuid().ToString("N");
        _outputSize = FfmpegArgs.EvenSize(region);
        _segments.Clear();
        _segmentErrors.Clear();
        _startedSegments = 0;
        StartSegment();
        return true;
    }

    /// <summary>The part of <paramref name="region"/> on the virtual desktop (all monitors).</summary>
    public static PxRect ClampToDesktop(PxRect region)
    {
        var d = System.Windows.Forms.SystemInformation.VirtualScreen;
        return region.Intersection(new PxRect(d.X, d.Y, d.Width, d.Height));
    }

    /// <summary>
    /// Mute/unmute tracks (v3 Part 5, option A): the track stays, fed from silence. A running segment is ended and a
    /// new one started with the new inputs (ffmpeg can't swap inputs live); while paused the flags just apply to the
    /// next segment. Flags survive Stop/Start — the coordinator resets them per session and keeps them over Restart.
    /// </summary>
    public async Task SetMutedAsync(bool systemAudio, bool microphone)
    {
        if (_muteSystem == systemAudio && _muteMic == microphone) return;
        _muteSystem = systemAudio;
        _muteMic = microphone;
        if (_finalPath is not null && _process is not null)
        {
            await StopSegmentAsync();
            if (_finalPath is not null) StartSegment();
        }
    }

    /// <summary>
    /// Re-point the session at a new region (Switch Window/Area). Call while paused: the next segment records the new
    /// region letterboxed into the session's first output size, so the <c>-c copy</c> concat still holds.
    /// </summary>
    public void Retarget(PxRect region)
    {
        var visible = ClampToDesktop(region);
        if (!visible.IsEmpty) _region = visible;
    }

    /// <summary>The region the next segment records.</summary>
    public PxRect Region => _region;

    /// <summary>Stop and delete everything recorded in this session (Restart / Discard) — nothing is concatenated.</summary>
    public async Task DiscardAsync()
    {
        if (_finalPath is null) return;
        _finalPath = null;
        await StopSegmentAsync();
        foreach (var s in _segments) TryDelete(s);
        _segments.Clear();
    }

    /// <summary>Pause: finalize the current active-span segment (kept for concat); no frames are captured until <see cref="Resume"/>.</summary>
    public async Task PauseAsync()
    {
        if (_process is not null)
            await StopSegmentAsync();
    }

    /// <summary>Resume: begin a fresh segment with the same config/region/audio.</summary>
    public void Resume()
    {
        if (_finalPath is not null && _process is null)
            StartSegment();
    }

    /// <summary>
    /// Stop the session, concatenate the active-span segments into the final MP4, and return its path (or null, with
    /// <see cref="LastFailure"/> saying why). Unreadable segments — an ffmpeg that died on a busy mic or a rejected
    /// region, or one force-killed at stop — are left out of the join (review round 1 #2); if the join still fails, the
    /// readable parts are moved next to the final file instead of being lost in %TEMP%.
    /// </summary>
    public async Task<string?> StopAsync()
    {
        if (_finalPath is null) return null;
        string final = _finalPath;
        _finalPath = null;

        await StopSegmentAsync();

        var segments = _segments.ToList();
        _segments.Clear();
        var readable = segments.Where(HasRecordedMedia).ToList();
        foreach (var bad in segments.Except(readable))
        {
            // Nothing recorded in it (ffmpeg died before its first fragment): its own stderr says why.
            ErrorLog.Write($"Recording segment empty, left out: {bad}\n{_segmentErrors.GetValueOrDefault(bad, "")}");
            TryDelete(bad);
        }
        if (readable.Count == 0)
        {
            if (_startedSegments > 0)
                LastFailure = "Recording failed — ffmpeg couldn't record (details in error.log)";
            return null;
        }

        try
        {
            // Always through the join, even for one part: it turns the fragmented segments into an ordinary MP4 with
            // its index up front (durations, thumbnails and seeking all read it).
            await ConcatAsync(readable, final);
            foreach (var s in readable) TryDelete(s);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException
                                   or System.ComponentModel.Win32Exception)
        {
            ErrorLog.Write("Couldn't join the recording's parts", ex);
            TryDelete(final); // a half-written join is not the recording (round 2 #11)
            int saved = RescueParts(readable, final);
            LastFailure = saved > 0
                ? $"Couldn't join the recording — its {saved} parts were saved next to it"
                : "Recording failed — couldn't save the video (details in error.log)";
            return null;
        }
        return File.Exists(final) ? final : null;
    }

    /// <summary>True once the current segment's ffmpeg is still running <paramref name="after"/> its start — false when
    /// it exited early (a region it rejects, a device it can't open). Used to undo a Switch onto a bad target.</summary>
    public async Task<bool> SegmentAliveAsync(TimeSpan after)
    {
        var process = _process;
        if (process is null) return false;
        await Task.Delay(after);
        try { return !process.HasExited; }
        catch (InvalidOperationException) { return false; }
    }

    /// <summary>A segment holding at least one recorded fragment (<c>moof</c>) — or, for a plain MP4, a non-zero
    /// <c>mvhd</c> duration. A segment whose ffmpeg died at once has only the header (or no file).</summary>
    public static bool HasRecordedMedia(string path)
    {
        try
        {
            if (!File.Exists(path)) return false;
            using var fs = File.OpenRead(path);
            if (TopLevelBoxes(fs).Contains("moof")) return true;
            fs.Position = 0;
            return BetterScreenshot.History.MediaInfo.Mp4Duration(fs) is { } d && d > TimeSpan.Zero;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or OverflowException)
        {
            return false;
        }
    }

    /// <summary>The types of an MP4's top-level boxes, stopping at a truncated one (a killed segment ends mid-box).</summary>
    internal static HashSet<string> TopLevelBoxes(Stream s)
    {
        var types = new HashSet<string>();
        var head = new byte[16];
        long pos = 0, length = s.Length;
        while (pos + 8 <= length)
        {
            s.Position = pos;
            if (s.Read(head, 0, 8) < 8) break;
            long size = (uint)(head[0] << 24 | head[1] << 16 | head[2] << 8 | head[3]);
            string type = System.Text.Encoding.ASCII.GetString(head, 4, 4);
            if (size == 1)
            {
                if (s.Read(head, 8, 8) < 8) break;
                size = (long)System.Buffers.Binary.BinaryPrimitives.ReadUInt64BigEndian(head.AsSpan(8, 8));
            }
            else if (size == 0) size = length - pos; // to the end of the file
            if (size < 8) break;
            types.Add(type);
            pos += size;
        }
        return types;
    }

    /// <summary>Moves the parts beside the final file as <c>name-part1.mp4</c>…; returns how many were saved.</summary>
    private static int RescueParts(IReadOnlyList<string> parts, string final)
    {
        int saved = 0;
        string dir = Path.GetDirectoryName(final) ?? Path.GetTempPath();
        string stem = Path.GetFileNameWithoutExtension(final);
        for (int i = 0; i < parts.Count; i++)
        {
            try
            {
                File.Move(parts[i], Path.Combine(dir, $"{stem}-part{i + 1}.mp4"), overwrite: true);
                saved++;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                ErrorLog.Write("Couldn't rescue recording part " + parts[i], ex);
            }
        }
        return saved;
    }

    private void StartSegment()
    {
        string seg = Path.Combine(Path.GetTempPath(), $"bs_rec_{_sessionId}_{_segments.Count}.mp4");
        _segments.Add(seg);
        var args = FfmpegArgs.BuildRecording(_config, _region, seg, _audio, new SegmentOptions
        {
            OutputSize = _outputSize,
            MuteSystemAudio = _muteSystem,
            MuteMicrophone = _muteMic,
        });
        var process = FfmpegRunner.StartRecording(args);
        _stderr = process.StandardError.ReadToEndAsync();
        _stdout = process.StandardOutput.ReadToEndAsync();
        _process = process;
        _startedSegments++;
        process.EnableRaisingEvents = true;
        process.Exited += (_, _) =>
        {
            // Still the live segment = nobody asked it to stop (StopSegmentAsync detaches it first).
            if (!ReferenceEquals(Volatile.Read(ref _process), process)) return;
            LastFailure = "Recording stopped early — ffmpeg quit (details in error.log)";
            SegmentDied?.Invoke();
        };
        if (process.HasExited && ReferenceEquals(_process, process)) // died before the handler was attached
        {
            LastFailure = "Recording stopped early — ffmpeg quit (details in error.log)";
            SegmentDied?.Invoke();
        }
    }

    private async Task StopSegmentAsync()
    {
        var process = _process;
        Volatile.Write(ref _process, null);
        if (process is null) return;
        string? segment = _segments.Count > 0 ? _segments[^1] : null;

        await FfmpegRunner.StopRecordingAsync(process);
        try { if (_stderr is not null) LastStdErr = await _stderr; } catch { /* pipe closed */ }
        if (segment is not null) _segmentErrors[segment] = LastStdErr;
        if (process.ExitCode is not 0 and not -1 && LastStdErr.Length > 0)
            ErrorLog.Write($"Recording ffmpeg exited with {process.ExitCode}:\n{Tail(LastStdErr)}");
        try { if (_stdout is not null) await _stdout; } catch { /* pipe closed */ }
        _stderr = null;
        _stdout = null;
        process.Dispose();
    }

    private static async Task ConcatAsync(IReadOnlyList<string> segments, string output)
    {
        string list = Path.Combine(Path.GetTempPath(), $"bs_concat_{Guid.NewGuid():N}.txt");
        await File.WriteAllLinesAsync(list, segments.Select(s => $"file '{s.Replace("'", "'\\''")}'"));
        try
        {
            var (ok, err) = await FfmpegRunner.RunAsync(new[]
            {
                "-hide_banner", "-y", "-f", "concat", "-safe", "0", "-i", list, "-c", "copy",
                "-movflags", "+faststart", output,
            }, timeoutMs: 30 * 60 * 1000);
            if (!ok) throw new IOException("ffmpeg concat failed: " + err);
        }
        finally
        {
            TryDelete(list);
        }
    }

    private static string Tail(string text) => text.Length <= 2000 ? text : text[^2000..];

    /// <summary>
    /// At launch, recover segments a previous run left in %TEMP% (it crashed or was killed mid-take — round 2 #2): each
    /// session's parts are joined into "Recovered recording ….mp4" in <paramref name="recordingsDir"/>; segments with
    /// nothing recorded are deleted. Returns how many recordings were recovered. Run off the UI thread.
    /// </summary>
    public static async Task<int> RecoverOrphansAsync(string recordingsDir, string? searchDir = null)
    {
        int recovered = 0;
        try
        {
            var files = Directory.GetFiles(searchDir ?? Path.GetTempPath(), "bs_rec_*_*.mp4");
            foreach (var session in files.GroupBy(f => Path.GetFileNameWithoutExtension(f).Split('_')[2]))
            {
                var parts = session
                    .OrderBy(f => int.TryParse(Path.GetFileNameWithoutExtension(f).Split('_').Last(), out var i) ? i : 0)
                    .ToList();
                var good = parts.Where(HasRecordedMedia).ToList();
                foreach (var empty in parts.Except(good)) TryDelete(empty);
                if (good.Count == 0) continue;
                Directory.CreateDirectory(recordingsDir);
                var when = File.GetLastWriteTime(good[0]);
                string target = Path.Combine(recordingsDir, BetterScreenshot.Capture.FileNamer.Name(when, "mp4", "Recovered recording"));
                try
                {
                    await ConcatAsync(good, target);
                    foreach (var p in good) TryDelete(p);
                    recovered++;
                    ErrorLog.Write($"Recovered an interrupted recording: {target}");
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException
                                           or System.ComponentModel.Win32Exception)
                {
                    ErrorLog.Write("Couldn't recover interrupted recording parts " + string.Join(", ", good), ex);
                }
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            ErrorLog.Write("Recording recovery sweep failed", ex);
        }
        return recovered;
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { /* best-effort */ }
    }
}
