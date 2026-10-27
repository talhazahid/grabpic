using System;
using System.IO;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;

namespace GrabPic;
public static class BrowserBridge
{
    public const string ExtensionId = "fnnldbdenmkagpnfneogfcfnjpgjjdpl";
    public static string Inbox => Path.Combine(Preferences.ProfileDirectory, "BrowserInbox");
    public static void WriteReceipt(string path, string result) { File.WriteAllText(path + ".tmp", result); File.Move(path + ".tmp", path, true); }
    public static void Register()
    {
        string directory = Path.Combine(Preferences.ProfileDirectory, "BrowserBridge");
        Directory.CreateDirectory(directory);
        foreach (string browser in new[] { "Chrome", "Edge", "Firefox" })
        {
            string manifest = Path.Combine(directory, browser + ".json");
            var common = new System.Collections.Generic.Dictionary<string, object> {
                ["name"] = "com.owl.grabpic", ["description"] = "Grabpic local screenshot bridge",
                ["path"] = Path.Combine(AppContext.BaseDirectory, "GrabPic.BrowserHost.exe"), ["type"] = "stdio" };
            common[browser == "Firefox" ? "allowed_extensions" : "allowed_origins"] = browser == "Firefox" ? new[] { "grabpic@owl.dev" } : new[] { "chrome-extension://" + ExtensionId + "/" };
            File.WriteAllText(manifest, JsonSerializer.Serialize(common));
            string vendor = browser == "Chrome" ? @"Google\Chrome" : browser == "Edge" ? @"Microsoft\Edge" : "Mozilla";
            using var key = Registry.CurrentUser.CreateSubKey(@"Software\" + vendor + @"\NativeMessagingHosts\com.owl.grabpic");
            key.SetValue("", manifest);
        }
    }
    public static void RunHost()
    {
        using var input = Console.OpenStandardInput(); using var output = Console.OpenStandardOutput();
        try
        {
            Span<byte> header = stackalloc byte[4]; input.ReadExactly(header);
            int size = System.Buffers.Binary.BinaryPrimitives.ReadInt32LittleEndian(header);
            if (size < 2 || size > 96 * 1024 * 1024) throw new InvalidDataException("Capture message is too large.");
            byte[] bytes = new byte[size]; input.ReadExactly(bytes);
            using var message = JsonDocument.Parse(bytes); string action = message.RootElement.GetProperty("action").GetString()!;
            if (action == "ping") { Reply(output, new { ok = true, version = "0.6.0" }); return; }
            string command;
            string? pending = null;
            if (action == "area") command = "area";
            else if (action == "image")
            {
                string data = message.RootElement.GetProperty("data").GetString()!;
                const string prefix = "data:image/png;base64,";
                if (!data.StartsWith(prefix, StringComparison.Ordinal)) throw new InvalidDataException("Expected a PNG screenshot.");
                byte[] png = Convert.FromBase64String(data[prefix.Length..]);
                using (var stream = new MemoryStream(png)) using (var bitmap = new System.Drawing.Bitmap(stream))
                    if ((long)bitmap.Width * bitmap.Height > 60_000_000) throw new InvalidDataException("Capture exceeds the 60 megapixel limit.");
                Directory.CreateDirectory(Inbox); string path = Path.Combine(Inbox, Guid.NewGuid().ToString("N") + ".png"); File.WriteAllBytes(path, png);
                pending = path;
                command = "browser:" + path;
            }
            else throw new InvalidDataException("Unknown browser action.");
            // Keep the tray process from inheriting the browser's native-messaging pipes.
            using var process = Process.Start(new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory, "GrabPic.exe"), "background") { UseShellExecute = true });
            if (!CommandBus.TrySend(command, 20000)) throw new IOException("Grabpic could not start. Please open the app and retry.");
            if (pending != null)
            {
                string receipt = pending + ".result";
                for (int attempt = 0; attempt < 200 && !File.Exists(receipt); attempt++) System.Threading.Thread.Sleep(100);
                if (!File.Exists(receipt)) throw new IOException("Grabpic did not confirm saving. Please open Grabpic and retry.");
                string result = File.ReadAllText(receipt); File.Delete(receipt);
                if (result != "ok") throw new IOException(result);
            }
            Reply(output, new { ok = true, message = "Saved in your Grabpic capture folder." });
        }
        catch (Exception error) { Reply(output, new { ok = false, error = error.Message }); }
    }
    private static void Reply(Stream output, object value)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(value));
        Span<byte> header = stackalloc byte[4]; System.Buffers.Binary.BinaryPrimitives.WriteInt32LittleEndian(header, bytes.Length);
        output.Write(header); output.Write(bytes); output.Flush();
    }
}
