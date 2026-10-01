using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using BetterScreenshot.Tours;
using Border = System.Windows.Controls.Border;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using FontFamily = System.Windows.Media.FontFamily;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Orientation = System.Windows.Controls.Orientation;
using VerticalAlignment = System.Windows.VerticalAlignment;

namespace BetterScreenshot.App.Tours;

/// <summary>
/// The ⓘ on every window (Mac v3 §7.3 <c>InfoButton</c>): a borderless 26 × 22 info glyph; pressing it opens a small
/// menu 4 below — <b>Replay Tour</b> (this window's tour, from step 1, for every user) and, when the window has
/// any, <b>Keyboard Shortcuts</b> (a transient list of keys → actions). Tooltip/name "Tour &amp; Keyboard Shortcuts".
/// </summary>
public sealed class InfoButton : Border
{
    private static readonly FontFamily IconFont = new("Segoe Fluent Icons, Segoe MDL2 Assets");
    private static readonly FontFamily UiFont = new("Segoe UI Variable Text, Segoe UI");
    private static readonly Brush Glyph = Frozen(Color.FromRgb(0xC8, 0xC8, 0xCC));
    private static readonly Brush HoverFill = Frozen(Color.FromArgb(0x1F, 0xFF, 0xFF, 0xFF));
    private static readonly Brush MenuFill = Frozen(Color.FromRgb(0x1C, 0x1C, 0x1E));
    private static readonly Brush MenuBorder = Frozen(Color.FromRgb(0x3A, 0x3A, 0x3C));
    private static readonly Brush Primary = Frozen(Color.FromRgb(0xF5, 0xF5, 0xF7));
    private static readonly Brush Secondary = Frozen(Color.FromRgb(0x98, 0x98, 0x9D));

    private readonly TourId _tour;
    private readonly Func<IReadOnlyList<(string Keys, string Action)>>? _shortcuts;
    private readonly Popup _popup;

    public InfoButton(TourId tour, Func<IReadOnlyList<(string Keys, string Action)>>? shortcuts = null)
    {
        _tour = tour;
        _shortcuts = shortcuts;
        Width = 26;
        Height = 22;
        CornerRadius = new CornerRadius(5);
        Background = Brushes.Transparent;
        Cursor = Cursors.Hand;
        ToolTip = "Tour & Keyboard Shortcuts";
        AutomationProperties.SetName(this, "Tour & Keyboard Shortcuts");
        Child = new TextBlock
        {
            Text = "", FontFamily = IconFont, FontSize = 14, Foreground = Glyph,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        };
        _popup = new Popup
        {
            PlacementTarget = this, Placement = PlacementMode.Bottom, VerticalOffset = 4, StaysOpen = false,
            AllowsTransparency = true, PopupAnimation = PopupAnimation.Fade,
        };
        MouseEnter += (_, _) => Background = HoverFill;
        MouseLeave += (_, _) => Background = Brushes.Transparent;
        MouseLeftButtonDown += (_, e) =>
        {
            e.Handled = true;
            if (_popup.IsOpen) { _popup.IsOpen = false; return; }
            ShowMenu();
        };
    }

    private void ShowMenu()
    {
        var items = new StackPanel { Margin = new Thickness(4) };
        items.Children.Add(Row("", "Replay Tour", () =>
        {
            _popup.IsOpen = false;
            TourEvents.Replay(_tour, Window.GetWindow(this));
        }));
        if (_shortcuts?.Invoke() is { Count: > 0 })
            items.Children.Add(Row("", "Keyboard Shortcuts", ShowShortcuts));
        _popup.Child = Panel(items);
        _popup.IsOpen = true;
    }

    private void ShowShortcuts()
    {
        var list = _shortcuts?.Invoke() ?? Array.Empty<(string, string)>();
        var grid = new Grid { Margin = new Thickness(14, 12, 14, 12) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var title = new TextBlock { Text = "Keyboard Shortcuts", FontFamily = UiFont, FontSize = 13, FontWeight = FontWeights.SemiBold, Foreground = Primary, Margin = new Thickness(0, 0, 0, 10) };
        Grid.SetColumnSpan(title, 3);
        grid.Children.Add(title);
        int r = 1;
        foreach (var (keys, action) in list)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var a = new TextBlock { Text = action, FontFamily = UiFont, FontSize = 12, Foreground = Secondary, Margin = new Thickness(0, r > 1 ? 6 : 0, 0, 0) };
            var k = new TextBlock { Text = keys, FontFamily = UiFont, FontSize = 12, FontWeight = FontWeights.Medium, Foreground = Primary, HorizontalAlignment = HorizontalAlignment.Right, Margin = a.Margin };
            Grid.SetRow(a, r);
            Grid.SetRow(k, r);
            Grid.SetColumn(k, 2);
            grid.Children.Add(a);
            grid.Children.Add(k);
            r++;
        }
        _popup.IsOpen = false;
        _popup.Child = Panel(grid);
        _popup.IsOpen = true;
    }

    private static Border Panel(UIElement content) => new()
    {
        Background = MenuFill, BorderBrush = MenuBorder, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8),
        Child = content, Margin = new Thickness(0, 0, 8, 8),
        Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 10, ShadowDepth = 2, Direction = 270, Opacity = 0.4 },
    };

    private static Border Row(string icon, string label, Action onClick)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(new TextBlock { Text = icon, FontFamily = IconFont, FontSize = 13, Foreground = Primary, VerticalAlignment = VerticalAlignment.Center, Width = 18 });
        row.Children.Add(new TextBlock { Text = label, FontFamily = UiFont, FontSize = 13, Foreground = Primary, Margin = new Thickness(8, 0, 12, 0), VerticalAlignment = VerticalAlignment.Center });
        var b = new Border { Child = row, Padding = new Thickness(8, 5, 8, 5), CornerRadius = new CornerRadius(4), Background = Brushes.Transparent, Cursor = Cursors.Hand };
        AutomationProperties.SetName(b, label);
        b.MouseEnter += (_, _) => b.Background = HoverFill;
        b.MouseLeave += (_, _) => b.Background = Brushes.Transparent;
        b.MouseLeftButtonUp += (_, e) => { e.Handled = true; onClick(); };
        return b;
    }

    private static Brush Frozen(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
}
