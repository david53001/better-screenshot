using System.Windows;
using BetterScreenshot.Tours;

namespace BetterScreenshot.App.Tours;

/// <summary>
/// The tour event bus (Mac v3 §7.2 <c>TourEvents</c>): surfaces report what the user did and when their window is on
/// screen; ⓘ buttons and the tray menu ask for replays. With no handler installed every call is a no-op, so surfaces
/// (and the off-screen preview renderer) never depend on the tour system existing.
/// </summary>
public static class TourEvents
{
    public static Action<TourEvent>? PostHandler;
    public static Action<TourSurface, Window>? SurfaceShownHandler;
    public static Action<TourId, Window?>? ReplayHandler;
    public static Func<Window, bool>? IsHostingHandler;

    public static void Post(TourEvent e) => PostHandler?.Invoke(e);
    public static void SurfaceShown(TourSurface surface, Window window) => SurfaceShownHandler?.Invoke(surface, window);
    public static void Replay(TourId id, Window? window) => ReplayHandler?.Invoke(id, window);
    /// <summary>A tour's tag is on this window right now (Quick Access cards don't auto-dismiss under one).</summary>
    public static bool IsHosting(Window window) => IsHostingHandler?.Invoke(window) ?? false;
}

/// <summary>Optional host hooks (Mac <c>TourHostShaping</c> / <c>TourEscapeClaiming</c> / <c>TourKeysClaiming</c>).</summary>
public interface ITourHost
{
    /// <summary>The visible shape in screen DIPs when the window is bigger than what the user sees (null = the window).</summary>
    TourHostShape? TourShape => null;
    /// <summary>The host wants Esc for itself right now (the editor on a drawing tool or with a selection).</summary>
    bool ClaimsTourEscape => false;
    /// <summary>The host wants Enter and Esc for itself right now (Settings while a shortcut is recording).</summary>
    bool ClaimsTourKeys => false;
}

public sealed record TourHostShape(Rect Frame, double CornerRadius, Rect? KeepOut);

/// <summary>What the coordinator drives (Mac <c>TourTagPresenting</c>): the real <see cref="TagOverlay"/>, or a test fake.</summary>
public interface ITourTagPresenter
{
    Action? OnNext { get; set; }
    Action? OnSkipStep { get; set; }
    Action? OnSkipTour { get; set; }
    bool IsDone { get; }
    void Show(Window host, TourStep step, string body, int number, int total, bool isLast);
    void ShowCompleted();
    void UpdateProgress(int number, int total, bool isLast);
    void Hide();
    void Detach();
}
