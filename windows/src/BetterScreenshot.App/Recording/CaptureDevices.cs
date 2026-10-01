using System.Runtime.InteropServices;
using System.Windows.Threading;
using BetterScreenshot.Recording;
using Windows.Devices.Enumeration;
using Windows.Media.Audio;
using Windows.Media.Capture;
using Windows.Media.Render;
using WinRT;

namespace BetterScreenshot.App.Recording;

/// <summary>Cameras for the Camera menu (v3 Part 4): WinRT VideoCapture devices — the id is what <c>MediaCapture</c>
/// takes; the default is the first one listed.</summary>
public static class CameraDevices
{
    public static async Task<DeviceList> ListAsync()
    {
        try
        {
            var all = await DeviceInformation.FindAllAsync(DeviceClass.VideoCapture);
            var devices = all.Where(d => d.IsEnabled).Select(d => new CaptureDevice(d.Id, d.Name)).ToList();
            return new DeviceList(devices, devices.FirstOrDefault()?.Id);
        }
        catch
        {
            return DeviceList.Empty;
        }
    }
}

/// <summary>Whether this desktop app may use the microphone (Settings › Privacy &amp; security › Microphone). Desktop
/// apps are never prompted, so anything but an explicit deny counts as allowed.</summary>
public static class MicrophoneAccess
{
    public static bool IsDenied()
    {
        try
        {
            var status = DeviceAccessInformation.CreateFromDeviceClass(DeviceClass.AudioCapture).CurrentStatus;
            return status is DeviceAccessStatus.DeniedByUser or DeviceAccessStatus.DeniedBySystem;
        }
        catch
        {
            return false;
        }
    }

    public static void OpenSettings()
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("ms-settings:privacy-microphone") { UseShellExecute = true }); }
        catch { /* no Settings app */ }
    }
}

/// <summary>
/// Live microphone level for the record strip's meter (v3 Part 4 Platform notes): a shared-mode capture through
/// <see cref="AudioGraph"/> on the chosen input (ffmpeg isn't running yet), average power per ~20 ms in dBFS,
/// delivered on the UI thread. Only started when access is already allowed, so opening the strip never prompts.
/// </summary>
public sealed class MicLevelMonitor : IDisposable
{
    private readonly Dispatcher _dispatcher;
    private readonly Action<double> _onLevelDb;
    private AudioGraph? _graph;
    private AudioFrameOutputNode? _output;
    private double _sum;
    private int _count, _quanta;
    private bool _disposed;

    private MicLevelMonitor(Dispatcher dispatcher, Action<double> onLevelDb)
    {
        _dispatcher = dispatcher;
        _onLevelDb = onLevelDb;
    }

    /// <summary>Starts metering the input whose name matches <paramref name="dshowName"/>; null if it can't be opened.</summary>
    public static async Task<MicLevelMonitor?> StartAsync(string dshowName, Dispatcher dispatcher, Action<double> onLevelDb)
    {
        var monitor = new MicLevelMonitor(dispatcher, onLevelDb);
        try
        {
            var inputs = await DeviceInformation.FindAllAsync(DeviceClass.AudioCapture);
            var device = inputs.FirstOrDefault(d => string.Equals(d.Name, dshowName, StringComparison.OrdinalIgnoreCase))
                         ?? inputs.FirstOrDefault(d => DshowDeviceList.MatchName(new[] { dshowName }, d.Name) is not null);
            if (device is null) return null;

            var created = await AudioGraph.CreateAsync(new AudioGraphSettings(AudioRenderCategory.Media));
            if (created.Status != AudioGraphCreationStatus.Success) return null;
            monitor._graph = created.Graph;
            var input = await monitor._graph.CreateDeviceInputNodeAsync(MediaCategory.Other, monitor._graph.EncodingProperties, device);
            if (input.Status != AudioDeviceNodeCreationStatus.Success || monitor._disposed) { monitor.Dispose(); return null; }
            monitor._output = monitor._graph.CreateFrameOutputNode();
            input.DeviceInputNode.AddOutgoingConnection(monitor._output);
            monitor._graph.QuantumStarted += monitor.OnQuantum;
            monitor._graph.Start();
            return monitor;
        }
        catch
        {
            monitor.Dispose();
            return null;
        }
    }

    private void OnQuantum(AudioGraph sender, object args)
    {
        if (_output is null) return;
        try
        {
            using var frame = _output.GetFrame();
            using var buffer = frame.LockBuffer(Windows.Media.AudioBufferAccessMode.Read);
            using var reference = buffer.CreateReference();
            reference.As<IMemoryBufferByteAccess>().GetBuffer(out IntPtr data, out uint capacity);
            int n = (int)Math.Min(capacity, buffer.Length) / sizeof(float);
            if (n > 0)
            {
                var samples = new float[n];
                Marshal.Copy(data, samples, 0, n);
                foreach (float s in samples) _sum += (double)s * s;
                _count += n;
            }
        }
        catch { return; }

        // Two 10 ms quanta per update (~20 ms, the meter's smoothing step).
        if (++_quanta < 2 || _count == 0) return;
        double rms = Math.Sqrt(_sum / _count);
        double db = rms > 0 ? 20 * Math.Log10(rms) : double.NegativeInfinity;
        _sum = 0; _count = 0; _quanta = 0;
        _dispatcher.BeginInvoke(() => { if (!_disposed) _onLevelDb(db); });
    }

    public void Dispose()
    {
        _disposed = true;
        if (_graph is { } g)
        {
            g.QuantumStarted -= OnQuantum;
            try { g.Stop(); } catch { /* already stopped */ }
            g.Dispose();
        }
        _graph = null;
        _output = null;
    }

    [ComImport, Guid("5B0D3235-4DBA-4D44-865E-8F1D0E4FD04D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMemoryBufferByteAccess
    {
        void GetBuffer(out IntPtr buffer, out uint capacity);
    }
}
