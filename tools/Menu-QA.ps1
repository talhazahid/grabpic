param([string]$Name='menu-qa',[switch]$Submenu,[switch]$InvokeFull)
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices; public class MenuTest { [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y); [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint dx,uint dy,uint data,UIntPtr extra); [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s,uint f,UIntPtr e); [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value); [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h,StringBuilder text,int length); }
"@
[MenuTest]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null
[System.Windows.Forms.SendKeys]::SendWait('{ESC}{ESC}')
$text=New-Object System.Text.StringBuilder 256
[MenuTest]::GetClassName([MenuTest]::GetForegroundWindow(),$text,256) | Out-Null
if($text.ToString() -notin @('Progman','WorkerW')) {
 [MenuTest]::keybd_event(0x5B,0,0,[UIntPtr]::Zero); [MenuTest]::keybd_event(0x44,0,0,[UIntPtr]::Zero); [MenuTest]::keybd_event(0x44,0,2,[UIntPtr]::Zero); [MenuTest]::keybd_event(0x5B,0,2,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 700
}
[MenuTest]::SetCursorPos(900,400) | Out-Null
Start-Sleep -Milliseconds 150
[MenuTest]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [MenuTest]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 150
[MenuTest]::mouse_event(8,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 50; [MenuTest]::mouse_event(16,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 500
[MenuTest]::SetCursorPos(1030,776) | Out-Null
[MenuTest]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [MenuTest]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 600
if($Submenu) { [MenuTest]::SetCursorPos(1030,544) | Out-Null; Start-Sleep -Milliseconds 600 }
$b=New-Object System.Drawing.Bitmap 1920,1080
$g=[System.Drawing.Graphics]::FromImage($b)
$g.CopyFromScreen(0,0,0,0,$b.Size)
$b.Save((Join-Path (Resolve-Path "$PSScriptRoot/../artifacts") "$Name.png"))
$g.Dispose(); $b.Dispose()



if($InvokeFull) { [MenuTest]::SetCursorPos(1250,546) | Out-Null; Start-Sleep -Milliseconds 150; [MenuTest]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [MenuTest]::mouse_event(4,0,0,0,[UIntPtr]::Zero); Start-Sleep -Seconds 3 }
