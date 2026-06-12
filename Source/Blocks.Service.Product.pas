{******************************************************************************}
{                                                                              }
{  DelphiBlock Installer                                                       }
{                                                                              }
{  Copyright (c) Luca Minuti <code@lucaminuti.it>                              }
{  All rights reserved.                                                        }
{                                                                              }
{  https://github.com/delphi-blocks/blocks                                     }
{                                                                              }
{  Licensed under the Apache-2.0 license                                       }
{                                                                              }
{******************************************************************************}
unit Blocks.Service.Product;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  Blocks.Model.Package,
  Blocks.Model.Database,
  Blocks.Model.Manifest,
  Blocks.Service.Script;

type
  TPlatformPaths = record
    ReleaseDCUPath: TArray<string>;
    SourcePath: TArray<string>;
    DebugDCUPath: TArray<string>;
  end;

  TProductPlatform = class
  private
    FName: string;
    FActive: Boolean;
    FSearchPath: string;
    FHPPOutputDirectory: string;
    FPackageDCPOutput: string;
    FPackageDPLOutput: string;
    FPackageSearchPath: string;
  public
    constructor Create(const AName: string);
    property Name: string read FName;
    property Active: Boolean read FActive write FActive;
    property SearchPath: string read FSearchPath write FSearchPath;
    property HPPOutputDirectory: string read FHPPOutputDirectory write FHPPOutputDirectory;
    property PackageDCPOutput: string read FPackageDCPOutput write FPackageDCPOutput;
    property PackageDPLOutput: string read FPackageDPLOutput write FPackageDPLOutput;
    property PackageSearchPath: string read FPackageSearchPath write FPackageSearchPath;
  end;

  /// <summary>Represents a single Delphi/RAD Studio installation.</summary>
  TProduct = class(TNoRefCountObject, IScriptHelper)
  private
    FBdsVersion: string;
    FVersionName: string;
    FDisplayName: string;
    FRootDir: string;
    FRegistryKey: string;
    FPackageVersion: string;
    FPlatforms: TObjectDictionary<string, TProductPlatform>;

    class var
      FProducts: TObjectList<TProduct>;

    function GetRank: Integer;
    function ExpandEnvironment(const AValue: string): string;
    function GetKnownPackageRegKey(const APlatform: string): string;
    function GetBPLFileName(const AWorkspaceDir: string; APackage: TPackageProject; const APlatform: string): string;
    function GetPlatforms: TDictionary<string, TProductPlatform>;
    procedure LoadPlatforms;

    class procedure LoadProducts;
    class function GetProductNames: TArray<string>; static;
    function GetPackageOutput(
        const AWorkspaceDir: string;
        APackage: TPackageProject;
        const APlatform, AConfig, AOutputType: string
    ): string;

    /// <summary>Locates MSBuild, sets the Delphi build environment variables, and
    ///   compiles a single project (<c>.dproj</c>) for one config/platform.</summary>
    /// <param name="AProjectFileName">Full path to the <c>.dproj</c> to build.</param>
    /// <param name="AConfig">Build configuration (e.g. <c>Debug</c> or <c>Release</c>).</param>
    /// <param name="APlatform">Target platform (e.g. <c>Win32</c>).</param>
    /// <param name="AOptions">DCC_* output/search-path overrides for this compilation.</param>
    /// <returns>The captured MSBuild stdout/stderr on success.</returns>
    /// <exception cref="Exception">Raised when MSBuild returns a non-zero exit code;
    ///   the error lines are printed to the console before the exception is raised.</exception>
    function CompileProject(const AWorkspaceDir, AManifestName, AProjectFileName, AConfig, APlatform: string): string;

  public
    constructor Create(const ABdsVersion, AVersionName, ADisplayName, ARootDir, ARegistryKey: string);
    destructor Destroy; override;
    class constructor Create;
    class destructor Destroy;

    /// <summary>Finds an installed product by version name and optional registry key.</summary>
    /// <param name="AVersionName">Internal version name (e.g. <c>delphi12</c>), matched case-insensitively.</param>
    /// <param name="ARegistryKey">Registry profile key (e.g. <c>BDS</c> or a custom key). Defaults to <c>BDS</c>.</param>
    /// <returns>The matching <see cref="TProduct"/> instance from <see cref="Products"/>.</returns>
    /// <exception cref="Exception">Raised when no installed product matches.</exception>
    class function Find(const AVersionName: string; const ARegistryKey: string = 'BDS'): TProduct;

    /// <summary>Selects an installed product interactively.</summary>
    /// <returns>The selected <see cref="TProduct"/>. Returns the newest product (index 0)
    ///   when the user presses ENTER without entering a number.</returns>
    /// <exception cref="Exception">Raised when no Delphi version is installed.</exception>
    class function Choose: TProduct;

    /// <summary>Checks whether this Delphi IDE instance is currently running.</summary>
    /// <returns><c>True</c> if a <c>bds.exe</c> process whose full image path matches
    ///   <c>RootDir\bin\bds.exe</c> is found in the process list.</returns>
    function IsRunning: Boolean;

    /// <summary>Checks whether the command-line compiler for a platform is
    ///   physically installed (its <c>dcc*.exe</c> exists under <c>RootDir\bin</c>).</summary>
    /// <param name="APlatform">Platform identifier, e.g. <c>Win32</c>, <c>Win64</c>, <c>Win64x</c>.</param>
    /// <returns><c>True</c> when the matching compiler executable exists; <c>False</c>
    ///   for an unmapped platform or a missing executable.</returns>
    /// <remarks>
    ///   Unlike <see cref="TProductPlatform.Active"/>, which reflects only what the
    ///   registry advertises, this verifies the toolchain is actually present on disk.
    /// </remarks>
    function HasCompiler(const APlatform: string): Boolean;

    /// <summary>Resolves the best matching package folder key for this Delphi version.</summary>
    /// <param name="APackageFolders">Dictionary mapping version-name keys (optionally suffixed
    ///   with <c>+</c>) to folder name values, as declared in the package manifest.</param>
    /// <returns>The folder name string for the greatest-lower-bound key.</returns>
    /// <exception cref="Exception">Raised when no compatible key is found
    ///   (installed version is older than all keys in the manifest).</exception>
    function GetPackageFolder(APackageFolders: TDictionary<string, string>): string;

    /// <summary>Resolves the directory that contains the <c>.dproj</c> files for this product.</summary>
    /// <param name="AProjectDir">Root directory of the extracted project.</param>
    /// <param name="AManifest">The package manifest providing the package options.</param>
    /// <returns><c>AProjectDir\&lt;rootFolder&gt;\&lt;versionFolder&gt;</c>, where <c>rootFolder</c>
    ///   defaults to <c>packages</c> and the version-specific folder is appended only when the
    ///   manifest declares one (an entry of <c>.</c> or an empty <c>folders</c> map means the
    ///   <c>.dproj</c> files live directly under the root folder).</returns>
    function GetPackagesPath(const AProjectDir: string; AManifest: TManifest): string;

    /// <summary>Expands the <c>%PACKAGE_VERSION%</c> placeholder in a manifest
    ///   package name to this product's package-version suffix (e.g. <c>370</c>
    ///   for <c>delphi13</c>), so a single manifest can target packages whose
    ///   <c>.dproj</c> name embeds that suffix. Case-insensitive; names without
    ///   the placeholder are returned unchanged.</summary>
    function ExpandPackageName(const AName: string): string;

    /// <summary>Compiles all declared packages and updates the Delphi library registry paths.</summary>
    /// <param name="AProjectDir">Root directory of the extracted project.</param>
    /// <param name="APackages">Package descriptors from the manifest, one per <c>.dproj</c> file.</param>
    /// <param name="APlatforms">Target platform configurations from the manifest.</param>
    /// <exception cref="Exception">Raised when a platform is not installed or a package fails to compile.</exception>
    procedure BuildPackages(const AWorkspaceDir, AProjectDir: string; const AManifest: TManifest);

    /// <summary>Delete package (bpl and dcp).</summary>
    procedure RemovePackage(
        const AWorkspaceDir: string;
        APackage: TPackageProject;
        const APlatformPair: TPair<string, TManifestPlatform>
    );

    /// <summary>Appends source, browsing, and debug DCU paths to the Delphi library registry.</summary>
    /// <param name="APlatform">Target platform identifier, e.g. <c>Win32</c>.</param>
    /// <param name="AProjectDir">Project root; relative paths are resolved against this directory.</param>
    /// <param name="APlatformPaths">Resolved path lists (source, release DCU, debug DCU) to register.</param>
    /// <remarks>
    ///   Already-present entries are skipped. Writes to
    ///   <c>HKCU\Software\Embarcadero\BDS\&lt;BdsVersion&gt;\Library\&lt;Platform&gt;</c>.
    /// </remarks>
    procedure UpdateSearchPaths(const APlatform, AProjectDir: string; APlatformPaths: TPlatformPaths);

    /// <summary>Delete source, browsing, and debug DCU paths from the Delphi library registry.</summary>
    procedure DeleteSearchPaths(const APlatform, AProjectDir: string; APlatformPaths: TPlatformPaths);

    /// <summary>Ensures the blocks DCP output directory (<c>{AWorkspaceDir}\.blocks\{Platform}\dcp</c>)
    ///   is the first entry of the Library <c>Search Path</c> for every supported platform.</summary>
    /// <remarks>
    ///   Idempotent: a platform already containing the path is left unchanged. Writes to
    ///   <c>HKCU\Software\Embarcadero\{RegKey}\{BdsVersion}\Library\{Platform}</c> for each platform in
    ///   <c>DCPPlatforms</c>; platforms whose registry key is absent are skipped.
    /// </remarks>
    procedure CheckDCPPath(const AWorkspaceDir: string);

    /// <summary>Ensures the blocks BPL output directory (<c>{AWorkspaceDir}\.blocks\{Platform}\bpl</c>)
    ///   is present in the PATH of the IDE environment variables for every supported platform.</summary>
    /// <remarks>
    ///   Idempotent: a platform whose PATH already contains the directory is left unchanged. Writes to
    ///   <c>HKCU\Software\Embarcadero\{RegKey}\{BdsVersion}\Environment Variables</c> (Win32) and
    ///   <c>...\Environment Variables x64</c> (Win64), creating the key if absent and initialising a
    ///   missing PATH as <c>$(PATH);...</c> so the inherited PATH is preserved. Unlike
    ///   <see cref="CheckDCPPath"/> this always runs; there is no configuration flag.
    /// </remarks>
    procedure CheckEnvironment(const AWorkspaceDir: string);

    /// <summary>Register package inside the Delphi IDE.</summary>
    procedure InstallPackage(
        APackage: TManifestPackage;
        const AWorkspaceDir, ADprojPath: string;
        APlatformPair: TPair<string, TManifestPlatform>
    );

    /// <summary>Registers an IDE expert <c>.dll</c> in the registry so the IDE loads it on
    ///   start. Implements <see cref="IScriptHelper.RegisterExpert"/>.</summary>
    /// <remarks>
    ///   Writes a value named <paramref name="AName"/> (= the full <paramref name="AExpertPath"/>) under
    ///   <c>HKCU\Software\Embarcadero\{RegKey}\{BdsVersion}\Experts</c> (Win32) or
    ///   <c>...\Experts x64</c> (Win64). Other platforms are skipped with a warning.
    /// </remarks>
    procedure RegisterExpert(const AExpertPath, AName, APlatform: string);

    /// <summary>Removes from the IDE Experts registry every expert this workspace installed
    ///   for <paramref name="AManifestName"/>.</summary>
    /// <remarks>
    ///   Scans <c>HKCU\Software\Embarcadero\{RegKey}\{BdsVersion}\Experts</c> and
    ///   <c>...\Experts x64</c>, deleting any value whose path starts with
    ///   <c>{AWorkspaceDir}\.blocks\lib\{AManifestName}\</c> — matched both as the absolute
    ///   path written at install and as the <c>$(BLOCKSDIR)\lib\{AManifestName}\</c> macro form.
    /// </remarks>
    procedure UnregisterExperts(const AWorkspaceDir, AManifestName: string);

    /// <summary>Unregister package from the Delphi IDE.</summary>
    procedure UninstallPackage(
        APackage: TManifestPackage;
        const AWorkspaceDir, ADprojPath: string;
        APlatformPair: TPair<string, TManifestPlatform>
    );

    /// <summary>Populates a Name=Value list with the Delphi environment variables
    ///   needed to expand <c>$(...)</c> macros in <c>.dproj</c> paths.</summary>
    /// <remarks>
    ///   Sets <c>BDS</c> (install root) and <c>BDSBIN</c> (bin directory) from
    ///   <c>HKLM\SOFTWARE\WOW6432Node\Embarcadero\BDS\&lt;BdsVersion&gt;</c>,
    ///   <c>ProductVersion</c> from <see cref="BdsVersion"/>, and every value
    ///   under <c>HKCU\Software\Embarcadero\&lt;RegistryKey&gt;\&lt;BdsVersion&gt;\Environment Variables</c>.
    ///   Existing entries in <c>AEnvironmentVariable</c> are overwritten by name.
    /// </remarks>
    procedure FillEnvironmentVariables(AEnvironmentVariable: TStrings);

    /// <summary>All installed Delphi/RAD Studio products, sorted newest-first.</summary>
    class property Products: TObjectList<TProduct> read FProducts;
    /// <summary>All installed Delphi/RAD Studio products by name.</summary>
    class property ProductNames: TArray<string> read GetProductNames;

    /// <summary>Internal BDS registry key version string (e.g. <c>23.0</c> for Delphi 12 Athens).</summary>
    property BdsVersion: string read FBdsVersion;
    /// <summary>Internal version name used in file paths and registry lookups (e.g. <c>delphi12</c>).</summary>
    property VersionName: string read FVersionName;
    /// <summary>Package-version suffix for this IDE (e.g. <c>370</c> for <c>delphi13</c>), the value
    ///   that replaces the <c>%PACKAGE_VERSION%</c> placeholder.</summary>
    property PackageVersionSuffix: string read FPackageVersion;
    /// <summary>Human-readable IDE display name (e.g. <c>Delphi 12 Athens</c>).</summary>
    property DisplayName: string read FDisplayName;
    /// <summary>Root installation directory of the IDE (e.g. <c>C:\Program Files (x86)\Embarcadero\Studio\23.0</c>).</summary>
    property RootDir: string read FRootDir;
    /// <summary>Registry key name under <c>HKCU\Software\Embarcadero</c> for this IDE profile (e.g. <c>BDS</c>).</summary>
    property RegistryKey: string read FRegistryKey;
    /// <summary>Platform configurations read from <c>HKCU\Software\Embarcadero\{RegKey}\{BdsVersion}\Library</c>, keyed by platform name.</summary>
    property Platforms: TDictionary<string, TProductPlatform> read GetPlatforms;
  end;

implementation

uses
  System.Win.Registry,
  Winapi.Windows,
  Winapi.TlHelp32,
  Blocks.Core,
  Blocks.Console,
  Blocks.Http;

const
  // Platforms for which blocks emits DCP output and registers it on the IDE
  // library path. Limited to Windows for now; DCU/DCP usage on other platforms
  // is unverified.
  DCPPlatforms: array[0..1] of string = ('Win32', 'Win64');

// -- WinAPI declarations missing from older Delphi headers --------------------

const
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

function QueryFullProcessImageNameW(
    hProcess: THandle;
    dwFlags: DWORD;
    lpExeName: PWideChar;
    var lpdwSize: DWORD
): BOOL; stdcall; external 'kernel32.dll' name 'QueryFullProcessImageNameW';

function NtQueryInformationProcess(
    ProcessHandle: THandle;
    ProcessInformationClass: ULONG;
    ProcessInformation: Pointer;
    ProcessInformationLength: ULONG;
    ReturnLength: PULONG
): LongInt; stdcall; external 'ntdll.dll' name 'NtQueryInformationProcess';

type
  // Mirror of the NT UNICODE_STRING. Not packed: natural alignment matches the
  // C ABI on both Win32 (8 bytes) and Win64 (16 bytes, 4-byte padding before Buffer).
  PNtUnicodeString = ^TNtUnicodeString;
  TNtUnicodeString = record
    Length: Word;
    MaximumLength: Word;
    Buffer: PWideChar;
  end;

// -- MSBuild location ----------------------------------------------------------

function GetMsBuildPath: string;
begin
  // 1. Already on PATH
  for var Candidate in GetEnvironmentVariable('PATH').Split([';']) do
  begin
    var Exe := IncludeTrailingPathDelimiter(Candidate) + 'MSBuild.exe';
    if TFile.Exists(Exe) then
      Exit(Exe);
  end;

  // 2. .NET Framework standard locations (used by Delphi build scripts)
  for var Candidate
      in [
          GetEnvironmentVariable('SystemRoot') + '\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe',
          GetEnvironmentVariable('SystemRoot') + '\Microsoft.NET\Framework\v3.5\MSBuild.exe'] do
    if TFile.Exists(Candidate) then
      Exit(Candidate);

  // 3. MSBuild registry ToolsVersions
  var Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('SOFTWARE\Microsoft\MSBuild\ToolsVersions\4.0') then
    begin
      var ToolsPath := Reg.ReadString('MSBuildToolsPath');
      Reg.CloseKey;
      if ToolsPath <> '' then
      begin
        var Candidate := IncludeTrailingPathDelimiter(ToolsPath) + 'MSBuild.exe';
        if TFile.Exists(Candidate) then
          Exit(Candidate);
      end;
    end;
  finally
    Reg.Free;
  end;

  raise Exception.Create('MSBuild not found. Please install .NET Framework SDK or Visual Studio Build Tools.');
end;

// -- Compiler location ---------------------------------------------------------

// Maps a platform identifier to its command-line compiler executable. All Delphi
// compilers live under <RootDir>\bin. Returns '' for platforms we do not map.
function GetCompilerExe(const APlatform: string): string;
begin
  if SameText(APlatform, 'Win32') then
    Result := 'dcc32.exe'
  else if SameText(APlatform, 'Win64') then
    Result := 'dcc64.exe'
  else if SameText(APlatform, 'Win64x') then
    Result := 'dcc64x.exe' // Win64 Modern (LLVM), Delphi 12+
  else if SameText(APlatform, 'OSX64') then
    Result := 'dccosx64.exe'
  else if SameText(APlatform, 'OSXARM64') then
    Result := 'dccosxarm64.exe'
  else if SameText(APlatform, 'Linux64') then
    Result := 'dcclinux64.exe'
  else if SameText(APlatform, 'Android') then
    Result := 'dccaarm.exe'
  else if SameText(APlatform, 'Android64') then
    Result := 'dccaarm64.exe'
  else if SameText(APlatform, 'iOSDevice64') then
    Result := 'dcciosarm64.exe'
  else
    Result := '';
end;

// -- Process execution with output capture -------------------------------------

function RunProcessWithOutput(const CmdLine: string; out Output: string): Integer;
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  hRead, hWrite: THandle;
  Buffer: array[0..4095] of Byte;
  BytesRead: DWORD;
  ExitCode: DWORD;
  MS: TMemoryStream;
  Bytes: TBytes;
begin
  Output := '';

  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;

  if not CreatePipe(hRead, hWrite, @SA, 0) then
    RaiseLastOSError;
  SetHandleInformation(hRead, HANDLE_FLAG_INHERIT, 0);

  ZeroMemory(@SI, SizeOf(SI));
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESTDHANDLES;
  SI.hStdOutput := hWrite;
  SI.hStdError := hWrite;
  SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);

  ZeroMemory(@PI, SizeOf(PI));

  if not CreateProcess(nil, PChar(CmdLine), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
  begin
    CloseHandle(hRead);
    CloseHandle(hWrite);
    RaiseLastOSError;
  end;

  CloseHandle(hWrite);

  MS := TMemoryStream.Create;
  try
    while ReadFile(hRead, Buffer[0], SizeOf(Buffer), BytesRead, nil) and (BytesRead > 0) do
      MS.Write(Buffer[0], BytesRead);

    SetLength(Bytes, MS.Size);
    if MS.Size > 0 then
    begin
      MS.Position := 0;
      MS.Read(Bytes[0], MS.Size);
    end;
    Output := TEncoding.Default.GetString(Bytes);
  finally
    MS.Free;
  end;

  WaitForSingleObject(PI.hProcess, INFINITE);
  GetExitCodeProcess(PI.hProcess, ExitCode);
  Result := Integer(ExitCode);

  CloseHandle(PI.hProcess);
  CloseHandle(PI.hThread);
  CloseHandle(hRead);
end;

// Runs the manifest scripts registered for a compile event (beforeCompile /
// afterCompile) for a single package, build config and platform. The per-config
// output paths are exposed through %DCU_PATH% / %BPL_PATH% / %DCP_PATH%, mirroring
// the layout produced by TProduct.BuildPackages, plus %PACKAGE% / %PLATFORM% /
// %CONFIG% for the current compilation.
procedure RunCompileScripts(
    const AManifest: TManifest;
    const AEvent, AWorkspaceDir, AProjectDir, APlatform, AConfig, APackage: string;
    const AHelper: IScriptHelper
);
begin
  var LBlocksDir := TPath.Combine(AWorkspaceDir, '.blocks');
  // Build configs flow in lowercase ('debug'/'release'); expose them capitalised
  // (Delphi's canonical config names) while keeping the lowercase 'debug' suffix.
  var LSuffix :=
      if SameText(AConfig, 'Debug') then 'debug'
      else '';
  var LConfigName :=
      if SameText(AConfig, 'Debug') then 'Debug'
      else 'Release';

  var LEnv := TStringList.Create;
  try
    LEnv.Values['CONFIG'] := LConfigName;
    LEnv.Values['PLATFORM'] := APlatform;
    LEnv.Values['PACKAGE'] := APackage;
    LEnv.Values['WORKSPACE_PATH'] := AWorkspaceDir;
    LEnv.Values['PROJECT_PATH'] := AProjectDir;
    LEnv.Values['BPL_PATH'] := TPath.Combine(LBlocksDir, APlatform, 'bpl', LSuffix);
    LEnv.Values['DCP_PATH'] := TPath.Combine(LBlocksDir, APlatform, 'dcp', LSuffix);
    // DCUs live under <workspace>\.blocks\lib\<manifest name>\<Platform>[\debug].
    var LDcuPath := TPath.Combine([LBlocksDir, 'lib', AManifest.Name, APlatform]);
    if LSuffix <> '' then
      LDcuPath := TPath.Combine(LDcuPath, LSuffix);
    LEnv.Values['DCU_PATH'] := LDcuPath;

    TScriptRunner.RunEvent(AManifest, AEvent, LEnv, AHelper);
  finally
    LEnv.Free;
  end;
end;

// -- TProductPlatform ----------------------------------------------------------

constructor TProductPlatform.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

// -- TProduct ------------------------------------------------------------------

constructor TProduct.Create(const ABdsVersion, AVersionName, ADisplayName, ARootDir, ARegistryKey: string);
begin
  inherited Create;
  FBdsVersion := ABdsVersion;
  FVersionName := AVersionName;
  FDisplayName := ADisplayName;
  FRootDir := ARootDir;
  FRegistryKey := ARegistryKey;
  if not PackageVersion.TryGetValue(FVersionName, FPackageVersion) then
    FPackageVersion := StringReplace(FBdsVersion, '.', '', [rfReplaceAll]);
end;

destructor TProduct.Destroy;
begin
  FPlatforms.Free;
  inherited;
end;

procedure TProduct.LoadPlatforms;
var
  LReg: TRegistry;
  LPlatformKeys: TStringList;
  LActiveSDKs: TDictionary<string, Boolean>;
begin
  FPlatforms := TObjectDictionary<string, TProductPlatform>.Create([doOwnsValues]);

  LReg := TRegistry.Create(KEY_READ);
  try
    LPlatformKeys := TStringList.Create;
    try
      LActiveSDKs := TDictionary<string, Boolean>.Create;
      try
        LReg.RootKey := HKEY_CURRENT_USER;

        var LSdkPath := 'Software\Embarcadero\' + FRegistryKey + '\' + FBdsVersion + '\PlatformSDKs';
        if LReg.OpenKeyReadOnly(LSdkPath) then
        begin
          var LValueNames := TStringList.Create;
          try
            LReg.GetValueNames(LValueNames);
            for var LValueName in LValueNames do
              LActiveSDKs.AddOrSetValue(LValueName.ToLower, True);
          finally
            LValueNames.Free;
          end;
          LReg.CloseKey;
        end;

        var LLibPath := 'Software\Embarcadero\' + FRegistryKey + '\' + FBdsVersion + '\Library';
        if not LReg.OpenKeyReadOnly(LLibPath) then
          Exit;
        LReg.GetKeyNames(LPlatformKeys);
        LReg.CloseKey;

        for var LPlatformName in LPlatformKeys do
        begin
          if not LReg.OpenKeyReadOnly(LLibPath + '\' + LPlatformName) then
            Continue;
          try
            var LPlatform := TProductPlatform.Create(LPlatformName);
            // Hand ownership to FPlatforms immediately so a later raise cannot leak it.
            FPlatforms.Add(LPlatformName, LPlatform);

            if SameText(LPlatformName, 'Win32') or SameText(LPlatformName, 'Win64') then
              LPlatform.Active := True
            else
              LPlatform.Active := LActiveSDKs.ContainsKey(('Default_' + LPlatformName).ToLower);

            LPlatform.SearchPath :=
                if LReg.ValueExists('Search Path') then LReg.ReadString('Search Path')
                else '';
            LPlatform.HPPOutputDirectory :=
                if LReg.ValueExists('HPP Output Directory') then LReg.ReadString('HPP Output Directory')
                else '';
            LPlatform.PackageDCPOutput :=
                if LReg.ValueExists('Package DCP Output') then LReg.ReadString('Package DCP Output')
                else '';
            LPlatform.PackageDPLOutput :=
                if LReg.ValueExists('Package DPL Output') then LReg.ReadString('Package DPL Output')
                else '';
            LPlatform.PackageSearchPath :=
                if LReg.ValueExists('Package Search Path') then LReg.ReadString('Package Search Path')
                else '';
          finally
            LReg.CloseKey;
          end;
        end;
      finally
        LActiveSDKs.Free;
      end;
    finally
      LPlatformKeys.Free;
    end;
  finally
    LReg.Free;
  end;
end;

function TProduct.GetPlatforms: TDictionary<string, TProductPlatform>;
begin
  if FPlatforms = nil then
    LoadPlatforms;
  Result := FPlatforms;
end;

class constructor TProduct.Create;
begin
  FProducts := TObjectList<TProduct>.Create({AOwnsObjects=} True);
  LoadProducts;
end;

procedure TProduct.DeleteSearchPaths(const APlatform, AProjectDir: string; APlatformPaths: TPlatformPaths);

  procedure RemovePaths(AReg: TRegistry; APaths: TArray<string>; const ARegValue: string);
  begin
    if Length(APaths) < 1 then
      Exit;

    var LExisting :=
        if AReg.ValueExists(ARegValue) then AReg.ReadString(ARegValue)
        else '';

    // APaths are registered verbatim by AppendPaths (absolute source paths, or
    // $(BLOCKSDIR)-rooted DCU paths), so match them against the stored entries directly.
    var LNewList: TArray<string> := [];
    for var LFullPath in LExisting.Split([';']) do
      if not TArray.Contains<string>(APaths, LFullPath, TIStringComparer.Ordinal) then
        LNewList := LNewList + [LFullPath];

    AReg.WriteString(ARegValue, string.Join(';', LNewList));
  end;

begin
  var RegPath := 'Software\Embarcadero\' + FRegistryKey + '\' + FBdsVersion + '\Library\' + APlatform;

  var Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKey(RegPath, False) then
      Exit;

    RemovePaths(Reg, APlatformPaths.ReleaseDCUPath, 'Search Path');
    RemovePaths(Reg, APlatformPaths.SourcePath, 'Browsing Path');
    RemovePaths(Reg, APlatformPaths.DebugDCUPath, 'Debug DCU Path');

    Reg.CloseKey;
  finally
    Reg.Free;
  end;
end;

class destructor TProduct.Destroy;
begin
  FProducts.Free;
end;

function TProduct.ExpandEnvironment(const AValue: string): string;
begin
  Result := AValue;
  Result :=
      StringReplace(
          Result,
          '$(BDSCOMMONDIR)',
          TPath.Combine([TPath.GetSharedDocumentsPath, 'Embarcadero', 'Studio', FBdsVersion]),
          [rfReplaceAll, rfIgnoreCase]
      );
end;

function TProduct.GetRank: Integer;
begin
  for var I := Low(VersionOrder) to High(VersionOrder) do
    if SameText(VersionOrder[I], FVersionName) then
      Exit(I);
  // Unknown version: rank beyond all known ones, ordered by BDS version number
  var BdsNum: Double;
  if TryStrToFloat(FBdsVersion.Replace('.', FormatSettings.DecimalSeparator), BdsNum) then
    Result := Length(VersionOrder) + Round(BdsNum * 10)
  else
    Result := Length(VersionOrder) + 9999;
end;

class procedure TProduct.LoadProducts;
var
  Reg: TRegistry;
  Keys: TStringList;
  SeenBds: TDictionary<string, Boolean>;
  Temp: TList<TProduct>; // non-owning; items transferred to FProducts

  procedure ScanPath(RootKey: HKEY; const SubPath, ARegKeyName: string);
  var
    VerName, DispName: string;
  begin
    Reg.RootKey := RootKey;
    if not Reg.OpenKeyReadOnly(SubPath) then
      Exit;
    Keys.Clear;
    Reg.GetKeyNames(Keys);
    Reg.CloseKey;

    for var I := 0 to Keys.Count - 1 do
    begin
      var BdsKey := Keys[I];
      // Deduplication key includes the registry key name so the same Delphi
      // version under different profiles is not collapsed
      var DedupeKey := ARegKeyName + ':' + BdsKey;
      if SeenBds.ContainsKey(DedupeKey) then
        Continue;
      SeenBds.Add(DedupeKey, True);

      Reg.RootKey := RootKey;
      if not Reg.OpenKeyReadOnly(SubPath + '\' + BdsKey) then
        Continue;
      var RootDir := Reg.ReadString('RootDir');
      Reg.CloseKey;

      if (RootDir = '') or not TDirectory.Exists(RootDir) then
        Continue;

      if BdsToVersion.TryGetValue(BdsKey, VerName) then
      begin
        if not VersionNames.TryGetValue(VerName, DispName) then
          DispName := VerName;
      end
      else
      begin
        // Only include entries that match a known BDS version number
        Continue;
      end;

      var P := TProduct.Create(BdsKey, VerName, DispName, ExcludeTrailingPathDelimiter(RootDir), ARegKeyName);
      Temp.Add(P);
    end;
  end;

begin
  Reg := TRegistry.Create(KEY_READ);
  Keys := TStringList.Create;
  SeenBds := TDictionary<string, Boolean>.Create;
  Temp := TList<TProduct>.Create;
  try
    // HKLM: standard installation entries always live under "BDS"
    ScanPath(HKEY_LOCAL_MACHINE, 'SOFTWARE\Embarcadero\BDS', 'BDS');
    ScanPath(HKEY_LOCAL_MACHINE, 'SOFTWARE\WOW6432Node\Embarcadero\BDS', 'BDS');

    // HKCU: enumerate ALL sub-keys of SOFTWARE\Embarcadero so that custom
    // profiles (created by running Delphi with -r <key>) are also detected
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('SOFTWARE\Embarcadero') then
    begin
      var EmbKeys := TStringList.Create;
      try
        Reg.GetKeyNames(EmbKeys);
        Reg.CloseKey;
        for var I := 0 to EmbKeys.Count - 1 do
          ScanPath(HKEY_CURRENT_USER, 'SOFTWARE\Embarcadero\' + EmbKeys[I], EmbKeys[I]);
      finally
        EmbKeys.Free;
      end;
    end;

    // Sort descending (newest first = default)
    Temp.Sort(
        TComparer<TProduct>
            .Construct(function(const A, B: TProduct): Integer begin Result := B.GetRank - A.GetRank; end)
    );

    for var P in Temp do
      FProducts.Add(P);
  finally
    Temp.Free; // non-owning; objects are now owned by FProducts
    SeenBds.Free;
    Keys.Free;
    Reg.Free;
  end;
end;

procedure TProduct.RemovePackage(
    const AWorkspaceDir: string;
    APackage: TPackageProject;
    const APlatformPair: TPair<string, TManifestPlatform>
);

  procedure SafeDeleteFile(const AFileName: string);
  begin
    // Write only if verbose is on
    // TConsole.WriteLine(Format('Deleting file %s', [AFileName]));
    if not System.SysUtils.DeleteFile(AFileName) then
      TConsole.WriteWarning(Format('Can''t delete file %s', [AFileName]));
  end;

begin
  var LFileName := '';

  LFileName := GetPackageOutput(AWorkspaceDir, APackage, APlatformPair.Key, 'release', 'bpl');
  SafeDeleteFile(LFileName);
  LFileName := GetPackageOutput(AWorkspaceDir, APackage, APlatformPair.Key, 'debug', 'bpl');
  SafeDeleteFile(LFileName);
  LFileName := GetPackageOutput(AWorkspaceDir, APackage, APlatformPair.Key, 'release', 'dcp');
  SafeDeleteFile(LFileName);
  LFileName := GetPackageOutput(AWorkspaceDir, APackage, APlatformPair.Key, 'debug', 'dcp');
  SafeDeleteFile(LFileName);

  if SameText(APlatformPair.Key, 'win64') then
  begin
    LFileName := GetPackageOutput(AWorkspaceDir, APackage, APlatformPair.Key, 'debug', 'rsm');
    if FileExists(LFileName) then
      SafeDeleteFile(LFileName);
  end;
end;

class function TProduct.Find(const AVersionName: string; const ARegistryKey: string = 'BDS'): TProduct;
begin
  for var P in FProducts do
    if SameText(P.FVersionName, AVersionName) and SameText(P.FRegistryKey, ARegistryKey) then
      Exit(P);
  raise Exception.CreateFmt(
      'Product "%s" with registry key "%s" not found among installed Delphi versions.',
      [AVersionName, ARegistryKey]);
end;

class function TProduct.Choose: TProduct;
begin
  if FProducts.Count = 0 then
    raise Exception.Create('No Delphi version found in the registry.');

  TConsole.WriteLine('Installed Delphi versions:', clGreen);
  for var I := 0 to FProducts.Count - 1 do
  begin
    var LLabel := FProducts[I].DisplayName;
    if not SameText(FProducts[I].RegistryKey, 'BDS') then
      LLabel := LLabel + ' [' + FProducts[I].RegistryKey + ']';
    if I = 0 then
      TConsole.WriteLine(Format('  [%d] %s (default)', [I + 1, LLabel]))
    else
      TConsole.WriteLine(Format('  [%d] %s', [I + 1, LLabel]));
  end;
  TConsole.WriteLine;

  TConsole.Write(Format('Select version [1-%d] (ENTER for default): ', [FProducts.Count]));
  var InputStr := Trim(TConsole.ReadLine);

  if InputStr = '' then
    Exit(FProducts[0]);

  var Index: Integer;
  if TryStrToInt(InputStr, Index) and (Index >= 1) and (Index <= FProducts.Count) then
    Exit(FProducts[Index - 1]);

  TConsole.WriteLine('Invalid selection, using default.', clYellow);
  Result := FProducts[0];
end;

procedure TProduct.InstallPackage(
    APackage: TManifestPackage;
    const AWorkspaceDir, ADprojPath: string;
    APlatformPair: TPair<string, TManifestPlatform>
);
begin
  if not APackage.IsDesignTime then
    Exit;

  var LPackage := TPackageProject.LoadFromFile(ADprojPath);
  try
    var LReg := TRegistry.Create(KEY_READ or KEY_WRITE);
    try
      LReg.RootKey := HKEY_CURRENT_USER;

      var LKnowPackageRegPath := GetKnownPackageRegKey(APlatformPair.Key);
      if LKnowPackageRegPath = '' then
        Exit;

      if not LReg.OpenKey(LKnowPackageRegPath, False) then
        raise Exception.CreateFmt('Cannot open registry key "%s"', [LKnowPackageRegPath]);

      var LPackagePath := GetBPLFileName(AWorkspaceDir, LPackage, APlatformPair.Key);
      if not FileExists(LPackagePath) then
        raise Exception.CreateFmt('Package bpl not found "%s"', [LPackagePath]);

      LReg.WriteString(LPackagePath, LPackage.Description);

      LReg.CloseKey;
    finally
      LReg.Free;
    end;
  finally
    LPackage.Free;
  end;

end;

procedure TProduct.RegisterExpert(const AExpertPath, AName, APlatform: string);
begin
  // The IDE loads experts from a per-platform registry key, mirroring the
  // 'Known Packages' / 'Known Packages x64' split used for design-time packages.
  var LExpertsSubKey :=
      if SameText(APlatform, 'Win32') then 'Experts'
      else if SameText(APlatform, 'Win64') then 'Experts x64'
      else '';
  if LExpertsSubKey = '' then
  begin
    // Caller printed the lead-in with Write; close its line, then warn.
    TConsole.WriteLine(' SKIPPED', clYellow);
    TConsole.WriteWarning(Format('Cannot register expert for platform "%s": unsupported', [APlatform]));
    Exit;
  end;

  if not FileExists(AExpertPath) then
  begin
    TConsole.WriteLine(' FAILED', clRed);
    raise Exception.CreateFmt('Expert dll not found "%s"', [AExpertPath]);
  end;

  var LRegPath := 'Software\Embarcadero\' + FRegistryKey + '\' + FBdsVersion + '\' + LExpertsSubKey;

  var LReg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    LReg.RootKey := HKEY_CURRENT_USER;
    // CanCreate: the Experts key may not exist until the first expert is registered.
    if not LReg.OpenKey(LRegPath, True) then
    begin
      TConsole.WriteLine(' FAILED', clRed);
      raise Exception.CreateFmt('Cannot open registry key "%s"', [LRegPath]);
    end;
    try
      LReg.WriteString(AName, AExpertPath);
    finally
      LReg.CloseKey;
    end;
  finally
    LReg.Free;
  end;

  TConsole.WriteLine(' OK', clGreen);
end;

procedure TProduct.UnregisterExperts(const AWorkspaceDir, AManifestName: string);
begin
  // An expert is ours when its registered path lives under the workspace blocks
  // lib folder for this manifest. Match both the absolute path written at install
  // and the $(BLOCKSDIR) macro form, so either survives. The trailing delimiter
  // keeps one manifest name from matching another that merely shares its prefix.
  var LLibSubPath := 'lib\' + AManifestName;
  var LFullPrefix := IncludeTrailingPathDelimiter(TPath.Combine([AWorkspaceDir, '.blocks', LLibSubPath]));
  var LMacroPrefix := '$(BLOCKSDIR)\' + LLibSubPath + '\';

  var LReg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    LReg.RootKey := HKEY_CURRENT_USER;
    for var LExpertsSubKey in ['Experts', 'Experts x64'] do
    begin
      var LRegPath := 'Software\Embarcadero\' + FRegistryKey + '\' + FBdsVersion + '\' + LExpertsSubKey;
      if not LReg.OpenKey(LRegPath, False) then
        Continue;
      try
        // GetValueNames is a snapshot, so deleting while iterating it is safe.
        var LNames := TStringList.Create;
        try
          LReg.GetValueNames(LNames);
          for var LName in LNames do
          begin
            var LValue := LReg.ReadString(LName);
            if LValue.StartsWith(LFullPrefix, True) or LValue.StartsWith(LMacroPrefix, True) then
            begin
              LReg.DeleteValue(LName);
              TConsole.WriteLine(Format('Unregistered expert %s', [LName]), clYellow);
            end;
          end;
        finally
          LNames.Free;
        end;
      finally
        LReg.CloseKey;
      end;
    end;
  finally
    LReg.Free;
  end;
end;

// Reads the command line of a process using NtQueryInformationProcess class 60
// (ProcessCommandLineInformation, available Windows 8.1+).
// Returns '' on failure (e.g. access denied, 64-bit target from 32-bit caller).
function GetProcessCommandLine(AhProcess: THandle): string;
const
  ProcessCommandLineInformation = 60;
var
  LRequired: ULONG;
  LBuf: TBytes;
  LUS: PNtUnicodeString;
  LOffset: NativeUInt;
begin
  Result := '';
  try
    LRequired := 0;
    NtQueryInformationProcess(AhProcess, ProcessCommandLineInformation, nil, 0, @LRequired);
    if LRequired < SizeOf(TNtUnicodeString) then
      Exit;
    SetLength(LBuf, LRequired);
    if NtQueryInformationProcess(AhProcess, ProcessCommandLineInformation, @LBuf[0], LRequired, @LRequired) <> 0 then
      Exit;
    LUS := PNtUnicodeString(@LBuf[0]);
    LOffset := NativeUInt(LUS.Buffer) - NativeUInt(@LBuf[0]);
    if LOffset + LUS.Length > LRequired then
      Exit;
    SetLength(Result, LUS.Length div SizeOf(WideChar));
    if LUS.Length > 0 then
      Move(LBuf[LOffset], Result[1], LUS.Length);
  except
    Result := '';
  end;
end;

// Extracts the registry key name from a bds.exe command line.
// Returns 'BDS' (the default) when no -r/-R/+/r flag is present.
function GetRegistryKeyFromCmdLine(const ACmdLine: string): string;
var
  LTokens: TArray<string>;
  I: Integer;
begin
  Result := 'BDS';
  LTokens := ACmdLine.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  for I := 0 to Length(LTokens) - 2 do
    if SameText(LTokens[I], '-r') or SameText(LTokens[I], '/r') then
    begin
      Result := LTokens[I + 1].Trim(['"', '''']);
      Exit;
    end;
end;

function TProduct.IsRunning: Boolean;
var
  Snapshot: THandle;
  Entry: TProcessEntry32W;
  BinPath: string;
  hProc: THandle;
  ExePath: string;
  PathLen: DWORD;
begin
  Result := False;
  BinPath := IncludeTrailingPathDelimiter(FRootDir) + 'bin\bds.exe';

  Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snapshot = INVALID_HANDLE_VALUE then
    Exit;
  try
    Entry.dwSize := SizeOf(Entry);
    if not Process32FirstW(Snapshot, Entry) then
      Exit;
    repeat
      if SameText(ChangeFileExt(string(Entry.szExeFile), ''), 'bds') then
      begin
        hProc := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, Entry.th32ProcessID);
        if hProc <> 0 then
          try
            SetLength(ExePath, MAX_PATH);
            PathLen := MAX_PATH;
            if QueryFullProcessImageNameW(hProc, 0, PChar(ExePath), PathLen) then
            begin
              SetLength(ExePath, PathLen);
              if SameText(ExePath, BinPath) then
              begin
                var LCmdLine := GetProcessCommandLine(hProc);
                // When we cannot read the command line (access denied, etc.) only
                // the default 'BDS' profile is assumed — custom profiles need an
                // explicit -r/+/r match to avoid false positives across profiles.
                var LMatches: Boolean;
                if LCmdLine = '' then
                  LMatches := SameText(FRegistryKey, 'BDS')
                else
                  LMatches := SameText(GetRegistryKeyFromCmdLine(LCmdLine), FRegistryKey);
                if LMatches then
                begin
                  Result := True;
                  Exit;
                end;
              end;
            end;
          finally
            CloseHandle(hProc);
          end;
      end;
    until not Process32NextW(Snapshot, Entry);
  finally
    CloseHandle(Snapshot);
  end;
end;

function TProduct.HasCompiler(const APlatform: string): Boolean;
begin
  var LCompiler := GetCompilerExe(APlatform);
  if LCompiler = '' then
    Exit(False);

  Result := TFile.Exists(TPath.Combine([FRootDir, 'bin', LCompiler]));
end;

function TProduct.GetPackageOutput(
    const AWorkspaceDir: string;
    APackage: TPackageProject;
    const APlatform, AConfig, AOutputType: string
): string;
begin
  // Release builds drop their artifacts directly under the output type folder; only Debug uses a subfolder.
  var LConfigDir := AConfig;
  if SameText(AConfig, 'release') then
    LConfigDir := '';

  // Win64 .rsm (remote symbol) files are emitted next to the .bpl, not in their own folder.
  var LOutputTypeDir := AOutputType;
  if SameText(AOutputType, 'rsm') then
    LOutputTypeDir := 'bpl';

  var LPackageNameSuffix := APackage.LibSuffix;
  if SameText(LPackageNameSuffix, 'AUTO') or SameText(LPackageNameSuffix, '$(Auto)') then
    LPackageNameSuffix := FPackageVersion;
  // .dcp files do not carry the LibSuffix, unlike .bpl/.rsm.
  if SameText(AOutputType, 'dcp') then
    LPackageNameSuffix := '';

  var LDefaultOutputDirectory := TPath.Combine([AWorkspaceDir, '.blocks', APlatform, LOutputTypeDir, LConfigDir]);

  var LPackageFileName := APackage.Name + LPackageNameSuffix + '.' + AOutputType;
  Result := ExpandEnvironment(TPath.Combine(LDefaultOutputDirectory, LPackageFileName));
end;

function TProduct.GetBPLFileName(
    const AWorkspaceDir: string;
    APackage: TPackageProject;
    const APlatform: string
): string;
begin
  Result := GetPackageOutput(AWorkspaceDir, APackage, APlatform, 'release', 'bpl');
end;

function TProduct.GetKnownPackageRegKey(const APlatform: string): string;
begin
  // Delphi supports two registry keys for design-time packages
  // 'Known Packages': for the 32-bit IDE
  // 'Known Packages x64': for the 64-bit IDE
  // Other platforms are not supported at the moment
  var LPlatformRegKey := '';
  if SameText(APlatform, 'Win32') then
    LPlatformRegKey := 'Known Packages'
  else if SameText(APlatform, 'Win64') then
    LPlatformRegKey := 'Known Packages x64'
  else
    // Manifest is misconfigured. Should I raise an exception?
    Exit('');

  Result := 'Software\Embarcadero\' + FRegistryKey + '\' + FBdsVersion + '\' + LPlatformRegKey;
end;

function TProduct.GetPackageFolder(APackageFolders: TDictionary<string, string>): string;
begin
  var SelfRank := GetRank;
  var BestRank := -1;
  var BestKey := '';

  for var Key in APackageFolders.Keys do
  begin
    var BaseKey := TrimRight(Key, ['+']);
    var KeyRank := -1;
    for var J := Low(VersionOrder) to High(VersionOrder) do
      if SameText(VersionOrder[J], BaseKey) then
      begin
        KeyRank := J;
        Break;
      end;

    if KeyRank < 0 then
      Continue; // config key must be a known version name

    if (KeyRank <= SelfRank) and (KeyRank > BestRank) then
    begin
      BestRank := KeyRank;
      BestKey := Key;
    end;
  end;

  if BestKey = '' then
    raise Exception.CreateFmt('No compatible package found for "%s". Delphi version too old?', [FVersionName]);

  Result := APackageFolders[BestKey];
end;

function TProduct.GetPackagesPath(const AProjectDir: string; AManifest: TManifest): string;
begin
  var LRootFolder := AManifest.PackageOptions.RootFolder;
  if LRootFolder = '' then
    LRootFolder := 'packages';
  Result := TPath.Combine(AProjectDir, LRootFolder);

  // The version-specific folder is optional: with no "folders" entries (or a "."
  // placeholder) the .dproj files live directly under the root folder.
  if AManifest.PackageOptions.Folders.Count > 0 then
  begin
    var LFolder := GetPackageFolder(AManifest.PackageOptions.Folders);
    if (LFolder <> '') and (LFolder <> '.') then
      Result := TPath.Combine(Result, LFolder);
  end;
end;

function TProduct.ExpandPackageName(const AName: string): string;
begin
  // Mirrors the %NAME% placeholder convention used by manifest scripts.
  Result := StringReplace(AName, '%PACKAGE_VERSION%', FPackageVersion, [rfReplaceAll, rfIgnoreCase]);
end;

class function TProduct.GetProductNames: TArray<string>;
begin
  Result := [];
  var LProducts := Products;
  for var P in LProducts do
    Result := Result + [P.DisplayName];
end;

procedure TProduct.UninstallPackage(
    APackage: TManifestPackage;
    const AWorkspaceDir, ADprojPath: string;
    APlatformPair: TPair<string, TManifestPlatform>
);
begin
  if not APackage.IsDesignTime then
    Exit;

  var LPackage := TPackageProject.LoadFromFile(ADprojPath);
  try
    var LReg := TRegistry.Create(KEY_READ or KEY_WRITE);
    try
      LReg.RootKey := HKEY_CURRENT_USER;

      var LKnowPackageRegPath := GetKnownPackageRegKey(APlatformPair.Key);
      if LKnowPackageRegPath = '' then
        Exit;

      if not LReg.OpenKey(LKnowPackageRegPath, False) then
        raise Exception.CreateFmt('Cannot open registry key "%s"', [LKnowPackageRegPath]);

      var LPackagePath := GetBPLFileName(AWorkspaceDir, LPackage, APlatformPair.Key);
      if not FileExists(LPackagePath) then
      begin
        TConsole.WriteWarning(Format('Package BPL not found, skipping registry removal: "%s"', [LPackagePath]));
        Exit;
      end;

      if LReg.ValueExists(LPackagePath) then
      begin
        LReg.DeleteValue(LPackagePath);
      end
      else
      begin
        TConsole.WriteWarning(Format('Value "%s" not found in registry', [LPackagePath]));
      end;

      LReg.CloseKey;
    finally
      LReg.Free;
    end;
  finally
    LPackage.Free;
  end;
end;

procedure TProduct.FillEnvironmentVariables(AEnvironmentVariable: TStrings);
begin
  AEnvironmentVariable.Values['ProductVersion'] := FBdsVersion;
  AEnvironmentVariable.Values['PackageVersion'] := FPackageVersion;

  var LReg := TRegistry.Create(KEY_READ);
  try
    LReg.RootKey := HKEY_LOCAL_MACHINE;
    if LReg.OpenKeyReadOnly('SOFTWARE\WOW6432Node\Embarcadero\BDS\' + FBdsVersion) then
    begin
      if LReg.ValueExists('RootDir') then
        AEnvironmentVariable.Values['BDS'] := ExcludeTrailingPathDelimiter(LReg.ReadString('RootDir'));
      if LReg.ValueExists('App') then
        AEnvironmentVariable.Values['BDSBIN'] := ExcludeTrailingPathDelimiter(ExtractFilePath(LReg.ReadString('App')));
      LReg.CloseKey;
    end;

    LReg.RootKey := HKEY_CURRENT_USER;
    if LReg.OpenKeyReadOnly('Software\Embarcadero\' + FRegistryKey + '\' + FBdsVersion + '\Environment Variables') then
    begin
      var LNames := TStringList.Create;
      try
        LReg.GetValueNames(LNames);
        for var LName in LNames do
          AEnvironmentVariable.Values[LName] := LReg.ReadString(LName);
      finally
        LNames.Free;
      end;
      LReg.CloseKey;
    end;
  finally
    LReg.Free;
  end;
end;

procedure TProduct.UpdateSearchPaths(const APlatform, AProjectDir: string; APlatformPaths: TPlatformPaths);

  procedure AppendPaths(AReg: TRegistry; APaths: TArray<string>; const ARegValue: string);
  begin
    if Length(APaths) < 1 then
      Exit;

    var LExisting :=
        if AReg.ValueExists(ARegValue) then AReg.ReadString(ARegValue)
        else '';

    var LExistingList := LExisting.Split([';']);
    var LNewPaths := LExistingList;

    for var LPath in APaths do
    begin
      // Paths that start with an IDE macro (e.g. $(BLOCKSDIR)) are already
      // resolved by Delphi at load time; combining them with AProjectDir would
      // corrupt the macro, so register them verbatim.
      var LNewPath :=
          if LPath.StartsWith('$(') then LPath
          else TPath.Combine(AProjectDir, LPath);
      if not TArray.Contains<string>(LNewPaths, LNewPath, TIStringComparer.Ordinal) then
      begin
        LNewPaths := LNewPaths + [LNewPath];
      end;
    end;
    AReg.WriteString(ARegValue, string.Join(';', LNewPaths));
  end;

begin
  var RegPath := 'Software\Embarcadero\' + FRegistryKey + '\' + FBdsVersion + '\Library\' + APlatform;

  var Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKey(RegPath, False) then
      Exit;

    AppendPaths(Reg, APlatformPaths.ReleaseDCUPath, 'Search Path');
    AppendPaths(Reg, APlatformPaths.SourcePath, 'Browsing Path');
    AppendPaths(Reg, APlatformPaths.DebugDCUPath, 'Debug DCU Path');

    Reg.CloseKey;
  finally
    Reg.Free;
  end;
end;

procedure TProduct.CheckDCPPath(const AWorkspaceDir: string);
begin
  var LReg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    LReg.RootKey := HKEY_CURRENT_USER;
    for var LPlatform in DCPPlatforms do
    begin
      var LRegPath := 'Software\Embarcadero\' + FRegistryKey + '\' + FBdsVersion + '\Library\' + LPlatform;
      if not LReg.OpenKey(LRegPath, False) then
        Continue;
      try
        var LDCPPath := TPath.Combine([AWorkspaceDir, '.blocks', LPlatform, 'dcp']);
        var LExisting :=
            if LReg.ValueExists('Search Path') then LReg.ReadString('Search Path')
            else '';

        if TArray.Contains<string>(LExisting.Split([';']), LDCPPath, TIStringComparer.Ordinal) then
          Continue;

        var LNewValue :=
            if LExisting <> '' then LDCPPath
                + ';'
                + LExisting
                else LDCPPath;
        LReg.WriteString('Search Path', LNewValue);
        TConsole.WriteLine(Format('Registered DCP path for %s: %s', [LPlatform, LDCPPath]), clGreen);
      finally
        LReg.CloseKey;
      end;
    end;
  finally
    LReg.Free;
  end;
end;

procedure TProduct.CheckEnvironment(const AWorkspaceDir: string);

  function EnvVarsSubKey(const APlatform: string): string;
  begin
    if SameText(APlatform, 'Win64') then
      Result := 'Environment Variables x64'
    else
      Result := 'Environment Variables';
  end;

begin
  var LReg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    LReg.RootKey := HKEY_CURRENT_USER;
    for var LPlatform in DCPPlatforms do
    begin
      var LRegPath := 'Software\Embarcadero\' + FRegistryKey + '\' + FBdsVersion + '\' + EnvVarsSubKey(LPlatform);
      // CanCreate: the Environment Variables key may not exist until the user
      // defines an override; this method must register the path regardless.
      if not LReg.OpenKey(LRegPath, True) then
        Continue;
      try
        // Expose the workspace's .blocks directory as a Delphi environment
        // variable so manifests/packages can reference $(BLOCKSDIR). Only set it
        // when missing, to avoid clobbering a value the user may have customised.
        if not LReg.ValueExists('BLOCKSDIR') then
        begin
          var LBlocksDir := TPath.Combine(AWorkspaceDir, '.blocks');
          LReg.WriteString('BLOCKSDIR', LBlocksDir);
          TConsole.WriteLine(Format('Registered BLOCKSDIR for %s: %s', [LPlatform, LBlocksDir]), clGreen);
        end;

        var LBplPath := TPath.Combine([AWorkspaceDir, '.blocks', LPlatform, 'bpl']);
        var LExisting :=
            if LReg.ValueExists('PATH') then LReg.ReadString('PATH')
            else '';

        if TArray.Contains<string>(LExisting.Split([';']), LBplPath, TIStringComparer.Ordinal) then
          Continue;

        // Prepend so the Blocks-managed bpl wins the Windows DLL search (first
        // match on PATH wins), staying consistent with CheckDCPPath and keeping
        // the loaded bpl aligned with its dcp. Keep the inherited PATH ($(PATH))
        // when creating the value from scratch.
        var LNewValue: string;
        if LExisting = '' then
          LNewValue := LBplPath + ';$(PATH)'
        else
          LNewValue := LBplPath + ';' + LExisting;
        LReg.WriteString('PATH', LNewValue);
        TConsole.WriteLine(Format('Registered bpl path for %s: %s', [LPlatform, LBplPath]), clGreen);
      finally
        LReg.CloseKey;
      end;
    end;
  finally
    LReg.Free;
  end;
end;

function TProduct.CompileProject(
    const AWorkspaceDir,
    AManifestName,
    AProjectFileName,
    AConfig,
    APlatform: string
): string;
begin
  var LPackageProject := TPackageProject.LoadFromFile(AProjectFileName);
  try
    var LBlocksDir := TPath.Combine(AWorkspaceDir, '.blocks');
    var LSuffix :=
        if SameText(AConfig, 'Debug') then 'debug'
        else '';
    var LConfigName :=
        if SameText(AConfig, 'Debug') then 'Debug'
        else 'Release';
    // Prepend the blocks dcp directory to the project's own resolved
    // DCC_UnitSearchPath (for this config/platform) instead of replacing it.
    var LUnitSearchPath := TPath.Combine(LBlocksDir, APlatform, 'dcp', LSuffix);
    var LOriginalUnitSearchPath :=
        LPackageProject.GetProperty(TPackageProject.DCCUnitSearchPath, LConfigName, APlatform);
    if LOriginalUnitSearchPath <> '' then
      LUnitSearchPath := LUnitSearchPath + ';' + LOriginalUnitSearchPath;

    var LDcuOutput := TPath.Combine([LBlocksDir, 'lib', AManifestName, APlatform]);
    if LSuffix <> '' then
      LDcuOutput := TPath.Combine(LDcuOutput, LSuffix);

    var LBdsDir := FRootDir;
    var LBdsCommonDir :=
        TPath.Combine(GetEnvironmentVariable('PUBLIC'), TPath.Combine('Documents\Embarcadero\Studio', FBdsVersion));
    var LMsBuild := GetMsBuildPath;

    // Set Delphi environment variables inherited by child processes
    SetEnvironmentVariable('BDS', PChar(LBdsDir));
    SetEnvironmentVariable('BDSINCLUDE', PChar(LBdsDir + '\include'));
    SetEnvironmentVariable('BDSCOMMONDIR', PChar(LBdsCommonDir));
    SetEnvironmentVariable('LANGDIR', 'EN');
    SetEnvironmentVariable('PLATFORM', '');

    // Prepend BDS bin dirs to PATH (no duplicates)
    var LCurPath := GetEnvironmentVariable('PATH');
    var LNewPath := LCurPath;
    for var LBinDir in [LBdsDir + '\bin64', LBdsDir + '\bin'] do
      if Pos(LBinDir, LNewPath) = 0 then
        LNewPath := LBinDir + ';' + LNewPath;
    if LNewPath <> LCurPath then
      SetEnvironmentVariable('PATH', PChar(LNewPath));

    // Only emit a /p:DCC_* override when a value is supplied: passing it empty would
    // wipe the path the project author declared. This lets a bare compile (e.g. an
    // expert built through IScriptHelper) keep the project's own settings.
    var LMSBuildParams := '';
    for var LOverride
        in [
            TPair<string, string>.Create('DCC_UnitSearchPath', LUnitSearchPath),
            TPair<string, string>.Create('DCC_BplOutput', TPath.Combine(LBlocksDir, APlatform, 'bpl', LSuffix)),
            TPair<string, string>.Create('DCC_DcpOutput', TPath.Combine(LBlocksDir, APlatform, 'dcp', LSuffix)),
            TPair<string, string>.Create('DCC_DcuOutput', LDcuOutput),
            // An expert produces an executable/library; drop it next to its DCUs.
            TPair<string, string>.Create('DCC_ExeOutput', LDcuOutput)] do
      if LOverride.Value <> '' then
        LMSBuildParams := LMSBuildParams + Format(' /p:%s="%s"', [LOverride.Key, LOverride.Value]);

    var LCmdLine :=
        Format(
            '"%s" "%s" /t:Make /p:config=%s /p:platform=%s %s /nologo /v:quiet',
            [LMsBuild, AProjectFileName, AConfig, APlatform, LMSBuildParams]
        );

    var LExitCode := RunProcessWithOutput(LCmdLine, Result);

    if LExitCode <> 0 then
    begin
      TConsole.WriteLine(' FAILED', clRed);
      var LLines := Result.Split([sLineBreak, #13, #10], TStringSplitOptions.ExcludeEmpty);
      for var LLine in LLines do
        if ContainsText(LLine, 'error') then
          TConsole.WriteLine('      ' + LLine, clRed);
      raise Exception.CreateFmt(
          'Compilation failed on "%s" for platform "%s".',
          [TPath.GetFileNameWithoutExtension(AProjectFileName), APlatform]);
    end;

  finally
    LPackageProject.Free;
  end;
end;

procedure TProduct.BuildPackages(const AWorkspaceDir, AProjectDir: string; const AManifest: TManifest);
begin
  var BuildConfigs := ['debug', 'release'];
  var PackagesPath := GetPackagesPath(AProjectDir, AManifest);

  var PlatformNames := TStringList.Create;
  try
    for var LPlatformPair in AManifest.Platforms do
    begin
      var LProductPlatform: TProductPlatform;
      if not (Platforms.TryGetValue(LPlatformPair.Key, LProductPlatform) and LProductPlatform.Active) then
        Continue;
      // A mapped platform whose compiler is missing on disk is not buildable;
      // exclude it here so the header and the "none active" check stay accurate.
      // The user-facing warning is emitted once, in the compile loop below.
      if (GetCompilerExe(LPlatformPair.Key) <> '') and not HasCompiler(LPlatformPair.Key) then
        Continue;
      PlatformNames.Add(LPlatformPair.Key);
    end;

    if PlatformNames.Count = 0 then
    begin
      var LManifestPlatforms := TStringList.Create;
      try
        for var LPlatformPair in AManifest.Platforms do
          LManifestPlatforms.Add(LPlatformPair.Key);
        raise Exception.CreateFmt(
            'None of the platforms supported by this package (%s) is active in %s.',
            [LManifestPlatforms.CommaText, FDisplayName]);
      finally
        LManifestPlatforms.Free;
      end;
    end;

    TConsole.WriteLine('Compiling packages...', clCyan);
    TConsole.WriteLine('  BDS       : ' + FRootDir);
    TConsole.WriteLine('  Packages  : ' + PackagesPath);
    TConsole.WriteLine('  Platforms : ' + PlatformNames.CommaText);
    TConsole.WriteLine;
  finally
    PlatformNames.Free;
  end;

  for var LPlatformPair in AManifest.Platforms do
  begin
    var LPlatform := LPlatformPair.Key;
    var LProductPlatform: TProductPlatform;
    if not (Platforms.TryGetValue(LPlatform, LProductPlatform) and LProductPlatform.Active) then
      Continue;

    // The platform is registered/active, but the command-line compiler may not
    // have been installed (e.g. a partial Delphi install). Skip it rather than
    // letting MSBuild fail with an opaque error.
    if (GetCompilerExe(LPlatform) <> '') and not HasCompiler(LPlatform) then
    begin
      TConsole.WriteLine(Format('  Skipping platform %s (compiler not installed)', [LPlatform]), clDkGray);
      Continue;
    end;

    TConsole.WriteLine('  [' + LPlatform + ']', clDkCyan);

    for var LPackage in AManifest.Packages do
    begin
      // Manifest package names may embed the %PACKAGE_VERSION% placeholder
      // (e.g. "Trysil%PACKAGE_VERSION%") so a single manifest can target
      // packages whose .dproj name embeds the Delphi package-version suffix.
      var PkgName := ExpandPackageName(LPackage.Name);
      var TypeStr := string.Join(', ', LPackage.&Type.ToStringArray);

      // Skip packages that do not target this Delphi product.
      if not LPackage.SupportsProduct(VersionName) then
      begin
        TConsole
            .WriteLine(Format('    Skipping %s [%s] (not supported on %s)', [PkgName, TypeStr, VersionName]), clDkGray);
        Continue;
      end;

      // Skip design-time packages on platforms flagged as runtime-only.
      if LPlatformPair.Value.RuntimeOnly and LPackage.IsDesignTime then
      begin
        TConsole.WriteLine(Format('    Skipping %s [%s] (runtime-only platform)', [PkgName, TypeStr]), clDkGray);
        Continue;
      end;

      var DprojPath := TPath.Combine(PackagesPath, PkgName + '.dproj');
      if not TFile.Exists(DprojPath) then
        raise Exception.CreateFmt('Package not found: %s', [DprojPath]);

      // Load the .dproj so we can preserve its own DCC_UnitSearchPath: passing
      // /p:DCC_UnitSearchPath as a global property would otherwise override (and
      // discard) the search paths declared by the package author.
      var LPackageProject := TPackageProject.LoadFromFile(DprojPath);
      try
        for var LBuildConfig in BuildConfigs do
        begin
          RunCompileScripts(
              AManifest,
              TScriptRunner.EventBeforeCompile,
              AWorkspaceDir,
              AProjectDir,
              LPlatform,
              LBuildConfig,
              PkgName,
              Self
          );

          TConsole.Write(Format('    Building %s [%s/%s]...', [PkgName, TypeStr, LBuildConfig]));

          CompileProject(AWorkspaceDir, AManifest.Name, DprojPath, LBuildConfig, LPlatform);
          TConsole.WriteLine(' OK', clGreen);

          RunCompileScripts(
              AManifest,
              TScriptRunner.EventAfterCompile,
              AWorkspaceDir,
              AProjectDir,
              LPlatform,
              LBuildConfig,
              PkgName,
              Self
          );
        end;
      finally
        LPackageProject.Free;
      end;

      InstallPackage(LPackage, AWorkspaceDir, DprojPath, LPlatformPair);
    end;

  end;

  TConsole.WriteLine;
  TConsole.WriteLine('All packages compiled successfully.', clGreen);
end;

end.
