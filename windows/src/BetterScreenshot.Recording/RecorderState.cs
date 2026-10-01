namespace BetterScreenshot.Recording;

public enum RecorderPhase { Idle, Armed, Recording, Paused, Finishing }

public enum RecorderEvent { Arm, Begin, Pause, Resume, Finish, Reset }

/// <summary>
/// Pure recording state machine: Idle → Armed → Recording ⇄ Paused → Finishing → Idle. Tracks the start time
/// and accumulated pause duration so elapsed time excludes pauses. Illegal transitions are rejected (return false).
/// </summary>
public struct RecorderState : IEquatable<RecorderState>
{
    public RecorderPhase Phase { get; private set; }
    public DateTime Started { get; private set; }
    public TimeSpan AccumulatedPause { get; private set; }
    public DateTime PausedSince { get; private set; }

    public static RecorderState Idle => new() { Phase = RecorderPhase.Idle };

    /// <summary>Applies an event. Returns true if the transition was legal (and applied), false otherwise.</summary>
    public bool Transition(RecorderEvent ev, DateTime at = default)
    {
        if (ev == RecorderEvent.Reset)
        {
            this = Idle;
            return true;
        }

        switch (Phase)
        {
            case RecorderPhase.Idle when ev == RecorderEvent.Arm:
                Phase = RecorderPhase.Armed;
                return true;
            case RecorderPhase.Armed when ev == RecorderEvent.Begin:
                Phase = RecorderPhase.Recording;
                Started = at;
                AccumulatedPause = TimeSpan.Zero;
                return true;
            case RecorderPhase.Recording when ev == RecorderEvent.Pause:
                Phase = RecorderPhase.Paused;
                PausedSince = at;
                return true;
            case RecorderPhase.Recording when ev == RecorderEvent.Finish:
                Phase = RecorderPhase.Finishing;
                return true;
            case RecorderPhase.Paused when ev == RecorderEvent.Resume:
                AccumulatedPause += at - PausedSince;
                Phase = RecorderPhase.Recording;
                return true;
            case RecorderPhase.Paused when ev == RecorderEvent.Finish:
                Phase = RecorderPhase.Finishing;
                return true;
            default:
                return false;
        }
    }

    /// <summary>"m:ss" while recording; "Paused · m:ss" (frozen) while paused; null otherwise.</summary>
    public string? ElapsedString(DateTime now)
    {
        return Phase switch
        {
            RecorderPhase.Recording => Format(now - Started - AccumulatedPause),
            RecorderPhase.Paused => "Paused · " + Format(PausedSince - Started - AccumulatedPause),
            _ => null,
        };
    }

    /// <summary>Recorded time so far, pauses excluded (frozen while paused); zero when not recording.</summary>
    public TimeSpan Elapsed(DateTime now)
    {
        var t = Phase switch
        {
            RecorderPhase.Recording => now - Started - AccumulatedPause,
            RecorderPhase.Paused => PausedSince - Started - AccumulatedPause,
            _ => TimeSpan.Zero,
        };
        return t < TimeSpan.Zero ? TimeSpan.Zero : t;
    }

    private static string Format(TimeSpan t)
    {
        if (t < TimeSpan.Zero) t = TimeSpan.Zero;
        int total = (int)t.TotalSeconds;
        return $"{total / 60}:{total % 60:D2}";
    }

    public bool Equals(RecorderState other) =>
        Phase == other.Phase && Started == other.Started &&
        AccumulatedPause == other.AccumulatedPause && PausedSince == other.PausedSince;

    public override bool Equals(object? obj) => obj is RecorderState s && Equals(s);
    public override int GetHashCode() => HashCode.Combine(Phase, Started, AccumulatedPause, PausedSince);
}
