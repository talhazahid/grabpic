param([string]$Name='capture-ui')
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System; using System.Runtime.InteropServices; public class QANative { [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r); public struct R { public int L,T,Rt,B; } }
"@
$p=Get-Process GrabPic | Select-Object -First 1
$r=New-Object QANative+R
[QANative]::GetWindowRect($p.MainWindowHandle,[ref]$r) | Out-Null
$bmp=New-Object System.Drawing.Bitmap ($r.Rt-$r.L),($r.B-$r.T)
$g=[System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L,$r.T,0,0,$bmp.Size)
$bmp.Save((Join-Path (Resolve-Path "$PSScriptRoot/../artifacts") "$Name.png"))
$g.Dispose(); $bmp.Dispose()
