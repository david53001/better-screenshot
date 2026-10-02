using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Controls;
using BetterScreenshot.History;
using Border = System.Windows.Controls.Border;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using FontFamily = System.Windows.Media.FontFamily;
using DataObject = System.Windows.DataObject;
using DragDropEffects = System.Windows.DragDropEffects;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Image = System.Windows.Controls.Image;
using Keyboard = System.Windows.Input.Keyboard;
using MouseButtonEventArgs = System.Windows.Input.MouseButtonEventArgs;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Orientation = System.Windows.Controls.Orientation;
using Point = System.Windows.Point;

namespace BetterScreenshot.App.History;

/// <summary>What the History window calls back into the capture layer for (reuses the coordinator's flows).</summary>
public sealed record HistoryWindowActions(Action<BitmapSource> Annotate, Action<BitmapSource> Pin)
{
    /// <summary>Edit Video… on a single MP4 recording whose file still exists (v3 Part 6; nothing is restored on close).</summary>
    public Action<string>? EditVideo { get; init; }

    /// <summary>The live Capture Area chord ("Ctrl+Shift+4"), named by the empty state (v3 §4.4 H3); null when unbound.</summary>
    public Func<string?>? CaptureAreaChord { get; init; }
}

/// <summary>
/// The capture-history browser (v3 §4.4): a thumbnail grid over <see cref="HistoryService"/> with a kind badge, the
/// relative date and the capture's pixel size or recording length; Ctrl/Shift multi-select
/// (<see cref="HistorySelection"/>), multi-file drag-out, double-click to open; an action bar (Copy · Annotate · Pin ·
/// Edit Video… · Show in Explorer · Delete) where Copy / Show in Explorer / Delete act on the whole selection and Delete
/// confirms when more than one is selected; "Clear All History…" lives in the ⋯ menu.
/// </summary>
public partial class HistoryWindow : Window
{
    // Cell surfaces are palette keys (History.* in Theme.xaml / ThemeLight.xaml), set by resource reference so the
    // grid follows the window's light/dark mode (round 3 #2).
    private static readonly Brush WarnBrush = Frozen(Color.FromRgb(0xFF, 0x9F, 0x0A));
    private static readonly Brush PlayDisc = Frozen(Color.FromArgb(0x99, 0x00, 0x00, 0x00));

    private readonly HistoryService _history;
    private readonly HistoryWindowActions _actions;
    private readonly Dictionary<Guid, Border> _cells = new();
    private readonly Dictionary<Guid, string?> _infoCache = new();
    private HistorySelectionState _selection = HistorySelectionState.Empty;
    private Guid? _pendingPlainClick;
    private Point? _pressAt;
    private Guid? _pressId;

    public HistoryWindow(HistoryService history, HistoryWindowActions actions)
    {
        InitializeComponent();
        Controls.Surfaces.UseMica(this); // v3 Part 9 + §4.9: History uses the window material too
        Controls.SystemTheme.Follow(this); // round 3 #2: light in Windows light mode
        _history = history;
        _actions = actions;
        InfoSlot.Content = new Tours.InfoButton(BetterScreenshot.Tours.TourId.History, () => new (string, string)[]
        {
            ("Click", "Select a capture"),
            ("Ctrl+click", "Add or remove one"),
            ("Shift+click", "Select a range"),
            ("Drag", "Drop the selection into another app"),
            ("Double-click", "Open (screenshots open in the editor)"),
        });
        Reload();
        ContentRendered += (_, _) => Tours.TourEvents.SurfaceShown(BetterScreenshot.Tours.TourSurface.History, this);
    }

    private IReadOnlyList<Guid> Order => _history.Entries.Select(e => e.Id).ToList();

    private IReadOnlyList<HistoryEntry> SelectedEntries =>
        _selection.InOrder(Order).Select(_history.Entry).OfType<HistoryEntry>().ToList();

    private HistoryEntry? Single => SelectedEntries is { Count: 1 } one ? one[0] : null;

    private void Reload()
    {
        CellsPanel.Children.Clear();
        _cells.Clear();
        var entries = _history.Entries;
        _selection = HistorySelection.Prune(_selection, Order);

        foreach (var entry in entries)
        {
            var cell = BuildCell(entry);
            _cells[entry.Id] = cell;
            CellsPanel.Children.Add(cell);
        }
        // Tour anchors: the newest cell, and the action bar only while there's something to act on (review H1).
        if (CellsPanel.Children.Count > 0) Tours.TourAnchors.Set(CellsPanel.Children[0], "history.item");
        Tours.TourAnchors.Set(ActionBar, entries.Count == 0 ? "" : "history.actions");

        var (title, detail) = HistoryEmptyState.Text(_history.Enabled, _actions.CaptureAreaChord?.Invoke());
        EmptyTitle.Text = title;
        EmptyDetail.Text = detail;
        EmptyState.Visibility = entries.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        Scroller.Visibility = entries.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        UpdateButtons();
    }

    private void UpdateButtons()
    {
        var selected = SelectedEntries;
        var single = selected.Count == 1 ? selected[0] : null;
        bool isScreenshot = single?.Kind == HistoryKind.Screenshot;
        int total = _history.Entries.Count;
        CountLabel.Text = selected.Count > 1
            ? $"{selected.Count} of {total} selected"
            : $"{total} item{(total == 1 ? "" : "s")}";
        CopyButton.IsEnabled = selected.Count > 0;
        AnnotateButton.IsEnabled = isScreenshot;
        PinButton.IsEnabled = isScreenshot;
        EditVideoButton.IsEnabled = single is { } r && EditablePath(r) is not null && _actions.EditVideo is not null;
        RevealButton.IsEnabled = selected.Any(CanReveal);
        DeleteButton.IsEnabled = selected.Count > 0;
        MoreButton.IsEnabled = total > 0;
    }

    /// <summary>The MP4 behind a recording entry, if it still exists.</summary>
    private string? EditablePath(HistoryEntry e) =>
        e.Kind == HistoryKind.Recording && _history.SavedFilePath(e) is { } p && File.Exists(p)
        && string.Equals(System.IO.Path.GetExtension(p), ".mp4", StringComparison.OrdinalIgnoreCase) ? p : null;

    private bool CanReveal(HistoryEntry e) => _history.FileFor(e) is not null;

    private Border BuildCell(HistoryEntry entry)
    {
        var thumb = new Image { Stretch = Stretch.Uniform, Height = 110, Source = LoadThumb(entry) };
        var thumbGrid = new Grid();
        thumbGrid.Children.Add(thumb);
        if (entry.Kind == HistoryKind.Recording)
        {
            // H2: recordings carry a play badge on the thumbnail.
            var play = new Grid { Width = 34, Height = 34, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, IsHitTestVisible = false };
            play.Children.Add(new System.Windows.Shapes.Ellipse { Fill = PlayDisc });
            play.Children.Add(new TextBlock
            {
                Text = "", FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), FontSize = 14,
                Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(2, 0, 0, 0),
            });
            thumbGrid.Children.Add(play);
        }
        var thumbHost = new Border { CornerRadius = new CornerRadius(8), Height = 110, Child = thumbGrid };
        thumbHost.SetResourceReference(Border.BackgroundProperty, "History.ThumbBrush");

        var badgeRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(2, 4, 0, 0) };
        var badge = new IconPresenter
        {
            IconKey = entry.Kind == HistoryKind.Recording ? "film" : "camera",
            Width = 15,
            Height = 15,
            VerticalAlignment = VerticalAlignment.Center,
        };
        badge.SetResourceReference(IconPresenter.BrushProperty, "History.BadgeBrush");
        badgeRow.Children.Add(badge);
        string text = HistoryDateFormat.Relative(DateTime.UtcNow, entry.Date);
        if (Info(entry) is { } info) text += "  ·  " + info;
        var when = new TextBlock
        {
            Text = text,
            FontSize = 11,
            Margin = new Thickness(5, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
            MaxWidth = 146,
        };
        when.SetResourceReference(TextBlock.ForegroundProperty, "History.BadgeBrush");
        badgeRow.Children.Add(when);
        if (entry.Kind == HistoryKind.Recording && !_history.SavedFileExists(entry))
        {
            badgeRow.Children.Add(new TextBlock
            {
                Text = "  file missing",
                Foreground = WarnBrush,
                FontSize = 10,
                VerticalAlignment = VerticalAlignment.Center,
            });
        }

        var stack = new StackPanel();
        stack.Children.Add(thumbHost);
        stack.Children.Add(badgeRow);

        var cell = new Border
        {
            Width = 180,
            Margin = new Thickness(6),
            Padding = new Thickness(6),
            CornerRadius = new CornerRadius(12), // §4.10: the tour outline is concentric with it (12 + 4)
            BorderThickness = new Thickness(2),
            Cursor = Cursors.Hand,
            Child = stack,
        };
        cell.SetResourceReference(Border.BackgroundProperty, "History.CellBrush");
        ShowSelected(cell, _selection.IsSelected(entry.Id));
        System.Windows.Automation.AutomationProperties.SetName(cell, (entry.Kind == HistoryKind.Recording ? "Recording, " : "Screenshot, ") + text);
        cell.MouseEnter += (_, _) => cell.SetResourceReference(Border.BackgroundProperty, "History.CellHoverBrush");
        cell.MouseLeave += (_, _) => cell.SetResourceReference(Border.BackgroundProperty, "History.CellBrush");
        cell.ContextMenu = BuildContextMenu(entry);
        cell.MouseRightButtonDown += (_, _) =>
        {
            if (!_selection.IsSelected(entry.Id)) Apply(HistorySelection.Click(_selection, entry.Id, HistoryClickModifier.None, Order));
        };
        cell.MouseLeftButtonDown += (_, e) => OnCellDown(entry, cell, e);
        cell.MouseMove += (_, e) => OnCellMove(cell, e);
        cell.MouseLeftButtonUp += (_, _) => OnCellUp(entry);
        return cell;
    }

    private System.Windows.Controls.ContextMenu BuildContextMenu(HistoryEntry entry)
    {
        var menu = new System.Windows.Controls.ContextMenu();
        void Add(string header, Action onClick, Func<bool> enabled)
        {
            var item = new System.Windows.Controls.MenuItem { Header = header };
            item.Click += (_, _) => onClick();
            menu.Opened += (_, _) => item.IsEnabled = enabled();
            menu.Items.Add(item);
        }
        Add("Copy", CopySelection, () => SelectedEntries.Count > 0);
        Add("Show in Explorer", RevealSelection, () => SelectedEntries.Any(CanReveal));
        if (EditablePath(entry) is { } editable && _actions.EditVideo is { } editVideo)
            Add("Edit Video…", () => editVideo(editable), () => SelectedEntries.Count == 1);
        menu.Items.Add(new Separator());
        Add("Delete", DeleteSelection, () => SelectedEntries.Count > 0);
        return menu;
    }

    // ------------------------------------------------------------------ selection + drag-out

    private static HistoryClickModifier CurrentModifier() =>
        (Keyboard.Modifiers & ModifierKeys.Shift) != 0 ? HistoryClickModifier.Range
        : (Keyboard.Modifiers & ModifierKeys.Control) != 0 ? HistoryClickModifier.Toggle
        : HistoryClickModifier.None;

    private void OnCellDown(HistoryEntry entry, Border cell, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
        {
            Apply(HistorySelection.Click(_selection, entry.Id, HistoryClickModifier.None, Order));
            Open(entry);
            return;
        }
        var modifier = CurrentModifier();
        _pressAt = e.GetPosition(cell);
        _pressId = entry.Id;
        if (HistorySelection.AppliesOnMouseUp(_selection, entry.Id, modifier))
            _pendingPlainClick = entry.Id; // a drag may still start from the whole selection
        else
            Apply(HistorySelection.Click(_selection, entry.Id, modifier, Order));
        Tours.TourEvents.Post(BetterScreenshot.Tours.TourEvent.Action("history.selected"));
    }

    private void OnCellUp(HistoryEntry entry)
    {
        if (_pendingPlainClick == entry.Id)
            Apply(HistorySelection.Click(_selection, entry.Id, HistoryClickModifier.None, Order));
        _pendingPlainClick = null;
        _pressAt = null;
        _pressId = null;
    }

    private void OnCellMove(Border cell, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || _pressAt is not { } at || _pressId is not { } id) return;
        var now = e.GetPosition(cell);
        if (Math.Abs(now.X - at.X) < SystemParameters.MinimumHorizontalDragDistance
            && Math.Abs(now.Y - at.Y) < SystemParameters.MinimumVerticalDragDistance) return;
        _pressAt = null;
        _pendingPlainClick = null;
        var (state, dragged) = HistorySelection.DragStart(_selection, id, Order);
        Apply(state);
        var files = dragged.Select(_history.Entry).OfType<HistoryEntry>().Select(_history.FileFor).OfType<string>().ToArray();
        if (files.Length == 0) return;
        var data = new DataObject();
        data.SetData(System.Windows.DataFormats.FileDrop, files);
        try { System.Windows.DragDrop.DoDragDrop(cell, data, DragDropEffects.Copy); }
        catch (Exception ex) // a target refused mid-drag: nothing to undo, but say what happened
        {
            BetterScreenshot.Platform.ErrorLog.Write("History drag-out failed", ex);
        }
    }

    private void Apply(HistorySelectionState state)
    {
        _selection = state;
        foreach (var (id, cell) in _cells) ShowSelected(cell, _selection.IsSelected(id));
        UpdateButtons();
    }

    /// <summary>Monochrome selection ring: the palette's strongest ink (white in dark mode, near-black in light).</summary>
    private static void ShowSelected(Border cell, bool selected)
    {
        if (selected) cell.SetResourceReference(Border.BorderBrushProperty, "History.SelectedBrush");
        else cell.BorderBrush = Brushes.Transparent;
    }

    // ------------------------------------------------------------------ H2 cell info

    /// <summary>"1920 × 1080" for a screenshot, "0:42 · MP4" for a recording — from file headers only, cached.</summary>
    private string? Info(HistoryEntry e)
    {
        if (_infoCache.TryGetValue(e.Id, out var cached)) return cached;
        string? text = null;
        try
        {
            if (e.Kind == HistoryKind.Screenshot && _history.ImagePath(e) is { } png && File.Exists(png))
            {
                using var fs = File.OpenRead(png);
                if (MediaInfo.PngSize(fs) is var (w, h)) text = MediaInfoText.PixelSize(w, h);
            }
            else if (e.Kind == HistoryKind.Recording && _history.SavedFilePath(e) is { } video && File.Exists(video))
            {
                using var fs = File.OpenRead(video);
                string ext = System.IO.Path.GetExtension(video);
                var length = ext.Equals(".gif", StringComparison.OrdinalIgnoreCase) ? MediaInfo.GifDuration(fs) : MediaInfo.Mp4Duration(fs);
                text = MediaInfoText.Recording(length, ext);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        _infoCache[e.Id] = text;
        return text;
    }

    private ImageSource? LoadThumb(HistoryEntry entry)
    {
        var path = _history.ThumbPath(entry);
        if (!File.Exists(path)) return null;
        try
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.UriSource = new Uri(path);
            bmp.EndInit();
            bmp.Freeze();
            return bmp;
        }
        catch
        {
            return null;
        }
    }

    // ------------------------------------------------------------------ actions

    private void Open(HistoryEntry entry)
    {
        if (entry.Kind == HistoryKind.Screenshot)
        {
            var image = _history.LoadImage(entry);
            if (image != null) _actions.Annotate(image);
        }
        else if (_history.SavedFilePath(entry) is { } path && File.Exists(path))
        {
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path) { UseShellExecute = true }); }
            catch { /* best-effort open */ }
        }
    }

    private void Copy_Click(object sender, RoutedEventArgs e) => CopySelection();

    private void CopySelection() => _history.CopyToClipboard(SelectedEntries);

    private void EditVideo_Click(object sender, RoutedEventArgs e)
    {
        if (Single is { } s && EditablePath(s) is { } p) _actions.EditVideo?.Invoke(p);
    }

    private void Annotate_Click(object sender, RoutedEventArgs e)
    {
        if (Single is { Kind: HistoryKind.Screenshot } s && _history.LoadImage(s) is { } img)
            _actions.Annotate(img);
    }

    private void Pin_Click(object sender, RoutedEventArgs e)
    {
        if (Single is { Kind: HistoryKind.Screenshot } s && _history.LoadImage(s) is { } img)
            _actions.Pin(img);
    }

    private void Reveal_Click(object sender, RoutedEventArgs e) => RevealSelection();

    private void RevealSelection() => _history.RevealInExplorer(SelectedEntries);

    private void Delete_Click(object sender, RoutedEventArgs e) => DeleteSelection();

    private void DeleteSelection()
    {
        var selected = SelectedEntries;
        if (selected.Count == 0) return;
        if (selected.Count > 1)
        {
            var confirm = System.Windows.MessageBox.Show(this,
                "Their stored copies are removed from History. Saved recording files on disk are not deleted.",
                $"Delete {selected.Count} captures from History?",
                System.Windows.MessageBoxButton.OKCancel, System.Windows.MessageBoxImage.Warning, System.Windows.MessageBoxResult.Cancel);
            if (confirm != System.Windows.MessageBoxResult.OK) return;
        }
        foreach (var s in selected) _history.Delete(s.Id);
        _selection = HistorySelectionState.Empty;
        Reload();
    }

    private void More_Click(object sender, RoutedEventArgs e)
    {
        // H4: the destructive Clear All lives here, out of the action row.
        var clear = new System.Windows.Controls.MenuItem { Header = "Clear All History…", Foreground = (Brush)FindResource("Theme.DangerBrush") };
        clear.Click += (_, _) => ClearAll();
        var menu = new System.Windows.Controls.ContextMenu
        {
            PlacementTarget = MoreButton,
            Placement = System.Windows.Controls.Primitives.PlacementMode.Top,
            Items = { clear },
        };
        clear.IsEnabled = _history.Entries.Count > 0;
        menu.IsOpen = true;
    }

    private void ClearAll()
    {
        if (_history.Entries.Count == 0) return;
        var confirm = System.Windows.MessageBox.Show(
            this,
            "Removes every remembered capture and its stored copies. Saved recording files on disk are not deleted.",
            "Clear all capture history?",
            System.Windows.MessageBoxButton.OKCancel,
            System.Windows.MessageBoxImage.Warning,
            System.Windows.MessageBoxResult.Cancel);
        if (confirm == System.Windows.MessageBoxResult.OK)
        {
            _history.ClearAll();
            _selection = HistorySelectionState.Empty;
            Reload();
        }
    }

    private static Brush Frozen(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
}
