#define AppVer GetEnv("APP_VERSION")
#if AppVer == ""
  #define AppVer "1.0.0"
#endif

[Setup]
AppId={{6C1E8A2B-3F4D-4E5A-9B7C-1D2E3F4A5B6C}
AppName=Balage Rádió
AppVersion={#AppVer}
AppPublisher=Balage Drone Services
DefaultDirName={autopf}\Balage Radio
DefaultGroupName=Balage Rádió
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\balage_radio.exe
OutputDir=..\dist
OutputBaseFilename=BalageRadio-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "hu"; MessagesFile: "compiler:Languages\Hungarian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Balage Rádió"; Filename: "{app}\balage_radio.exe"
Name: "{autodesktop}\Balage Rádió"; Filename: "{app}\balage_radio.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\balage_radio.exe"; Description: "{cm:LaunchProgram,Balage Rádió}"; Flags: nowait postinstall skipifsilent
