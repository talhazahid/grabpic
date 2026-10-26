$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$compiler = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 7\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe"
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (!$compiler) { throw 'Install Inno Setup 6 or 7 before building the setup.' }
& "$PSScriptRoot/Build-Icons.ps1"
dotnet publish "$root/src/GrabPic" -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o "$root/dist/GrabPic"
if ($LASTEXITCODE -ne 0) { throw 'Publishing failed.' }
& $compiler "$root/installer/GrabPic.iss"
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
