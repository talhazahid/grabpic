using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Forms = System.Windows.Forms;
namespace GrabPic;
public sealed class MainWindow : Window
{
    private static readonly Brush Ink = Brush("#EEEFF5"), Muted = Brush("#A3A4B5"), Accent = Brush("#A294FA");
    private readonly Preferences settings = Preferences.Load();
    private readonly StackPanel page = new();
    private readonly Button captureNav; private readonly Button settingsNav;
    private int navigationVersion;
    private readonly TextBlock title = Text("", 28), subtitle = Text("", 13, Muted), status = Text("Ready when you are.", 12, Muted);
    private readonly Image preview = new() { Width = 80, Height = 56, Stretch = Stretch.Uniform };
    private readonly TextBlock latestName = Text("Your next capture starts here", 14), latestDetail = Text("Take a screenshot to see it here.", 12, Muted);
    private readonly DispatcherTimer clipboardTimer = new() { Interval = TimeSpan.FromMilliseconds(220) };
    private ShortcutService? shortcuts;
    private string? latestPath; private uint ignoredClipboard; private bool capturing; private IntPtr handle; private string hotkeyWarning = "";
    public MainWindow()
    {
        Icon = System.Windows.Media.Imaging.BitmapFrame.Create(new Uri("pack://application:,,,/Assets/GrabPic-256.png")); Title = "Grab Pic"; Width = 1080; Height = 780; MinWidth = 880; MinHeight = 660; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        FontFamily = new FontFamily("Segoe UI Variable, Segoe UI"); FontSize = 13; FontWeight = FontWeights.Normal; Background = Brush("#14151B");
        Resources.Add(typeof(Button), ButtonStyle());
        var root = new Grid(); root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(212) }); root.ColumnDefinitions.Add(new ColumnDefinition()); Content = root;
        var side = new DockPanel { Margin = new Thickness(18, 28, 18, 22) };
        var sidebar = new Border { Background = Brush("#191A22"), BorderBrush = Brush("#2B2C37"), BorderThickness = new Thickness(0, 0, 1, 0), Child = side }; root.Children.Add(sidebar);
        var brand = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(10, 0, 0, 34) };
        brand.Children.Add(new Image { Width = 34, Height = 34, Source = System.Windows.Media.Imaging.BitmapFrame.Create(new Uri("pack://application:,,,/Assets/GrabPic-128.png")) }); brand.Children.Add(new TextBlock { Text = "Grab Pic", FontSize = 21, Margin = new Thickness(10, 1, 0, 0), Foreground = Ink }); DockPanel.SetDock(brand, Dock.Top); side.Children.Add(brand);
        var foot = new StackPanel(); foot.Children.Add(new Border { Background = Brush("#232430"), CornerRadius = new CornerRadius(9), Padding = new Thickness(12), Child = Stack(Text("A little less friction.", 13), Gap(5), Text("Capture. Copy. Carry on.", 12, Muted)) }); foot.Children.Add(new TextBlock { Text = "GRAB PIC  /  LOCAL PREVIEW", FontSize = 10, Foreground = Muted, Margin = new Thickness(8, 16, 0, 0) }); DockPanel.SetDock(foot, Dock.Bottom); side.Children.Add(foot);
        captureNav = Button("\uE722", "Capture", CapturePage, true); settingsNav = Button("\uE713", "Settings", SettingsPage, true); var nav = Stack(captureNav, Gap(6), settingsNav); side.Children.Add(nav);
        var body = new DockPanel { Margin = new Thickness(36, 28, 36, 20) }; Grid.SetColumn(body, 1); root.Children.Add(body);
        var bottom = new Border { BorderBrush = Brush("#2B2C37"), BorderThickness = new Thickness(0, 1, 0, 0), Padding = new Thickness(0, 14, 0, 0), Margin = new Thickness(0, 20, 0, 0), Child = status }; DockPanel.SetDock(bottom, Dock.Bottom); body.Children.Add(bottom);
        var header = Stack(title, Gap(8), subtitle, Gap(26)); DockPanel.SetDock(header, Dock.Top); body.Children.Add(header);
        body.Children.Add(new ScrollViewer { Content = page, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Padding = new Thickness(0, 0, 4, 0) });
        SourceInitialized += (_, _) => { handle = new WindowInteropHelper(this).Handle; HwndSource.FromHwnd(handle).CompositionTarget.RenderMode = RenderMode.SoftwareOnly; HwndSource.FromHwnd(handle).AddHook(Messages); if (Environment.GetEnvironmentVariable("GRABPIC_SCREENSHOT_MODE") != "1") { shortcuts = new ShortcutService(handle, Dispatcher, InvokeShortcut, () => !capturing && !IsActive); foreach (int action in new[] { 1, 2, 3 }) { if (!shortcuts.Set(action, BindingFor(action), out var error)) { hotkeyWarning = error; status.Text = error; } } } int dark = 1; DwmSetWindowAttribute(handle, 20, ref dark, sizeof(int)); Native.AddClipboardFormatListener(handle); };
        clipboardTimer.Tick += ClipboardTick;
        Closing += (_, e) => { e.Cancel = true; Hide(); };
        Application.Current.Exit += (_, _) => { shortcuts?.Dispose(); Native.RemoveClipboardFormatListener(handle); };
        CapturePage();
    }
    [System.Runtime.InteropServices.DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
    private static Brush Brush(string value) => (Brush)new BrushConverter().ConvertFromString(value)!;
    private static TextBlock Text(string value, double size = 13, Brush? foreground = null) => new() { Text = value, FontSize = size, Foreground = foreground ?? Ink, TextWrapping = TextWrapping.Wrap, FontWeight = FontWeights.Normal };
    private static FrameworkElement Gap(double height) => new Border { Height = height };
    private static StackPanel Stack(params UIElement[] children) { var stack = new StackPanel(); foreach (var child in children) stack.Children.Add(child); return stack; }
    private static TextBlock Glyph(string glyph, double size, Brush color) => new() { Text = glyph, FontFamily = new FontFamily("Segoe Fluent Icons"), FontSize = size, Foreground = color, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private static Border Card(UIElement child, string color = "#1D1E28", double padding = 22) => new() { Background = Brush(color), BorderBrush = Brush("#30313E"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = new Thickness(padding), Child = child };
    private static Style ButtonStyle()
    {
        var style = new Style(typeof(Button)); style.Setters.Add(new Setter(Control.BackgroundProperty, Brush("#1D1E28"))); style.Setters.Add(new Setter(Control.ForegroundProperty, Ink)); style.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(16, 10, 16, 10))); style.Setters.Add(new Setter(Control.BorderBrushProperty, Brush("#353645"))); style.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(1))); style.Setters.Add(new Setter(Control.FontWeightProperty, FontWeights.Normal)); style.Setters.Add(new Setter(Control.CursorProperty, System.Windows.Input.Cursors.Hand));
        var border = new FrameworkElementFactory(typeof(Border)); border.SetValue(Border.CornerRadiusProperty, new CornerRadius(8)); border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent }); border.SetBinding(Border.BorderBrushProperty, new System.Windows.Data.Binding("BorderBrush") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent }); border.SetValue(Border.BorderThicknessProperty, new Thickness(1)); border.SetBinding(Border.PaddingProperty, new System.Windows.Data.Binding("Padding") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        var content = new FrameworkElementFactory(typeof(ContentPresenter)); content.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center); border.AppendChild(content); style.Setters.Add(new Setter(Control.TemplateProperty, new ControlTemplate(typeof(Button)) { VisualTree = border }));
        var hover = new Trigger { Property = IsMouseOverProperty, Value = true }; hover.Setters.Add(new Setter(OpacityProperty, 0.78)); style.Triggers.Add(hover); var focus = new Trigger { Property = IsKeyboardFocusedProperty, Value = true }; focus.Setters.Add(new Setter(Control.BorderBrushProperty, Accent)); style.Triggers.Add(focus); return style;
    }
    private Button Button(string glyph, string label, Action action, bool nav = false)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal }; if (glyph.Length > 0) { var icon = Glyph(glyph, 16, nav ? Muted : Accent); icon.Margin = new Thickness(0, 0, 12, 0); row.Children.Add(icon); } row.Children.Add(Text(label)); var button = new Button { Content = row, Background = nav ? Brushes.Transparent : Brush("#1D1E28") }; if (nav) button.BorderBrush = Brushes.Transparent; System.Windows.Automation.AutomationProperties.SetName(button, label); button.Click += (_, _) => action(); return button;
    }
    private static void Detach(FrameworkElement element) { if (element.Parent is Panel panel) panel.Children.Remove(element); else if (element.Parent is Border border) border.Child = null; }
    private void CapturePage()
    {
        navigationVersion++;
        captureNav.Background = Brush("#343049"); settingsNav.Background = Brushes.Transparent; Detach(preview); Detach(latestName); Detach(latestDetail); page.Children.Clear(); title.Text = "A good moment. Captured."; subtitle.Text = "A small tool for the things worth keeping.";
        var hero = Stack(Text("LESS FRICTION. MORE FOCUS.", 10, Accent), Gap(16), Text("Keep the useful bits.", 26), Gap(10), Text("Grab your screen or select just the part you need.\nSaved neatly. Ready to paste.", 14, Brush("#C1BCD8")), Gap(22), Text("LOCAL BY DESIGN     /     PNG + JPG     /     AUTOMATIC SAVING", 10, Brush("#ADA3D0")));
        page.Children.Add(Card(hero, "#272337", 28)); page.Children.Add(Gap(18));
        var choices = new Grid(); choices.ColumnDefinitions.Add(new ColumnDefinition()); choices.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(16) }); choices.ColumnDefinitions.Add(new ColumnDefinition());
        foreach (bool area in new[] { false, true }) { var icon = Glyph(area ? "\uE7A8" : "\uE7F4", 26, Accent); icon.HorizontalAlignment = HorizontalAlignment.Left; var button = new Button { Padding = new Thickness(24), Content = Stack(icon, Gap(20), Text(area ? "Grab an area" : "Grab full screen", 19), Gap(8), Text(area ? "Only what matters. Nothing extra." : "The whole picture, in one click.", 12, Muted), Gap(18), Text((area ? settings.AreaShortcut : settings.FullScreenShortcut)?.Label ?? "No shortcut assigned", 11, Muted)) }; System.Windows.Automation.AutomationProperties.SetName(button, area ? "Grab an area" : "Grab full screen"); button.Click += (_, _) => BeginCapture(area); Grid.SetColumn(button, area ? 2 : 0); choices.Children.Add(button); }
        page.Children.Add(choices); page.Children.Add(Gap(24));
        var label = new DockPanel(); var folder = Button("", "Open folder ↗", OpenFolder); folder.Background = Brushes.Transparent; folder.BorderBrush = Brushes.Transparent; folder.Padding = new Thickness(0); DockPanel.SetDock(folder, Dock.Right); label.Children.Add(folder); label.Children.Add(Text("Your latest capture", 16)); page.Children.Add(label); page.Children.Add(Gap(12));
        var recent = new DockPanel(); var reveal = Button("", "Reveal", () => { if (latestPath != null && File.Exists(latestPath)) Process.Start("explorer.exe", $"/select,\"{latestPath}\""); }); reveal.VerticalAlignment = VerticalAlignment.Center; reveal.IsEnabled = latestPath != null; DockPanel.SetDock(reveal, Dock.Right); recent.Children.Add(reveal);
        var image = new Border { Width = 84, Height = 60, CornerRadius = new CornerRadius(6), Background = Brush("#292A36"), Child = preview }; DockPanel.SetDock(image, Dock.Left); recent.Children.Add(image); var info = Stack(latestName, Gap(6), latestDetail); info.Margin = new Thickness(16, 0, 12, 0); info.VerticalAlignment = VerticalAlignment.Center; recent.Children.Add(info); page.Children.Add(Card(recent, padding: 16));

    }
    private void SettingsPage()
    {
        navigationVersion++;
        settingsNav.Background = Brush("#343049"); captureNav.Background = Brushes.Transparent; page.Children.Clear(); title.Text = "Make it yours."; subtitle.Text = "A few thoughtful defaults. Everything in its place.";
        void Section(string text) { page.Children.Add(Gap(page.Children.Count == 0 ? 0 : 22)); page.Children.Add(Text(text, 10, Muted)); page.Children.Add(Gap(10)); }
        Section("SHORTCUTS");
        page.Children.Add(ShortcutCard());
        Section("SAVING");
        var path = Text(settings.Folder, 12, Accent); var choose = Button("", "Choose…", () => { using var dialog = new Forms.FolderBrowserDialog { InitialDirectory = settings.Folder, Description = "Choose your capture folder", UseDescriptionForTitle = true }; if (dialog.ShowDialog() == Forms.DialogResult.OK) { settings.Folder = dialog.SelectedPath; settings.Save(); SettingsPage(); } });
        var saving = Stack(Row(Stack(Text("Capture folder", 15), Gap(5), Text("A home for everything you grab.", 12, Muted)), choose), Gap(14), path, Divider());
        var example = Text("", 11, Muted); void Example() => example.Text = Path.Combine(settings.Subfolder(DateTime.Now), "Grab_14-32-08." + (settings.Format == 0 ? "png" : "jpg")); Example();
        saving.Children.Add(Row(Stack(Text("Organize by date"), Gap(5), Text("New folders appear as you capture.", 12, Muted)), Select(new[] { "Daily", "Weekly", "Monthly" }, settings.Organization, value => { settings.Organization = value; Save(); Example(); })));
        saving.Children.Add(Gap(12)); saving.Children.Add(example); saving.Children.Add(Divider());
        saving.Children.Add(Row(Text("Image format"), Select(new[] { "PNG", "JPG" }, settings.Format, value => { settings.Format = value; Save(); Example(); })));
        var qualityLabel = Text(settings.Quality.ToString(), 12, Muted); var slider = new Slider { Minimum = 40, Maximum = 100, Value = settings.Quality, Width = 140, TickFrequency = 1, IsSnapToTickEnabled = true, Margin = new Thickness(0, 0, 12, 0) }; slider.ValueChanged += (_, _) => { settings.Quality = (int)slider.Value; qualityLabel.Text = settings.Quality.ToString(); Save(); }; var quality = new StackPanel { Orientation = Orientation.Horizontal }; quality.Children.Add(slider); quality.Children.Add(qualityLabel); saving.Children.Add(Gap(18)); saving.Children.Add(Row(Text("JPG quality"), quality)); page.Children.Add(Card(saving));
        Section("CAPTURE BEHAVIOR");
        page.Children.Add(Card(Stack(Row(Text("Full-screen captures"), Select(new[] { "Current monitor", "All monitors" }, settings.Monitor, value => { settings.Monitor = value; Save(); })), Gap(14), Check("Copy captures to clipboard", settings.Copy, value => { settings.Copy = value; Save(); }), Check("Save images copied from other apps", settings.Watch, value => { settings.Watch = value; ignoredClipboard = Native.GetClipboardSequenceNumber(); Save(); }), Text("Clipboard saving works while Grab Pic is running.", 12, Muted), Gap(8), StartupControl())));
        Section("DESKTOP INTEGRATION");
        if (Integration.IsPackaged) { page.Children.Add(Card(Stack(Text("Desktop menu", 15), Gap(7), Text("Windows installs and removes the capture menu with the Store package.", 12, Muted)))); return; }
        var actions = new StackPanel { Orientation = Orientation.Horizontal }; actions.Children.Add(Button("", "Enable menu", () => { try { Integration.Menu(true); status.Text = "Enabled. Right-click the desktop → Show more options → Grab Pic."; } catch (Exception e) { status.Text = e.Message; } })); var remove = Button("", "Remove menu", () => { try { Integration.Menu(false); status.Text = "Desktop menu removed."; } catch (Exception e) { status.Text = e.Message; } }); remove.Margin = new Thickness(10, 0, 0, 0); actions.Children.Add(remove);
        page.Children.Add(Card(Stack(Text("Capture from your desktop", 15), Gap(7), Text("This preview uses Windows’ “Show more options” menu.\nSetup adds this menu automatically.", 12, Muted), Gap(16), actions)));
    }
    private UIElement StartupControl() => Integration.IsPackaged ? Stack(Text("Starts in the tray. Windows manages startup for Store apps.", 12, Muted), Gap(8), Button("", "Manage startup in Windows", () => Integration.Startup(true))) : Check("Start Grab Pic when I sign in", Integration.StartsWithWindows, value => { try { Integration.Startup(value); status.Text = "Startup preference updated."; } catch (Exception e) { status.Text = e.Message; } });
    private static Border Divider() => new() { Height = 1, Background = Brush("#30313E"), Margin = new Thickness(0, 18, 0, 18) };
    private ShortcutBinding? BindingFor(int action) => action switch { 1 => settings.FullScreenShortcut, 2 => settings.AreaShortcut, _ => settings.OpenCapturesShortcut };
    private void SetBinding(int action, ShortcutBinding? binding)
    {
        if (action == 1) settings.FullScreenShortcut = binding;
        else if (action == 2) settings.AreaShortcut = binding;
        else settings.OpenCapturesShortcut = binding;
    }
    private void InvokeShortcut(int action)
    {
        if (capturing) return;
        if (action == 3) OpenFolder(); else BeginCapture(action == 2);
    }
    private Border ShortcutCard()
    {
        var card = Stack(Text("Always within reach.", 17), Gap(6), Text("Click a shortcut to record a key, combination, or mouse button.", 12, Muted), Gap(18));
        foreach (int action in new[] { 1, 2, 3 })
        {
            string name = action switch { 1 => "Full screen", 2 => "Grab area", _ => "Open captures" };
            string caption = action switch { 1 => "Capture your monitor or entire desktop.", 2 => "Drag to select just the part you need.", _ => "Go straight to your capture folder." };
            var controls = new StackPanel { Orientation = Orientation.Horizontal };
            var record = Button("", BindingFor(action)?.Label ?? "Set shortcut", () => RecordShortcut(action, name));
            record.MinWidth = 165; record.Background = Brush("#2B283B");
            System.Windows.Automation.AutomationProperties.SetName(record, "Set " + name + " shortcut");
            controls.Children.Add(record);
            var clear = Button("", "Clear", () => { if (shortcuts?.Set(action, null, out _) == true) { SetBinding(action, null); Save(); SettingsPage(); } });
            clear.Margin = new Thickness(8, 0, 0, 0); System.Windows.Automation.AutomationProperties.SetName(clear, "Clear " + name + " shortcut"); controls.Children.Add(clear);
            card.Children.Add(Row(Stack(Text(name, 14), Gap(5), Text(caption, 12, Muted)), controls));
            if (action < 3) card.Children.Add(Divider());
        }
        card.Children.Add(Gap(18));
        card.Children.Add(Text("Mouse shortcuts pause while Grab Pic is focused so you can change them here.", 11, Muted));
        card.Children.Add(Gap(5)); card.Children.Add(Text("Assigned Windows-key combinations use Grab Pic while it is running.", 11, Muted));
        card.Children.Add(Gap(12)); var reset = Button("", "Restore default shortcuts", ResetShortcuts); reset.HorizontalAlignment = HorizontalAlignment.Left; card.Children.Add(reset);
        return Card(card);
    }
    private void RecordShortcut(int action, string name)
    {
        if (shortcuts == null) return;
        shortcuts.Suspend(); var dialog = new ShortcutRecorder(this, name);
        try { dialog.ShowDialog(); } finally { var warning = shortcuts.Resume(); if (warning.Length > 0) status.Text = warning; }
        if (dialog.Binding == null) { status.Text = "Shortcut unchanged."; return; }
        foreach (int other in new[] { 1, 2, 3 })
            if (other != action && BindingFor(other) == dialog.Binding) { status.Text = "That shortcut is already assigned to another Grab Pic action."; return; }
        if (!shortcuts.Set(action, dialog.Binding, out var error)) { status.Text = error; return; }
        var previous = BindingFor(action); SetBinding(action, dialog.Binding);
        try { settings.Save(); status.Text = name + " shortcut saved · " + dialog.Binding.Label; }
        catch (Exception exception) { shortcuts.Set(action, previous, out _); SetBinding(action, previous); status.Text = "Could not save shortcut: " + exception.Message; }
        SettingsPage();
    }
    private void ResetShortcuts()
    {
        if (shortcuts == null) return;
        foreach (int action in new[] { 1, 2, 3 }) shortcuts.Set(action, null, out _);
        string errors = "";
        foreach (int action in new[] { 1, 2, 3 }) { var binding = ShortcutBinding.Keyboard(0x30 + action); SetBinding(action, binding); if (!shortcuts.Set(action, binding, out var error)) errors = error; }
        Save(); SettingsPage(); if (errors.Length > 0) status.Text = errors;
    }
    private static Grid Row(UIElement label, FrameworkElement control) { var grid = new Grid(); grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); var content = new Border { Child = label, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 20, 0) }; grid.Children.Add(content); Grid.SetColumn(control, 1); control.VerticalAlignment = VerticalAlignment.Center; grid.Children.Add(control); return grid; }
    private static ComboBox Select(string[] values, int selected, Action<int> action) { var box = new ComboBox { ItemsSource = values, SelectedIndex = selected, MinWidth = 160, Padding = new Thickness(10, 7, 10, 7), FontSize = 13 }; box.SelectionChanged += (_, _) => { if (box.SelectedIndex >= 0) action(box.SelectedIndex); }; return box; }
    private static CheckBox Check(string text, bool value, Action<bool> action) { var check = new CheckBox { Content = text, IsChecked = value, Foreground = Ink, Margin = new Thickness(0, 8, 0, 8), VerticalContentAlignment = VerticalAlignment.Center }; check.Checked += (_, _) => action(true); check.Unchecked += (_, _) => action(false); return check; }
    private void Save() { try { settings.Save(); status.Text = "Preferences saved."; } catch (Exception e) { status.Text = "Could not save preferences: " + e.Message; } }
    public async void ShowApp()
    {
        int request = ++navigationVersion;
        Show(); WindowState = WindowState.Normal; Activate();
        try
        {
            var path = latestPath != null && File.Exists(latestPath) ? latestPath : await Task.Run(() => RecentCapture.Find(settings.Folder));
            if (path != null)
            {
                var image = await Task.Run(() => { var bitmap = new System.Windows.Media.Imaging.BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad; bitmap.DecodePixelWidth = 320; bitmap.UriSource = new Uri(path); bitmap.EndInit(); bitmap.Freeze(); return bitmap; });
                if (request != navigationVersion) return;
                latestPath = path; preview.Source = image; latestName.Text = Path.GetFileName(path); latestDetail.Text = $"{new FileInfo(path).Length / 1024:N0} KB  ·  {File.GetLastWriteTime(path):g}";
            }
        }
        catch (Exception error) { status.Text = "Could not load the last capture: " + error.Message; }
        if (request == navigationVersion) CapturePage();
    }
    private void ShowSettings() { Show(); WindowState = WindowState.Normal; Activate(); SettingsPage(); }
    public void HandleCommand(string command) { switch (command) { case "full": BeginCapture(false); break; case "area": BeginCapture(true); break; case "folder": OpenFolder(); break; case "settings": ShowSettings(); break; case "quit": Application.Current.Shutdown(); break; case "background": break; default: ShowApp(); break; } }
    private void OpenFolder() { try { Directory.CreateDirectory(settings.Folder); Process.Start(new ProcessStartInfo(settings.Folder) { UseShellExecute = true }); } catch (Exception e) { status.Text = e.Message; ShowApp(); } }
    public async void BeginCapture(bool area)
    {
        if (capturing) return; capturing = true; Native.GetCursorPos(out var pointer); Hide();
        try
        {
            await Task.Delay(320); var bounds = area || settings.Monitor == 1 ? Forms.SystemInformation.VirtualScreen : Forms.Screen.FromPoint(pointer).Bounds;
            using var screenshot = Native.Capture(bounds);
            if (area) { var overlay = new AreaOverlay(screenshot, bounds); overlay.ShowDialog(); if (overlay.Selected is not { } selected || selected.Width < 2 || selected.Height < 2) { status.Text = "Capture cancelled."; return; } var relative = new System.Drawing.Rectangle(selected.X - bounds.X, selected.Y - bounds.Y, selected.Width, selected.Height); using var cropped = screenshot.Clone(relative, screenshot.PixelFormat); await Finish(cropped); }
            else await Finish(screenshot);
        }
        catch (Exception e) { status.Text = "Capture failed: " + e.Message; }
        finally { capturing = false; }
    }
    private async Task Finish(System.Drawing.Bitmap bitmap)
    {
        latestPath = await Task.Run(() => settings.SaveImage(bitmap)); RecentCapture.Remember(latestPath); string clipboard = "Saved";
        if (settings.Copy) { for (int attempt = 0; attempt < 5; attempt++) { try { System.Windows.Clipboard.SetImage(AreaOverlay.ImageSource(bitmap)); ignoredClipboard = Native.GetClipboardSequenceNumber(); clipboard = "Saved and copied"; break; } catch { clipboard = "Saved; clipboard busy"; await Task.Delay(90); } } }
        preview.Source = AreaOverlay.ImageSource(bitmap); latestName.Text = Path.GetFileName(latestPath); latestDetail.Text = $"{bitmap.Width} × {bitmap.Height}  ·  {new FileInfo(latestPath).Length / 1024:N0} KB  ·  Just now"; status.Text = clipboard + " · " + latestPath;
        CapturePage();
    }
    private IntPtr Messages(IntPtr hwnd, int message, IntPtr wparam, IntPtr lparam, ref bool handled)
    {
        if (message == 0x0312) { shortcuts?.KeyboardMessage(wparam.ToInt32()); handled = true; }
        if (message == 0x031D && settings.Watch) { clipboardTimer.Stop(); clipboardTimer.Start(); }
        return IntPtr.Zero;
    }
    private async void ClipboardTick(object? sender, EventArgs e)
    {
        clipboardTimer.Stop(); var sequence = Native.GetClipboardSequenceNumber(); if (!settings.Watch || sequence == ignoredClipboard || capturing) return;
        try { if (!System.Windows.Clipboard.ContainsImage()) return; var image = System.Windows.Clipboard.GetImage(); if (image == null) return; using var stream = new MemoryStream(); var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder(); encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(image)); encoder.Save(stream); stream.Position = 0; using var bitmap = new System.Drawing.Bitmap(stream); latestPath = await Task.Run(() => settings.SaveImage(bitmap)); RecentCapture.Remember(latestPath); ignoredClipboard = sequence; preview.Source = image; latestName.Text = Path.GetFileName(latestPath); latestDetail.Text = $"{bitmap.Width} × {bitmap.Height}  ·  From clipboard"; status.Text = "Clipboard image saved · " + latestPath; }
        catch (Exception error) { status.Text = "Could not save clipboard image: " + error.Message; }
    }
}
