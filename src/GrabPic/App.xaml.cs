using System;
using System.Threading;
using System.Windows;
using Forms = System.Windows.Forms;
namespace GrabPic;
public partial class App : Application
{
    private Mutex? mutex;
    private Forms.NotifyIcon? tray;
    private System.Drawing.Icon? trayIcon;
    protected override void OnStartup(StartupEventArgs e)
    {
        if (e.Args.Length == 2 && e.Args[0] == "--verify") { Verification.Run(e.Args[1]); Shutdown(); return; }
        if (e.Args.Length == 1 && (e.Args[0] == "--menu-enable" || e.Args[0] == "--menu-remove")) { try { Integration.WriteMenu(e.Args[0] == "--menu-enable", true); Shutdown(0); } catch { Shutdown(1); } return; }
        if (e.Args.Length == 1 && e.Args[0] == "quit") { CommandBus.Send("quit"); Shutdown(); return; }
        if (Environment.GetEnvironmentVariable("GRABPIC_SCREENSHOT_MODE") != "1")
            try { BrowserBridge.Register(); } catch (Exception error) { System.Diagnostics.Debug.WriteLine(error.Message); }
        base.OnStartup(e); mutex = new Mutex(true, "Local\\GrabPic.App" + Preferences.InstanceSuffix, out bool first);
        if (!first) { CommandBus.Send(e.Args.Length > 0 ? e.Args[0] : "show"); Shutdown(); return; }
        DispatcherUnhandledException += (_, a) => { MessageBox.Show(a.Exception.Message, "Grab Pic"); a.Handled = true; };
        var window = new MainWindow(); MainWindow = window; new System.Windows.Interop.WindowInteropHelper(window).EnsureHandle();
        using (var iconStream = GetResourceStream(new Uri("pack://application:,,,/Assets/GrabPic.ico")).Stream)
        using (var loadedIcon = new System.Drawing.Icon(iconStream, Forms.SystemInformation.SmallIconSize))
            trayIcon = (System.Drawing.Icon)loadedIcon.Clone();
        tray = new Forms.NotifyIcon { Icon = trayIcon, Text = "Grab Pic", Visible = true, ContextMenuStrip = new Forms.ContextMenuStrip() };
        tray.ContextMenuStrip.BackColor = System.Drawing.Color.FromArgb(29, 30, 40);
        tray.ContextMenuStrip.ForeColor = System.Drawing.Color.FromArgb(238, 239, 245);
        tray.ContextMenuStrip.Renderer = new Forms.ToolStripProfessionalRenderer(new DarkTrayColors());
        tray.ContextMenuStrip.Items.Add("Grab full screen", null, (_, _) => window.BeginCapture(false));
        tray.ContextMenuStrip.Items.Add("Grab area", null, (_, _) => window.BeginCapture(true));
        tray.ContextMenuStrip.Items.Add("Open captures", null, (_, _) => window.HandleCommand("folder"));
        tray.ContextMenuStrip.Items.Add("Open Grab Pic", null, (_, _) => window.ShowApp());
        tray.ContextMenuStrip.Items.Add("Quit Grab Pic", null, (_, _) => Shutdown()); tray.DoubleClick += (_, _) => window.ShowApp();
        CommandBus.Listen(command => Dispatcher.Invoke(() => window.HandleCommand(command)));
        if (e.Args.Length > 0) window.HandleCommand(e.Args[0]); else window.ShowApp();
    }
    protected override void OnExit(ExitEventArgs e) { tray?.Dispose(); trayIcon?.Dispose(); mutex?.Dispose(); base.OnExit(e); }
    private sealed class DarkTrayColors : Forms.ProfessionalColorTable
    {
        public DarkTrayColors() { UseSystemColors = false; }
        public override System.Drawing.Color ToolStripDropDownBackground => System.Drawing.Color.FromArgb(29, 30, 40);
        public override System.Drawing.Color ImageMarginGradientBegin => ToolStripDropDownBackground;
        public override System.Drawing.Color ImageMarginGradientMiddle => ToolStripDropDownBackground;
        public override System.Drawing.Color ImageMarginGradientEnd => ToolStripDropDownBackground;
        public override System.Drawing.Color MenuItemSelected => System.Drawing.Color.FromArgb(52, 48, 73);
        public override System.Drawing.Color MenuItemBorder => MenuItemSelected;
        public override System.Drawing.Color MenuBorder => System.Drawing.Color.FromArgb(53, 54, 69);
    }
}
