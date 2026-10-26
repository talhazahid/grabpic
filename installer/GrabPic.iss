#define AppVersion "0.5.0"

[Setup]
AppId={{B50DB06B-07A3-4540-99C6-4C52064B1E2D}
AppName=Grab Pic
AppVersion={#AppVersion}
AppPublisher=Grab Pic
DefaultDirName={autopf}\Grab Pic
DefaultGroupName=Grab Pic
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.22000
OutputDir=..\dist\Setup
OutputBaseFilename=GrabPic-Setup-{#AppVersion}-x64
SetupIconFile=..\src\GrabPic\Assets\GrabPic.ico
UninstallDisplayIcon={app}\GrabPic.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern dark
WizardSizePercent=110
WizardImageStretch=yes
CloseApplications=yes
CloseApplicationsFilter=GrabPic.exe
RestartApplications=no
ChangesAssociations=yes
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "..\dist\GrabPic\GrabPic.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "..\packaging\Licenses\*"; DestDir: "{app}\Licenses"; Flags: ignoreversion recursesubdirs
Source: "..\packaging\SOURCE.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Grab Pic"; Filename: "{app}\GrabPic.exe"; AppUserModelID: "GrabPic.Desktop"
Name: "{autodesktop}\Grab Pic"; Filename: "{app}\GrabPic.exe"; Tasks: desktopicon

[Registry]
; Remove the obsolete preview registrations. The menu is now installed for Windows itself.
Root: HKCU; Subkey: "Software\Classes\DesktopBackground\Shell\GrabPic"; Flags: deletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\GrabPic"; Flags: deletekey
Root: HKCU; Subkey: "Software\Classes\GrabPic.Commands"; Flags: deletekey
Root: HKLM; Subkey: "Software\GrabPic"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DesktopBackground\Shell\GrabPic"; ValueType: string; ValueName: "MUIVerb"; ValueData: "Grab Pic"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DesktopBackground\Shell\GrabPic"; ValueType: string; ValueName: "SubCommands"; ValueData: ""
Root: HKLM; Subkey: "Software\Classes\DesktopBackground\Shell\GrabPic"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\GrabPic.exe"",0"
Root: HKLM; Subkey: "Software\Classes\DesktopBackground\Shell\GrabPic\shell\01screen"; ValueType: string; ValueName: "MUIVerb"; ValueData: "Grab Full Screen"
Root: HKLM; Subkey: "Software\Classes\DesktopBackground\Shell\GrabPic\shell\01screen\command"; ValueType: string; ValueName: ""; ValueData: """{app}\GrabPic.exe"" full"
Root: HKLM; Subkey: "Software\Classes\DesktopBackground\Shell\GrabPic\shell\02area"; ValueType: string; ValueName: "MUIVerb"; ValueData: "Grab Area"
Root: HKLM; Subkey: "Software\Classes\DesktopBackground\Shell\GrabPic\shell\02area\command"; ValueType: string; ValueName: ""; ValueData: """{app}\GrabPic.exe"" area"
Root: HKLM; Subkey: "Software\Classes\DesktopBackground\Shell\GrabPic\shell\03folder"; ValueType: string; ValueName: "MUIVerb"; ValueData: "Open Captures"
Root: HKLM; Subkey: "Software\Classes\DesktopBackground\Shell\GrabPic\shell\03folder\command"; ValueType: string; ValueName: ""; ValueData: """{app}\GrabPic.exe"" folder"
Root: HKLM; Subkey: "Software\Classes\DesktopBackground\Shell\GrabPic\shell\04settings"; ValueType: string; ValueName: "MUIVerb"; ValueData: "Settings"
Root: HKLM; Subkey: "Software\Classes\DesktopBackground\Shell\GrabPic\shell\04settings\command"; ValueType: string; ValueName: ""; ValueData: """{app}\GrabPic.exe"" settings"
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "GrabPic"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "GrabPic"; ValueData: """{app}\GrabPic.exe"" background"

[Run]
Filename: "{app}\GrabPic.exe"; Parameters: "background"; Flags: nowait runasoriginaluser

[UninstallRun]
Filename: "{app}\GrabPic.exe"; Parameters: "quit"; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "QuitGrabPic"

[Code]
procedure InitializeWizard();
begin
  WizardForm.Font.Name := 'Segoe UI';
  WizardForm.Font.Size := 10;
  WizardForm.WelcomeLabel1.Font.Style := [];
  WizardForm.PageNameLabel.Font.Style := [];
  WizardForm.FinishedHeadingLabel.Font.Style := [];
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Code: Integer;
begin
  Result := '';
  if FileExists(ExpandConstant('{app}\GrabPic.exe')) then
  begin
    Exec(ExpandConstant('{app}\GrabPic.exe'), 'quit', '', SW_HIDE, ewWaitUntilTerminated, Code);
    Sleep(500);
  end;
end;
