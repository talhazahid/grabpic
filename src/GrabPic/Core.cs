using System;
using System.IO;
using System.IO.Pipes;

using System.Text.Json;
using System.Threading.Tasks;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using System.Diagnostics;
using System.Security.Principal;
namespace GrabPic;
public sealed class Preferences
{
    public string Folder { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Grab Pic");
    public int Organization { get; set; }
    public int Format { get; set; }
    public int Quality { get; set; } = 100;
    public int SettingsVersion { get; set; }
    public ShortcutBinding? FullScreenShortcut { get; set; } = ShortcutBinding.Keyboard(0x31);
    public ShortcutBinding? AreaShortcut { get; set; } = ShortcutBinding.Keyboard(0x32);
    public ShortcutBinding? OpenCapturesShortcut { get; set; } = ShortcutBinding.Keyboard(0x33);
    public int Monitor { get; set; }
    public bool Copy { get; set; } = true;
    public bool Watch { get; set; }
    public static string ProfileDirectory => Environment.GetEnvironmentVariable("GRABPIC_PROFILE_DIRECTORY") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "GrabPic");
    public static string InstanceSuffix => Environment.GetEnvironmentVariable("GRABPIC_PROFILE_DIRECTORY") is string directory ? "." + Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(directory)))[..12] : "";
    public static string ConfigPath => Path.Combine(ProfileDirectory, "settings.json");
    public static Preferences Load()
    {
        Preferences preferences;
        try { preferences = JsonSerializer.Deserialize<Preferences>(File.ReadAllText(ConfigPath)) ?? new(); } catch { preferences = new(); }
        if (preferences.SettingsVersion < 1) { preferences.Quality = 100; preferences.SettingsVersion = 1; preferences.Save(); }
        return preferences;
    }
    public void Save() { Directory.CreateDirectory(Path.GetDirectoryName(ConfigPath)!); File.WriteAllText(ConfigPath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true })); }
    public string Subfolder(DateTime date) => Organization switch { 1 => $"{ISOWeek.GetYear(date)}-W{ISOWeek.GetWeekOfYear(date):00}", 2 => date.ToString("yyyy-MM", CultureInfo.InvariantCulture), _ => date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) };
    public string SaveImage(Bitmap bitmap)
    {
        var now = DateTime.Now; string directory = Path.Combine(Folder, Subfolder(now)); Directory.CreateDirectory(directory);
        string path = Path.Combine(directory, $"Grab_{now:yyyy-MM-dd_HH-mm-ss-fff}_{Guid.NewGuid().ToString("N")[..4]}.{(Format == 0 ? "png" : "jpg")}");
        if (Format == 0) bitmap.Save(path, ImageFormat.Png);
        else { using var parameters = new EncoderParameters(1); parameters.Param[0] = new EncoderParameter(Encoder.Quality, (long)Quality); var codec = Array.Find(ImageCodecInfo.GetImageEncoders(), x => x.FormatID == ImageFormat.Jpeg.Guid)!; bitmap.Save(path, codec, parameters); }
        return path;
    }
}
public static class Native
{
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hwnd, int id);
    [DllImport("user32.dll")] public static extern bool AddClipboardFormatListener(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool RemoveClipboardFormatListener(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
    public static Bitmap Capture(Rectangle bounds) { var bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb); try { using var graphics = Graphics.FromImage(bitmap); graphics.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size, CopyPixelOperation.SourceCopy); return bitmap; } catch { bitmap.Dispose(); throw; } }
}
public static class RecentCapture
{
    private static string StatePath => Path.Combine(Path.GetDirectoryName(Preferences.ConfigPath)!, "latest-capture.json");
    public static void Remember(string path) { try { Directory.CreateDirectory(Path.GetDirectoryName(StatePath)!); File.WriteAllText(StatePath, JsonSerializer.Serialize(path)); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    public static string? Find(string folder)
    {
        try { var path = JsonSerializer.Deserialize<string>(File.ReadAllText(StatePath)); if (path != null && File.Exists(path)) return path; } catch (IOException) { } catch (JsonException) { } catch (UnauthorizedAccessException) { }
        try
        {
            string? latest = null; DateTime time = DateTime.MinValue;
            if (!Directory.Exists(folder)) return null;
            foreach (var path in Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories))
            {
                var extension = Path.GetExtension(path); if (!extension.Equals(".png", StringComparison.OrdinalIgnoreCase) && !extension.Equals(".jpg", StringComparison.OrdinalIgnoreCase) && !extension.Equals(".jpeg", StringComparison.OrdinalIgnoreCase)) continue;
                var modified = File.GetLastWriteTimeUtc(path); if (modified > time) { time = modified; latest = path; }
            }
            return latest;
        }
        catch (IOException) { return null; } catch (UnauthorizedAccessException) { return null; }
    }
}
public static class Integration
{
    public static bool IsPackaged { get { int length = 0; return GetCurrentPackageFullName(ref length, null) != 15700 && length > 0; } }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern int GetCurrentPackageFullName(ref int length, System.Text.StringBuilder? name);
    private const string MenuKey = @"Software\Classes\DesktopBackground\Shell\GrabPic";
    public static bool MachineMenu
    {
        get
        {
            using var install = Registry.LocalMachine.OpenSubKey(@"Software\GrabPic");
            using var policy = Registry.LocalMachine.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Policies\System");
            return install?.GetValue("InstallPath") != null || (policy?.GetValue("EnableLUA") is int value && value == 0);
        }
    }
    public static void Menu(bool enable)
    {
        if (MachineMenu && !new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator))
        {
            using var helper = Process.Start(new ProcessStartInfo(Environment.ProcessPath!, enable ? "--menu-enable" : "--menu-remove") { UseShellExecute = true, Verb = "runas" });
            helper!.WaitForExit(); if (helper.ExitCode != 0) throw new InvalidOperationException("Windows could not update the desktop menu."); return;
        }
        WriteMenu(enable, MachineMenu);
    }
    public static void WriteMenu(bool enable, bool machine)
    {
        if (IsPackaged) throw new InvalidOperationException("Windows manages the Store package's menu automatically.");
        var hive = machine ? Registry.LocalMachine : Registry.CurrentUser;
        hive.DeleteSubKeyTree(MenuKey, false);
        if (!enable) return;
        using var root = hive.CreateSubKey(MenuKey); root.SetValue("MUIVerb", "Grab Pic"); root.SetValue("SubCommands", "");
        var exe = Environment.ProcessPath!; root.SetValue("Icon", $"\"{exe}\",0");
        var items = new[] { ("01screen", "Grab Full Screen", "full"), ("02area", "Grab Area", "area"), ("03folder", "Open Captures", "folder"), ("04settings", "Settings", "settings") };
        foreach (var (key, title, command) in items) { using var child = root.CreateSubKey(@"shell\" + key); child.SetValue("MUIVerb", title); using var action = child.CreateSubKey("command"); action.SetValue("", $"\"{exe}\" {command}"); }
        SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero);
    }
    [DllImport("shell32.dll")] private static extern void SHChangeNotify(uint events, uint flags, IntPtr first, IntPtr second);
    public static bool StartsWithWindows { get { using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"); return key?.GetValue("GrabPic") != null; } }
    public static void Startup(bool enable) { if (IsPackaged) { Process.Start(new ProcessStartInfo("ms-settings:startupapps") { UseShellExecute = true }); return; } using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"); if (enable) key.SetValue("GrabPic", $"\"{Environment.ProcessPath}\" background"); else key.DeleteValue("GrabPic", false); }
}
public static class CommandBus
{
    private static string PipeName => "GrabPic." + Environment.UserName + Preferences.InstanceSuffix;
    public static void Send(string command) { try { using var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.Out); pipe.Connect(2000); using var writer = new StreamWriter(pipe); writer.WriteLine(command); } catch { } }
    public static void Listen(Action<string> action) => Task.Run(async () => { while (true) { try { using var pipe = new NamedPipeServerStream(PipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly); await pipe.WaitForConnectionAsync(); using var reader = new StreamReader(pipe); var command = await reader.ReadLineAsync(); if (command != null) action(command); } catch { await Task.Delay(500); } } });
}
