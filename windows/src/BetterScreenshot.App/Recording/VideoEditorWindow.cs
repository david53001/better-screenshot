using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using BetterScreenshot.App.Controls;
using BetterScreenshot.App.Overlays;
using BetterScreenshot.Recording;
using Border = System.Windows.Controls.Border;
using Brush = System.Windows.Media.Brush;
using Button = System.Windows.Controls.Button;
using CheckBox = System.Windows.Controls.CheckBox;
using Color = System.Windows.Media.Color;
using ContextMenu = System.Windows.Controls.ContextMenu;
using Cursors = System.Windows.Input.Cursors;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MenuItem = System.Windows.Controls.MenuItem;
using Orientation = System.Windows.Controls.Orientation;
using ProgressBar = System.Windows.Controls.ProgressBar;
using RadioButton = System.Windows.Controls.RadioButton;
using ScrollBarVisibility = System.Windows.Controls.ScrollBarVisibility;
using Separator = System.Windows.Controls.Separator;
using Slider = System.Windows.Controls.Slider;
using TextBlock = System.Windows.Controls.TextBlock;
using VerticalAlignment = System.Windows.VerticalAlignment;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// The recording editor (Mac v3 A.3 export rules + Part 6 cut editor + Part 0 card restore): preview, filmstrip
/// timeline with split / delete / edge trim / per-segment speed + mute, undo / redo, and Save as Copy · Export as
/// GIF · Replace Original. Nothing touches the original until an export succeeds. <see cref="RestoreCard"/> runs
/// exactly once when the window closes, whatever closed it (Part 0). Preview = the source in a MediaElement that
/// skips cuts, applies each segment's speed and mutes muted segments (WPF can't play a cut list directly).
/// </summary>
public sealed class VideoEditorWindow : Window
{
    private static readonly Brush White85 = Frozen(Color.FromArgb(0xD9, 0xFF, 0xFF, 0xFF));
    private static readonly Brush White60 = Frozen(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF));
    private static readonly Brush White55 = Frozen(Color.FromArgb(0x8C, 0xFF, 0xFF, 0xFF));
    private static readonly Brush White50 = Frozen(Color.FromArgb(0x80, 0xFF, 0xFF, 0xFF));
    private static readonly Brush White45 = Frozen(Color.FromArgb(0x73, 0xFF, 0xFF, 0xFF));
    private static readonly Brush White30 = Frozen(Color.FromArgb(0x4D, 0xFF, 0xFF, 0xFF));

    private readonly string _path;
    private readonly List<Action> _restore = new();
    private readonly MediaElement _player = new() { LoadedBehavior = MediaState.Manual, UnloadedBehavior = MediaState.Manual, ScrubbingEnabled = true, Stretch = Stretch.Uniform };
    private readonly CutTimeline _timeline = new();
    private readonly ScrollViewer _timelineScroller = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled };
    private readonly DispatcherTimer _tick = new() { Interval = TimeSpan.FromMilliseconds(30) };
    private readonly TextBlock _time = new(), _segTitle = new(), _segRange = new(), _hint = new(), _kept = new(), _pct = new();
    private readonly IconPresenter _playIcon = new() { IconKey = "play", Width = 15, Height = 15 };
    private readonly Button _playButton = new(), _split = new(), _delete = new(), _undo = new(), _redo = new(), _zoomOut = new(), _zoomIn = new();
    private readonly Button _cancel = new(), _saveCopy = new(), _saveMenu = new(), _replace = new();
    private readonly Slider _zoom = new() { Minimum = 1, Maximum = 12, Value = 1, Width = 110, VerticalAlignment = VerticalAlignment.Center };
    private readonly RadioButton[] _speeds = new RadioButton[CutList.Speeds.Length];
    private readonly CheckBox _muteSegment = new() { Content = "Mute segment" }, _muteAll = new() { Content = "Mute whole video" };
    private readonly ProgressBar _progress = new() { Width = 160, Height = 6, Minimum = 0, Maximum = 1, VerticalAlignment = VerticalAlignment.Center };
    private readonly Grid _body = new(), _errorPanel = new();
    private readonly Border _card = new();
    private CutHistory _history = new(new CutList(1));
    private MediaInfo? _info;
    private int _selected;
    private double _playhead;
    private bool _playing, _exporting, _broken, _updating;
    private int _playIndex;
    private string? _note;
    private string? _framesDir;

    /// <summary>A copy was saved (it needs its own card + History entry).</summary>
    public Action<string>? CopySaved { get; init; }
    /// <summary>A GIF was exported (it needs its own card + History entry).</summary>
    public Action<string>? GifSaved { get; init; }

    public string FilePath => _path;

    public VideoEditorWindow(string path, Action? restoreCard)
    {
        _path = path;
        if (restoreCard is not null) _restore.Add(restoreCard);
        Title = "Edit Video — " + Path.GetFileName(path);
        Width = 960;
        Height = 720;
        MinWidth = 780;
        MinHeight = 560;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Foreground = System.Windows.Media.Brushes.White;
        Content = BuildLayout();
        Surfaces.UseMica(this); // dark translucent material + the Opacity layer
        Loaded += async (_, _) => await LoadAsync();
        ContentRendered += (_, _) => Tours.TourEvents.SurfaceShown(BetterScreenshot.Tours.TourSurface.VideoEditor, this);
        PreviewKeyDown += OnKey;
        Closing += (_, e) => { if (_exporting) e.Cancel = true; };
        Closed += (_, _) => OnClosedOnce();
        _tick.Tick += (_, _) => OnPlaybackTick();
        _player.MediaEnded += (_, _) => { if (_playing) StopAtEnd(); };
    }

    /// <summary>Opening the same file from another card chains its restore onto this window's close (both come back).</summary>
    public void AddRestore(Action restore) => _restore.Add(restore);

    // ------------------------------------------------------------------ layout

    private UIElement BuildLayout()
    {
        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(52) });

        // Body: preview + card (or the error block).
        _body.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star), MinHeight = 200 });
        _body.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var preview = new Border { Background = System.Windows.Media.Brushes.Black, Child = _player, Cursor = Cursors.Hand, Margin = new Thickness(0, 0, 0, 12) };
        Tours.TourAnchors.Set(preview, "video.preview");
        preview.MouseLeftButtonUp += (_, _) => TogglePlay();
        _body.Children.Add(preview);
        _card.SetResourceReference(Border.BackgroundProperty, "Panel.SurfaceBrush");
        _card.BorderBrush = Frozen(Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF));
        _card.BorderThickness = new Thickness(1);
        _card.CornerRadius = new CornerRadius(12);
        _card.Padding = new Thickness(14, 12, 14, 12);
        _card.Margin = new Thickness(12, 0, 12, 12);
        _card.Child = BuildCard();
        Grid.SetRow(_card, 1);
        _body.Children.Add(_card);
        root.Children.Add(_body);
        _errorPanel.Visibility = Visibility.Collapsed;
        root.Children.Add(_errorPanel);

        var bar = BuildActionBar();
        Grid.SetRow(bar, 1);
        root.Children.Add(bar);
        return root;
    }

    private UIElement BuildCard()
    {
        var stack = new StackPanel();

        // 1. transport / edit row
        var row = new DockPanel { Height = 28, LastChildFill = false };
        _playButton.Content = _playIcon;
        StyleButton(_playButton, borderless: true, width: 29);
        _playButton.Click += (_, _) => TogglePlay();
        Dock(row, _playButton);
        _time.FontFamily = new System.Windows.Media.FontFamily("Segoe UI Variable Text, Segoe UI");
        _time.Typography.NumeralAlignment = FontNumeralAlignment.Tabular;
        _time.FontSize = 12;
        _time.FontWeight = FontWeights.Medium;
        _time.Foreground = White85;
        _time.MinWidth = 116;
        _time.Margin = new Thickness(8, 0, 10, 0);
        _time.VerticalAlignment = VerticalAlignment.Center;
        _time.ToolTip = "Playhead / length of the edit";
        Dock(row, _time);
        Labelled(_split, "scissors", "Split", "Split the segment at the playhead (S or Ctrl+B)", Split);
        Labelled(_delete, "trash", "Delete", "Delete the selected (yellow) segment (Delete)", DeleteSelected);
        Dock(row, _split);
        Dock(row, _delete, 8);
        Dock(row, new Border { Width = 1, Height = 18, Background = Frozen(Color.FromArgb(0x26, 0xFF, 0xFF, 0xFF)), Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
        IconOnly(_undo, "undo", "Undo (Ctrl+Z)", () => { if (_history.Undo()) AfterHistoryMove(); });
        IconOnly(_redo, "redo", "Redo (Ctrl+Shift+Z)", () => { if (_history.Redo()) AfterHistoryMove(); });
        Dock(row, _undo, 8);
        Dock(row, _redo, 8);
        IconOnly(_zoomIn, "zoom-in", "Zoom in the timeline", () => _zoom.Value = Math.Min(12, _zoom.Value * 1.5), borderless: true);
        IconOnly(_zoomOut, "zoom-out", "Zoom out the timeline", () => _zoom.Value = Math.Max(1, _zoom.Value / 1.5), borderless: true);
        _zoom.ToolTip = "Timeline zoom";
        DockPanel.SetDock(_zoomIn, System.Windows.Controls.Dock.Right);
        DockPanel.SetDock(_zoom, System.Windows.Controls.Dock.Right);
        DockPanel.SetDock(_zoomOut, System.Windows.Controls.Dock.Right);
        _zoom.Margin = new Thickness(4, 0, 4, 0);
        row.Children.Add(_zoomIn);
        row.Children.Add(_zoom);
        row.Children.Add(_zoomOut);
        _zoom.ValueChanged += (_, _) => ApplyZoom();
        stack.Children.Add(row);

        // 2. timeline
        _timelineScroller.Content = _timeline;
        _timelineScroller.Margin = new Thickness(0, 10, 0, 0);
        _timelineScroller.Height = CutTimeline.ViewHeight + 12;
        _timelineScroller.SizeChanged += (_, _) => ApplyZoom();
        _timeline.Seek += (output, index) => { Pause(); _selected = index; SetPlayhead(output, seekPlayer: true); Refresh(); };
        _timeline.EdgeDragging += (work, preview) => { Pause(); _timeline.Cuts = work; _player.Position = TimeSpan.FromSeconds(preview); UpdateKeptLabel(work); };
        _timeline.EdgeDragged += (final, index, start) =>
        {
            _history.Commit(final);
            _selected = Math.Min(index, _history.Current.Segments.Count - 1);
            var seg = _history.Current.Segments[_selected];
            double source = start ? seg.Start : Math.Max(seg.Start, seg.End - 1.0 / 60);
            _note = null;
            SetPlayhead(_history.Current.OutputTimeForSource(source) ?? 0, seekPlayer: true);
            Refresh();
        };
        _timeline.SegmentMenu += ShowSegmentMenu;
        stack.Children.Add(_timelineScroller);

        // 3. selected-segment row
        var seg = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 10, 0, 0), Height = 24 };
        Tours.TourAnchors.Set(seg, "video.segment");
        _segTitle.FontSize = 11;
        _segTitle.FontWeight = FontWeights.SemiBold;
        _segTitle.Foreground = Frozen(Color.FromArgb(0xE6, 0xFF, 0xFF, 0xFF));
        _segTitle.VerticalAlignment = VerticalAlignment.Center;
        _segRange.FontSize = 11;
        _segRange.Foreground = White50;
        _segRange.Typography.NumeralAlignment = FontNumeralAlignment.Tabular;
        _segRange.Margin = new Thickness(8, 0, 14, 0);
        _segRange.VerticalAlignment = VerticalAlignment.Center;
        _segRange.ToolTip = "Where this segment comes from in the original recording";
        seg.Children.Add(_segTitle);
        seg.Children.Add(_segRange);
        seg.Children.Add(new TextBlock { Text = "Speed", FontSize = 11, Foreground = White60, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) });
        var speedRow = new StackPanel { Orientation = Orientation.Horizontal, ToolTip = "Play this segment faster (sped-up segments start muted)" };
        for (int i = 0; i < CutList.Speeds.Length; i++)
        {
            double speed = CutList.Speeds[i];
            var rb = new RadioButton
            {
                Content = speed == 1 ? "1×" : CutTimeline.FormatSpeed(speed), GroupName = "editor-speed", MinWidth = 46, FontSize = 11, // sized by the segment template (round 1 #9)
                Style = (Style)FindResource(i == 0 ? "Theme.SegmentLeft" : i == CutList.Speeds.Length - 1 ? "Theme.SegmentRight" : "Theme.SegmentMid"),
            };
            rb.Checked += (_, _) => { if (!_updating) ApplyEdit(c => c.SetSpeed(speed, _selected)); };
            _speeds[i] = rb;
            speedRow.Children.Add(rb);
        }
        seg.Children.Add(speedRow);
        _muteSegment.FontSize = 11;
        _muteSegment.Margin = new Thickness(10, 0, 0, 0);
        _muteSegment.VerticalAlignment = VerticalAlignment.Center;
        _muteSegment.ToolTip = "Silence this segment's audio (the rest keeps its sound)";
        _muteSegment.Click += (_, _) => ApplyEdit(c => c.SetMuted(_muteSegment.IsChecked == true, _selected));
        seg.Children.Add(_muteSegment);
        stack.Children.Add(seg);

        // 4. hint line + export progress slot (fixed 16 high: showing progress moves nothing)
        var hint = new DockPanel { Height = 16, Margin = new Thickness(0, 8, 0, 0), LastChildFill = true };
        var info = new IconPresenter { IconKey = "info", Width = 11, Height = 11, Brush = White45, Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };
        DockPanel.SetDock(info, System.Windows.Controls.Dock.Left);
        hint.Children.Add(info);
        _pct.Width = 34;
        _pct.FontSize = 11;
        _pct.Foreground = White60;
        _pct.TextAlignment = TextAlignment.Right;
        _pct.VerticalAlignment = VerticalAlignment.Center;
        _pct.Typography.NumeralAlignment = FontNumeralAlignment.Tabular;
        DockPanel.SetDock(_pct, System.Windows.Controls.Dock.Right);
        DockPanel.SetDock(_progress, System.Windows.Controls.Dock.Right);
        _progress.Margin = new Thickness(8, 0, 4, 0);
        _progress.Visibility = _pct.Visibility = Visibility.Collapsed;
        hint.Children.Add(_pct);
        hint.Children.Add(_progress);
        _hint.FontSize = 11;
        _hint.Foreground = White55;
        _hint.TextTrimming = TextTrimming.CharacterEllipsis;
        _hint.VerticalAlignment = VerticalAlignment.Center;
        hint.Children.Add(_hint);
        stack.Children.Add(hint);
        return stack;
    }

    private UIElement BuildActionBar()
    {
        var bar = new Border
        {
            Background = Frozen(Color.FromRgb(0x1F, 0x1F, 0x21)),
            BorderBrush = Frozen(Color.FromArgb(0x1F, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(0, 1, 0, 0),
            Padding = new Thickness(16, 0, 16, 0),
        };
        var row = new DockPanel { LastChildFill = false, VerticalAlignment = VerticalAlignment.Center };
        _kept.FontSize = 12;
        _kept.Foreground = (Brush)FindResource("Theme.SecondaryTextBrush");
        _kept.Typography.NumeralAlignment = FontNumeralAlignment.Tabular;
        _kept.VerticalAlignment = VerticalAlignment.Center;
        _kept.ToolTip = "Length of the saved video / length of the recording";
        Dock(row, _kept);
        _muteAll.Margin = new Thickness(14, 0, 0, 0);
        _muteAll.VerticalAlignment = VerticalAlignment.Center;
        _muteAll.ToolTip = "Save without any sound";
        _muteAll.Click += (_, _) => { _note = null; ApplyPlaybackAudio(); Refresh(); };
        Dock(row, _muteAll);

        _replace.Content = "Replace Original";
        _replace.Style = (Style)FindResource("Theme.AccentButton");
        _replace.Padding = new Thickness(12, 4, 12, 4);
        _replace.Click += async (_, _) => await ReplaceAsync();
        _saveCopy.Content = "Save as Copy";
        _saveCopy.Padding = new Thickness(12, 4, 8, 4);
        _saveCopy.ToolTip = "Save the edit as a new file next to the original — the ▾ menu exports a GIF";
        _saveCopy.Click += async (_, _) => await SaveCopyAsync();
        _saveMenu.Content = new IconPresenter { IconKey = "chevron-down", Width = 12, Height = 12, Brush = White85 };
        _saveMenu.Padding = new Thickness(6, 4, 6, 4);
        _saveMenu.ToolTip = _saveCopy.ToolTip;
        var gifItem = new MenuItem { Header = "Export as GIF", ToolTip = "Save the edit as an animated GIF next to the original (10 fps, up to 960 px wide)" };
        gifItem.Click += async (_, _) => await ExportGifAsync();
        _saveMenu.ContextMenu = new ContextMenu { Items = { gifItem } };
        _saveMenu.Click += (_, _) => { _saveMenu.ContextMenu.PlacementTarget = _saveMenu; _saveMenu.ContextMenu.Placement = PlacementMode.Bottom; _saveMenu.ContextMenu.IsOpen = true; };
        var split = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(10, 0, 0, 0) };
        split.Children.Add(_saveCopy);
        split.Children.Add(_saveMenu);
        Tours.TourAnchors.Set(split, "video.saveCopy");
        Tours.TourAnchors.Set(_replace, "video.replace");
        Tours.TourAnchors.Set(_timelineScroller, "video.timeline");
        var infoButton = new Tours.InfoButton(BetterScreenshot.Tours.TourId.VideoEditor, () => new (string, string)[]
        {
            ("Space", "Play / pause"), ("S", "Split at the playhead"), ("Delete", "Delete the selected part"),
            ("I", "Trim the start to the playhead"), ("O", "Trim the end to the playhead"), ("← →", "One frame back / forward"),
            ("Ctrl+Z", "Undo"), ("Ctrl+Shift+Z", "Redo"),
        }) { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(10, 0, 0, 0) };
        Dock(row, infoButton);
        _cancel.Content = "Cancel";
        _cancel.Padding = new Thickness(12, 4, 12, 4);
        _cancel.ToolTip = "Close without saving";
        _cancel.Click += (_, _) => Close();
        foreach (var el in new FrameworkElement[] { _replace, split, _cancel })
        {
            DockPanel.SetDock(el, System.Windows.Controls.Dock.Right);
            el.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(el);
        }
        _replace.Margin = new Thickness(10, 0, 0, 0);
        bar.Child = row;
        return bar;
    }

    private void StyleButton(Button b, bool borderless, double width = 0)
    {
        if (borderless) b.Style = (Style)FindResource("Theme.SubtleButton");
        if (width > 0) b.Width = width;
        b.Height = 28;
        b.Cursor = Cursors.Hand;
        b.VerticalAlignment = VerticalAlignment.Center;
    }

    private void Labelled(Button b, string icon, string label, string tip, Action click)
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal };
        sp.Children.Add(new IconPresenter { IconKey = icon, Width = 13, Height = 13, Brush = White85, Margin = new Thickness(0, 0, 5, 0), VerticalAlignment = VerticalAlignment.Center });
        sp.Children.Add(new TextBlock { Text = label, FontSize = 12, VerticalAlignment = VerticalAlignment.Center });
        b.Content = sp;
        b.ToolTip = tip;
        b.Padding = new Thickness(10, 0, 10, 0);
        b.Height = 28;
        b.Click += (_, _) => click();
        ToolTipService.SetShowOnDisabled(b, true);
    }

    private void IconOnly(Button b, string icon, string tip, Action click, bool borderless = false)
    {
        b.Content = new IconPresenter { IconKey = icon, Width = 13, Height = 13, Brush = White85 };
        b.ToolTip = tip;
        b.Padding = new Thickness(0); // the implicit Button padding (12,5) left 8 px and clipped the glyph (round 1 #8)
        b.Width = borderless ? 26 : 32;
        b.Height = 28;
        if (borderless) b.Style = (Style)FindResource("Theme.SubtleButton");
        b.Click += (_, _) => click();
        ToolTipService.SetShowOnDisabled(b, true);
        System.Windows.Automation.AutomationProperties.SetName(b, tip);
    }

    private static void Dock(DockPanel row, FrameworkElement el, double left = 0)
    {
        DockPanel.SetDock(el, System.Windows.Controls.Dock.Left);
        if (left > 0) el.Margin = new Thickness(left, el.Margin.Top, el.Margin.Right, el.Margin.Bottom);
        el.VerticalAlignment = VerticalAlignment.Center;
        row.Children.Add(el);
    }

    // ------------------------------------------------------------------ load

    private async Task LoadAsync()
    {
        _kept.Text = "Loading…";
        SetEnabled(false);
        if (!File.Exists(_path)) { ShowError(missing: true); return; }
        _info = await VideoExporter.ProbeAsync(_path);
        if (_info is null) { ShowError(missing: false); return; }
        _history = new CutHistory(new CutList(_info.Duration));
        _timeline.Aspect = _info.Height > 0 ? _info.Width / (double)_info.Height : 16.0 / 9;
        _selected = 0;
        _player.Source = new Uri(_path);
        _player.Play();
        _player.Pause();
        _player.IsMuted = false;
        SetEnabled(true);
        Refresh();
        _ = LoadFramesAsync();
    }

    private async Task LoadFramesAsync()
    {
        if (_info is null) return;
        double tile = Math.Clamp((CutTimeline.ViewHeight - 24 - 8) * _timeline.Aspect, 24, 160);
        int count = FilmstripFrames.Count(_info.Duration, SystemParameters.PrimaryScreenWidth * 12, tile);
        _framesDir = Path.Combine(Path.GetTempPath(), "bs-filmstrip-" + Guid.NewGuid().ToString("N"));
        var files = await VideoExporter.FilmstripAsync(_path, _info.Duration, count, _framesDir);
        var frames = new List<BitmapSource?>();
        foreach (var f in files)
        {
            try
            {
                var bmp = new BitmapImage();
                bmp.BeginInit();
                bmp.CacheOption = BitmapCacheOption.OnLoad;
                bmp.DecodePixelHeight = 100;
                bmp.UriSource = new Uri(f);
                bmp.EndInit();
                bmp.Freeze();
                frames.Add(bmp);
            }
            catch { frames.Add(null); }
        }
        if (IsLoaded) _timeline.Frames = frames;
        TryDeleteFrames();
        FramesReady.TrySetResult();
    }

    /// <summary>Set once the filmstrip has loaded (the off-screen preview renderer waits for it).</summary>
    internal TaskCompletionSource FramesReady { get; } = new();

    /// <summary>Preview renderer hook: apply edits, select a segment and park the playhead (no undo semantics needed).</summary>
    internal void PreviewEdit(Func<CutList, bool> edit, int select, double playhead)
    {
        _history.Apply(edit);
        _selected = select;
        SetPlayhead(playhead, seekPlayer: false);
        Refresh();
    }

    private void ShowError(bool missing)
    {
        _broken = true;
        _body.Visibility = Visibility.Collapsed;
        _errorPanel.Visibility = Visibility.Visible;
        var stack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 400 };
        stack.Children.Add(new IconPresenter { IconKey = "warning", Width = 34, Height = 34, Brush = White60, HorizontalAlignment = HorizontalAlignment.Center });
        stack.Children.Add(new TextBlock
        {
            Text = missing ? "This recording can't be found" : "This video can't be opened",
            FontSize = 15, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 14, 0, 6), HorizontalAlignment = HorizontalAlignment.Center,
        });
        stack.Children.Add(new TextBlock
        {
            Text = missing
                ? "It may have been moved, renamed or deleted. Close this window, then open the recording again from its new place."
                : "The file may be damaged or still being saved. Close this window and try again in a moment, or check the file in Explorer.",
            FontSize = 12, Foreground = White60, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center,
        });
        if (!missing)
        {
            var reveal = new Button { Content = "Show in Explorer", Padding = new Thickness(12, 4, 12, 4), Margin = new Thickness(0, 18, 0, 0), HorizontalAlignment = HorizontalAlignment.Center, ToolTip = "Select the file in an Explorer window" };
            reveal.Click += (_, _) => { try { System.Diagnostics.Process.Start("explorer.exe", $"/select,\"{_path}\""); } catch { } };
            stack.Children.Add(reveal);
        }
        _errorPanel.Children.Add(stack);
        _kept.Text = "";
        _cancel.Content = "Close";
        _cancel.ToolTip = "Close the editor";
        SetEnabled(false);
        _cancel.IsEnabled = true;
    }

    // ------------------------------------------------------------------ edits

    private CutList Cuts => _history.Current;

    private void ApplyEdit(Func<CutList, bool> edit)
    {
        if (_exporting || _info is null) return;
        if (!_history.Apply(edit)) { System.Media.SystemSounds.Beep.Play(); Refresh(); return; }
        _note = null;
        _selected = Math.Clamp(_selected, 0, Cuts.Segments.Count - 1);
        ResyncPlayback();
        Refresh();
    }

    private void Split()
    {
        double source = Cuts.SourceTimeForOutput(_playhead);
        int before = Cuts.Segments.Count;
        int index = Cuts.SegmentIndexContainingSource(source) ?? _selected;
        ApplyEdit(c => c.Split(source));
        if (Cuts.Segments.Count > before)
        {
            _selected = index; // the left half
            Tours.TourEvents.Post(BetterScreenshot.Tours.TourEvent.Action("video.split"));
        }
        Refresh();
    }

    private void DeleteSelected()
    {
        int index = _selected;
        double start = Cuts.OutputStart(index);
        if (!_history.Apply(c => c.Remove(index))) { System.Media.SystemSounds.Beep.Play(); return; }
        Tours.TourEvents.Post(BetterScreenshot.Tours.TourEvent.Action("video.segmentDeleted"));
        _note = null;
        _selected = Math.Min(index, Cuts.Segments.Count - 1);
        SetPlayhead(Math.Min(start, Cuts.KeptDuration), seekPlayer: true);
        ResyncPlayback();
        Refresh();
    }

    private void InPoint()
    {
        double source = Cuts.SourceTimeForOutput(_playhead);
        ApplyEdit(c => c.TrimBefore(source));
        _selected = 0;
        SetPlayhead(0, seekPlayer: true);
        ResyncPlayback();
        Refresh();
    }

    private void OutPoint()
    {
        double source = Cuts.SourceTimeForOutput(_playhead);
        ApplyEdit(c => c.TrimAfter(source));
        _selected = Cuts.Segments.Count - 1;
        SetPlayhead(Math.Max(0, Cuts.KeptDuration - 1.0 / 60), seekPlayer: true);
        ResyncPlayback();
        Refresh();
    }

    /// <summary>Undo / redo: keep the same source frame if it's still kept, else go to 0.</summary>
    private void AfterHistoryMove()
    {
        double source = _player.Position.TotalSeconds;
        _selected = Math.Clamp(_selected, 0, Cuts.Segments.Count - 1);
        _note = null;
        SetPlayhead(Cuts.OutputTimeForSource(source) ?? 0, seekPlayer: true);
        ResyncPlayback();
        Refresh();
    }

    private void ShowSegmentMenu(int index)
    {
        _selected = index;
        Refresh();
        var seg = Cuts.Segments[index];
        var menu = new ContextMenu();
        var speed = new MenuItem { Header = "Speed" };
        foreach (double s in CutList.Speeds)
        {
            double v = s;
            var item = new MenuItem { Header = s == 1 ? "1× (normal)" : CutTimeline.FormatSpeed(s), IsCheckable = true, IsChecked = Math.Abs(seg.Speed - s) < 1e-9 };
            item.Click += (_, _) => ApplyEdit(c => c.SetSpeed(v, index));
            speed.Items.Add(item);
        }
        menu.Items.Add(speed);
        var mute = new MenuItem { Header = "Mute Segment", IsCheckable = true, IsChecked = seg.Muted, IsEnabled = _muteAll.IsChecked != true };
        mute.Click += (_, _) => ApplyEdit(c => c.SetMuted(!seg.Muted, index));
        menu.Items.Add(mute);
        menu.Items.Add(new Separator());
        var split = new MenuItem { Header = "Split at Playhead", InputGestureText = "Ctrl+B", IsEnabled = CanSplit() };
        split.Click += (_, _) => Split();
        menu.Items.Add(split);
        var del = new MenuItem { Header = "Delete Segment", InputGestureText = "Delete", IsEnabled = Cuts.Segments.Count > 1 };
        del.Click += (_, _) => DeleteSelected();
        menu.Items.Add(del);
        menu.PlacementTarget = _timeline;
        menu.IsOpen = true;
    }

    private bool CanSplit()
    {
        double source = Cuts.SourceTimeForOutput(_playhead);
        return Cuts.Segments.Any(s => source >= s.Start + CutList.MinimumSegment - 1e-6 && source <= s.End - CutList.MinimumSegment + 1e-6);
    }

    // ------------------------------------------------------------------ playback

    private void TogglePlay()
    {
        if (_exporting || _info is null || _broken) return;
        if (_playing) { Pause(); return; }
        if (_playhead >= Cuts.KeptDuration - 1e-3) SetPlayhead(0, seekPlayer: true);
        _playIndex = Cuts.SegmentIndexAtOutput(_playhead);
        _player.Position = TimeSpan.FromSeconds(Cuts.SourceTimeForOutput(_playhead));
        ApplySegmentPlayback();
        _player.Play();
        _playing = true;
        _tick.Start();
        Refresh();
    }

    private void Pause()
    {
        if (!_playing) return;
        _player.Pause();
        _playing = false;
        _tick.Stop();
        Refresh();
    }

    private void StopAtEnd()
    {
        Pause();
        SetPlayhead(Cuts.KeptDuration, seekPlayer: false);
        Refresh();
    }

    private void ApplySegmentPlayback()
    {
        var seg = Cuts.Segments[_playIndex];
        _player.SpeedRatio = seg.Speed;
        ApplyPlaybackAudio();
    }

    private void ApplyPlaybackAudio()
    {
        bool segMuted = _playIndex < Cuts.Segments.Count && Cuts.Segments[_playIndex].Muted;
        _player.IsMuted = _muteAll.IsChecked == true || segMuted;
    }

    /// <summary>
    /// After any edit while playing (delete, trim, split, speed, undo/redo — review round 1 #1), find the segment being
    /// played again: the one holding the player's source position, else the one under the playhead (seeking there).
    /// The cut list can shrink under the running timer, so <c>_playIndex</c> must never be trusted across an edit.
    /// </summary>
    private void ResyncPlayback()
    {
        if (!_playing) return;
        if (Cuts.Segments.Count == 0) { Pause(); return; }
        double source = _player.Position.TotalSeconds;
        if (Cuts.SegmentIndexContainingSource(source) is { } here)
        {
            _playIndex = here;
        }
        else
        {
            _playIndex = Math.Clamp(Cuts.SegmentIndexAtOutput(_playhead), 0, Cuts.Segments.Count - 1);
            _player.Position = TimeSpan.FromSeconds(Cuts.SourceTimeForOutput(_playhead));
        }
        ApplySegmentPlayback();
    }

    /// <summary>Skip through the cut list: at a segment's end jump to the next one's start (its speed + mute), stop at the end.</summary>
    private void OnPlaybackTick()
    {
        if (!_playing) return;
        if (_playIndex < 0 || _playIndex >= Cuts.Segments.Count) ResyncPlayback();
        if (!_playing) return;
        double pos = _player.Position.TotalSeconds;
        var seg = Cuts.Segments[_playIndex];
        if (pos >= seg.End - 0.015 || pos < seg.Start - 0.25)
        {
            if (_playIndex + 1 >= Cuts.Segments.Count) { StopAtEnd(); return; }
            _playIndex++;
            _player.Position = TimeSpan.FromSeconds(Cuts.Segments[_playIndex].Start);
            ApplySegmentPlayback();
            pos = Cuts.Segments[_playIndex].Start;
        }
        _playhead = Cuts.OutputStart(_playIndex) + (Math.Clamp(pos, Cuts.Segments[_playIndex].Start, Cuts.Segments[_playIndex].End) - Cuts.Segments[_playIndex].Start) / Cuts.Segments[_playIndex].Speed;
        _timeline.Playhead = _playhead;
        UpdateTimeLabel();
        KeepPlayheadVisible();
    }

    private void SetPlayhead(double output, bool seekPlayer)
    {
        _playhead = Math.Clamp(output, 0, Cuts.KeptDuration);
        _timeline.Playhead = _playhead;
        if (seekPlayer) _player.Position = TimeSpan.FromSeconds(Cuts.SourceTimeForOutput(_playhead));
        UpdateTimeLabel();
    }

    /// <summary>While playing, re-anchor at 15 % from the left when the playhead leaves the visible part.</summary>
    private void KeepPlayheadVisible()
    {
        double x = _timeline.PlayheadX, left = _timelineScroller.HorizontalOffset, width = _timelineScroller.ViewportWidth;
        if (x < left || x > left + width) _timelineScroller.ScrollToHorizontalOffset(Math.Max(0, x - width * 0.15));
    }

    private void ApplyZoom()
    {
        double visible = Math.Max(100, _timelineScroller.ActualWidth);
        _timeline.Width = visible * _zoom.Value;
        _zoomOut.IsEnabled = _zoom.Value > 1.0001 && !_exporting;
        _zoomIn.IsEnabled = _zoom.Value < 11.999 && !_exporting;
    }

    // ------------------------------------------------------------------ keys

    private void OnKey(object sender, KeyEventArgs e)
    {
        if (_exporting || _broken) return;
        var mods = Keyboard.Modifiers;
        bool ctrl = (mods & ModifierKeys.Control) != 0, shift = (mods & ModifierKeys.Shift) != 0;
        if (ctrl && e.Key == Key.Z) { if (shift ? _history.Redo() : _history.Undo()) AfterHistoryMove(); e.Handled = true; return; }
        if (ctrl && e.Key == Key.Y) { if (_history.Redo()) AfterHistoryMove(); e.Handled = true; return; }
        if (ctrl && e.Key == Key.B) { Split(); e.Handled = true; return; }
        if ((mods & (ModifierKeys.Control | ModifierKeys.Alt | ModifierKeys.Windows)) != 0) return; // plain keys only
        switch (e.Key)
        {
            case Key.Space: TogglePlay(); break;
            case Key.S: Split(); break;
            case Key.Delete: case Key.Back: DeleteSelected(); break;
            case Key.I: InPoint(); break;
            case Key.O: OutPoint(); break;
            case Key.Left: Pause(); SetPlayhead(_playhead - 1 / Math.Max(1, _info?.Fps ?? 30), seekPlayer: true); break;
            case Key.Right: Pause(); SetPlayhead(_playhead + 1 / Math.Max(1, _info?.Fps ?? 30), seekPlayer: true); break;
            default: return;
        }
        e.Handled = true;
    }

    // ------------------------------------------------------------------ exports

    private async Task SaveCopyAsync()
    {
        if (_info is null) return;
        var path = await RunExport(p => VideoExporter.SaveCopyAsync(_path, Cuts, _info, _muteAll.IsChecked == true, p));
        if (path is null) { Fail("Couldn't export the edit — original untouched"); return; }
        CopySaved?.Invoke(path);
        Close();
    }

    private async Task ExportGifAsync()
    {
        if (_info is null) return;
        var path = await RunExport(p => VideoExporter.ExportGifAsync(_path, Cuts, _info, p));
        if (path is null) { Fail("Couldn't export the GIF — nothing was changed"); return; }
        _note = "GIF saved ✓ " + Path.GetFileName(path);
        GifSaved?.Invoke(path);
        Refresh();
    }

    private async Task ReplaceAsync()
    {
        if (_info is null) return;
        Pause();
        var cuts = Cuts;
        bool muteAll = _muteAll.IsChecked == true;
        _player.Source = null; // release the file so it can be swapped
        bool ok = await RunExport(async p => await VideoExporter.ReplaceAsync(_path, cuts, _info, muteAll, p) ? "ok" : null) is not null;
        var info = ok ? await VideoExporter.ProbeAsync(_path) : _info;
        _info = info ?? _info;
        _player.Source = new Uri(_path);
        _player.Play();
        _player.Pause();
        if (!ok) { Fail("Couldn't export the edit — original untouched"); return; }
        _history.Reset(new CutList(_info.Duration));
        _selected = 0;
        _muteAll.IsChecked = false;
        _note = "Edited ✓ original replaced · " + TrimRange.Timestamp(_info.Duration);
        _cancel.Content = "Done";
        _cancel.ToolTip = "Close the editor";
        _timeline.Frames = Array.Empty<BitmapSource?>();
        _ = LoadFramesAsync();
        SetPlayhead(0, seekPlayer: true);
        HudController.Show("Recording edited", HudIcon.Done);
        Refresh();
    }

    private async Task<string?> RunExport(Func<Action<double?>, Task<string?>> export)
    {
        Pause();
        _exporting = true;
        SetEnabled(false);
        _progress.Visibility = Visibility.Visible;
        Refresh();
        void Progress(double? f) => Dispatcher.BeginInvoke(() =>
        {
            _progress.IsIndeterminate = f is null;
            _pct.Visibility = f is null ? Visibility.Collapsed : Visibility.Visible;
            if (f is { } v) { _progress.Value = v; _pct.Text = $"{Math.Round(v * 100)}%"; }
        });
        try
        {
            return await export(Progress);
        }
        catch
        {
            return null;
        }
        finally
        {
            _exporting = false;
            _progress.Visibility = _pct.Visibility = Visibility.Collapsed;
            _progress.IsIndeterminate = false;
            SetEnabled(true);
            Refresh();
        }
    }

    private void Fail(string message)
    {
        _note = message;
        HudController.Show(message, HudIcon.Warning);
        Refresh();
    }

    // ------------------------------------------------------------------ state → UI

    private void SetEnabled(bool on)
    {
        foreach (var c in new UIElement[] { _playButton, _split, _delete, _undo, _redo, _zoom, _zoomIn, _zoomOut, _muteSegment, _muteAll, _saveCopy, _saveMenu, _replace, _cancel, _timeline })
            c.IsEnabled = on;
        foreach (var rb in _speeds) rb.IsEnabled = on;
    }

    private void Refresh()
    {
        if (_info is null || _broken) return;
        _updating = true;
        var cuts = Cuts;
        _selected = Math.Clamp(_selected, 0, cuts.Segments.Count - 1);
        _timeline.Cuts = cuts;
        _timeline.Selected = _selected;
        _timeline.Playhead = _playhead;
        var seg = cuts.Segments[_selected];
        bool idle = !_exporting;

        _playIcon.IconKey = _playing ? "pause" : "play";
        _playIcon.Brush = idle ? White85 : White30;
        _playButton.ToolTip = _playing ? "Pause (Space)" : "Play (Space)";
        _split.IsEnabled = idle && CanSplit();
        _delete.IsEnabled = idle && cuts.Segments.Count > 1;
        _undo.IsEnabled = idle && _history.CanUndo;
        _redo.IsEnabled = idle && _history.CanRedo;
        ApplyZoom();

        _segTitle.Text = $"Segment {_selected + 1} of {cuts.Segments.Count}";
        _segRange.Text = $"{TrimRange.Timestamp(seg.Start)} – {TrimRange.Timestamp(seg.End)}";
        for (int i = 0; i < _speeds.Length; i++) _speeds[i].IsChecked = Math.Abs(CutList.Speeds[i] - seg.Speed) < 1e-9;
        bool muteAll = _muteAll.IsChecked == true;
        _muteSegment.IsChecked = muteAll || seg.Muted;
        _muteSegment.IsEnabled = idle && !muteAll;

        _hint.Text = _exporting ? "Exporting — the original stays untouched until it's done."
            : muteAll ? "Mute whole video is on: the saved video will have no sound at all."
            : seg.Speed > 1 && seg.Muted ? "Sped-up segments are muted so the audio doesn't sound rushed — untick Mute segment to keep it."
            : seg.Speed > 1 ? "Sped-up audio keeps its pitch but plays faster."
            : cuts.Segments.Count == 1 ? "Move the playhead, then press S (or Ctrl+B) to split · drag the yellow edges to trim · I / O set in / out"
            : "Click a segment to select it · Delete removes it · right-click for speed and mute · Space plays the edit";

        UpdateKeptLabel(cuts);
        bool differs = !cuts.IsWhole || muteAll;
        _replace.IsEnabled = idle && differs;
        _replace.ToolTip = differs ? "Overwrite the original recording with the edit" : "Make an edit first — the original already matches this video";
        ToolTipService.SetShowOnDisabled(_replace, true);
        UpdateTimeLabel();
        _updating = false;
    }

    private void UpdateKeptLabel(CutList cuts)
    {
        if (_info is null) return;
        _kept.Text = _note ?? (cuts.IsWhole
            ? "Whole recording · " + TrimRange.Timestamp(_info.Duration)
            : $"{TrimRange.Timestamp(cuts.KeptDuration)} kept of {TrimRange.Timestamp(_info.Duration)}");
    }

    private void UpdateTimeLabel() =>
        _time.Text = $"{TrimRange.Timestamp(_playhead)} / {TrimRange.Timestamp(Cuts.KeptDuration)}";

    // ------------------------------------------------------------------ close

    private void OnClosedOnce()
    {
        _tick.Stop();
        _player.Stop();
        _player.Source = null;
        _player.Close();
        TryDeleteFrames();
        var restore = _restore.ToList();
        _restore.Clear();
        foreach (var r in restore) r();
    }

    private void TryDeleteFrames()
    {
        try { if (_framesDir is not null && Directory.Exists(_framesDir)) Directory.Delete(_framesDir, recursive: true); } catch { }
    }

    private static SolidColorBrush Frozen(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }
}
