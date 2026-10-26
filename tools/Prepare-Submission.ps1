$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$output="$root/submission"
foreach($folder in @('listing','screenshots','packages','icons')){New-Item -ItemType Directory -Force "$output/$folder" | Out-Null}
Add-Type -AssemblyName System.Drawing
foreach($file in Get-ChildItem "$root/docs/images/0*.png") { $image=[System.Drawing.Image]::FromFile($file.FullName); try { if($image.Width -lt 1366 -or $image.Height -lt 768){throw "Store screenshot is too small: $($file.Name)"} } finally {$image.Dispose()} }
Copy-Item "$root/docs/images/0*.png" "$output/screenshots" -Force
Copy-Item "$root/src/GrabPic/Assets/GrabPic.svg" "$output/icons/Grabpic-master.svg" -Force
Copy-Item "$root/dist/Setup/GrabPic-Setup-0.5.1-x64.exe" "$output/packages" -Force
Copy-Item "$root/docs/STORE.md" "$output/START-HERE.md" -Force
Copy-Item "$root/docs/PRIVACY.md" "$output/listing/Privacy-policy.md" -Force
$listing=[ordered]@{
 name='Grabpic'; publisher='Owl Dev'; version='0.5.1'; license='GPL-3.0'; category='Productivity'; priceSuggestion='Free'; language='en-US'
 shortDescription='An easy, open-source screenshot app for Windows. Capture, copy, and keep things organized.'
 description='Grabpic makes screenshots simple. Capture your full screen or drag to select an area, copy the result to your clipboard, and save it automatically in neatly organized date folders. Customize your keyboard or mouse shortcuts, choose PNG or JPG, and keep capturing from the tray without opening the app each time. A dark interface and a remembered latest capture keep the experience straightforward. No account, uploads, ads, or analytics. Optional clipboard-image saving is off by default.'
 features=@('Full-screen and area capture','Current-monitor or all-monitor screenshots','Clipboard copying and automatic saving','Daily, weekly, or monthly folders','Custom keyboard and mouse shortcuts','PNG and JPG output with quality control','Dark interface and background tray operation','Latest-capture recovery after restart','Optional local clipboard-image saving','Open source under GPL-3.0')
 keywords=@('screenshot','screen capture','clipboard','productivity','open source','Windows')
 website='https://talhazahid.github.io/grabpic/'; support='https://github.com/talhazahid/grabpic/issues'; privacy='https://talhazahid.github.io/grabpic/privacy/'; store='https://apps.microsoft.com/detail/9PJ3HBXBCTX1'
 systemRequirements='Windows 11 (build 22000 or later), Intel/AMD x64.'
}
$listing | ConvertTo-Json -Depth 6 | Set-Content "$output/listing/Listing.json" -Encoding utf8
@($listing.name,'',$listing.shortDescription,'',$listing.description,'','Features:')+$listing.features+@('','Support: '+$listing.support,'Privacy: '+$listing.privacy) | Set-Content "$output/listing/Copy-and-paste.txt" -Encoding utf8
@'
Certification notes

Grabpic is a full-trust Windows desktop screenshot utility. It needs runFullTrust for desktop capture, global user-assigned shortcuts, the tray, and native desktop integration. Images and preferences stay local; there is no account, advertising, analytics, or screenshot upload service. Clipboard-image monitoring is optional and disabled by default. The app can run in the tray and start with Windows through its declared StartupTask. The packaged menu is implemented through IExplorerCommand and declared COM/package extensions, not elevated registry writes.

Test flow: open Grabpic, choose a capture folder, take Full Screen or Area, paste the clipboard image, and check the saved file. The main window stays hidden after capturing. Reopen it to see the latest capture. Settings includes configurable keyboard/mouse bindings, image format, quality, date grouping, and a link to Windows startup settings.

No sign-in or test account is needed.
'@ | Set-Content "$output/listing/Certification-notes.txt" -Encoding utf8
@'
01-capture.png: Capture a full screen or a selected area and find the latest saved image.
02-shortcuts.png: Choose keyboard combinations and mouse buttons that fit your workflow.
03-saving.png: Select your folder, date grouping, image format, and JPG quality.
04-background.png: Keep clipboard and capture behavior simple while the app runs in the tray.

Screenshots use the real app with an isolated profile and a generated sample image.
'@ | Set-Content "$output/listing/Screenshot-captions.txt" -Encoding utf8
$files=Get-ChildItem "$output/icons","$output/screenshots" -File -Recurse
Add-Type -AssemblyName System.Drawing
$assets=foreach($file in $files){if($file.Extension -eq '.png'){ $image=[System.Drawing.Image]::FromFile($file.FullName); try{[ordered]@{file=$file.FullName.Substring($output.Length+1).Replace('\','/');width=$image.Width;height=$image.Height;bytes=$file.Length}}finally{$image.Dispose()} }}
$assets | ConvertTo-Json -Depth 5 | Set-Content "$output/Asset-inventory.json" -Encoding utf8
Get-ChildItem "$output/packages" -File | Get-FileHash -Algorithm SHA256 | ForEach-Object {$_.Hash+'  '+[IO.Path]::GetFileName($_.Path)} | Set-Content "$output/SHA256SUMS.txt"
Compress-Archive -Path "$output/*" -DestinationPath "$root/dist/Grabpic-Submission-0.5.1.zip" -Force
Write-Output "Submission files: $output"
