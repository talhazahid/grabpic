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
 Keys @(0x1B)
 Settings
 Invoke-Button 'Restore default shortcuts'
 Invoke-Button 'Set Full screen shortcut'; Keys @(0x11,0x10,0x47)
 Assert ((Prefs).FullScreenShortcut.Code -eq 0x47 -and (Prefs).FullScreenShortcut.Modifiers -eq 6) 'Record and persist Ctrl + Shift + G'
 $before = (Latest).FullName
 Keys @(0x11,0x10,0x47); Start-Sleep -Seconds 2
 Assert ((Latest).FullName -ne $before) 'Custom global keyboard shortcut captures'
 Settings
 Invoke-Button 'Set Grab area shortcut'; Keys @(0x11,0x10,0x47)
 Assert ((Prefs).AreaShortcut.Code -eq 0x32) 'Reject shortcut assigned to another action'
 $reserved = [ShortcutQA]::RegisterHotKey([IntPtr]::Zero,890,0x4000,0x78)
 Assert $reserved 'Reserve F9 externally for conflict test'
 Invoke-Button 'Set Full screen shortcut'; Keys @(0x78)
 Assert ((Prefs).FullScreenShortcut.Code -eq 0x47) 'Reject external conflict and retain previous shortcut'
 [ShortcutQA]::UnregisterHotKey([IntPtr]::Zero,890) | Out-Null
 Invoke-Button 'Set Grab area shortcut'
 $dialog = $null
 for($attempt=0;$attempt -lt 30;$attempt++) {
  $dialog = (Root).FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.Name -like 'Set shortcut*Grab area' -and $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window } | Select-Object -First 1
  if($dialog) { break }; Start-Sleep -Milliseconds 100
 }
 if(!$dialog) { throw 'Recording dialog not found.' }
 $input = $dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.Name -like 'Listening for Grab area*' } | Select-Object -First 1
 $bounds = $input.Current.BoundingRectangle
 [ShortcutQA]::keybd_event(0x11,0,0,[UIntPtr]::Zero)
 [ShortcutQA]::SetCursorPos(([int]$bounds.Left+30),([int]$bounds.Top+8)) | Out-Null
 Start-Sleep -Milliseconds 150
 [ShortcutQA]::mouse_event(0x20,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 150; [ShortcutQA]::mouse_event(0x40,0,0,0,[UIntPtr]::Zero)
 [ShortcutQA]::keybd_event(0x11,0,2,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 400
 Assert ((Prefs).AreaShortcut.Device -eq 'Mouse' -and (Prefs).AreaShortcut.Code -eq 3 -and (Prefs).AreaShortcut.Modifiers -eq 2) 'Record and persist Ctrl + Middle click'
 [ShortcutQA]::PostMessage((Get-Process GrabPic).MainWindowHandle,0x10,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
 Start-Sleep -Milliseconds 300
 [ShortcutQA]::SetCursorPos(500,300) | Out-Null
 [ShortcutQA]::keybd_event(0x11,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 100
 [ShortcutQA]::mouse_event(0x20,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 100; [ShortcutQA]::mouse_event(0x40,0,0,0,[UIntPtr]::Zero)
 [ShortcutQA]::keybd_event(0x11,0,2,[UIntPtr]::Zero)
 Start-Sleep -Seconds 2
 $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
 $overlays = @($windows | Where-Object { $_.Current.ProcessId -eq (Get-Process GrabPic).Id -and $_.Current.BoundingRectangle.Width -gt 3000 })
 Assert ($overlays.Count -gt 0) 'Mouse shortcut launches region overlay globally'
 Keys @(0x1B)
 Settings
 Invoke-Button 'Set Open captures shortcut'; Keys @(0x77)
 Assert ((Prefs).OpenCapturesShortcut.Code -eq 0x77 -and (Prefs).OpenCapturesShortcut.Modifiers -eq 0) 'Record single-key F8 binding'
 Keys @(0x77); Start-Sleep -Milliseconds 700
 $shell = New-Object -ComObject Shell.Application
 $captureWindows = @($shell.Windows() | Where-Object { $_.Document.Folder.Self.Path -eq (Prefs).Folder })
 Assert ($captureWindows.Count -gt 0) 'Single-key shortcut opens capture folder'
 Settings
 Invoke-Button 'Set Full screen shortcut'; Keys @(0x1B)
 Assert ((Prefs).FullScreenShortcut.Code -eq 0x47) 'Escape cancels recording without changing shortcut'
 Invoke-Button 'Restore default shortcuts'
 Assert ((Prefs).FullScreenShortcut.Code -eq 0x31 -and (Prefs).AreaShortcut.Code -eq 0x32 -and (Prefs).OpenCapturesShortcut.Code -eq 0x33) 'Restore all three defaults'
 Assert ((Prefs).Quality -eq 100) 'Quality defaults/migrates to 100'
 $results.Add('ALL INTERACTIVE CHECKS PASSED')
} catch { $results.Add($_.ToString()); throw }
finally {
 [ShortcutQA]::UnregisterHotKey([IntPtr]::Zero,890) | Out-Null
 $results | Set-Content "$PSScriptRoot/../artifacts/shortcut-verification.txt"
 $results
}
