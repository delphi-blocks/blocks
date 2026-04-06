#define MyAppExe "Blocks.exe"
#define MyAppPath AddBackslash(SourcePath) + "..\\" + MyAppExe
#define MyAppVersion GetFileVersion(MyAppPath)

[Setup]
AppName=Blocks
AppVersion={#MyAppVersion}
DefaultDirName={localappdata}\Programs\Blocks
DefaultGroupName=Blocks
OutputBaseFilename=blocks-setup
Compression=lzma
SolidCompression=yes
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription=Blocks Installer
PrivilegesRequired=lowest

[Files]
; exe reale
Source: "..\Blocks.exe"; DestDir: "{app}"; Flags: ignoreversion

; launcher (alias)
Source: "..\launcher.exe"; DestDir: "{localappdata}\Microsoft\WindowsApps"; DestName: "blocks.exe"; Flags: ignoreversion

[Registry]
Root: HKCU; Subkey: "Software\Blocks"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"
Root: HKCU; Subkey: "Software\Blocks"; Flags: uninsdeletekeyifempty

[UninstallDelete]
; Rimuovi alias
Type: files; Name: "{localappdata}\Microsoft\WindowsApps\blocks.exe"