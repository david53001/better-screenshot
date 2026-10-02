using System.Collections.Concurrent;
using System.IO;
using System.IO.Pipes;
using BetterScreenshot.Recording;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace BetterScreenshot.Platform;

/// <summary>
/// System audio for one recording segment, captured IN-PROCESS with WASAPI loopback of the default output device
/// (what the user hears) and streamed to ffmpeg as raw PCM through a named pipe (review round 3 #1). Needs no
/// "Stereo Mix" or virtual cable, which most PCs don't have.
///
/// Loopback only delivers packets while something plays, so a silent stream is rendered to the same device for the
/// segment's life: the PCM then runs continuously and ffmpeg's sample-count timestamps stay in step with the video.
/// Packets are queued and written by one thread, so a busy pipe never stalls the WASAPI capture thread.
/// Lifecycle: <see cref="Create"/> (before ffmpeg starts — it fixes the format for the args), start ffmpeg with
/// <see cref="Pipe"/>, then <see cref="StartAsync"/>; <see cref="Dispose"/> after ffmpeg has exited.
/// </summary>
public sealed class LoopbackPipe : IDisposable
{
    private readonly WasapiLoopbackCapture _capture;
    private readonly NamedPipeServerStream _server;
    private readonly BlockingCollection<byte[]> _queue = new(boundedCapacity: 2000);
    private WasapiOut? _keepAlive;
    private Thread? _writer;
    private bool _disposed;

    public PcmPipe Pipe { get; }

    private LoopbackPipe(WasapiLoopbackCapture capture, NamedPipeServerStream server, PcmPipe pipe)
    {
        _capture = capture;
        _server = server;
        Pipe = pipe;
    }

    /// <summary>Whether Windows has a default output device to loop back from.</summary>
    public static bool Available()
    {
        try
        {
            using var devices = new MMDeviceEnumerator();
            return devices.HasDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
        }
        catch (Exception ex) when (ex is System.Runtime.InteropServices.COMException or InvalidOperationException)
        {
            return false;
        }
    }

    /// <summary>Opens the loopback and the pipe (nothing flows yet); null when there's no output device.</summary>
    public static LoopbackPipe? Create()
    {
        WasapiLoopbackCapture? capture = null;
        try
        {
            capture = new WasapiLoopbackCapture();
            var format = capture.WaveFormat;
            string sample = SampleFormat(format);
            string name = "bs_sys_" + Guid.NewGuid().ToString("N");
            var server = new NamedPipeServerStream(name, PipeDirection.Out, 1, PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous, inBufferSize: 0, outBufferSize: 1 << 20);
            var pipe = new LoopbackPipe(capture, server, new PcmPipe(@"\\.\pipe\" + name, sample, format.SampleRate, format.Channels));
            if (!pipe.Warm()) { pipe.Dispose(); return null; }
            return pipe;
        }
        catch (Exception ex) when (ex is System.Runtime.InteropServices.COMException or IOException
                                   or InvalidOperationException or NotSupportedException)
        {
            ErrorLog.Write("System audio loopback unavailable", ex);
            capture?.Dispose();
            return null;
        }
    }

    /// <summary>KSDATAFORMAT_SUBTYPE_IEEE_FLOAT.</summary>
    private static readonly Guid IeeeFloatSubtype = new("00000003-0000-0010-8000-00aa00389b71");

    /// <summary>ffmpeg's raw sample format for the device mix format (float32 on virtually every Windows device).</summary>
    internal static string SampleFormat(WaveFormat format)
    {
        bool isFloat = format.Encoding == WaveFormatEncoding.IeeeFloat
            || (format is WaveFormatExtensible ext && ext.SubFormat == IeeeFloatSubtype);
        if (isFloat) return format.BitsPerSample == 64 ? "f64le" : "f32le";
        return format.BitsPerSample switch { 16 => "s16le", 24 => "s24le", 32 => "s32le", _ => "s16le" };
    }

    /// <summary>Waits (≤ 5 s) for ffmpeg to open the pipe, then lets the (already running) capture through to the
    /// writer. False if ffmpeg never connected (it then fails on its own and the segment is reported).</summary>
    public async Task<bool> StartAsync()
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        try { await _server.WaitForConnectionAsync(timeout.Token); }
        catch (Exception ex) when (ex is OperationCanceledException or IOException or ObjectDisposedException)
        {
            ErrorLog.Write("ffmpeg never opened the system-audio pipe", ex);
            return false;
        }
        if (_disposed) return false;
        // ffmpeg opens this pipe first and the screen grab right after: samples from this moment on line up with the
        // first video frame. Everything captured before it (the capture is already warm) was dropped in OnData.
        Volatile.Write(ref _connected, true);
        _writer = new Thread(WriteLoop) { IsBackground = true, Name = "BS system-audio pipe" };
        _writer.Start();
        return true;
    }

    private bool _connected;

    /// <summary>Starts the silent keep-alive and the loopback capture BEFORE ffmpeg starts, so the stream is already
    /// flowing at the connection instant and ffmpeg gets its first samples at once.
    /// Captured data is dropped until <see cref="StartAsync"/> sees ffmpeg connect.</summary>
    private bool Warm()
    {
        try
        {
            _keepAlive = new WasapiOut(AudioClientShareMode.Shared, useEventSync: false, latency: 100);
            _keepAlive.Init(new SilenceProvider(_capture.WaveFormat));
            _keepAlive.Play();
        }
        catch (Exception ex) when (ex is System.Runtime.InteropServices.COMException or InvalidOperationException
                                   or ArgumentException)
        {
            // Without it, silent stretches carry no packets: the audio may drift; recording still works.
            ErrorLog.Write("System audio keep-alive couldn't start", ex);
            _keepAlive?.Dispose();
            _keepAlive = null;
        }

        _capture.DataAvailable += OnData;
        try { _capture.StartRecording(); }
        catch (Exception ex) when (ex is System.Runtime.InteropServices.COMException or InvalidOperationException)
        {
            ErrorLog.Write("System audio loopback couldn't start", ex);
            return false;
        }
        return true;
    }

    private void OnData(object? sender, WaveInEventArgs e)
    {
        if (e.BytesRecorded <= 0 || _queue.IsAddingCompleted || !Volatile.Read(ref _connected)) return;
        var chunk = new byte[e.BytesRecorded];
        Buffer.BlockCopy(e.Buffer, 0, chunk, 0, e.BytesRecorded);
        _queue.TryAdd(chunk); // a full queue (ffmpeg stalled ~20 s) drops rather than blocking WASAPI
    }

    private void WriteLoop()
    {
        try
        {
            foreach (var chunk in _queue.GetConsumingEnumerable())
                _server.Write(chunk, 0, chunk.Length);
        }
        catch (Exception ex) when (ex is IOException or ObjectDisposedException or InvalidOperationException)
        {
            // ffmpeg closed its end (the segment stopped) — nothing more to deliver.
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _capture.DataAvailable -= OnData;
        try { _capture.StopRecording(); } catch (Exception ex) when (ex is System.Runtime.InteropServices.COMException or InvalidOperationException) { }
        _capture.Dispose();
        try { _keepAlive?.Stop(); } catch (Exception ex) when (ex is System.Runtime.InteropServices.COMException or InvalidOperationException) { }
        _keepAlive?.Dispose();
        _queue.CompleteAdding();
        _server.Dispose(); // unblocks a writer stuck on a pipe nobody reads any more
        _writer?.Join(2000);
        _queue.Dispose();
    }
}
