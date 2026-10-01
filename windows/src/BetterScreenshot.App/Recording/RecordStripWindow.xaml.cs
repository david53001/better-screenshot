using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using BetterScreenshot.App.Controls;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;
using Windows.Devices.Enumeration;
using Border = System.Windows.Controls.Border;
using Brush = System.Windows.Media.Brush;
using RadioButton = System.Windows.Controls.RadioButton;
using Button = System.Windows.Controls.Button;
using Color = System.Windows.Media.Color;
using ComboBox = System.Windows.Controls.ComboBox;
using ComboBoxItem = System.Windows.Controls.ComboBoxItem;
using Cursors = System.Windows.Input.Cursors;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Orientation = System.Windows.Controls.Orientation;
using Separator = System.Windows.Controls.Separator;
using TextBlock = System.Windows.Controls.TextBlock;
using VerticalAlignment = System.Windows.VerticalAlignment;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// The pre-record setup strip v2 (Mac v3 Part 4 <c>RecordStripController</c>), 964 × 164: target buttons + Format /
/// FPS choice controls + close on top; one column per source (Microphone with a live level meter, System audio,
/// Camera with its size, Mouse cursor), each a caption + dropdown; and a hint line that explains whatever the
/// pointer (or keyboard focus) is on. Every choice saves at once into <see cref="SettingsStore.Recording"/>;
/// device lists are read fresh on open and rebuilt live when a device is plugged in or removed.
/// </summary>
public partial class RecordStripWindow : Window
{
    private const double SourceColumnWidth = 252;
    private const double CursorColumnWidth = 128;
    private const int MeterSegments = 16;

    private static readonly SolidColorBrush White = Frozen(Color.FromRgb(0xFF, 0xFF, 0xFF));
    private static readonly SolidColorBrush White60 = Frozen(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF));
    private static readonly SolidColorBrush White10 = Frozen(Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF));
    private static readonly SolidColorBrush Unlit = Frozen(Color.FromArgb(0x24, 0xFF, 0xFF, 0xFF));
    private static readonly SolidColorBrush[] BandBrushes =
    {
        Frozen(Color.FromRgb(0x30, 0xD1, 0x58)), Frozen(Color.FromRgb(0xFF, 0xD6, 0x0A)), Frozen(Color.FromRgb(0xFF, 0x45, 0x3A)),
    };

    private readonly SettingsStore _settings;
    private readonly List<StripArea> _hovered = new();
    private readonly Dictionary<StripArea, List<FrameworkElement>> _captions = new();
    private readonly TextBlock _hint = new() { FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
    private readonly ComboBox _mic = Dropdown(SourceColumnWidth), _system = Dropdown(SourceColumnWidth), _camera = Dropdown(SourceColumnWidth), _cursor = Dropdown(CursorColumnWidth);
    private readonly Border[] _segments = new Border[MeterSegments];
    private readonly StackPanel _meter = new() { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
    private readonly Button _accessLink = new();
    private Action? _refreshFormat, _refreshFps;
    private DeviceList _mics = DeviceList.Empty, _cameras = DeviceList.Empty;
    private MicLevelMonitor? _monitor;
    private string? _meteredMic;
    private double _level;
    private bool _building;
    private DeviceWatcher? _audioWatcher, _videoWatcher;
    private StripArea _focused = StripArea.None;

    public Action? OnFullScreen { get; set; }
    public Action? OnArea { get; set; }
    public Action? OnWindow { get; set; }
    public Action? OnCancel { get; set; }

    public RecordStripWindow(SettingsStore settings)
    {
        InitializeComponent();
        _settings = settings;
        Build();
        Loaded += async (_, _) =>
        {
            Reposition();
            await ReloadDevicesAsync(fresh: true);
            WatchDevices();
        };
        Closed += (_, _) => { StopMeter(); StopWatching(); };
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { e.Handled = true; OnCancel?.Invoke(); } };
        MouseLeftButtonDown += (_, e) => { if (e.OriginalSource is Border or StackPanel or Grid) { try { DragMove(); } catch { } } };
    }

    private RecordingConfig Config => _settings.Recording;

    private void Persist(RecordingConfig config)
    {
        _settings.Recording = config;
        _settings.Save();
    }

    // ------------------------------------------------------------------ layout

    private void Build()
    {
        // Top row: targets · flexible space · Format · FPS · close.
        var top = new DockPanel { LastChildFill = false, Height = 28 };
        var targets = new StackPanel { Orientation = Orientation.Horizontal };
        targets.Children.Add(Area(TargetButton("display", "Full Screen", () => OnFullScreen?.Invoke()), StripArea.FullScreen));
        targets.Children.Add(Area(TargetButton("rect-dashed", "Area…", () => OnArea?.Invoke(), 8), StripArea.Area));
        targets.Children.Add(Area(TargetButton("window", "Window…", () => OnWindow?.Invoke(), 8), StripArea.Window));
        DockPanel.SetDock(targets, Dock.Left);
        top.Children.Add(targets);

        var close = new Button
        {
            Width = 22, Height = 22, Cursor = Cursors.Hand, ToolTip = "Close without recording",
            Style = (Style)FindResource("Theme.SubtleButton"), VerticalAlignment = VerticalAlignment.Center,
            Content = new IconPresenter { IconKey = "close-circle", Width = 16, Height = 16, Brush = White60 },
        };
        System.Windows.Automation.AutomationProperties.SetName(close, "Cancel");
        close.Click += (_, _) => OnCancel?.Invoke();
        Caption(StripArea.Close, (FrameworkElement)close.Content);
        DockPanel.SetDock(close, Dock.Right);
        var fps = Choice("FPS", "Frame rate", StripArea.Fps, new[] { "30", "60" }, () => Config.Fps == 60 ? 1 : 0,
            i => Persist(Config with { Fps = i == 1 ? 60 : 30 }), out _refreshFps);
        fps.Margin = new Thickness(0, 0, 16, 0);
        DockPanel.SetDock(fps, Dock.Right);
        var format = Choice("Format", "Format", StripArea.Format, new[] { "MP4", "GIF" }, () => Config.Format == RecordingFormat.Gif ? 1 : 0,
            i => { Persist(Config with { Format = i == 1 ? RecordingFormat.Gif : RecordingFormat.Mp4 }); ApplyFormat(); }, out _refreshFormat);
        format.Margin = new Thickness(0, 0, 20, 0);
        DockPanel.SetDock(format, Dock.Right);
        top.Children.Add(close);
        top.Children.Add(fps);
        top.Children.Add(format);
        Stack.Children.Add(top);
        Stack.Children.Add(Hairline());

        // Sources row: four columns, 16 apart.
        var sources = new StackPanel { Orientation = Orientation.Horizontal };
        BuildMeter();
        sources.Children.Add(SourceColumn("mic", "Microphone", StripArea.Microphone, _mic, SourceColumnWidth, MicAccessory()));
        sources.Children.Add(SourceColumn("speaker", "System audio", StripArea.SystemAudio, _system, SourceColumnWidth, null, 16));
        sources.Children.Add(SourceColumn("video", "Camera", StripArea.Camera, _camera, SourceColumnWidth, null, 16));
        sources.Children.Add(SourceColumn("cursor", "Mouse cursor", StripArea.Cursor, _cursor, CursorColumnWidth, null, 16));
        Stack.Children.Add(sources);
        Stack.Children.Add(Hairline());

        // Hint row.
        var hintRow = new DockPanel();
        var info = new IconPresenter { IconKey = "info", Width = 12, Height = 12, Brush = White60, Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };
        DockPanel.SetDock(info, Dock.Left);
        hintRow.Children.Add(info);
        hintRow.Children.Add(_hint);
        Stack.Children.Add(hintRow);

        _mic.SelectionChanged += (_, _) => OnMicChosen();
        _system.SelectionChanged += (_, _) => OnSystemChosen();
        _camera.SelectionChanged += (_, _) => OnCameraChosen();
        _cursor.SelectionChanged += (_, _) => { if (!_building && _cursor.SelectedItem is ComboBoxItem { Tag: bool shown }) Persist(Config with { ShowsCursor = shown }); };

        FillStaticMenus();
        ApplyFormat();
        UpdateHint();
    }

    private static Border Hairline() => new() { Height = 1, Background = White10, Margin = new Thickness(0, 12, 0, 12) };

    private Button TargetButton(string icon, string label, Action onClick, double leftMargin = 0)
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal };
        sp.Children.Add(new IconPresenter { IconKey = icon, Width = 16, Height = 16, Brush = White, Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center });
        sp.Children.Add(new TextBlock { Text = label, FontSize = 13, VerticalAlignment = VerticalAlignment.Center });
        var b = new Button { Content = sp, Height = 28, Padding = new Thickness(12, 0, 12, 0), Margin = new Thickness(leftMargin, 0, 0, 0), Cursor = Cursors.Hand };
        System.Windows.Automation.AutomationProperties.SetName(b, label == "Full Screen" ? "Record Full Screen" : label == "Area…" ? "Record Area…" : "Record Window…");
        b.Click += (_, _) => onClick();
        return b;
    }

    /// <summary>The Format / FPS choice control: a white-10 % track, two 40 × 22 options; chosen = accent fill, white semibold.</summary>
    private FrameworkElement Choice(string label, string accessibleName, StripArea area, string[] options, Func<int> selected,
        Action<int> choose, out Action refresh)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var caption = new TextBlock { Text = label, FontSize = 12, Foreground = White60, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) };
        row.Children.Add(caption);
        Caption(area, caption);
        var track = new StackPanel { Orientation = Orientation.Horizontal };
        var trackBorder = new Border { Background = White10, CornerRadius = new CornerRadius(7), Padding = new Thickness(2), Child = track };
        System.Windows.Automation.AutomationProperties.SetName(trackBorder, accessibleName);
        var buttons = new List<RadioButton>();
        for (int i = 0; i < options.Length; i++)
        {
            int index = i;
            var rb = new RadioButton
            {
                Content = options[i], GroupName = "strip-" + label, Width = 40, Height = 22, FontSize = 13,
                Margin = new Thickness(i == 0 ? 0 : 2, 0, 0, 0), Cursor = Cursors.Hand, Template = ChoiceTemplate(),
            };
            rb.Checked += (_, _) => { if (!_building) choose(index); };
            buttons.Add(rb);
            track.Children.Add(rb);
        }
        refresh = () =>
        {
            int sel = selected();
            for (int i = 0; i < buttons.Count; i++)
            {
                bool on = i == sel;
                buttons[i].IsChecked = on;
                buttons[i].Background = on ? SystemAccent.Brush : System.Windows.Media.Brushes.Transparent;
                buttons[i].Foreground = on ? White : White60;
                buttons[i].FontWeight = on ? FontWeights.SemiBold : FontWeights.Normal;
            }
        };
        foreach (var rb in buttons) rb.Checked += (_, _) => refreshAll();
        void refreshAll() { _refreshFormat?.Invoke(); _refreshFps?.Invoke(); }
        row.Children.Add(trackBorder);
        Area(row, area);
        _building = true;
        refresh();
        _building = false;
        return row;
    }

    private static ControlTemplate ChoiceTemplate()
    {
        var t = new ControlTemplate(typeof(RadioButton));
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(5));
        border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        var content = new FrameworkElementFactory(typeof(ContentPresenter));
        content.SetValue(HorizontalAlignmentProperty, HorizontalAlignment.Center);
        content.SetValue(VerticalAlignmentProperty, VerticalAlignment.Center);
        border.AppendChild(content);
        t.VisualTree = border;
        return t;
    }

    private FrameworkElement SourceColumn(string icon, string caption, StripArea area, ComboBox dropdown, double width,
        FrameworkElement? accessory, double leftGap = 0)
    {
        var column = new StackPanel { Width = width, Margin = new Thickness(leftGap, 0, 0, 0), Background = System.Windows.Media.Brushes.Transparent };
        var header = new DockPanel { Height = 16, Margin = new Thickness(0, 0, 0, 6) };
        var ic = new IconPresenter { IconKey = icon, Width = 13, Height = 13, Brush = White60, Margin = new Thickness(0, 0, 5, 0), VerticalAlignment = VerticalAlignment.Center };
        var text = new TextBlock { Text = caption, FontSize = 12, FontWeight = FontWeights.Medium, Foreground = White60, VerticalAlignment = VerticalAlignment.Center };
        Caption(area, ic);
        Caption(area, text);
        DockPanel.SetDock(ic, Dock.Left);
        DockPanel.SetDock(text, Dock.Left);
        header.Children.Add(ic);
        header.Children.Add(text);
        if (accessory is not null)
        {
            DockPanel.SetDock(accessory, Dock.Right);
            accessory.HorizontalAlignment = HorizontalAlignment.Right;
            header.Children.Add(accessory);
        }
        column.Children.Add(header);
        column.Children.Add(dropdown);
        System.Windows.Automation.AutomationProperties.SetName(dropdown, caption);
        return Area(column, area);
    }

    private static ComboBox Dropdown(double width) => new() { Width = width, Height = 28, FontSize = 12 };

    private void BuildMeter()
    {
        for (int i = 0; i < MeterSegments; i++)
        {
            // 120 wide: 16 segments with 2 gaps → (120 − 15·2) / 16 = 5.625.
            _segments[i] = new Border { Width = 5.625, Height = 6, CornerRadius = new CornerRadius(1.5), Background = Unlit, Margin = new Thickness(i == 0 ? 0 : 2, 0, 0, 0) };
            _meter.Children.Add(_segments[i]);
        }
        _meter.Width = 120;
        System.Windows.Automation.AutomationProperties.SetName(_meter, "Microphone level");
    }

    private FrameworkElement MicAccessory()
    {
        _accessLink.Content = new TextBlock { Text = "Allow microphone access…", FontSize = 11, Foreground = SystemAccent.Brush };
        _accessLink.Template = LinkTemplate();
        _accessLink.Cursor = Cursors.Hand;
        _accessLink.Height = 15;
        _accessLink.Click += (_, _) => MicrophoneAccess.OpenSettings();
        Area(_accessLink, StripArea.MicAccessLink);
        var host = new Grid { Height = 16 };
        host.Children.Add(_meter);
        host.Children.Add(_accessLink);
        return host;
    }

    private static ControlTemplate LinkTemplate()
    {
        var t = new ControlTemplate(typeof(Button));
        t.VisualTree = new FrameworkElementFactory(typeof(ContentPresenter));
        return t;
    }

    // ------------------------------------------------------------------ hint line

    /// <summary>Hover areas nest: the most recently entered wins; leaving falls back to the one still under the pointer.</summary>
    private T Area<T>(T element, StripArea area) where T : FrameworkElement
    {
        element.MouseEnter += (_, _) => { _hovered.Remove(area); _hovered.Add(area); UpdateHint(); };
        element.MouseLeave += (_, _) => { _hovered.Remove(area); UpdateHint(); };
        element.IsKeyboardFocusWithinChanged += (_, e) =>
        {
            if ((bool)e.NewValue) _focused = area;
            else if (_focused == area) _focused = StripArea.None;
            UpdateHint();
        };
        return element;
    }

    private void Caption(StripArea area, FrameworkElement element)
    {
        if (!_captions.TryGetValue(area, out var list)) _captions[area] = list = new List<FrameworkElement>();
        list.Add(element);
    }

    private void UpdateHint()
    {
        var active = _hovered.Count > 0 ? _hovered[^1] : _focused;
        _hint.Text = RecordStripHints.For(active, Config.Format);
        _hint.Foreground = active == StripArea.None ? White60 : White;
        foreach (var (area, elements) in _captions)
            foreach (var el in elements)
            {
                var brush = area == active || (active == StripArea.MicAccessLink && area == StripArea.Microphone) ? White : White60;
                if (el is TextBlock tb) tb.Foreground = brush;
                else if (el is IconPresenter ip) ip.Brush = brush;
            }
    }

    // ------------------------------------------------------------------ menus

    private void FillStaticMenus()
    {
        _building = true;
        _system.Items.Clear();
        foreach (var mode in new[] { SystemAudioMode.Off, SystemAudioMode.All })
            _system.Items.Add(new ComboBoxItem { Content = mode.Title(), Tag = mode, ToolTip = RecordStripHints.SystemAudioTooltip(mode) });
        // excludeSelf (Mac-only) reads as All apps here.
        _system.SelectedIndex = Config.SystemAudioMode == SystemAudioMode.Off ? 0 : 1;

        _cursor.Items.Clear();
        _cursor.Items.Add(new ComboBoxItem { Content = "Shown", Tag = true, ToolTip = RecordStripHints.CursorTooltip(true) });
        _cursor.Items.Add(new ComboBoxItem { Content = "Hidden", Tag = false, ToolTip = RecordStripHints.CursorTooltip(false) });
        _cursor.SelectedIndex = Config.ShowsCursor ? 0 : 1;
        _building = false;
    }

    private async Task ReloadDevicesAsync(bool fresh)
    {
        if (fresh) DshowAudioDevices.InvalidateCache();
        var micsTask = DshowAudioDevices.MicrophonesAsync();
        var camsTask = CameraDevices.ListAsync();
        _mics = await micsTask;
        _cameras = await camsTask;
        if (!IsLoaded) return;
        FillDeviceMenus();
        UpdateMeter();
    }

    private void FillDeviceMenus()
    {
        _building = true;
        FillDevices(_mic, _mics, _mics.Choice(Config.Microphone, Config.MicrophoneDeviceId));

        FillDevices(_camera, _cameras, _cameras.Choice(Config.Camera, Config.CameraDeviceId));
        _camera.Items.Add(new Separator());
        foreach (var size in new[] { CameraSize.Small, CameraSize.Medium })
            _camera.Items.Add(new ComboBoxItem
            {
                Content = (Config.CameraSize == size ? "✓ " : "    ") + "Camera Size: " + (size == CameraSize.Small ? "Small" : "Medium"),
                Tag = size,
            });
        _building = false;
    }

    private static void FillDevices(ComboBox box, DeviceList list, DeviceChoice selected)
    {
        box.Items.Clear();
        foreach (var (choice, title) in list.Options())
        {
            var item = new ComboBoxItem { Content = title, Tag = choice, ToolTip = title.Length > 34 ? title : null };
            box.Items.Add(item);
            if (choice == selected) box.SelectedItem = item;
        }
        if (box.SelectedItem is null && box.Items.Count > 0) box.SelectedIndex = 0;
        box.ToolTip = (box.SelectedItem as ComboBoxItem)?.Content is string s && s.Length > 34 ? s : null; // full name when truncated
    }

    private void OnMicChosen()
    {
        if (_building || _mic.SelectedItem is not ComboBoxItem { Tag: DeviceChoice choice }) return;
        Persist(Config.WithMicrophone(choice));
        _mic.ToolTip = (_mic.SelectedItem as ComboBoxItem)?.ToolTip;
        UpdateMeter();
    }

    private void OnSystemChosen()
    {
        if (_building || _system.SelectedItem is not ComboBoxItem { Tag: SystemAudioMode mode }) return;
        Persist(Config with { SystemAudioMode = mode });
    }

    private void OnCameraChosen()
    {
        if (_building) return;
        switch (_camera.SelectedItem)
        {
            case ComboBoxItem { Tag: CameraSize size }:
                // The size rows set Small/Medium without changing the selected camera row.
                Persist(Config with { CameraSize = size });
                FillDeviceMenus();
                break;
            case ComboBoxItem { Tag: DeviceChoice choice }:
                Persist(Config.WithCamera(choice));
                break;
        }
    }

    /// <summary>GIF dims the two audio dropdowns (values kept) and hides the meter — GIFs have no sound.</summary>
    private void ApplyFormat()
    {
        bool audio = Config.RecordsAudio;
        _mic.IsEnabled = _system.IsEnabled = audio;
        UpdateMeter();
        UpdateHint();
    }

    // ------------------------------------------------------------------ meter

    /// <summary>Runs only while visible, MP4, a mic chosen and access allowed; otherwise the link (denied) or nothing.</summary>
    private void UpdateMeter()
    {
        var choice = _mic.SelectedItem is ComboBoxItem { Tag: DeviceChoice c } ? c : DeviceChoice.Off;
        bool wanted = IsLoaded && Config.RecordsAudio && !choice.IsOff;
        bool denied = wanted && MicrophoneAccess.IsDenied();
        _accessLink.Visibility = denied ? Visibility.Visible : Visibility.Collapsed;
        _meter.Visibility = wanted && !denied ? Visibility.Visible : Visibility.Hidden;
        if (!wanted || denied) { StopMeter(); return; }
        if (_meteredMic == choice.DeviceId && _monitor is not null) return;
        StopMeter();
        _meteredMic = choice.DeviceId;
        _ = StartMeterAsync(choice.DeviceId!);
    }

    private async Task StartMeterAsync(string device)
    {
        var monitor = await MicLevelMonitor.StartAsync(device, Dispatcher, OnLevel);
        if (monitor is null) return;
        if (_meteredMic != device || !IsLoaded) { monitor.Dispose(); return; }
        _monitor = monitor;
    }

    private void StopMeter()
    {
        _monitor?.Dispose();
        _monitor = null;
        _meteredMic = null;
        _level = 0;
        PaintMeter();
    }

    private void OnLevel(double db)
    {
        _level = MicLevel.Smoothed(_level, MicLevel.Fraction(db));
        PaintMeter();
    }

    private void PaintMeter()
    {
        int lit = MicLevel.LitSegments(_level, MeterSegments);
        for (int i = 0; i < MeterSegments; i++)
            _segments[i].Background = i < lit ? BandBrushes[MicLevel.Band(i, MeterSegments)] : Unlit;
    }

    // ------------------------------------------------------------------ devices plugged / unplugged

    private void WatchDevices()
    {
        _audioWatcher = Watch(DeviceClass.AudioCapture);
        _videoWatcher = Watch(DeviceClass.VideoCapture);
    }

    private DeviceWatcher? Watch(DeviceClass kind)
    {
        try
        {
            var w = DeviceInformation.CreateWatcher(kind);
            bool ready = false;
            w.EnumerationCompleted += (_, _) => ready = true;
            void Changed() { if (ready) Dispatcher.BeginInvoke(async () => { if (IsLoaded) await ReloadDevicesAsync(fresh: true); }); }
            w.Added += (_, _) => Changed();
            w.Removed += (_, _) => Changed();
            w.Updated += (_, _) => { };
            w.Start();
            return w;
        }
        catch
        {
            return null;
        }
    }

    private void StopWatching()
    {
        foreach (var w in new[] { _audioWatcher, _videoWatcher })
            try { if (w is { Status: DeviceWatcherStatus.Started or DeviceWatcherStatus.EnumerationCompleted }) w.Stop(); } catch { /* best-effort */ }
        _audioWatcher = _videoWatcher = null;
    }

    // ------------------------------------------------------------------ placement

    /// <summary>Centred on the work area of the monitor under the pointer, bottom edge 60 above its bottom.</summary>
    private void Reposition()
    {
        var work = WindowPlacement.WorkAreaUnderCursor();
        const double margin = 12; // the card's shadow margin
        Left = work.Left + (work.Width - ActualWidth) / 2;
        Top = work.Bottom - (ActualHeight - margin) - 60;
    }

    private static SolidColorBrush Frozen(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }
}
