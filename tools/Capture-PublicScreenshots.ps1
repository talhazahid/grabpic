param([string]$Exe)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(!$Exe){$Exe="$root/src/GrabPic/bin/Release/net8.0-windows/GrabPic.exe"}
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System; using System.Runtime.InteropServices;
public class PublicCapture {
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd,IntPtr dc,uint flags);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd,out Rect r);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int w,int h,uint flags);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
 public struct Rect { public int Left,Top,Right,Bottom; }
}
"@
[PublicCapture]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null
$profile="$PSScriptRoot/.cache/public-screenshot-profile"
$folder=Join-Path ([Environment]::GetFolderPath('CommonPictures')) 'Grabpic'
foreach($directory in @($profile,$folder,"$root/docs/images","$root/submission/screenshots")){New-Item -ItemType Directory -Force $directory | Out-Null}
# The app runs against an isolated profile and a generated sample image. No private desktop is photographed.
$sample=Join-Path $folder 'Sample-capture.png'
$bitmap=[System.Drawing.Bitmap]::new(1200,760); $g=[System.Drawing.Graphics]::FromImage($bitmap)
$g.Clear([System.Drawing.ColorTranslator]::FromHtml('#272337'))
$font=[System.Drawing.Font]::new('Segoe UI',40,[System.Drawing.FontStyle]::Regular)
$g.DrawString('A little less friction.',$font,[System.Drawing.Brushes]::White,90,280)
$small=[System.Drawing.Font]::new('Segoe UI',21,[System.Drawing.FontStyle]::Regular)
$g.DrawString('Sample capture for the Grabpic preview',$small,[System.Drawing.Brushes]::LightGray,95,360)
$g.Dispose(); $font.Dispose(); $small.Dispose(); $bitmap.Save($sample,[System.Drawing.Imaging.ImageFormat]::Png); $bitmap.Dispose()
@{Folder=$folder;Organization=0;Format=0;Quality=100;SettingsVersion=1;Copy=$true;Watch=$false;FullScreenShortcut=@{Device='Keyboard';Code=49;Modifiers=6};AreaShortcut=@{Device='Keyboard';Code=83;Modifiers=12};OpenCapturesShortcut=@{Device='Keyboard';Code=51;Modifiers=6}} | ConvertTo-Json -Depth 6 | Set-Content "$profile/settings.json"
ConvertTo-Json $sample | Set-Content "$profile/latest-capture.json"
$oldProfile=$env:GRABPIC_PROFILE_DIRECTORY; $oldMode=$env:GRABPIC_SCREENSHOT_MODE
$env:GRABPIC_PROFILE_DIRECTORY=$profile; $env:GRABPIC_SCREENSHOT_MODE='1'
try {
 $process=Start-Process -FilePath $Exe -PassThru
 for($i=0;$i -lt 100;$i++){ $process.Refresh(); if($process.MainWindowHandle -ne [IntPtr]::Zero){break}; Start-Sleep -Milliseconds 100 }
 $handle=$process.MainWindowHandle
 if($handle -eq [IntPtr]::Zero){throw 'Screenshot app did not open.'}
 [PublicCapture]::SetWindowPos($handle,[IntPtr]::Zero,200,70,1366,900,0x14) | Out-Null
 Start-Sleep -Milliseconds 800
 function Save-Window([string]$name) {
  Start-Sleep -Milliseconds 400
  $r=New-Object PublicCapture+Rect; [PublicCapture]::GetWindowRect($handle,[ref]$r) | Out-Null
  $image=[System.Drawing.Bitmap]::new($r.Right-$r.Left,$r.Bottom-$r.Top); $draw=[System.Drawing.Graphics]::FromImage($image); $draw.Clear([System.Drawing.Color]::FromArgb(20,21,27)); $dc=$draw.GetHdc()
  try {if(![PublicCapture]::PrintWindow($handle,$dc,2)){throw 'Window capture failed.'}}finally{$draw.ReleaseHdc($dc)}
  $image.Save("$root/docs/images/$name.png",[System.Drawing.Imaging.ImageFormat]::Png); $draw.Dispose(); $image.Dispose()
  Copy-Item "$root/docs/images/$name.png" "$root/submission/screenshots/$name.png" -Force
 }
 function Root { [System.Windows.Automation.AutomationElement]::FromHandle($handle) }
 Save-Window '01-capture'
 $condition=New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::NameProperty),'Settings'
 $button=(Root).FindFirst([System.Windows.Automation.TreeScope]::Descendants,$condition)
 ([System.Windows.Automation.InvokePattern]$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
 Save-Window '02-shortcuts'
 $condition=New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ControlTypeProperty),([System.Windows.Automation.ControlType]::Pane)
 $scroll=(Root).FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition) | Where-Object { $_.GetSupportedPatterns().ProgrammaticName -contains 'ScrollPatternIdentifiers.Pattern' } | Select-Object -First 1
 if(!$scroll){ throw 'Settings scroll control not found.' }
 $pattern=[System.Windows.Automation.ScrollPattern]$scroll.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
 $pattern.SetScrollPercent(-1,75); Save-Window '03-saving'
 $pattern.SetScrollPercent(-1,100); Save-Window '04-background'
} finally {
 if($process -and !$process.HasExited){ $quit=Start-Process -FilePath $Exe -ArgumentList 'quit' -PassThru; $quit.WaitForExit() }
 $env:GRABPIC_PROFILE_DIRECTORY=$oldProfile; $env:GRABPIC_SCREENSHOT_MODE=$oldMode
}
