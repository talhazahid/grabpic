param([string]$SigningThumbprint, [switch]$SkipPublish)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot/Build-Icons.ps1"
if(!$SkipPublish) {
 dotnet publish "$root/src/GrabPic" -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o "$root/dist/GrabPic"
 if($LASTEXITCODE -ne 0) { throw 'App publishing failed.' }
}
dotnet restore "$root/packaging/BuildTools.csproj"
if($LASTEXITCODE -ne 0) { throw 'Windows packaging tools could not be restored.' }
[xml]$project=Get-Content "$root/packaging/BuildTools.csproj"
$sdkVersion=$project.Project.ItemGroup.PackageReference.Version
$nuget=if($env:NUGET_PACKAGES){$env:NUGET_PACKAGES}else{"$env:USERPROFILE/.nuget/packages"}
$sdk=Get-ChildItem "$nuget/microsoft.windows.sdk.buildtools/$sdkVersion/bin/*/x64/MakeAppx.exe" | Select-Object -First 1
if(!$sdk){throw 'MakeAppx.exe was not found.'}
$zig="$PSScriptRoot/.cache/zig/zig-x86_64-windows-0.15.2/zig.exe"
if(!(Test-Path $zig)) {
 New-Item -ItemType Directory -Force "$PSScriptRoot/.cache" | Out-Null
 $archive="$PSScriptRoot/.cache/zig.zip"
 Invoke-WebRequest 'https://ziglang.org/download/0.15.2/zig-x86_64-windows-0.15.2.zip' -OutFile $archive
 if((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne '3a0ed1e8799a2f8ce2a6e6290a9ff22e6906f8227865911fb7ddedc3cc14cb0c'){throw 'Compiler checksum mismatch.'}
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 [IO.Compression.ZipFile]::ExtractToDirectory($archive,"$PSScriptRoot/.cache/zig")
}
$native="$root/dist/StoreNative"; New-Item -ItemType Directory -Force $native | Out-Null
& $zig c++ "$root/packaging/ShellExtension.cpp" "$root/packaging/ShellExtension.def" -target x86_64-windows-gnu -shared -O2 -lole32 -luuid -lshell32 -o "$native/GrabPic.ShellExtension.dll"
if($LASTEXITCODE -ne 0){throw 'Desktop menu compilation failed.'}
& $zig c++ "$root/packaging/Startup.cpp" -target x86_64-windows-gnu -municode '-Wl,--subsystem,windows' -static -O2 -o "$native/GrabPic.Startup.exe"
if($LASTEXITCODE -ne 0){throw 'Startup launcher compilation failed.'}
[xml]$manifest=Get-Content "$root/packaging/AppxManifest.template.xml"
$version=$manifest.Package.Identity.Version
$stage="$root/dist/MSIX/stage-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force "$stage/Assets","$root/submission/packages" | Out-Null
Copy-Item "$root/dist/GrabPic/GrabPic.exe","$native/GrabPic.ShellExtension.dll","$native/GrabPic.Startup.exe" $stage
Copy-Item "$root/packaging/Assets/*" "$stage/Assets"
Copy-Item "$root/packaging/AppxManifest.template.xml" "$stage/AppxManifest.xml"
Copy-Item "$root/LICENSE" "$stage/LICENSE.txt"
Copy-Item "$root/packaging/SOURCE.txt" "$stage/SOURCE.txt"
Copy-Item "$root/packaging/Licenses" "$stage/Licenses" -Recurse
& $zig c++ "$root/packaging/VerifyShell.cpp" -target x86_64-windows-gnu -municode -static -O2 -lole32 -luuid -o "$native/VerifyShell.exe"
if($LASTEXITCODE -ne 0){throw 'Native verification compilation failed.'}
& "$native/VerifyShell.exe" "$stage/GrabPic.ShellExtension.dll"
if($LASTEXITCODE -ne 0){throw 'Native desktop command verification failed.'}
$output="$root/submission/packages/Grabpic-$version-x64.msix"
& $sdk.FullName pack /d $stage /p $output /o
if($LASTEXITCODE -ne 0){throw 'MSIX validation/packaging failed.'}
if($SigningThumbprint) {
 $sign=Join-Path $sdk.DirectoryName 'signtool.exe'
 & $sign sign /fd SHA256 /sha1 $SigningThumbprint /s My $output
 if($LASTEXITCODE -ne 0){throw 'Package signing failed.'}
}
Get-FileHash $output -Algorithm SHA256 | Format-List
Write-Output "Store package: $output"
