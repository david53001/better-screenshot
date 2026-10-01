using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Controls;
using BetterScreenshot.History;
using Border = System.Windows.Controls.Border;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Image = System.Windows.Controls.Image;
using MouseButtonEventArgs = System.Windows.Input.MouseButtonEventArgs;
using Orientation = System.Windows.Controls.Orientation;
using Path = System.Windows.Shapes.Path;

namespace BetterScreenshot.App.History;

/// <summary>What the History window calls back into the capture layer for (reuses the coordinator's flows).</summary>
public sealed record HistoryWindowActions(Action<BitmapSource> Annotate, Action<BitmapSource> Pin)
{
    /// <summary>Edit Video… on a single MP4 recording whose file still exists (v3 Part 6; nothing is restored on close).</summary>
    public Action<string>? EditVideo { get; init; }
}

/// <summary>
/// The capture-history browser: a thumbnail grid over <see cref="HistoryService"/> with a kind badge + relative
/// date, single-click select, double-click open (annotate / play), and an action bar
/// (Copy / Annotate / Pin / Show in Explorer / Delete / Clear All). Screenshots are annotate/pin-able; recordings
/// are copy/reveal/open only. The grid refreshes after any mutation.
/// </summary>
public partial class HistoryWindow : Window
{
    private static readonly Brush CellBg = new SolidColorBrush(Color.FromRgb(0x16, 0x16, 0x18));
    private static readonly Brush ThumbBg = new SolidColorBrush(Color.FromRgb(0x0E, 0x0E, 0x0E));
    private static readonly Brush SelectedBorder = new SolidColorBrush(Color.FromRgb(0xFF, 0xFF, 0xFF)); // monochrome selection (was blue)
    private static readonly Brush BadgeBrush = new SolidColorBrush(Color.FromRgb(0xB0, 0xB0, 0xB5));
    private static readonly Brush WarnBrush = new SolidColorBrush(Color.FromRgb(0xFF, 0x9F, 0x0A));

    private readonly HistoryService _history;
    private readonly HistoryWindowActions _actions;
    private Guid? _selected;

    public HistoryWindow(HistoryService history, HistoryWindowActions actions)
    {
        InitializeComponent();
        Controls.Surfaces.UseMica(this); // v3 Part 9 + §4.9: History uses the window material too
        _history = history;
        _actions = actions;
        InfoSlot.Content = new Tours.InfoButton(BetterScreenshot.Tours.TourId.History, () => new (string, string)[]
        {
            ("Click", "Select a capture"),
            ("Double-click", "Open (screenshots open in the editor)"),
            ("Right-click", "More actions"),
        });
        Reload();
        ContentRendered += (_, _) => Tours.TourEvents.SurfaceShown(BetterScreenshot.Tours.TourSurface.History, this);
    }

    private HistoryEntry? Selected => _selected is { } id ? _history.Entry(id) : null;

    private void Reload()
    {
        CellsPanel.Children.Clear();
        var entries = _history.Entries;
        if (_selected is { } id && _history.Entry(id) is null) _selected = null;

        foreach (var entry in entries)
            CellsPanel.Children.Add(BuildCell(entry));
        // Tour anchors: the newest cell, and the action bar only while there's something to act on (review H1).
        if (CellsPanel.Children.Count > 0) Tours.TourAnchors.Set(CellsPanel.Children[0], "history.item");
        Tours.TourAnchors.Set(ActionBar, entries.Count == 0 ? "" : "history.actions");

        EmptyLabel.Visibility = entries.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        Scroller.Visibility = entries.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        CountLabel.Text = $"{entries.Count} item{(entries.Count == 1 ? "" : "s")}";
        UpdateButtons();
    }

    private void UpdateButtons()
    {
        var sel = Selected;
        bool isScreenshot = sel?.Kind == HistoryKind.Screenshot;
        CopyButton.IsEnabled = sel != null;
        AnnotateButton.IsEnabled = isScreenshot;
        PinButton.IsEnabled = isScreenshot;
        EditVideoButton.IsEnabled = sel is { } r && EditablePath(r) is not null && _actions.EditVideo is not null;
        RevealButton.IsEnabled = sel != null && CanReveal(sel);
        DeleteButton.IsEnabled = sel != null;
        ClearAllButton.IsEnabled = _history.Entries.Count > 0;
    }

    /// <summary>The MP4 behind a recording entry, if it still exists.</summary>
    private string? EditablePath(HistoryEntry e) =>
        e.Kind == HistoryKind.Recording && _history.SavedFilePath(e) is { } p && File.Exists(p)
        && string.Equals(System.IO.Path.GetExtension(p), ".mp4", StringComparison.OrdinalIgnoreCase) ? p : null;

    private void EditVideo_Click(object sender, RoutedEventArgs e)
    {
        if (Selected is { } s && EditablePath(s) is { } p) _actions.EditVideo?.Invoke(p);
    }

    private bool CanReveal(HistoryEntry e) => e.Kind == HistoryKind.Screenshot
        ? _history.ImagePath(e) is { } p && File.Exists(p)
        : _history.SavedFileExists(e);

    private Border BuildCell(HistoryEntry entry)
    {
        var thumb = new Image
        {
            Stretch = Stretch.Uniform,
            Height = 110,
            Source = LoadThumb(entry),
        };
        var thumbHost = new Border
        {
            Background = ThumbBg,
            CornerRadius = new CornerRadius(6),
            Height = 110,
            Child = thumb,
        };

        var badgeRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(2, 4, 0, 0) };
        badgeRow.Children.Add(new IconPresenter
        {
            IconKey = entry.Kind == HistoryKind.Recording ? "film" : "camera",
            Brush = BadgeBrush,
            Width = 15,
            Height = 15,
            VerticalAlignment = VerticalAlignment.Center,
        });
        badgeRow.Children.Add(new TextBlock
        {
            Text = HistoryDateFormat.Relative(DateTime.UtcNow, entry.Date),
            Foreground = BadgeBrush,
            FontSize = 11,
            Margin = new Thickness(5, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
        });
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
            CornerRadius = new CornerRadius(8),
            Background = CellBg,
            BorderThickness = new Thickness(2),
            BorderBrush = _selected == entry.Id ? SelectedBorder : Brushes.Transparent,
            Cursor = Cursors.Hand,
            Child = stack,
        };
        if (EditablePath(entry) is { } editable && _actions.EditVideo is { } editVideo)
        {
            var item = new System.Windows.Controls.MenuItem { Header = "Edit Video…" };
            item.Click += (_, _) => editVideo(editable);
            cell.ContextMenu = new System.Windows.Controls.ContextMenu { Items = { item } };
        }
        cell.MouseRightButtonDown += (_, _) => Select(entry.Id);
        cell.MouseLeftButtonDown += (_, e) =>
        {
            if (e.ClickCount == 2) Open(entry);
            else Select(entry.Id);
            if (e.ClickCount == 1) Tours.TourEvents.Post(BetterScreenshot.Tours.TourEvent.Action("history.selected"));
        };
        return cell;
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

    private void Select(Guid id)
    {
        _selected = id;
        RefreshSelectionBorders();
        UpdateButtons();
    }

    private void RefreshSelectionBorders()
    {
        var entries = _history.Entries;
        for (int i = 0; i < CellsPanel.Children.Count && i < entries.Count; i++)
        {
            if (CellsPanel.Children[i] is Border b)
                b.BorderBrush = _selected == entries[i].Id ? SelectedBorder : Brushes.Transparent;
        }
    }

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

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        if (Selected is { } s) _history.CopyToClipboard(s);
    }

    private void Annotate_Click(object sender, RoutedEventArgs e)
    {
        if (Selected is { Kind: HistoryKind.Screenshot } s && _history.LoadImage(s) is { } img)
            _actions.Annotate(img);
    }

    private void Pin_Click(object sender, RoutedEventArgs e)
    {
        if (Selected is { Kind: HistoryKind.Screenshot } s && _history.LoadImage(s) is { } img)
            _actions.Pin(img);
    }

    private void Reveal_Click(object sender, RoutedEventArgs e)
    {
        if (Selected is { } s) _history.RevealInExplorer(s);
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (Selected is { } s)
        {
            _history.Delete(s.Id);
            _selected = null;
            Reload();
        }
    }

    private void ClearAll_Click(object sender, RoutedEventArgs e)
    {
        if (_history.Entries.Count == 0) return;
        var confirm = System.Windows.MessageBox.Show(
            this,
            "Removes every remembered capture and its stored copies. Saved recording files on disk are not deleted.",
            "Clear all capture history?",
            System.Windows.MessageBoxButton.OKCancel,
            System.Windows.MessageBoxImage.Warning);
        if (confirm == System.Windows.MessageBoxResult.OK)
        {
            _history.ClearAll();
            _selected = null;
            Reload();
        }
    }
}
