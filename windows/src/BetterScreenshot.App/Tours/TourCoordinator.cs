using System.Windows;
using System.Windows.Threading;
using BetterScreenshot.Platform;
using BetterScreenshot.Tours;

namespace BetterScreenshot.App.Tours;

/// <summary>
/// Runs the tours (Mac v3 §7.2 coordinator): starts a surface's tour when it's shown (queued → paused → auto-start
/// for a user who said yes), feeds posted events to the running tour, replays on request, keeps one tour on screen
/// (pausing the other, or marking a hand-over tour on its last step seen), pauses when the host window goes, and
/// persists <c>toursSeen</c> / <c>toursPaused</c>. Existing users never get a tour by itself: auto-start needs
/// <c>firstUseToursEnabled == true</c>, which only the Welcome answer or the Settings switch sets.
/// </summary>
public sealed class TourCoordinator
{
    private readonly SettingsStore _settings;
    private readonly Func<string, string?> _shortcut;
    private readonly ITourTagPresenter _tag;
    private readonly Action _save;
    private readonly Dictionary<TourSurface, List<Window>> _windows = new();
    private readonly HashSet<TourId> _queued = new();
    private readonly List<(TourEngine Engine, Window Host)> _interrupted = new();
    private readonly DispatcherTimer _check;
    private TourEngine? _engine;
    private Window? _host;
    private DispatcherTimer? _doneTimer;

    /// <summary>A finished run left the screen (not on Skip Tour). The app closes Welcome when its tour finishes.</summary>
    public Action<TourId>? OnFinished;
    /// <summary>Opens a surface the app can open itself (Welcome, Settings, History); false = it can't.</summary>
    public Func<TourSurface, bool>? OpenSurface;
    /// <summary>A step is now on screen / left (Settings' opacity demo listens).</summary>
    public Action<TourId, int>? OnStepShown;
    public Action? OnStepLeft;
    /// <summary>Shows a short HUD note.</summary>
    public Action<string>? Hud;

    public TourCoordinator(SettingsStore settings, Func<string, string?> shortcut, ITourTagPresenter? tag = null, Action? save = null)
    {
        _settings = settings;
        _shortcut = shortcut;
        _tag = tag ?? new TagOverlay();
        _save = save ?? (() => settings.Save());
        _tag.OnNext = () => Apply(_engine?.Next(IsPresent));
        _tag.OnSkipStep = () => Apply(_engine?.SkipStep(IsPresent));
        _tag.OnSkipTour = () => Apply(_engine?.SkipTour());
        _check = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(500) };
        _check.Tick += (_, _) => Check();
    }

    public void Install()
    {
        TourEvents.PostHandler = Post;
        TourEvents.SurfaceShownHandler = SurfaceShown;
        TourEvents.ReplayHandler = Replay;
        TourEvents.IsHostingHandler = w => _engine is { Status: TourStatus.Running } && ReferenceEquals(w, _host);
    }

    public TourId? RunningTour => _engine?.Status == TourStatus.Running ? _engine.Tour.Id : null;

    private bool IsPresent(string anchor) => TourAnchors.IsPresent(_host, anchor);

    private static Func<string, bool> PresentIn(Window w) => a => TourAnchors.IsPresent(w, a);

    private static bool Visible(Window? w) => w is not null && w.IsVisible && w.WindowState != WindowState.Minimized;

    // ------------------------------------------------------------------ bus handlers

    public void SurfaceShown(TourSurface surface, Window window)
    {
        if (!_windows.TryGetValue(surface, out var list)) _windows[surface] = list = new List<Window>();
        if (!list.Contains(window))
        {
            list.Add(window);
            window.Closed += (_, _) => WindowGone(surface, window);
        }

        var tours = TourCatalog.All.Where(t => t.Surface == surface).ToList();
        // (0) the running tour is on its last step (or just finished) and hands over to a tour here.
        if (_engine is { } cur && (cur.Status == TourStatus.Finished || cur.IsOnLastStep) && cur.Tour.HandsOverTo is { } handOver
            && tours.FirstOrDefault(t => t.Id == handOver) is { } next && Start(next, window, 0, null, replay: true)) return;
        // (1) queued, (2) paused, (3) auto-start — never restarting the tour already running.
        foreach (var t in tours.Where(t => _queued.Contains(t.Id) && t.Id != RunningTour))
            if (Start(t, window, 0, null, replay: true)) return;
        foreach (var t in tours.Where(t => _settings.ToursPaused.ContainsKey(t.Id.Raw()) && t.Id != RunningTour))
        {
            var seeded = _interrupted.FirstOrDefault(i => i.Engine.Tour.Id == t.Id).Engine?.Observed;
            if (Start(t, window, _settings.ToursPaused[t.Id.Raw()], seeded, replay: true)) return;
        }
        foreach (var t in tours.Where(t => t.Trigger.Kind == TriggerKind.SurfaceShown && t.Id != RunningTour))
            if (MayAutoStart(t) && Start(t, window, 0, null, replay: false)) return;
    }

    public void Post(TourEvent e)
    {
        bool wasRunning = _engine?.Status == TourStatus.Running;
        if (wasRunning && !_tag.IsDone)
        {
            var effect = _engine!.Handle(e, IsPresent);
            if (effect.Kind is TourEffectKind.Show or TourEffectKind.Finished)
            {
                // A Try step was just done: brief "Done", then the next step (or the finish).
                _tag.ShowCompleted();
                var engine = _engine;
                _doneTimer?.Stop();
                _doneTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(0.8) };
                _doneTimer.Tick += (_, _) =>
                {
                    _doneTimer!.Stop();
                    _doneTimer = null;
                    if (!ReferenceEquals(engine, _engine)) return;
                    Apply(effect);
                };
                _doneTimer.Start();
            }
            else
            {
                // The action may have hidden the anchor: re-check on the next UI turn.
                System.Windows.Application.Current?.Dispatcher.BeginInvoke(DispatcherPriority.Background, () =>
                {
                    if (_engine?.Status == TourStatus.Running && !_tag.IsDone) Apply(_engine.SkipIfAnchorMissing(IsPresent));
                });
            }
        }
        if (wasRunning) return; // event-triggered tours never interrupt a running tour

        foreach (var t in TourCatalog.All.Where(t => t.Trigger.Kind == TriggerKind.Event && t.Trigger.Event == e))
        {
            bool queued = _queued.Contains(t.Id);
            if (!queued && !MayAutoStart(t)) continue;
            var host = NewestVisible(t.Surface);
            if (host is not null && Start(t, host, 0, null, replay: queued)) return;
        }
    }

    public void Replay(TourId id, Window? window)
    {
        var tour = TourCatalog.Get(id);
        if (window is not null)
        {
            if (_engine?.Tour.Id == id) StopCurrent();
            if (!Start(tour, window, 0, null, replay: true)) _queued.Add(id);
            return;
        }
        if (NewestVisible(tour.Surface) is { } host)
        {
            if (_engine?.Tour.Id == id) StopCurrent();
            if (Start(tour, host, 0, null, replay: true)) return;
        }
        _queued.Add(id);
        if (OpenSurface?.Invoke(tour.Surface) != true) Hud?.Invoke($"{id.MenuTitle()} starts the next time you use it");
    }

    /// <summary>Reset All Tours: clears seen + paused only (never the audience, the answer or the switch).</summary>
    public string ResetAll()
    {
        _settings.ToursSeen.Clear();
        _settings.ToursPaused.Clear();
        _save();
        return TourRules.ResetConfirmation(_settings.FirstUseToursEnabled == true);
    }

    // ------------------------------------------------------------------ running

    private bool MayAutoStart(Tour t) =>
        TourRules.ShouldAutoStart(t, _settings.FirstUseToursEnabled, _settings.ToursSeen.TryGetValue(t.Id.Raw(), out var v) ? v : null);

    private Window? NewestVisible(TourSurface surface)
    {
        if (!_windows.TryGetValue(surface, out var list)) return null;
        return list.LastOrDefault(w => w.IsActive && Visible(w)) ?? list.LastOrDefault(Visible);
    }

    private bool Start(Tour tour, Window host, int at, IEnumerable<TourEvent>? observed, bool replay)
    {
        if (!Visible(host)) return false;
        var engine = new TourEngine(tour, observed);
        var effect = engine.Start(at, PresentIn(host));
        if (effect.Kind != TourEffectKind.Show) return false; // nothing presentable: never started, never marked seen

        if (_engine is { Status: TourStatus.Finished } finished)
        {
            // Replaced during its "Done" state: the finished run leaves the screen now.
            _doneTimer?.Stop();
            _doneTimer = null;
            _tag.Hide();
            OnStepLeft?.Invoke();
            MarkSeen(finished.Tour);
            if (finished.Tour.HandsOverTo is { } h && h != tour.Id) _queued.Add(h);
            OnFinished?.Invoke(finished.Tour.Id);
        }
        else if (_engine is { } other && other.Status is TourStatus.Running or TourStatus.Paused)
        {
            if (other.IsOnLastStep && other.Tour.HandsOverTo == tour.Id)
            {
                MarkSeen(other.Tour);
                _tag.Hide();
                OnStepLeft?.Invoke();
                OnFinished?.Invoke(other.Tour.Id);
            }
            else
            {
                other.Pause();
                _settings.ToursPaused[other.Tour.Id.Raw()] = other.Current;
                _interrupted.RemoveAll(i => i.Engine.Tour.Id == other.Tour.Id);
                _interrupted.Add((other, _host!));
                _tag.Hide();
                OnStepLeft?.Invoke();
            }
        }
        _interrupted.RemoveAll(i => i.Engine.Tour.Id == tour.Id);
        _queued.Remove(tour.Id);
        _settings.ToursPaused.Remove(tour.Id.Raw());
        _save();
        _engine = engine;
        _host = host;
        _check.Start();
        Present(effect.Step);
        return true;
    }

    private void StopCurrent()
    {
        _doneTimer?.Stop();
        _doneTimer = null;
        _engine = null;
        _tag.Hide();
        OnStepLeft?.Invoke();
    }

    private void Apply(TourEffect? effect)
    {
        if (effect is not { } e || _engine is null) return;
        var tour = _engine.Tour;
        switch (e.Kind)
        {
            case TourEffectKind.Show:
                OnStepLeft?.Invoke();
                Present(e.Step);
                break;
            case TourEffectKind.Finished:
                MarkSeen(tour);
                End();
                OnFinished?.Invoke(tour.Id);
                if (e.HandsOverTo is { } next)
                {
                    _queued.Add(next);
                    var nextTour = TourCatalog.Get(next);
                    if (NewestVisible(nextTour.Surface) is { } h && Start(nextTour, h, 0, null, replay: true)) return;
                }
                ResumeInterrupted();
                break;
            case TourEffectKind.Skipped:
                MarkSeen(tour);
                End();
                ResumeInterrupted();
                break;
            case TourEffectKind.Paused:
                _settings.ToursPaused[tour.Id.Raw()] = e.Step;
                _save();
                _tag.Hide();
                OnStepLeft?.Invoke();
                break;
        }
    }

    private void Present(int step)
    {
        if (_engine is null || _host is null) return;
        var s = _engine.Tour.Steps[step];
        TourAnchors.Find(_host, s.Anchor)?.BringIntoView();
        var engine = _engine;
        // Lay out after the scroll has settled.
        _host.Dispatcher.BeginInvoke(DispatcherPriority.Loaded, () =>
        {
            if (!ReferenceEquals(engine, _engine) || _engine.Current != step || _host is null) return;
            var (n, total) = _engine.Progress(IsPresent) ?? (1, 1);
            _tag.Show(_host, s, TourText.Resolve(s.Body, _shortcut), n, total, _engine.IsOnLastStep);
            OnStepShown?.Invoke(_engine.Tour.Id, step);
        });
    }

    private void MarkSeen(Tour tour)
    {
        _settings.ToursSeen[tour.Id.Raw()] = Math.Max(_settings.ToursSeen.TryGetValue(tour.Id.Raw(), out var v) ? v : 0, tour.Version);
        _settings.ToursPaused.Remove(tour.Id.Raw());
        _save();
    }

    private void End()
    {
        _doneTimer?.Stop();
        _doneTimer = null;
        _engine = null;
        _tag.Hide();
        OnStepLeft?.Invoke();
        _check.Stop();
    }

    private void ResumeInterrupted()
    {
        for (int i = _interrupted.Count - 1; i >= 0; i--)
        {
            var (engine, host) = _interrupted[i];
            if (!Visible(host)) continue;
            _interrupted.RemoveAt(i);
            if (Start(engine.Tour, host, engine.Current, engine.Observed, replay: true)) return;
        }
    }

    /// <summary>The 0.5 s check: host gone → pause; anchor gone → skip the step; progress changed → update the counter.</summary>
    private void Check()
    {
        if (_engine is null) { _check.Stop(); return; }
        if (_engine.Status != TourStatus.Running || _tag.IsDone) return;
        if (!Visible(_host))
        {
            PauseForHost();
            return;
        }
        var effect = _engine.SkipIfAnchorMissing(IsPresent);
        if (effect.Kind != TourEffectKind.None) { Apply(effect); return; }
        if (_engine.Progress(IsPresent) is var (n, total)) _tag.UpdateProgress(n, total, _engine.IsOnLastStep);
    }

    private void PauseForHost()
    {
        if (_engine is null) return;
        var engine = _engine;
        engine.Pause();
        _settings.ToursPaused[engine.Tour.Id.Raw()] = engine.Current;
        _save();
        _interrupted.RemoveAll(i => i.Engine.Tour.Id == engine.Tour.Id);
        if (_host is not null) _interrupted.Add((engine, _host));
        _engine = null;
        _tag.Detach();
        OnStepLeft?.Invoke();
        _check.Stop();
        ResumeInterrupted();
    }

    private void WindowGone(TourSurface surface, Window window)
    {
        if (_windows.TryGetValue(surface, out var list)) list.Remove(window);
        if (ReferenceEquals(window, _host))
        {
            if (_engine is { Status: TourStatus.Running } && !_tag.IsDone) PauseForHost();
            else if (_engine is not null && _tag.IsDone)
            {
                // Closed during the "Done" state: the run finished; let the done timer carry the effect, minus the tag.
                _tag.Detach();
            }
            _host = _engine is null ? null : _host;
        }
        // An interrupted run whose window closed stays paused in toursPaused (resumes when its surface shows again).
        _interrupted.RemoveAll(i => ReferenceEquals(i.Host, window));
    }
}
