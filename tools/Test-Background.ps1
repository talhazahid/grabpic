$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System; using System.Runtime.InteropServices;
public class ShortcutQA {
 [DllImport("user32.dll")] public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint dx,uint dy,uint data,UIntPtr extra);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint msg,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h,int id,uint mods,uint key);
 [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h,int id);
}
"@
[ShortcutQA]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null
$exe = (Get-Process GrabPic | Select-Object -First 1).Path
$config = Join-Path $env:LOCALAPPDATA 'GrabPic\settings.json'
$results = [System.Collections.Generic.List[string]]::new()
function Assert($condition, $label) { if (!$condition) { throw "FAIL $label" }; $results.Add("PASS $label") }
function Prefs { Get-Content $config -Raw | ConvertFrom-Json }
function Root { for($i=0;$i -lt 60;$i++) { $h=(Get-Process GrabPic | Select-Object -First 1).MainWindowHandle; if($h -ne [IntPtr]::Zero) { return [System.Windows.Automation.AutomationElement]::FromHandle($h) }; Start-Sleep -Milliseconds 150 }; throw 'App window not ready.' }
function Invoke-Button([string]$name) {
 $condition = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::NameProperty),$name
 $button = (Root).FindFirst([System.Windows.Automation.TreeScope]::Descendants,$condition)
 if (!$button) { throw "Missing button: $name" }
 ([System.Windows.Automation.InvokePattern]$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
 Start-Sleep -Milliseconds 250
}
function Keys([byte[]]$keys) {
 foreach($key in $keys) { [ShortcutQA]::keybd_event($key,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 60 }
 Start-Sleep -Milliseconds 100
 for($i=$keys.Count-1; $i -ge 0; $i--) { [ShortcutQA]::keybd_event($keys[$i],0,2,[UIntPtr]::Zero) }
 Start-Sleep -Milliseconds 300
}
function Settings { Start-Process -FilePath $exe -ArgumentList 'settings' -Wait; for($attempt=0;$attempt -lt 40;$attempt++) { $condition=New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::NameProperty),'Set Grab area shortcut'; if((Root).FindFirst([System.Windows.Automation.TreeScope]::Descendants,$condition)) { return }; Start-Sleep -Milliseconds 150 }; throw 'Settings did not open.' }
function Latest { Get-ChildItem (Prefs).Folder -File -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }

try {
 Settings
 $before = (Latest).FullName
 Start-Process -FilePath $exe -ArgumentList 'full' -Wait
 for($i=0;$i -lt 50;$i++) { if((Latest).FullName -ne $before) { break }; Start-Sleep -Milliseconds 100 }
 Start-Sleep -Milliseconds 700
 $file = Latest
 Assert ($file.FullName -ne $before) 'Capture launched from visible settings saves successfully'
 Assert ((Get-Process GrabPic).MainWindowHandle -eq [IntPtr]::Zero) 'Capture does not reopen Grab Pic'
 Add-Type -AssemblyName System.Windows.Forms
 $clip=[System.Windows.Forms.Clipboard]::GetImage()
 Assert ($null -ne $clip) 'Capture copies image to clipboard in background'
 if($clip) { $clip.Dispose() }
 Start-Process -FilePath $exe -ArgumentList 'show' -Wait
 for($i=0;$i -lt 50;$i++) {
  $c=New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::NameProperty),$file.Name
  $item=(Root).FindFirst([System.Windows.Automation.TreeScope]::Descendants,$c)
  if($item) { break }; Start-Sleep -Milliseconds 100
 }
 Assert ($null -ne $item) 'Explicit Open Grab Pic shows latest filename'
 Start-Process -FilePath $exe -ArgumentList 'quit' -Wait
 Start-Process -FilePath $exe -ArgumentList 'background'
 Start-Sleep -Seconds 3
 Assert ((Get-Process GrabPic).MainWindowHandle -eq [IntPtr]::Zero) 'Restart stays in background'
 Start-Process -FilePath $exe -ArgumentList 'show' -Wait
 for($i=0;$i -lt 50;$i++) {
  $c=New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::NameProperty),$file.Name
  $item=(Root).FindFirst([System.Windows.Automation.TreeScope]::Descendants,$c)
  if($item) { break }; Start-Sleep -Milliseconds 100
 }
 Assert ($null -ne $item) 'Latest capture restores after restart'
 $results.Add('ALL BACKGROUND CAPTURE CHECKS PASSED')
} finally { $results | Set-Content "$PSScriptRoot/../artifacts/background-verification.txt"; $results }
