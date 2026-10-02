using System.Diagnostics;
using System.Runtime.InteropServices;

namespace BetterScreenshot.Platform;

/// <summary>
/// One Windows Job object for every ffmpeg this app starts, with <c>KILL_ON_JOB_CLOSE</c>: when BetterScreenshot exits
/// for ANY reason — a crash, a Task Manager kill — Windows closes the job handle and ends the children with it, so a
/// recording ffmpeg can never keep capturing the screen and microphone on its own (review round 2 #2; ffmpeg treats
/// a closed stdin as "no key" and would otherwise never quit). Best-effort: if the job can't be created or a process
/// can't join it, the process still runs.
/// </summary>
public static class ChildProcessJob
{
    private static readonly Lazy<IntPtr> Job = new(Create);

    /// <summary>Puts <paramref name="process"/> (already started) in the job. Never throws.</summary>
    public static void Add(Process process)
    {
        try
        {
            if (Job.Value != IntPtr.Zero && !AssignProcessToJobObject(Job.Value, process.Handle))
                ErrorLog.Write($"Couldn't add ffmpeg (pid {process.Id}) to the job: error {Marshal.GetLastWin32Error()}");
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            // The process already exited — nothing to contain.
        }
    }

    private static IntPtr Create()
    {
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero)
        {
            ErrorLog.Write($"Couldn't create the ffmpeg job object: error {Marshal.GetLastWin32Error()}");
            return IntPtr.Zero;
        }
        var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        int size = Marshal.SizeOf<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>();
        IntPtr ptr = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(info, ptr, false);
            if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, ptr, (uint)size))
                ErrorLog.Write($"Couldn't set kill-on-close on the ffmpeg job: error {Marshal.GetLastWin32Error()}");
        }
        finally { Marshal.FreeHGlobal(ptr); }
        return job; // held for the life of the process on purpose: closing it is what ends the children
    }

    private const int JobObjectExtendedLimitInformation = 9;
    private const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IO_COUNTERS
    {
        public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
        public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string? lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(IntPtr hJob, int infoClass, IntPtr lpInfo, uint cbInfoLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);
}
