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
 foreach($keys in @(@(0x10,0x5B,0x53),@(0x5B,0x10,0x53),@(0x5C,0x10,0x53))) {
  Invoke-Button 'Set Grab area shortcut'; Keys $keys
  Assert ((Prefs).AreaShortcut.Code -eq 0x53 -and (Prefs).AreaShortcut.Modifiers -eq 12) ('Record Win+Shift+S order: '+($keys -join ','))
 }
 Keys @(0x5B,0x10,0x53); Start-Sleep -Milliseconds 700
 $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
 Assert (@($windows | Where-Object { $_.Current.ProcessId -eq (Get-Process GrabPic).Id -and $_.Current.BoundingRectangle.Width -gt 3000 }).Count -eq 1) 'Win+Shift+S opens one Grab Pic selection overlay'
 Keys @(0x1B)
 Settings
 Invoke-Button 'Set Grab area shortcut'; Keys @(0x12,0x10,0x47)
 Assert ((Prefs).AreaShortcut.Code -eq 0x47 -and (Prefs).AreaShortcut.Modifiers -eq 5) 'Alt+Shift combination saves correctly'
 Invoke-Button 'Set Grab area shortcut'; Keys @(0xA3,0xA1,0x47)
 Assert ((Prefs).AreaShortcut.Code -eq 0x47 -and (Prefs).AreaShortcut.Modifiers -eq 6) 'Right Ctrl and Right Shift normalize correctly'
 Invoke-Button 'Set Grab area shortcut'; Keys @(0x5B,0x10,0x53)
 Assert ((Prefs).AreaShortcut.Code -eq 0x53 -and (Prefs).AreaShortcut.Modifiers -eq 12) 'Requested Win+Shift+S binding left saved'
 Start-Process -FilePath $exe -ArgumentList 'quit' -Wait
 Start-Process -FilePath $exe -ArgumentList 'background'
 Start-Sleep -Seconds 3
 Assert ((Prefs).AreaShortcut.Code -eq 0x53 -and (Prefs).AreaShortcut.Modifiers -eq 12) 'Windows binding persists through restart'
 Keys @(0x5B,0x10,0x53); Start-Sleep -Milliseconds 700
 $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
 Assert (@($windows | Where-Object { $_.Current.ProcessId -eq (Get-Process GrabPic).Id -and $_.Current.BoundingRectangle.Width -gt 3000 }).Count -eq 1) 'Windows binding works after background restart'
 Keys @(0x1B)
 $results.Add('ALL WINDOWS SHORTCUT CHECKS PASSED')
} finally { $results | Set-Content "$PSScriptRoot/../artifacts/windows-shortcut-verification.txt"; $results }
