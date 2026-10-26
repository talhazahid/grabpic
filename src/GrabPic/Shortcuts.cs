using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace GrabPic;

public sealed record ShortcutBinding
{
    public string Device { get; init; } = "Keyboard";
    public int Code { get; init; }
    public uint Modifiers { get; init; }
    public static ShortcutBinding Keyboard(int code, uint modifiers = 6) => new() { Code = code, Modifiers = modifiers };
    [System.Text.Json.Serialization.JsonIgnore]
    public string Label
    {
        get
        {
            var parts = new List<string>();
            if ((Modifiers & 2) != 0) parts.Add("Ctrl");
            if ((Modifiers & 4) != 0) parts.Add("Shift");
            if ((Modifiers & 1) != 0) parts.Add("Alt");
            if ((Modifiers & 8) != 0) parts.Add("Win");
            parts.Add(Device == "Mouse" ? Code switch { 1 => "Left click", 2 => "Right click", 3 => "Middle click", 4 => "Mouse 4", 5 => "Mouse 5", _ => "Mouse" } : KeyName(Code));
            return string.Join(" + ", parts);
        }
    }
    private static string KeyName(int code) => code is >= 0x30 and <= 0x39 || code is >= 0x41 and <= 0x5A ? ((char)code).ToString() : code switch
    { 0x0D => "Enter", 0x20 => "Space", 0x2C => "Print Screen", 0xBA => ";", 0xBB => "=", 0xBC => ",", 0xBD => "-", 0xBE => ".", 0xBF => "/", 0xC0 => "`", 0xDB => "[", 0xDC => "\\", 0xDD => "]", 0xDE => "'", _ => KeyInterop.KeyFromVirtualKey(code).ToString() };
    public static uint CurrentModifiers()
    {
        uint value = 0;
        if (Down(0x11)) value |= 2; if (Down(0x10)) value |= 4; if (Down(0x12)) value |= 1;
        if (Down(0x5B) || Down(0x5C)) value |= 8; return value;
    }
    private static bool Down(int key) => (GetAsyncKeyState(key) & 0x8000) != 0;
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
}

public sealed class ShortcutService : IDisposable
{
    private readonly IntPtr window;
    private readonly Dispatcher dispatcher;
    private readonly Action<int> invoke;
    private readonly Func<bool> canUseMouse;
    private readonly HookProc mouseCallback;
    private readonly HookProc keyboardCallback;
    private IntPtr keyboardHook;
    private readonly HashSet<int> heldKeys = new();
    private readonly Dictionary<int, ShortcutBinding> bindings = new();
    private IntPtr mouseHook;
    private bool suspended;
    private int heldMouse;
    public ShortcutService(IntPtr window, Dispatcher dispatcher, Action<int> invoke, Func<bool> canUseMouse)
    {
        this.window = window; this.dispatcher = dispatcher; this.invoke = invoke; this.canUseMouse = canUseMouse;
        mouseCallback = MouseHook;
        keyboardCallback = KeyboardHook;
        keyboardHook = SetWindowsHookEx(13, keyboardCallback, GetModuleHandle(null), 0);
        if (keyboardHook == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        mouseHook = SetWindowsHookEx(14, mouseCallback, GetModuleHandle(null), 0);
        if (mouseHook == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
    }
    public bool Set(int action, ShortcutBinding? binding, out string error)
    {
        error = "";
        if (binding != null)
        {
            foreach (var entry in bindings)
                if (entry.Key != action && entry.Value == binding) { error = "That shortcut is already assigned to another Grab Pic action."; return false; }
            if (binding.Device is not ("Keyboard" or "Mouse") || (binding.Device == "Keyboard" && binding.Code is < 1 or > 254) || (binding.Device == "Mouse" && binding.Code is < 1 or > 5)) { error = "Choose a valid keyboard key or mouse button."; return false; }
            if ((binding.Modifiers & ~15u) != 0) { error = "That modifier combination is not supported."; return false; }
            if (binding.Device == "Keyboard" && binding.Code is 0x10 or 0x11 or 0x12 or 0x5B or 0x5C or >= 0xA0 and <= 0xA5) { error = "Add a regular key to the modifier combination."; return false; }
            if (binding.Device == "Keyboard" && ((binding.Code == 0x4C && (binding.Modifiers & 8) != 0) || (binding.Code == 0x2E && (binding.Modifiers & 3) == 3))) { error = "Windows protects that security shortcut. Choose another combination."; return false; }
        }
        bindings.TryGetValue(action, out var previous);
        Native.UnregisterHotKey(window, action);
        if (!suspended && binding?.Device == "Keyboard" && (binding.Modifiers & 8) == 0 && !Native.RegisterHotKey(window, action, binding.Modifiers | 0x4000, (uint)binding.Code))
        {
            if (previous?.Device == "Keyboard" && (previous.Modifiers & 8) == 0) Native.RegisterHotKey(window, action, previous.Modifiers | 0x4000, (uint)previous.Code);
            error = "Windows or another app is using that shortcut. Choose a different combination."; return false;
        }
        if (binding == null) bindings.Remove(action); else bindings[action] = binding;
        return true;
    }
    public void Suspend()
    {
        suspended = true;
        foreach (int action in bindings.Keys) Native.UnregisterHotKey(window, action);
    }
    public string Resume()
    {
        suspended = false; var unavailable = new List<string>();
        foreach (var (action, binding) in bindings)
            if (binding.Device == "Keyboard" && (binding.Modifiers & 8) == 0 && !Native.RegisterHotKey(window, action, binding.Modifiers | 0x4000, (uint)binding.Code)) unavailable.Add(binding.Label);
        return unavailable.Count == 0 ? "" : "Unavailable shortcuts: " + string.Join(", ", unavailable);
    }
    public void KeyboardMessage(int action) { if (!suspended && bindings.ContainsKey(action)) dispatcher.BeginInvoke(() => invoke(action)); }
    private IntPtr KeyboardHook(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0)
        {
            int key = Marshal.ReadInt32(data), kind = message.ToInt32();
            if (kind is 0x101 or 0x105 && heldKeys.Remove(key)) return new IntPtr(1);
            if (!suspended && kind is 0x100 or 0x104)
            {
                if (heldKeys.Contains(key)) return new IntPtr(1);
                uint modifiers = ShortcutBinding.CurrentModifiers();
                foreach (var (action, binding) in bindings)
                {
                    if (binding.Device != "Keyboard" || (binding.Modifiers & 8) == 0 || binding.Code != key || binding.Modifiers != modifiers) continue;
                    heldKeys.Add(key); dispatcher.BeginInvoke(() => invoke(action)); return new IntPtr(1);
                }
            }
        }
        return CallNextHookEx(keyboardHook, code, message, data);
    }
    private IntPtr MouseHook(int code, IntPtr wparam, IntPtr lparam)
    {
        if (code >= 0)
        {
            int message = wparam.ToInt32();
            var data = Marshal.PtrToStructure<MouseData>(lparam);
            bool down = message is 0x201 or 0x204 or 0x207 or 0x20B;
            bool up = message is 0x202 or 0x205 or 0x208 or 0x20C;
            int button = message switch { 0x201 or 0x202 => 1, 0x204 or 0x205 => 2, 0x207 or 0x208 => 3, 0x20B or 0x20C => (data.MouseDataValue >> 16) == 1 ? 4 : 5, _ => 0 };
            if (up && heldMouse == button) { heldMouse = 0; return new IntPtr(1); }
            if (!suspended && down && button != 0 && canUseMouse())
            {
                uint modifiers = ShortcutBinding.CurrentModifiers();
                foreach (var (action, binding) in bindings)
                {
                    if (binding.Device != "Mouse" || binding.Code != button || binding.Modifiers != modifiers) continue;
                    // Do not redirect ordinary primary clicks; the settings window stays usable.
                    bool consume = button > 2 || modifiers != 0;
                    if (consume) heldMouse = button;
                    dispatcher.BeginInvoke(DispatcherPriority.Background, () => invoke(action));
                    if (consume) return new IntPtr(1);
                    break;
                }
            }
        }
        return CallNextHookEx(mouseHook, code, wparam, lparam);
    }
    public void Dispose() { foreach (int action in bindings.Keys) Native.UnregisterHotKey(window, action); if (mouseHook != IntPtr.Zero) { UnhookWindowsHookEx(mouseHook); mouseHook = IntPtr.Zero; } if (keyboardHook != IntPtr.Zero) { UnhookWindowsHookEx(keyboardHook); keyboardHook = IntPtr.Zero; } }
    private delegate IntPtr HookProc(int code, IntPtr wparam, IntPtr lparam);
    [StructLayout(LayoutKind.Sequential)] private struct MouseData { public int X, Y; public uint MouseDataValue, Flags, Time; public UIntPtr Extra; }
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int id, HookProc callback, IntPtr module, uint thread);
    [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wparam, IntPtr lparam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string? name);
}

public sealed class ShortcutRecorder : Window
{
    private IntPtr keyboardHook;
    private IntPtr recordingMouseHook;
    private readonly RecordHook callback;
    private readonly RecordHook mouseCallback;
    private Rect inputBounds;
    private bool completing;
    public ShortcutBinding? Binding { get; private set; }
    public ShortcutRecorder(Window owner, string action)
    {
        callback = RecordKey; mouseCallback = RecordMouse;
        SourceInitialized += (_, _) => { int dark = 1; DwmSetWindowAttribute(new System.Windows.Interop.WindowInteropHelper(this).Handle, 20, ref dark, sizeof(int)); };
        Owner = owner; Title = "Set shortcut · " + action; Width = 460; Height = 280; ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterOwner; ShowInTaskbar = false;
        FontFamily = owner.FontFamily; FontSize = 13; Background = (Brush)new BrushConverter().ConvertFromString("#191A22")!; Foreground = (Brush)new BrushConverter().ConvertFromString("#EEEFF5")!;
        var content = new StackPanel { Margin = new Thickness(28) }; Content = content;
        content.Children.Add(new TextBlock { Text = "Your shortcut. Your way.", FontSize = 23, Margin = new Thickness(0, 0, 0, 10) });
        content.Children.Add(new TextBlock { Text = "Press a key or a key combination. For a mouse shortcut,\nclick inside the box below while holding any modifiers.", Foreground = (Brush)new BrushConverter().ConvertFromString("#A3A4B5")!, TextWrapping = TextWrapping.Wrap });
        var input = new Border { Background = (Brush)new BrushConverter().ConvertFromString("#2B283B")!, CornerRadius = new CornerRadius(10), Margin = new Thickness(0, 18, 0, 12), Padding = new Thickness(18), Child = new TextBlock { Text = "Listening for " + action + "…", Foreground = (Brush)new BrushConverter().ConvertFromString("#B3A5FF")! } };
        content.Children.Add(input); content.Children.Add(new TextBlock { Text = "Esc cancels. Close this window to keep your current shortcut.", FontSize = 11, Foreground = (Brush)new BrushConverter().ConvertFromString("#A3A4B5")! });
        PreviewKeyDown += (_, e) =>
        {
            e.Handled = true; var key = e.Key == Key.System ? e.SystemKey : e.Key;
            if (key == Key.Escape) { DialogResult = false; return; }
            if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin) return;
            Binding = ShortcutBinding.Keyboard(KeyInterop.VirtualKeyFromKey(key), ShortcutBinding.CurrentModifiers()); DialogResult = true;
        };
        input.PreviewMouseDown += (_, e) => { e.Handled = true; Binding = new ShortcutBinding { Device = "Mouse", Modifiers = ShortcutBinding.CurrentModifiers(), Code = e.ChangedButton switch { MouseButton.Left => 1, MouseButton.Right => 2, MouseButton.Middle => 3, MouseButton.XButton1 => 4, _ => 5 } }; DialogResult = true; };
        Loaded += (_, _) => { inputBounds = new Rect(input.PointToScreen(new Point(0, 0)), input.PointToScreen(new Point(input.ActualWidth, input.ActualHeight))); keyboardHook = SetWindowsHookEx(13, callback, GetModuleHandle(null), 0); recordingMouseHook = SetWindowsHookEx(14, mouseCallback, GetModuleHandle(null), 0); if (keyboardHook == IntPtr.Zero) { content.Children.Add(new TextBlock { Text = "Some reserved keys may not be recordable.", Foreground = (Brush)new BrushConverter().ConvertFromString("#A3A4B5")! }); } };
        LocationChanged += (_, _) => { if (IsLoaded) inputBounds = new Rect(input.PointToScreen(new Point(0, 0)), input.PointToScreen(new Point(input.ActualWidth, input.ActualHeight))); };
        Closed += (_, _) => { if (keyboardHook != IntPtr.Zero) { UnhookWindowsHookEx(keyboardHook); keyboardHook = IntPtr.Zero; } if (recordingMouseHook != IntPtr.Zero) { UnhookWindowsHookEx(recordingMouseHook); recordingMouseHook = IntPtr.Zero; } };
    }
    private IntPtr RecordMouse(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0 && !completing && inputBounds.Contains(new Point(Marshal.ReadInt32(data), Marshal.ReadInt32(data, 4))))
        {
            int button = message.ToInt32() switch { 0x201 => 1, 0x204 => 2, 0x207 => 3, 0x20B => (Marshal.ReadInt32(data, 8) >> 16) == 1 ? 4 : 5, _ => 0 };
            if (button != 0)
            {
                completing = true; var binding = new ShortcutBinding { Device = "Mouse", Code = button, Modifiers = ShortcutBinding.CurrentModifiers() };
                Dispatcher.BeginInvoke(() => { if (IsVisible) { Binding = binding; DialogResult = true; } });
                return new IntPtr(1);
            }
        }
        return CallNextHookEx(recordingMouseHook, code, message, data);
    }
    private IntPtr RecordKey(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0 && message.ToInt32() is 0x100 or 0x104)
        {
            int key = Marshal.ReadInt32(data);
            if (key is not (0x10 or 0x11 or 0x12 or 0x5B or 0x5C or 0xA0 or 0xA1 or 0xA2 or 0xA3 or 0xA4 or 0xA5))
            {
                if (!completing)
                {
                    completing = true; var binding = ShortcutBinding.Keyboard(key, ShortcutBinding.CurrentModifiers());
                    Dispatcher.BeginInvoke(() => { if (!IsVisible) return; if (key == 0x1B) DialogResult = false; else { Binding = binding; DialogResult = true; } });
                }
                return new IntPtr(1);
            }
        }
        return CallNextHookEx(keyboardHook, code, message, data);
    }
    private delegate IntPtr RecordHook(int code, IntPtr message, IntPtr data);
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int id, RecordHook callback, IntPtr module, uint thread);
    [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string? name);
}
