using System.IO;
using System.Runtime.CompilerServices;
using BetterScreenshot.Platform;

namespace BetterScreenshot.Tests;

/// <summary>
/// Runs before any test: points the app's settings + History folder (<see cref="SettingsStore.DefaultDirectory"/>) at
/// a throwaway temp folder for the whole test run, so no test can ever read or write the real
/// <c>%APPDATA%\BetterScreenshot</c> profile. (A capture test used to build a <c>CaptureCoordinator</c> on the real
/// History folder: every run recorded a full-screen capture there and the 50-entry cap pruned real entries.)
/// </summary>
internal static class TestProfile
{
    public static string Directory { get; } = Path.Combine(Path.GetTempPath(), "bs-tests-profile-" + Environment.ProcessId);

    [ModuleInitializer]
    internal static void Isolate() =>
        Environment.SetEnvironmentVariable(SettingsStore.DirectoryOverrideVariable, Directory);
}
