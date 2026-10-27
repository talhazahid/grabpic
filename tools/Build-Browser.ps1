$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$publicKey='MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAo+PRwyW0oMZ5LOGR4dK2xW2KYfqTk0CtyL+z9IWHA90z/faIWcxeI+/h0Q94GjLLpOICxXvU70v7NcK6gTygU9ARJ+G7bfrvesOgkD3t16ADiVsNbQlJBfVeeGtAHgyAvK4RNuox9OryRswrrBcBqpbAnCa45G2BuAmpMDRjBbdbKT8qiv6T63a8qMLf2mcTNvAzzaUxdO2aBX+1s/IObwmg92gXrHnGJBWZu9r3GT0w0DFqEFzCRAaewc3ZN1lscVv7sfFab7Xb1dudbQX0FUU7QY0dvW1VaH/DaGjkROAljHXkp3a1kNk0fN8btsfb1lseu+eynocA5mK4rjhMHQIDAQAB'
foreach($browser in @('chromium','firefox')) {
 $folder="$root/dist/Browser/$browser"; New-Item -ItemType Directory -Force $folder | Out-Null
 Copy-Item "$root/browser-extension/shared/*" $folder -Force
 Copy-Item "$root/src/GrabPic/Assets/GrabPic-128.png" "$folder/icon.png" -Force
 $manifest=[ordered]@{manifest_version=3;name='Grabpic';version='0.6.0';description='Full scrolling-page, visible-view, and area screenshots saved locally with Grabpic.';permissions=@('activeTab','contextMenus','scripting','nativeMessaging');icons=@{'128'='icon.png'} }
 if($browser -eq 'chromium') { $manifest.key=$publicKey; $manifest.background=@{service_worker='background.js'} }
 else { $manifest.background=@{scripts=@('background.js')};$manifest.browser_specific_settings=@{gecko=@{id='grabpic@owl.dev';strict_min_version='126.0';data_collection_permissions=@{required=@('none')}}} }
 $manifest | ConvertTo-Json -Depth 8 | Set-Content "$folder/manifest.json" -Encoding utf8
 Compress-Archive -Path "$folder/*" -DestinationPath "$root/dist/Grabpic-Browser-$browser-0.6.0.zip" -Force
}
dotnet publish "$root/src/GrabPic.BrowserHost" -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o "$root/dist/BrowserHost"
if($LASTEXITCODE -ne 0){throw 'Browser bridge publishing failed.'}
Copy-Item "$root/dist/BrowserHost/GrabPic.BrowserHost.exe" "$root/dist/GrabPic/GrabPic.BrowserHost.exe" -Force
