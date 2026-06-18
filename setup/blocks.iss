; ============================================================
; Parametro di architettura passabile da riga di comando:
;   ISCC.exe /DPlatform=win64 blocks-setup.iss
;   ISCC.exe /DPlatform=win32 blocks-setup.iss
;   ISCC.exe blocks-setup.iss            (default: win32)
; ============================================================
#ifndef Platform
  #define Platform "win32"
#endif

#define PlatformLower Lowercase(Platform)

#if PlatformLower == "win64"
  #define Arch "Win64"
  #define ArchSuffix "x64"
#else
  #define Arch "Win32"
  #define ArchSuffix "x32"
#endif

#define MyAppExe "Blocks.exe"
#define MyAppPath AddBackslash(SourcePath) + Arch + "\\" + MyAppExe
#define MyAppVersion GetFileVersion(MyAppPath)

#define MyAppVerMajor
#define MyAppVerMinor
#define MyAppVerRev
#define MyAppVerBuild
#expr ParseVersion(MyAppPath, MyAppVerMajor, MyAppVerMinor, MyAppVerRev, MyAppVerBuild)
#define MyAppVersionShort Str(MyAppVerMajor) + "." + Str(MyAppVerMinor) + "." + Str(MyAppVerRev)

[Setup]
AppName=Blocks
AppVersion={#MyAppVersion}
DefaultDirName={localappdata}\Programs\Blocks
DefaultGroupName=Blocks
OutputBaseFilename=blocks-{#MyAppVersionShort}-setup-{#ArchSuffix}
Compression=lzma
SolidCompression=yes
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription=Blocks Installer
PrivilegesRequired=lowest

[Files]
; exe reale
Source: "{#Arch}\Blocks.exe"; DestDir: "{app}"; Flags: ignoreversion
; launcher (alias)
Source: "{#Arch}\launcher.exe"; DestDir: "{localappdata}\Microsoft\WindowsApps"; DestName: "blocks.exe"; Flags: ignoreversion

[Registry]
Root: HKCU; Subkey: "Software\Blocks"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"
Root: HKCU; Subkey: "Software\Blocks"; Flags: uninsdeletekeyifempty

[UninstallDelete]
; Rimuovi alias
Type: files; Name: "{localappdata}\Microsoft\WindowsApps\blocks.exe"
