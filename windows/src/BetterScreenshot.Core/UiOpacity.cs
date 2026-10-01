namespace BetterScreenshot.Core;

/// <summary>
/// The "Opacity" setting's mapping (v3 §4.9 / Part 9 <c>OpacityCurve</c>): piecewise-linear through each surface's
/// (Transparent 0, default 0.5, Opaque 1) anchors. The Mac anchors are calibrated for a blurred material; WPF HUD
/// windows are layered (no DWM blur behind them), so the Windows HUD anchors are re-measured against the contrast
/// contract instead (white text over a white page: ≥ 4.5:1 at the default, ≥ 3:1 at Transparent) — the doc says
/// the ratios are the contract, the alphas are Mac-calibrated.
/// </summary>
public static class UiOpacity
{
    public const double Default = 0.5;

    /// <summary>The HUD fill (dark grey #171719) and, at Opaque, the solid dark grey (white 0.13 = #212121).</summary>
    public static readonly (byte R, byte G, byte B) HudColor = (0x17, 0x17, 0x19);
    public static readonly (byte R, byte G, byte B) SolidColor = (0x21, 0x21, 0x21);

    /// <summary>Piecewise-linear through (0, a0), (0.5, aHalf), (1, a1); the input is clamped to 0…1 (NaN → default).</summary>
    public static double Curve(double value, double a0, double aHalf, double a1)
    {
        double v = double.IsFinite(value) ? Math.Clamp(value, 0, 1) : Default;
        return v <= 0.5 ? a0 + (aHalf - a0) * (v / 0.5) : aHalf + (a1 - aHalf) * ((v - 0.5) / 0.5);
    }

    /// <summary>Floating HUD (pill, strip, toast, countdown, keystrokes, chips): fill alpha over whatever is behind.</summary>
    public static double HudAlpha(double value) => Curve(value, 0.50, 0.69, 1.0);

    /// <summary>At Opaque the HUD becomes the solid dark grey (Mac: white 0.13).</summary>
    public static bool HudIsSolid(double value) => double.IsFinite(value) && value >= 0.999;

    /// <summary>Docked panels on the editor's dark backdrop (tool pill, inspector, video card): fill alpha.</summary>
    public static double PanelAlpha(double value) => Curve(value, 0.5, 0.85, 1.0);

    /// <summary>Main windows (Settings, editor, video editor, History): background colour layer over the Mica material.</summary>
    public static double WindowLayerAlpha(double value) => Curve(value, 0.15, 0.52, 1.0);

    /// <summary>Settings card fill: the text colour at 3 % … 4 % … 5 %.</summary>
    public static double CardFillAlpha(double value) => Curve(value, 0.03, 0.04, 0.05);

    /// <summary>White text contrast on the HUD over a backdrop of luminance <paramref name="backdropLuminance"/> (1 = white page).</summary>
    public static double HudTextContrast(double value, double backdropLuminance = 1, double textAlpha = 1)
    {
        var (r, g, b) = HudIsSolid(value) ? SolidColor : HudColor;
        double a = HudIsSolid(value) ? 1 : HudAlpha(value);
        double back = Srgb.Encode(backdropLuminance);
        double Mix(byte c) => Srgb.Expand(a * (c / 255.0) + (1 - a) * back);
        double bg = 0.2126 * Mix(r) + 0.7152 * Mix(g) + 0.0722 * Mix(b);
        // Text at textAlpha white over that background.
        double bgEncoded = Srgb.Encode(bg);
        double text = Srgb.Expand(textAlpha + (1 - textAlpha) * bgEncoded);
        return Srgb.ContrastRatio(text, bg);
    }
}
