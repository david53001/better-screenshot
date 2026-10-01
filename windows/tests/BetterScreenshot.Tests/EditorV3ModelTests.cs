using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using S = BetterScreenshot.Editor.InspectorSection;
using T = BetterScreenshot.Editor.EditorTool;

namespace BetterScreenshot.Tests;

/// <summary>Ports of the Mac EditorKit pure-logic tests for v3 Parts 1–3 (InspectorModel, EditorTool metadata,
/// RecentColors, ZoomMath, TextScale, TextHandles, TextStylePreset, TextChip, style edits, frame resize).</summary>
public class EditorV3ModelTests
{
    private static InspectorContent C(T tool, params T[] sel) => InspectorModel.Content(tool, sel);

    // ---- InspectorModel (§1.2, §2.4, §3.2)

    [Fact]
    public void StrokeToolsShowColourStrokeOpacity()
    {
        foreach (var t in new[] { T.Arrow, T.Line, T.Rectangle, T.Ellipse })
            Assert.Equal(new[] { S.Colour, S.Stroke, S.Opacity }, C(t).Sections);
        Assert.Equal("Arrow", C(T.Arrow).Title);
    }

    [Fact]
    public void FilledRectangleAndCounterShowColourOpacity()
    {
        Assert.Equal(new[] { S.Colour, S.Opacity }, C(T.FilledRectangle).Sections);
        Assert.Equal(new[] { S.Colour, S.Opacity }, C(T.Counter).Sections);
    }

    [Fact]
    public void TextShowsStylesColourFontBackgroundEffectsOpacity() =>
        Assert.Equal(new[] { S.Styles, S.Colour, S.Font, S.Background, S.Effects, S.Opacity }, C(T.Text).Sections);

    [Fact]
    public void RedactionAndCropTools()
    {
        Assert.Equal(new[] { S.Redaction, S.Strength }, C(T.Blur).Sections);
        Assert.Equal(new[] { S.Redaction, S.Strength }, C(T.Pixelate).Sections);
        Assert.Equal(new[] { S.Redaction }, C(T.Blackout).Sections);
        Assert.Equal("Black-out", C(T.Blackout).Title);
        Assert.Equal(new[] { S.CropHelp }, C(T.Crop).Sections);
    }

    [Fact]
    public void DrawingToolIgnoresItsSelectionForSections() =>
        Assert.Equal(C(T.Arrow).Sections, C(T.Arrow, T.Text).Sections);

    [Fact]
    public void SelectWithNothingSelected()
    {
        var c = C(T.Select);
        Assert.Equal("Nothing selected", c.Title);
        Assert.Equal(new[] { S.SelectHelp }, c.Sections);
    }

    [Fact]
    public void SelectWithOneObjectShowsItsSectionsPlusArrange()
    {
        Assert.Equal(new[] { S.Styles, S.Colour, S.Font, S.Background, S.Effects, S.Opacity, S.Arrange }, C(T.Select, T.Text).Sections);
        Assert.Equal("Text", C(T.Select, T.Text).Title);
        Assert.Equal(new[] { S.Redaction, S.Strength, S.Arrange }, C(T.Select, T.Blur).Sections);
    }

    [Fact]
    public void SelectWithSeveralShowsSharedSectionsPlusArrange()
    {
        var c = C(T.Select, T.Arrow, T.Text);
        Assert.Equal(new[] { S.Colour, S.Opacity, S.Arrange }, c.Sections);
        Assert.Equal("2 objects", c.Title);
        Assert.Equal(new[] { S.Colour, S.Stroke, S.Opacity, S.Arrange }, C(T.Select, T.Arrow, T.Rectangle).Sections);
        Assert.Equal(new[] { S.Arrange }, C(T.Select, T.Arrow, T.Pixelate).Sections);
    }

    [Fact]
    public void RedactionSelectionsShareStrengthOnlyWithinOneMode()
    {
        Assert.Equal(new[] { S.Redaction, S.Strength, S.Arrange }, C(T.Select, T.Blur, T.Blur).Sections);
        Assert.Equal(new[] { S.Redaction, S.Arrange }, C(T.Select, T.Blur, T.Pixelate).Sections);
        Assert.Equal(new[] { S.Redaction, S.Arrange }, C(T.Select, T.Pixelate, T.Blackout).Sections);
    }

    [Fact]
    public void HighlighterAndSpotlightSections()
    {
        Assert.Equal(new[] { S.Colour, S.HighlighterStroke, S.Opacity }, C(T.Highlighter).Sections);
        Assert.Equal(new[] { S.SpotlightShape, S.SpotlightDim }, C(T.Spotlight).Sections);
        Assert.Equal(new[] { S.Colour, S.Opacity, S.Arrange }, C(T.Select, T.Highlighter, T.Arrow).Sections);
    }

    [Fact]
    public void SectionsKeepPanelOrder()
    {
        foreach (T tool in Enum.GetValues<T>())
        {
            var secs = C(tool).Sections.ToList();
            Assert.Equal(secs.OrderBy(s => (int)s).ToList(), secs);
        }
    }

    [Fact]
    public void HintsCoverEveryToolAndState()
    {
        foreach (T tool in Enum.GetValues<T>()) Assert.False(string.IsNullOrWhiteSpace(InspectorModel.Hint(tool, Array.Empty<T>(), false)));
        Assert.Contains("Enter", InspectorModel.Hint(T.Arrow, Array.Empty<T>(), true));
        Assert.Contains("corner", InspectorModel.Hint(T.Select, new[] { T.Text }, false));
        Assert.Contains("handle", InspectorModel.Hint(T.Select, new[] { T.Spotlight }, false));
        Assert.Contains("together", InspectorModel.Hint(T.Select, new[] { T.Arrow, T.Line }, false));
        Assert.Equal("Drag to draw an arrow — it points to where you let go.", InspectorModel.Hint(T.Arrow, Array.Empty<T>(), false));
        Assert.Contains("Shift", InspectorModel.Hint(T.Highlighter, Array.Empty<T>(), false));
        Assert.Contains("Alt", InspectorModel.Hint(T.Spotlight, Array.Empty<T>(), false));
    }

    // ---- EditorTool metadata

    [Fact]
    public void ToolShortcutsAreUniqueAndCaseInsensitive()
    {
        var keys = Enum.GetValues<T>().Select(t => t.ShortcutKey()).ToList();
        Assert.Equal(keys.Count, keys.Distinct().Count());
        Assert.Equal(T.Arrow, ToolInfo.ForShortcut("A"));
        Assert.Equal(T.Arrow, ToolInfo.ForShortcut("a"));
        Assert.Equal(T.Highlighter, ToolInfo.ForShortcut("h"));
        Assert.Equal(T.Spotlight, ToolInfo.ForShortcut("S"));
        Assert.Equal(T.Blackout, ToolInfo.ForShortcut("x"));
        Assert.Null(ToolInfo.ForShortcut("z"));
        Assert.Null(ToolInfo.ForShortcut("ab"));
        Assert.Equal("Arrow (A)", T.Arrow.Tooltip());
        Assert.Equal("Filled Rectangle (F)", T.FilledRectangle.Tooltip());
    }

    [Fact]
    public void EveryAnnotationTypeMapsToItsTool()
    {
        var st = AnnotationStyle.Default;
        Assert.Equal(T.Arrow, ToolInfo.MakerOf(new ArrowAnnotation(Guid.NewGuid(), st, default, default)));
        Assert.Equal(T.Line, ToolInfo.MakerOf(new LineAnnotation(Guid.NewGuid(), st, default, default)));
        Assert.Equal(T.Rectangle, ToolInfo.MakerOf(new RectangleAnnotation(Guid.NewGuid(), st, default, false)));
        Assert.Equal(T.FilledRectangle, ToolInfo.MakerOf(new FilledRectangleAnnotation(Guid.NewGuid(), st, default)));
        Assert.Equal(T.Ellipse, ToolInfo.MakerOf(new EllipseAnnotation(Guid.NewGuid(), st, default)));
        Assert.Equal(T.Text, ToolInfo.MakerOf(new TextAnnotation(Guid.NewGuid(), st, "x", default)));
        Assert.Equal(T.Counter, ToolInfo.MakerOf(new CounterAnnotation(Guid.NewGuid(), st, 1, default)));
        Assert.Equal(T.Pixelate, ToolInfo.MakerOf(new RedactionAnnotation(Guid.NewGuid(), st with { RedactionMode = RedactionMode.Pixelate }, default)));
        Assert.Equal(T.Blackout, ToolInfo.MakerOf(new RedactionAnnotation(Guid.NewGuid(), st with { RedactionMode = RedactionMode.Blackout }, default)));
        Assert.Equal(T.Highlighter, ToolInfo.MakerOf(new HighlighterAnnotation(Guid.NewGuid(), st, new[] { new PxPoint(1, 1) })));
        Assert.Equal(T.Spotlight, ToolInfo.MakerOf(new SpotlightAnnotation(Guid.NewGuid(), st, default)));
    }

    // ---- RecentColors

    [Fact]
    public void RecentColoursAreMostRecentFirstUniqueAndCapped()
    {
        var r = new RecentColors();
        for (int i = 0; i < 8; i++) r.Add(new RGBAColor(i / 10.0, 0, 0, 1));
        Assert.Equal(6, r.Colors.Count);
        Assert.Equal(new RGBAColor(0.7, 0, 0, 1), r.Colors[0]);
        r.Add(new RGBAColor(0.5, 0, 0, 1)); // existing → moved to the front, no duplicate
        Assert.Equal(new RGBAColor(0.5, 0, 0, 1), r.Colors[0]);
        Assert.Equal(6, r.Colors.Count);
        r.Add(new RGBAColor(0.9, 0.9, 0, 1), replacingFront: true);
        Assert.Equal(new RGBAColor(0.9, 0.9, 0, 1), r.Colors[0]);
        Assert.DoesNotContain(r.Colors, c => c.SameAs(new RGBAColor(0.5, 0, 0, 1)));
        var restored = new RecentColors(new[] { RGBAColor.White, RGBAColor.Black, RGBAColor.White });
        Assert.Equal(new[] { RGBAColor.White, RGBAColor.Black }, restored.Colors);
    }

    // ---- ZoomMath (§1.6)

    [Fact]
    public void PercentIsPerScreenPixel()
    {
        Assert.Equal(100, ZoomMath.Percent(0.5, 2), 9);
        Assert.Equal(0.5, ZoomMath.Magnification(100, 2), 9);
    }

    [Fact]
    public void FitCoversBothDimensionsAndNeverUpscalesPastOneHundredPercent()
    {
        Assert.Equal(0.5, ZoomMath.FitMagnification(new PxSize(2000, 1000), new PxSize(1000, 1000), 1), 9);
        Assert.Equal(1, ZoomMath.FitMagnification(new PxSize(200, 100), new PxSize(1000, 1000), 1), 9);
        Assert.Equal(0.2, ZoomMath.FitMagnification(new PxSize(1000, 3000), new PxSize(1000, 600), 2), 9);
        Assert.Equal(0.5, ZoomMath.FitMagnification(new PxSize(360, 225), new PxSize(1000, 600), 2), 9);
        Assert.Equal(0.5, ZoomMath.FitMagnification(new PxSize(1600, 1000), new PxSize(920, 577), 2), 3);
    }

    [Fact]
    public void PointSizeIsTheCapturesRealOnScreenSize()
    {
        Assert.Equal(new PxSize(800, 500), ZoomMath.PointSize(new PxSize(1600, 1000), 2));
        Assert.Equal(new PxSize(1600, 1000), ZoomMath.PointSize(new PxSize(1600, 1000), 1));
        Assert.Equal(new PxSize(1600, 1000), ZoomMath.PointSize(new PxSize(1600, 1000), 0));
    }

    [Fact]
    public void ClampRangeIsFitToEightHundred()
    {
        Assert.Equal(4, ZoomMath.Clamp(10, 0.3, 2), 9);
        Assert.Equal(0.3, ZoomMath.Clamp(0.1, 0.3, 2), 9);
        Assert.Equal(0.5, ZoomMath.Clamp(0.5, 1, 2), 9); // fit 1 > 100% lets 0.5 (=100%) through
    }

    [Fact]
    public void StepsWalkTheStopTable()
    {
        Assert.Equal(150, ZoomMath.SteppedPercent(100, true));
        Assert.Equal(75, ZoomMath.SteppedPercent(57, true));
        Assert.Equal(50, ZoomMath.SteppedPercent(57, false));
        Assert.Equal(800, ZoomMath.SteppedPercent(800, true));
        Assert.Equal(10, ZoomMath.SteppedPercent(10, false));
        // A 99.8% fit is shown as "100%": + must leave it, not land on 100.
        Assert.Equal(150, ZoomMath.SteppedPercent(99.8, true));
        Assert.Equal(75, ZoomMath.SteppedPercent(100.3, false));
    }

    [Fact]
    public void AnchoredZoomKeepsThePointUnderThePointer()
    {
        var o = ZoomMath.AnchoredOrigin(new PxPoint(300, 200), new PxPoint(100, 50), 1, 2);
        Assert.Equal(new PxPoint(400, 250), o);
        var back = ZoomMath.AnchoredOrigin(new PxPoint(600, 400), o, 2, 1);
        Assert.Equal(new PxPoint(100, 50), back);
    }

    [Fact]
    public void ZoomLabels()
    {
        Assert.Equal("Fit · 57%", ZoomMath.Label(57.3, true));
        Assert.Equal("150%", ZoomMath.Label(150, false));
    }

    // ---- TextScale + TextHandles (§2.4)

    [Theory]
    [InlineData(TextScale.Corner.BottomRight, 200, 50, 2)]
    [InlineData(TextScale.Corner.TopRight, 200, -50, 2)]
    [InlineData(TextScale.Corner.BottomLeft, -200, 50, 2)]
    [InlineData(TextScale.Corner.TopLeft, -200, -50, 2)]
    [InlineData(TextScale.Corner.TopLeft, 100, 25, 0.5)]
    public void DraggingACornerAlongTheDiagonalScalesProportionally(TextScale.Corner c, double dx, double dy, double f) =>
        Assert.Equal(f, TextScale.Factor(new PxRect(100, 100, 200, 50), c, dx, dy), 9);

    [Fact]
    public void DragAcrossTheDiagonalDoesNotScale()
    {
        Assert.Equal(1, TextScale.Factor(new PxRect(0, 0, 200, 50), TextScale.Corner.BottomRight, -50, 200), 9);
        Assert.Equal(1, TextScale.Factor(new PxRect(5, 5, 0, 0), TextScale.Corner.BottomRight, 30, 30), 9);
    }

    [Fact]
    public void ScaledRoundsTheFontAndScalesTheRestByTheSameFactor()
    {
        var st = AnnotationStyle.Default with { TextBackgroundPadding = 6, TextBackgroundCornerRadius = 4, TextOutlineWidth = 3 };
        var (s, w) = TextScale.Scaled(st, 240, 1.55);
        Assert.Equal(37, s.FontSize);
        double k = 37.0 / 24;
        Assert.Equal(240 * k, w!.Value, 9);
        Assert.Equal(6 * k, s.TextBackgroundPadding, 9);
        Assert.Equal(4 * k, s.TextBackgroundCornerRadius, 9);
        Assert.Equal(3 * k, s.TextOutlineWidth, 9);
        Assert.Null(TextScale.Scaled(st, null, 2).WrapWidth);
    }

    [Fact]
    public void ScaledClampsTheFontTo8Through400()
    {
        Assert.Equal(400, TextScale.Scaled(AnnotationStyle.Default, null, 100).Style.FontSize);
        var (s, w) = TextScale.Scaled(AnnotationStyle.Default, 120, 0.01);
        Assert.Equal(8, s.FontSize);
        Assert.Equal(40, w!.Value, 9);
        Assert.Equal(8, TextScale.Scaled(AnnotationStyle.Default, null, -3).Style.FontSize);
    }

    [Fact]
    public void ScaledKeepsPaddingRadiusAndOutlineInTheirRanges()
    {
        var st = AnnotationStyle.Default with { FontSize = 10, TextBackgroundPadding = 30, TextBackgroundCornerRadius = 30, TextOutlineWidth = 2 };
        var s = TextScale.Scaled(st, null, 10).Style;
        Assert.Equal(40, s.TextBackgroundPadding);
        Assert.Equal(40, s.TextBackgroundCornerRadius);
        Assert.Equal(20, s.TextOutlineWidth);
        Assert.Equal(1, TextScale.Scaled(st with { TextOutlineWidth = 1 }, null, 0.8).Style.TextOutlineWidth);
    }

    [Fact]
    public void PlacedKeepsTheOppositeCornerFixed()
    {
        var size = new PxSize(80, 30);
        var a = new PxPoint(100, 100);
        Assert.Equal(new PxRect(100, 100, 80, 30), TextScale.Placed(size, a, TextScale.Corner.BottomRight));
        Assert.Equal(new PxRect(20, 70, 80, 30), TextScale.Placed(size, a, TextScale.Corner.TopLeft));
        Assert.Equal(new PxRect(100, 70, 80, 30), TextScale.Placed(size, a, TextScale.Corner.TopRight));
        Assert.Equal(new PxRect(20, 100, 80, 30), TextScale.Placed(size, a, TextScale.Corner.BottomLeft));
        Assert.Equal(new PxPoint(40, 60), TextScale.Anchor(TextScale.Corner.TopLeft, new PxRect(10, 20, 30, 40)));
        Assert.Equal(new PxPoint(40, 20), TextScale.Anchor(TextScale.Corner.BottomLeft, new PxRect(10, 20, 30, 40)));
    }

    [Fact]
    public void CornerDragScalesATextAndKeepsTheOppositeCorner()
    {
        var t = new TextAnnotation(Guid.NewGuid(), AnnotationStyle.Default, "Hello world", new PxPoint(100, 100), 200);
        var box = t.BoundingBox();
        var big = t.Scaled(TextScale.Corner.BottomRight, box.Width, box.Height);
        Assert.Equal(48, big.Style.FontSize);
        Assert.Equal(400, big.WrapWidth);
        Assert.Equal(box.X, big.BoundingBox().X, 6);
        Assert.Equal(box.Y, big.BoundingBox().Y, 6);
        Assert.Equal(t.Id, big.Id);
        var small = t.Scaled(TextScale.Corner.TopLeft, box.Width / 2, box.Height / 2);
        Assert.Equal(12, small.Style.FontSize);
        Assert.Equal(box.Right, small.BoundingBox().Right, 6);
        Assert.Equal(box.Bottom, small.BoundingBox().Bottom, 6);
    }

    [Fact]
    public void CornerDragAnchorsTheBoxBehindTheText()
    {
        var st = AnnotationStyle.Default with { TextBackgroundMode = TextBackgroundMode.Solid, TextBackgroundPadding = 6 };
        var t = new TextAnnotation(Guid.NewGuid(), st, "Boxed", new PxPoint(100, 100), 150);
        var box = t.BoundingBox();
        var big = t.Scaled(TextScale.Corner.TopLeft, -box.Width, -box.Height);
        Assert.Equal(12, big.Style.TextBackgroundPadding, 6);
        Assert.Equal(box.Right, big.BoundingBox().Right, 6);
        Assert.Equal(box.Bottom, big.BoundingBox().Bottom, 6);
    }

    [Fact]
    public void TextCornersSitOutsideTheBoxAndSidesClearThem()
    {
        var box = new PxRect(100, 100, 200, 60);
        var r = TextHandles.Rects(box);
        Assert.Equal(6, r.Count);
        Assert.True(r[0].Right < box.X + 1 && r[0].Bottom < box.Y + 1);
        Assert.True(r[7].X > box.Right - 1 && r[7].Y > box.Bottom - 1);
        Assert.Equal(16, r[3].Height, 9);
        Assert.True(r[3].Y > r[0].Bottom && r[3].Bottom < r[5].Y);
    }

    [Fact]
    public void SideBarsShrinkThenDisappearOnShortTexts()
    {
        Assert.Equal(12, TextHandles.Rects(new PxRect(0, 0, 100, 17))[3].Height, 9);
        Assert.Equal(4, TextHandles.Rects(new PxRect(0, 0, 100, 6)).Count);
    }

    // ---- Presets + TextChip (§2.2)

    [Fact]
    public void PresetsSetTheirLook()
    {
        var label = TextStylePreset.Label.Apply(AnnotationStyle.Default);
        Assert.Equal(RGBAColor.White, label.StrokeColor);
        Assert.Equal(TextBackgroundMode.Solid, label.TextBackgroundMode);
        Assert.Equal(new RGBAColor(0, 0, 0, 0.8), label.TextBackgroundColor);
        Assert.True(label.FontBold);
        var code = TextStylePreset.Code.Apply(AnnotationStyle.Default);
        Assert.Equal(TextFont.Mono, code.FontFamily);
        Assert.False(code.FontBold);
        Assert.Equal(48, TextStylePreset.Title.Apply(AnnotationStyle.Default).FontSize);
        Assert.Equal(18, TextStylePreset.Subtle.Apply(AnnotationStyle.Default).FontSize);
    }

    [Fact]
    public void PresetsOnlyTouchTheTextLook()
    {
        var st = AnnotationStyle.Default with { TextAlignment = TextAlign.Center, Opacity = 0.5, LineWidth = 7, FontSize = 30, TextOutline = true, TextShadow = true, FontItalic = true };
        var label = TextStylePreset.Label.Apply(st);
        Assert.Equal(TextAlign.Center, label.TextAlignment);
        Assert.Equal(0.5, label.Opacity);
        Assert.Equal(7, label.LineWidth);
        Assert.Equal(30, label.FontSize);
        Assert.False(label.TextOutline || label.TextShadow || label.FontItalic);
        Assert.Equal(st.StrokeColor, TextStylePreset.Title.Apply(st).StrokeColor);
    }

    [Fact]
    public void PresetsRoundTripAndAreRecognised()
    {
        foreach (var p in Enum.GetValues<TextStylePreset>())
        {
            Assert.False(p.IsApplied(AnnotationStyle.Default) && p != TextStylePreset.Title, $"{p} active on the default");
            var s = p.Apply(AnnotationStyle.Default);
            Assert.True(p.IsApplied(s));
            var json = AnnotationStyle.FromJson(s.ToJson());
            Assert.True(p.IsApplied(json));
            foreach (var other in Enum.GetValues<TextStylePreset>().Where(o => o != p && o != TextStylePreset.Title))
                Assert.False(other.IsApplied(s), $"{other} also active after {p}");
        }
    }

    [Fact]
    public void AutoBoxContrastsWithTheTextColour()
    {
        Assert.Equal(TextChip.DarkChip, TextChip.AutoColor(RGBAColor.White));
        Assert.Equal(TextChip.LightChip, TextChip.AutoColor(RGBAColor.Black));
        Assert.Equal(new PxSize(6, 3), TextChip.Insets(6));
    }

    [Fact]
    public void ContrastRatioIsWcag()
    {
        Assert.Equal(21, TextChip.ContrastRatio(RGBAColor.White, RGBAColor.Black), 6);
        Assert.InRange(TextChip.ContrastRatio(AnnotationStyle.DefaultRed, RGBAColor.White), 3.3, 3.6);
        Assert.InRange(TextChip.ContrastRatio(AnnotationStyle.DefaultRed, RGBAColor.Black), 5.9, 6.4);
    }

    [Fact]
    public void OutlineContrastsWithTheTextColour()
    {
        var yellow = new RGBAColor(1, 0.84, 0.04, 1);
        Assert.Equal(RGBAColor.Black, TextChip.OutlineColor(RGBAColor.White, RGBAColor.White));
        Assert.Equal(RGBAColor.Black, TextChip.OutlineColor(RGBAColor.White, yellow));
        Assert.Equal(RGBAColor.White, TextChip.OutlineColor(RGBAColor.Black, RGBAColor.Black));
        Assert.Equal(RGBAColor.White, TextChip.OutlineColor(RGBAColor.White, AnnotationStyle.DefaultRed));
        var blue = new RGBAColor(0.04, 0.52, 1, 1);
        Assert.Equal(blue, TextChip.OutlineColor(blue, RGBAColor.White));
        Assert.Equal(RGBAColor.Black, TextChip.OutlineColor(RGBAColor.Black, RGBAColor.White));
    }

    [Fact]
    public void BoundingBoxIncludesTheBoxPadding()
    {
        var plain = new TextAnnotation(Guid.NewGuid(), AnnotationStyle.Default, "Hi", new PxPoint(50, 50));
        foreach (var mode in new[] { TextBackgroundMode.Solid, TextBackgroundMode.Auto })
        {
            var boxed = plain with { Style = plain.Style with { TextBackgroundMode = mode, TextBackgroundPadding = 10 } };
            var a = plain.BoundingBox();
            var b = boxed.BoundingBox();
            Assert.Equal(a.X - 10, b.X, 6);
            Assert.Equal(a.Y - 5, b.Y, 6);
            Assert.Equal(a.Width + 20, b.Width, 6);
        }
    }

    // ---- Style edits (§1.4, §3.3)

    private static EditorDocument Doc(params IAnnotation[] a) => new(new PxSize(500, 500), a);

    [Fact]
    public void StyleEditRestylesTheSelectionOnly()
    {
        var a = new ArrowAnnotation(Guid.NewGuid(), AnnotationStyle.Default, new PxPoint(0, 0), new PxPoint(10, 10));
        var b = new ArrowAnnotation(Guid.NewGuid(), AnnotationStyle.Default, new PxPoint(0, 0), new PxPoint(20, 20));
        var next = StyleEdits.ApplyToDocument(Doc(a, b), new[] { a.Id }, s => s with { LineWidth = 9 }, false, null)!;
        Assert.Equal(9, next.Find(a.Id)!.Style.LineWidth);
        Assert.Equal(4, next.Find(b.Id)!.Style.LineWidth);
    }

    [Fact]
    public void EditWithNothingSelectedLeavesTheDocumentAlone() =>
        Assert.Null(StyleEdits.ApplyToDocument(Doc(new ArrowAnnotation(Guid.NewGuid(), AnnotationStyle.Default, default, default)),
            Array.Empty<Guid>(), s => s with { LineWidth = 9 }, false, null));

    [Fact]
    public void DimEditReachesEverySpotlight_shapeEditOnlyTheSelected()
    {
        var s1 = new SpotlightAnnotation(Guid.NewGuid(), AnnotationStyle.Default, new PxRect(0, 0, 10, 10));
        var s2 = new SpotlightAnnotation(Guid.NewGuid(), AnnotationStyle.Default, new PxRect(20, 20, 10, 10));
        var dimmed = StyleEdits.ApplyToDocument(Doc(s1, s2), Array.Empty<Guid>(), s => s with { SpotlightDim = 0.3 }, true, 0.3)!;
        Assert.All(dimmed.Annotations, a => Assert.Equal(0.3, a.Style.SpotlightDim));
        var shaped = StyleEdits.ApplyToDocument(Doc(s1, s2), new[] { s1.Id }, s => s with { SpotlightShape = SpotlightShape.Ellipse }, false, null)!;
        Assert.Equal(SpotlightShape.Ellipse, shaped.Find(s1.Id)!.Style.SpotlightShape);
        Assert.Equal(SpotlightShape.Rectangle, shaped.Find(s2.Id)!.Style.SpotlightShape);
    }

    [Fact]
    public void PenStyleIsItsOwnStickyDefault()
    {
        Assert.True(StyleEdits.EditsPen(T.Highlighter, Array.Empty<T>()));
        Assert.True(StyleEdits.EditsPen(T.Select, new[] { T.Highlighter, T.Highlighter }));
        Assert.False(StyleEdits.EditsPen(T.Select, new[] { T.Highlighter, T.Arrow }));
        var d = StyleEdits.ApplyToDefault(AnnotationStyle.Default, s => s with { LineWidth = 32, Opacity = 0.7 }, editsPen: true);
        Assert.Equal(32, d.HighlighterPen.Width);
        Assert.Equal(0.7, d.HighlighterPen.Opacity);
        Assert.Equal(4, d.LineWidth);   // the next arrow is untouched
        Assert.Equal(1, d.Opacity);
    }

    [Fact]
    public void AdoptingAnObjectsStyleKeepsTheCurrentToolDefaults()
    {
        var current = AnnotationStyle.Default with { BlurRadius = 30, RedactionMode = RedactionMode.Pixelate, SpotlightDim = 0.2 };
        var adopted = AnnotationStyle.Default.KeepingToolDefaults(current);
        Assert.Equal(30, adopted.BlurRadius);
        Assert.Equal(RedactionMode.Pixelate, adopted.RedactionMode);
        Assert.Equal(0.2, adopted.SpotlightDim);
    }

    [Fact]
    public void RedactionIsAlwaysOpaque()
    {
        var r = new RedactionAnnotation(Guid.NewGuid(), AnnotationStyle.Default with { Opacity = 0.3 }, new PxRect(0, 0, 10, 10));
        Assert.Equal(1, r.Style.Opacity);
        Assert.Equal(1, ((RedactionAnnotation)r.WithStyle(r.Style with { Opacity = 0.2 })).Style.Opacity);
    }

    [Fact]
    public void SwitchingModeConvertsTheSelectedRedactionInPlace()
    {
        var r = new RedactionAnnotation(Guid.NewGuid(), AnnotationStyle.Default, new PxRect(0, 0, 10, 10));
        var other = new ArrowAnnotation(Guid.NewGuid(), AnnotationStyle.Default, default, default);
        var next = StyleEdits.ApplyToDocument(Doc(r, other), new[] { r.Id }, s => s with { RedactionMode = RedactionMode.Blackout }, false, null)!;
        Assert.Equal(0, next.IndexOf(r.Id));
        Assert.Equal(T.Blackout, ToolInfo.MakerOf(next.Find(r.Id)!));
    }

    [Fact]
    public void HighlighterBoundingBoxIsPathPlusHalfWidthAndMovesWithIt()
    {
        var h = new HighlighterAnnotation(Guid.NewGuid(), AnnotationStyle.Default with { LineWidth = 20 },
            new[] { new PxPoint(10, 20), new PxPoint(60, 25), new PxPoint(40, 50) });
        Assert.Equal(new PxRect(0, 10, 70, 50), h.BoundingBox());
        Assert.Equal(new PxRect(5, 15, 70, 50), h.MovedBy(5, 5).BoundingBox());
    }

    [Fact]
    public void SpotlightsAreHitLastAndResizeLikeBoxes()
    {
        var spot = new SpotlightAnnotation(Guid.NewGuid(), AnnotationStyle.Default, new PxRect(0, 0, 200, 200));
        var arrow = new ArrowAnnotation(Guid.NewGuid(), AnnotationStyle.Default, new PxPoint(50, 50), new PxPoint(80, 80));
        var doc = Doc(arrow, spot);
        Assert.Equal(arrow.Id, doc.TopmostHit(new PxPoint(60, 60)));
        Assert.Equal(spot.Id, doc.TopmostHit(new PxPoint(150, 150)));
        Assert.IsAssignableFrom<IFramedAnnotation>(spot);
    }

    [Fact]
    public void FrameResizeMovesOnlyTheDraggedEdges()
    {
        var f = new PxRect(10, 10, 100, 50);
        Assert.Equal(new PxRect(10, 10, 120, 70), FrameResize.Resize(f, 7, 20, 20));
        Assert.Equal(new PxRect(0, 10, 110, 50), FrameResize.Resize(f, 3, -10, 99));
        Assert.Equal(new PxRect(110, 10, 20, 50), FrameResize.Resize(f, 3, 120, 0)); // dragged past the right edge flips
        var (dx, dy) = FrameResize.ClampDelta(new[] { f }, -50, 1000, new PxSize(500, 500));
        Assert.Equal(-10, dx);
        Assert.Equal(440, dy);
    }

    // ---- A.1 text layout (headless approximation)

    [Fact]
    public void NewlineMakesTheBoxTallerAndWrapWidthBoundsIt()
    {
        var one = new TextAnnotation(Guid.NewGuid(), AnnotationStyle.Default, "Hello", default);
        var two = one with { Text = "Hello\nworld" };
        Assert.True(two.BoundingBox().Height >= 1.8 * one.BoundingBox().Height);
        var sentence = one with { Text = "A fairly long sentence that has to wrap inside a narrow box", WrapWidth = 200 };
        Assert.True(sentence.BoundingBox().Width <= 200 + 1e-9);
        Assert.True(sentence.BoundingBox().Height >= 1.8 * one.BoundingBox().Height);
    }

    [Fact]
    public void SideHandleSetsTheWrapWidthMinusPadding()
    {
        var st = AnnotationStyle.Default with { TextBackgroundMode = TextBackgroundMode.Solid, TextBackgroundPadding = 10 };
        var t = new TextAnnotation(Guid.NewGuid(), st, "Hi there", new PxPoint(100, 100));
        var w = t.WithBoxSpan(90, 390);
        Assert.Equal(280, w.WrapWidth);
        Assert.Equal(100, w.Origin.X);
        Assert.Equal(24, t.WithBoxSpan(90, 95).WrapWidth); // minimum = the font size
    }
}
