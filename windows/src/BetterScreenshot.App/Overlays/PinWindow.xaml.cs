using System.Windows;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using ContextMenu = System.Windows.Controls.ContextMenu;
using MenuItem = System.Windows.Controls.MenuItem;
using MouseButtonEventArgs = System.Windows.Input.MouseButtonEventArgs;
using MouseWheelEventArgs = System.Windows.Input.MouseWheelEventArgs;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// A floating, always-on-top pinned image. Drag to move, scroll to resize (aspect-locked 0.25×–3× via the tested
/// <see cref="PinGeometry.ZoomedFrame"/>), double-click to copy, right-click for Copy/Save/Close. Multi-pin capable.
/// </summary>
public partial class PinWindow : Window
{
    private readonly PxSize _naturalSize; // logical (DIP) natural size, for aspect-locked zoom
    private readonly PinActions _actions;

    public PinWindow(BitmapSource image, PinStyle style, PinActions actions, PxSize naturalSize)
    {
        InitializeComponent();
        Img.Source = image;
        _naturalSize = naturalSize;
        _actions = actions;

        Frame.CornerRadius = new CornerRadius(style.CornerRadius);
        if (style.Shadow) Frame.Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 2, Opacity = 0.35 };

        MouseEnter += (_, _) => CloseButton.Visibility = Visibility.Visible;
        MouseLeave += (_, _) => CloseButton.Visibility = Visibility.Collapsed;
        MouseLeftButtonDown += OnLeftDown;
        MouseWheel += OnWheel;
        ContextMenu = BuildMenu();
    }

    private void OnLeftDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2) { _actions.OnCopy(); return; }
        DragMove();
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();

    private void OnWheel(object sender, MouseWheelEventArgs e)
    {
        double factor = 1 + e.Delta * 0.001;
        var zoomed = PinGeometry.ZoomedFrame(new PxRect(Left, Top, Width, Height), _naturalSize, factor);
        Left = zoomed.X;
        Top = zoomed.Y;
        Width = zoomed.Width;
        Height = zoomed.Height;
    }

    private ContextMenu BuildMenu()
    {
        var menu = new ContextMenu();
        menu.Items.Add(Item("Copy", () => _actions.OnCopy()));
        menu.Items.Add(Item("Save", () => _actions.OnSave()));
        menu.Items.Add(Item("Close", Close));
        return menu;
    }

    private static MenuItem Item(string header, Action onClick)
    {
        var item = new MenuItem { Header = header };
        item.Click += (_, _) => onClick();
        return item;
    }
}
