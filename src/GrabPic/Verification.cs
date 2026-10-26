using System;
using System.Drawing;
using System.IO;
using System.Collections.Generic;
namespace GrabPic;
public static class Verification
{
    public static void Run(string report)
    {
        string folder = Path.Combine(Path.GetTempPath(), "GrabPic-QA-" + Guid.NewGuid().ToString("N")); var results = new List<string>();
        try
        {
            var preferences = new Preferences { Folder = folder };
            void Check(bool condition, string message) { if (!condition) throw new Exception(message); results.Add("PASS " + message); }
            Check(preferences.Quality == 100 && preferences.Format == 0, "Lossless PNG and JPG quality 100 defaults");
            using (var iconStream = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Assets/GrabPic.ico")).Stream)
            using (var icon = new Icon(iconStream, new Size(16,16)))
            using (var iconBitmap = icon.ToBitmap())
            {
                int colored = 0; for(int y=0;y<16;y++) for(int x=0;x<16;x++) { var color=iconBitmap.GetPixel(x,y); if(color.A>200 && color.B>color.G+30 && color.R>100) colored++; }
                Check(iconBitmap.Width==16 && colored>20, "Tray-size ICO retains purple color and correct dimensions");
            }
            var mouseBinding = new ShortcutBinding { Device = "Mouse", Code = 3, Modifiers = 2 };
            Check(mouseBinding.Label == "Ctrl + Middle click", "Mouse shortcut display");
            var serialized = System.Text.Json.JsonSerializer.Serialize(mouseBinding);
            Check(System.Text.Json.JsonSerializer.Deserialize<ShortcutBinding>(serialized) == mouseBinding, "Shortcut persistence round-trip");
            Check(preferences.FullScreenShortcut != preferences.AreaShortcut && preferences.AreaShortcut != preferences.OpenCapturesShortcut, "Three distinct default action shortcuts");
            using (var source = new System.Windows.Interop.HwndSource(new System.Windows.Interop.HwndSourceParameters("Grab Pic shortcut QA") { Width = 1, Height = 1, WindowStyle = 0 }))
            using (var shortcuts = new ShortcutService(source.Handle, System.Windows.Threading.Dispatcher.CurrentDispatcher, _ => { }, () => false))
            {
                Check(!shortcuts.Set(1, ShortcutBinding.Keyboard(0x4C, 8), out _), "Reject protected Win+L without sending it");
                Check(!shortcuts.Set(1, ShortcutBinding.Keyboard(0x2E, 3), out _), "Reject protected Ctrl+Alt+Delete without sending it");
                Check(!shortcuts.Set(1, ShortcutBinding.Keyboard(0x10, 0), out _), "Reject modifier-only binding");
                Check(shortcuts.Set(1, ShortcutBinding.Keyboard(0x53, 12), out _), "Accept Windows snipping combination through hook route");
                Check(!shortcuts.Set(2, ShortcutBinding.Keyboard(0x53, 12), out _), "Reject duplicate Windows combination");
            }
            Check(preferences.Subfolder(new DateTime(2026, 10, 26)) == "2026-10-26", "Daily folder");
            preferences.Organization = 1; Check(preferences.Subfolder(new DateTime(2021, 1, 1)) == "2020-W53", "ISO week year boundary");
            preferences.Organization = 2; Check(preferences.Subfolder(new DateTime(2026, 10, 26)) == "2026-10", "Monthly folder");
            using var bitmap = new Bitmap(300, 200); using (var graphics = Graphics.FromImage(bitmap)) graphics.Clear(Color.MediumPurple);
            var preview = AreaOverlay.ImageSource(bitmap); var pixels = new byte[300 * 200 * 4]; preview.CopyPixels(pixels, 300 * 4, 0);
            Check(pixels[0] == Color.MediumPurple.B && pixels[1] == Color.MediumPurple.G && pixels[2] == Color.MediumPurple.R, "Direct preview pixel copy preserves RGB colors");
            foreach (int format in new[] { 0, 1 }) { preferences.Format = format; string path = preferences.SaveImage(bitmap); using var decoded = Image.FromFile(path); Check(decoded.Width == 300 && decoded.Height == 200, (format == 0 ? "PNG" : "JPG") + " encode/decode and dimensions"); }
            Check(preferences.SaveImage(bitmap) != preferences.SaveImage(bitmap), "Unique capture filenames");
            var bounds = System.Windows.Forms.SystemInformation.VirtualScreen; using var desktop = Native.Capture(bounds); Check(desktop.Width == bounds.Width && desktop.Height == bounds.Height, "All-monitor capture bounds");
            results.Add("ALL CHECKS PASSED");
        }
        catch (Exception error) { results.Add("FAIL " + error); Environment.ExitCode = 1; }
        finally { File.WriteAllLines(report, results); if (Directory.Exists(folder)) Directory.Delete(folder, true); }
    }
}
