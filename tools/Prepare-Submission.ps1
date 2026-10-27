$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$output="$root/submission"
foreach($folder in @('listing','screenshots','packages','icons')){New-Item -ItemType Directory -Force "$output/$folder" | Out-Null}
Add-Type -AssemblyName System.Drawing
foreach($file in Get-ChildItem "$root/docs/images/0*.png") { $image=[System.Drawing.Image]::FromFile($file.FullName); try { if($image.Width -lt 1366 -or $image.Height -lt 768){throw "Store screenshot is too small: $($file.Name)"} } finally {$image.Dispose()} }
Copy-Item "$root/docs/images/0*.png" "$output/screenshots" -Force
Copy-Item "$root/src/GrabPic/Assets/GrabPic.svg" "$output/icons/Grabpic-master.svg" -Force
Copy-Item "$root/dist/Setup/GrabPic-Setup-0.6.0-x64.exe" "$output/packages" -Force
Copy-Item "$root/docs/STORE.md" "$output/START-HERE.md" -Force
New-Item -ItemType Directory -Force "$output/browser-extensions" | Out-Null
Copy-Item "$root/dist/Grabpic-Browser-*-0.6.0.zip","$root/docs/BROWSERS.md" "$output/browser-extensions" -Force
Copy-Item "$root/docs/PRIVACY.md" "$output/listing/Privacy-policy.md" -Force
Copy-Item "$root/docs/RELEASE-0.6.0.md" "$output/listing/Release-notes.md" -Force
$listing=[ordered]@{
 name='Grabpic'; publisher='Owl Dev'; version='0.6.0'; license='GPL-3.0'; category='Productivity'; priceSuggestion='Free'; language='en-US'
 shortDescription='An easy, open-source screenshot app for Windows. Capture, copy, and keep things organized.'
 description='Grabpic makes screenshots simple. Capture your full screen or drag to select an area, copy the result to your clipboard, and save it automatically in neatly organized date folders. Customize your keyboard or mouse shortcuts, choose PNG or JPG, and keep capturing from the tray without opening the app each time. With the separately enabled browser companion, right-click an ordinary webpage to capture its full scrolling page, visible view, or a selected screen area. Browser extensions require a separate setup and browser-store publication. A dark interface and a remembered latest capture keep the experience straightforward. No account, uploads, ads, or analytics. Optional clipboard-image saving is off by default.'
 features=@('Full-screen and area capture','Scrolling webpage and visible-view capture with the separately enabled companion extension for Edge, Chrome, and Firefox','Current-monitor or all-monitor screenshots','Clipboard copying and automatic saving','Daily, weekly, or monthly folders','Custom keyboard and mouse shortcuts','PNG and JPG output with quality control','Dark interface and background tray operation','Latest-capture recovery after restart','Optional local clipboard-image saving','Open source under GPL-3.0')
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

Browser capture is optional and requires enabling the separate companion extension; test ZIPs and instructions are in browser-extensions. Full page scrolls/stitches the top-level page; Visible view captures the viewport; Area invokes the native selector. The unvirtualizedResources capability is required for narrowly scoped native-host registry registrations to be visible to browsers and for the local BrowserBridge/BrowserInbox folders to be shared between the browser-launched host and packaged app. All capture data stays local. Review docs/STORE.md and docs/BROWSERS.md for limits and the separate browser-store publication requirement.
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
$currentPackages=Get-ChildItem "$output/packages" -File | Where-Object {$_.Name -match '0\.6\.0'}
$currentPackages | Get-FileHash -Algorithm SHA256 | ForEach-Object {$_.Hash+'  '+[IO.Path]::GetFileName($_.Path)} | Set-Content "$output/SHA256SUMS.txt"
$bundle="$root/dist/Submission-0.6.0-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force "$bundle/packages" | Out-Null
Get-ChildItem $output | Where-Object {$_.Name -ne 'packages'} | Copy-Item -Destination $bundle -Recurse
$currentPackages | Copy-Item -Destination "$bundle/packages"
Compress-Archive -Path "$bundle/*" -DestinationPath "$root/dist/Grabpic-Submission-0.6.0.zip" -Force
Write-Output "Submission files: $output"
