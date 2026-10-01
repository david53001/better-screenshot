using BetterScreenshot.Core;

namespace BetterScreenshot.Editor;

/// <summary>
/// The annotation document: a base-image size plus an ordered list of annotations (array order = z-order,
/// first = back, last = front). The WPF editor holds the actual base bitmap alongside; this pure model carries
/// only the size so it stays headless-testable. All coordinates are base-image pixels, top-left origin.
/// </summary>
public sealed class EditorDocument
{
    private readonly List<IAnnotation> _annotations;

    public PxSize Size { get; }
    public IReadOnlyList<IAnnotation> Annotations => _annotations;

    public EditorDocument(PxSize size, IEnumerable<IAnnotation>? annotations = null)
    {
        Size = size;
        _annotations = annotations?.ToList() ?? new List<IAnnotation>();
    }

    public void Add(IAnnotation a) => _annotations.Add(a);

    public bool Remove(Guid id) => _annotations.RemoveAll(a => a.Id == id) > 0;

    public int? IndexOf(Guid id)
    {
        int i = _annotations.FindIndex(a => a.Id == id);
        return i < 0 ? null : i;
    }

    public void Move(Guid id, double dx, double dy)
    {
        int i = _annotations.FindIndex(a => a.Id == id);
        if (i >= 0) _annotations[i] = _annotations[i].MovedBy(dx, dy);
    }

    public void Replace(Guid id, IAnnotation a)
    {
        int i = _annotations.FindIndex(x => x.Id == id);
        if (i >= 0) _annotations[i] = a;
    }

    public void BringToFront(Guid id)
    {
        int i = _annotations.FindIndex(a => a.Id == id);
        if (i < 0) return;
        var a = _annotations[i];
        _annotations.RemoveAt(i);
        _annotations.Add(a);
    }

    public void SendToBack(Guid id)
    {
        int i = _annotations.FindIndex(a => a.Id == id);
        if (i < 0) return;
        var a = _annotations[i];
        _annotations.RemoveAt(i);
        _annotations.Insert(0, a);
    }

    /// <summary>Topmost (last-drawn) annotation whose lenient hit-test contains the point, or null. Spotlights are
    /// tried last, so clicking an arrow inside a spotlight picks the arrow (v3 Part 3).</summary>
    public Guid? TopmostHit(PxPoint p, double slop = AnnotationExtensions.HitSlop)
    {
        for (int i = _annotations.Count - 1; i >= 0; i--)
            if (_annotations[i] is not SpotlightAnnotation && _annotations[i].HitTest(p, slop)) return _annotations[i].Id;
        for (int i = _annotations.Count - 1; i >= 0; i--)
            if (_annotations[i] is SpotlightAnnotation && _annotations[i].HitTest(p, slop)) return _annotations[i].Id;
        return null;
    }

    public IAnnotation? Find(Guid id) => _annotations.FirstOrDefault(a => a.Id == id);

    /// <summary>Ids of annotations whose bounding box intersects <paramref name="rect"/> (marquee selection).</summary>
    public IReadOnlyList<Guid> IdsIntersecting(PxRect rect) =>
        _annotations.Where(a => !a.BoundingBox().Intersection(rect).IsEmpty).Select(a => a.Id).ToList();

    /// <summary>Next counter number = (# of existing counter annotations) + 1.</summary>
    public int NextCounterNumber() => _annotations.OfType<CounterAnnotation>().Count() + 1;

    /// <summary>Crops the document to <paramref name="rect"/>: new size = rect.Size, annotations offset by −rect.origin.</summary>
    public EditorDocument Cropped(PxRect rect)
    {
        var moved = _annotations.Select(a => a.MovedBy(-rect.X, -rect.Y));
        return new EditorDocument(new PxSize(rect.Width, rect.Height), moved);
    }
}
