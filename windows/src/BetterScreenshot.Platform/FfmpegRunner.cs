using System.Diagnostics;
using System.IO;

namespace BetterScreenshot.Platform;

/// <summary>
/// Locates and drives ffmpeg (the recording/encoding backend). Prefers a bundled <c>ffmpeg.exe</c> next to the
/// app, otherwise falls back to <c>ffmpeg</c> on PATH. Provides a long-running recording process (stopped
/// gracefully by sending 'q' to stdin) and a run-to-completion helper for MP4→GIF conversion.
/// </summary>
public static class FfmpegRunner
{
    /// <summary>Resolved ffmpeg path (a bundled exe if present, else "ffmpeg" to be found on PATH).</summary>
    public static string ExecutablePath { get; } = ResolvePath();

    private static string ResolvePath()
    {
        string[] candidates =
        {
            Path.Combine(AppContext.BaseDirectory, "ffmpeg.exe"),
            Path.Combine(AppContext.BaseDirectory, "tools", "ffmpeg.exe"),
        };
        foreach (var c in candidates)
            if (File.Exists(c)) return c;
        return "ffmpeg";
    }

    private static bool _knownAvailable;

    /// <summary>Whether ffmpeg runs. A success is cached for the session (review round 1 #16: every recording start
    /// used to spawn <c>ffmpeg -version</c> on the UI thread); a failure is re-checked, so installing ffmpeg works
    /// without a restart.</summary>
    public static bool IsAvailable() => _knownAvailable || (_knownAvailable = Probe());

    private static bool Probe()
    {
        try
        {
            using var p = Process.Start(new ProcessStartInfo(ExecutablePath, "-version")
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            });
            if (p is null) return false;
            p.WaitForExit(5000);
            return p.HasExited && p.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>Starts a long-running ffmpeg process (e.g. a screen recording). Stop it with <see cref="StopRecordingAsync"/>.</summary>
    public static Process StartRecording(IEnumerable<string> args)
    {
        var psi = new ProcessStartInfo(ExecutablePath)
        {
            RedirectStandardInput = true,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);
        var process = new Process { StartInfo = psi };
        process.Start();
        ChildProcessJob.Add(process);
        return process;
    }

    /// <summary>Stops a recording gracefully (sends 'q'); force-kills after <paramref name="timeoutMs"/>. Returns the exit code.</summary>
    public static async Task<int> StopRecordingAsync(Process process, int timeoutMs = 8000)
    {
        try
        {
            await process.StandardInput.WriteAsync('q');
            await process.StandardInput.FlushAsync();
        }
        catch
        {
            // stdin may already be closed — fall through to wait/kill.
        }

        using var cts = new CancellationTokenSource(timeoutMs);
        try
        {
            await process.WaitForExitAsync(cts.Token);
        }
        catch (OperationCanceledException)
        {
            try { process.Kill(entireProcessTree: true); } catch { /* already gone */ }
            try { await process.WaitForExitAsync(); } catch { }
        }
        return process.HasExited ? process.ExitCode : -1;
    }

    /// <summary>Runs ffmpeg to completion (e.g. MP4→GIF). Returns success + captured stderr for diagnostics.</summary>
    public static async Task<(bool Success, string StdErr)> RunAsync(IEnumerable<string> args, int timeoutMs = 300000,
        CancellationToken cancel = default)
    {
        var psi = new ProcessStartInfo(ExecutablePath)
        {
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);

        using var process = new Process { StartInfo = psi };
        process.Start();
        ChildProcessJob.Add(process);
        var errTask = process.StandardError.ReadToEndAsync();
        var outTask = process.StandardOutput.ReadToEndAsync();

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancel);
        cts.CancelAfter(timeoutMs);
        try
        {
            await process.WaitForExitAsync(cts.Token);
        }
        catch (OperationCanceledException)
        {
            // Timed out or cancelled: end it and wait, so its input file is released when this returns.
            try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { /* already gone */ }
            try { await process.WaitForExitAsync(); } catch (InvalidOperationException) { }
        }

        string stderr = await errTask;
        await outTask;
        return (process.HasExited && process.ExitCode == 0, stderr);
    }

    /// <summary>Like <see cref="RunAsync"/>, but hands every stdout line to <paramref name="onLine"/> as it arrives
    /// (for <c>-progress pipe:1</c>). The callback runs on a thread-pool thread. No timeout: exports can be long.</summary>
    public static async Task<(bool Success, string StdErr)> RunWithProgressAsync(IEnumerable<string> args, Action<string> onLine,
        CancellationToken cancel = default)
    {
        var psi = new ProcessStartInfo(ExecutablePath)
        {
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);

        using var process = new Process { StartInfo = psi };
        process.Start();
        ChildProcessJob.Add(process);
        var errTask = process.StandardError.ReadToEndAsync();
        var outTask = Task.Run(async () =>
        {
            string? line;
            while ((line = await process.StandardOutput.ReadLineAsync()) is not null) onLine(line);
        });
        try
        {
            await process.WaitForExitAsync(cancel);
        }
        catch (OperationCanceledException)
        {
            try { process.Kill(entireProcessTree: true); } catch { }
        }
        string stderr = await errTask;
        await outTask;
        return (process.HasExited && process.ExitCode == 0, stderr);
    }

    private static bool? _nvenc;

    /// <summary>Whether this ffmpeg build lists the NVIDIA H.264 encoder (the owner's RTX 3060 Ti). A listed encoder can
    /// still fail at runtime (no driver) — callers fall back to libx264 on failure.</summary>
    public static async Task<bool> HasNvencAsync()
    {
        if (_nvenc is { } known) return known;
        try
        {
            var psi = new ProcessStartInfo(ExecutablePath) { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
            foreach (var a in new[] { "-hide_banner", "-encoders" }) psi.ArgumentList.Add(a);
            using var p = Process.Start(psi)!;
            var outTask = p.StandardOutput.ReadToEndAsync();
            _ = p.StandardError.ReadToEndAsync();
            await p.WaitForExitAsync();
            _nvenc = (await outTask).Contains("h264_nvenc");
        }
        catch
        {
            _nvenc = false;
        }
        return _nvenc.Value;
    }
}
