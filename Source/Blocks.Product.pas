unit Blocks.Product;

interface

uses
  System.Generics.Collections,
  Blocks.Database,
  Blocks.Manifest;

/// <summary>Represents a single Delphi/RAD Studio installation.</summary>
/// <remarks>
///   The class constructor populates <see cref="Products"/> with one TProduct
///   per installed IDE found in the Windows registry, sorted newest-first.
///   The list lives for the lifetime of the process.
/// </remarks>
type
  TProduct = class
  private
    FBdsVersion: string;
    FVersionName: string;
    FDisplayName: string;
    FRootDir: string;

    class var
      FProducts: TObjectList<TProduct>;

    class procedure LoadProducts;
    function GetRank: Integer;
    class function GetProductNames: TArray<string>; static;

  public
    constructor Create(const ABdsVersion, AVersionName, ADisplayName, ARootDir: string);
    class constructor Create;
    class destructor Destroy;

    /// <summary>Finds an installed product by display name or version name.</summary>
    /// <param name="AProduct">Display name (e.g. <c>Delphi 12 Athens</c>) or internal
    ///   version name (e.g. <c>delphi12</c>), matched case-insensitively.</param>
    /// <returns>The matching <see cref="TProduct"/> instance from <see cref="Products"/>.</returns>
    /// <exception cref="Exception">Raised when no installed product matches <c>AProduct</c>.</exception>
    class function Find(const AProduct: string): TProduct;

    /// <summary>Selects an installed product interactively or by name.</summary>
    /// <param name="AProduct">When non-empty, delegates to <see cref="Find"/>.
    ///   When empty, displays a numbered menu on stdout and reads the choice from stdin.</param>
    /// <returns>The selected <see cref="TProduct"/>. Returns the newest product (index 0)
    ///   when the user presses ENTER without entering a number.</returns>
    /// <exception cref="Exception">Raised when no Delphi version is installed.</exception>
    class function Select(const AProduct: string): TProduct;

    /// <summary>Checks whether this Delphi IDE instance is currently running.</summary>
    /// <returns><c>True</c> if a <c>bds.exe</c> process whose full image path matches
    ///   <c>RootDir\bin\bds.exe</c> is found in the process list.</returns>
    function IsRunning: Boolean;

    /// <summary>Resolves the best matching package folder key for this Delphi version.</summary>
    /// <param name="APackageFolders">Dictionary mapping version-name keys (optionally suffixed
    ///   with <c>+</c>) to folder name values, as declared in the package manifest.</param>
    /// <returns>The folder name string for the greatest-lower-bound key.</returns>
    /// <exception cref="Exception">Raised when no compatible key is found
    ///   (installed version is older than all keys in the manifest).</exception>
    function GetPackageFolder(APackageFolders: TDictionary<string, string>): string;

    /// <summary>Checks whether a target platform is installed for this Delphi version.</summary>
    /// <param name="APlatform">Platform identifier, e.g. <c>Win32</c>, <c>Win64</c>, <c>Android</c>.</param>
    /// <returns><c>True</c> if the platform's library registry key exists under HKLM or HKCU.</returns>
    function TestPlatformInstalled(const APlatform: string): Boolean;

    /// <summary>Compiles all declared packages and updates the Delphi library registry paths.</summary>
    /// <param name="AProjectDir">Root directory of the extracted project.</param>
    /// <param name="APackageFolder">Subfolder under <c>packages\</c> that contains the <c>.dproj</c> files.</param>
    /// <param name="APackages">Package descriptors from the manifest, one per <c>.dproj</c> file.</param>
    /// <param name="APlatforms">Target platform configurations from the manifest.</param>
    /// <exception cref="Exception">Raised when a platform is not installed or a package fails to compile.</exception>
    procedure BuildPackages(
        const AProjectDir, APackageFolder: string;
        const APackages: TManifestPackageList;
        const APlatforms: TSupportedPlatforms
    );

    /// <summary>Appends source, browsing, and debug DCU paths to the Delphi library registry.</summary>
    /// <param name="APlatform">Target platform identifier, e.g. <c>Win32</c>.</param>
    /// <param name="AProjectDir">Project root; manifest paths are resolved relative to this directory.</param>
    /// <param name="APlatformConfig">Platform record from the manifest containing the path lists to register.</param>
    /// <remarks>
    ///   Already-present entries are skipped. Writes to
    ///   <c>HKCU\Software\Embarcadero\BDS\&lt;BdsVersion&gt;\Library\&lt;Platform&gt;</c>.
    /// </remarks>
    procedure UpdateSearchPaths(const APlatform, AProjectDir: string; const APlatformConfig: TManifestPlatform);

    /// <summary>Recursively installs a dependency and its sub-dependencies into the workspace.</summary>
    /// <param name="ADependencySpec">Package identifier in the form <c>owner.pkg</c> or
    ///   <c>owner.pkg@commitsha</c>.</param>
    /// <param name="ADatabase">Database instance used to check and record installed packages.</param>
    /// <param name="ASilent">When <c>True</c>, skips non-critical interactive prompts and uses defaults.</param>
    /// <param name="AOverwrite">When <c>True</c>, replaces an existing project directory without asking.</param>
    /// <param name="ADepth">Recursion depth used only to indent console output. Pass <c>0</c> for top-level calls.</param>
    /// <remarks>Uses <see cref="TWorkspace.WorkDir"/> and <see cref="TWorkspace.BlocksDir"/>
    ///   as the installation target.</remarks>
    procedure Install(
        const ADependencySpec: string;
        ADatabase: TDatabase;
        ASilent, AOverwrite: Boolean;
        ADepth: Integer = 0
    );

    /// <summary>All installed Delphi/RAD Studio products, sorted newest-first.</summary>
    class property Products: TObjectList<TProduct> read FProducts;
    /// <summary>All installed Delphi/RAD Studio products by name.</summary>
    class property ProductNames: TArray<string> read GetProductNames;

    /// <summary>Internal BDS registry key version string (e.g. <c>23.0</c> for Delphi 12 Athens).</summary>
    property BdsVersion: string read FBdsVersion;
    /// <summary>Internal version name used in file paths and registry lookups (e.g. <c>delphi12</c>).</summary>
    property VersionName: string read FVersionName;
    /// <summary>Human-readable IDE display name (e.g. <c>Delphi 12 Athens</c>).</summary>
    property DisplayName: string read FDisplayName;
    /// <summary>Root installation directory of the IDE (e.g. <c>C:\Program Files (x86)\Embarcadero\Studio\23.0</c>).</summary>
    property RootDir: string read FRootDir;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Defaults,
  System.Win.Registry,
  Winapi.Windows,
  Winapi.TlHelp32,
  Blocks.Consts,
  Blocks.Console,
  Blocks.Http,
  Blocks.Workspace;

// -- WinAPI declarations missing from older Delphi headers --------------------

const
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

function QueryFullProcessImageNameW(
    hProcess: THandle;
    dwFlags: DWORD;
    lpExeName: PWideChar;
    var lpdwSize: DWORD
): BOOL; stdcall; external 'kernel32.dll' name 'QueryFullProcessImageNameW';

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

// -- TProduct ------------------------------------------------------------------

constructor TProduct.Create(const ABdsVersion, AVersionName, ADisplayName, ARootDir: string);
begin
  inherited Create;
  FBdsVersion := ABdsVersion;
  FVersionName := AVersionName;
  FDisplayName := ADisplayName;
  FRootDir := ARootDir;
end;

class constructor TProduct.Create;
begin
  FProducts := TObjectList<TProduct>.Create({AOwnsObjects=} True);
  LoadProducts;
end;

class destructor TProduct.Destroy;
begin
  FProducts.Free;
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

  procedure ScanPath(RootKey: HKEY; const SubPath: string);
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
      if SeenBds.ContainsKey(BdsKey) then
        Continue;
      SeenBds.Add(BdsKey, True);

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
        VerName := 'bds_' + BdsKey;
        DispName := 'Delphi (BDS ' + BdsKey + ')';
      end;

      var P := TProduct.Create(BdsKey, VerName, DispName, ExcludeTrailingPathDelimiter(RootDir));
      Temp.Add(P);
    end;
  end;

begin
  Reg := TRegistry.Create(KEY_READ);
  Keys := TStringList.Create;
  SeenBds := TDictionary<string, Boolean>.Create;
  Temp := TList<TProduct>.Create;
  try
    ScanPath(HKEY_LOCAL_MACHINE, 'SOFTWARE\Embarcadero\BDS');
    ScanPath(HKEY_LOCAL_MACHINE, 'SOFTWARE\WOW6432Node\Embarcadero\BDS');
    ScanPath(HKEY_CURRENT_USER, 'SOFTWARE\Embarcadero\BDS');

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

class function TProduct.Find(const AProduct: string): TProduct;
begin
  for var P in FProducts do
    if SameText(P.FDisplayName, AProduct) or SameText(P.FVersionName, AProduct) then
      Exit(P);
  raise Exception.CreateFmt('Product "%s" not found among installed Delphi versions.', [AProduct]);
end;

class function TProduct.Select(const AProduct: string): TProduct;
begin
  if FProducts.Count = 0 then
    raise Exception.Create('No Delphi version found in the registry.');

  if AProduct <> '' then
    Exit(Find(AProduct));

  TConsole.WriteLine('Installed Delphi versions:', clGreen);
  for var I := 0 to FProducts.Count - 1 do
  begin
    if I = 0 then
      TConsole.WriteLine(Format('  [%d] %s (default)', [I + 1, FProducts[I].DisplayName]))
    else
      TConsole.WriteLine(Format('  [%d] %s', [I + 1, FProducts[I].DisplayName]));
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
                Result := True;
                Exit;
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
    raise Exception.CreateFmt('No compatible package folder found for "%s". Delphi version too old?', [FVersionName]);

  Result := APackageFolders[BestKey];
end;

class function TProduct.GetProductNames: TArray<string>;
begin
  Result := [];
  var LProducts := Products;
  for var P in LProducts do
    Result := Result + [P.DisplayName];
end;

function TProduct.TestPlatformInstalled(const APlatform: string): Boolean;
begin
  Result := False;
  var Reg := TRegistry.Create(KEY_READ);
  try
    for var RegPath
        in [
            'SOFTWARE\WOW6432Node\Embarcadero\BDS\' + FBdsVersion + '\Library\' + APlatform,
            'SOFTWARE\Embarcadero\BDS\' + FBdsVersion + '\Library\' + APlatform] do
    begin
      Reg.RootKey := HKEY_LOCAL_MACHINE;
      if Reg.OpenKeyReadOnly(RegPath) then
      begin
        Reg.CloseKey;
        Result := True;
        Exit;
      end;
    end;
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('SOFTWARE\Embarcadero\BDS\' + FBdsVersion + '\Library\' + APlatform) then
    begin
      Reg.CloseKey;
      Result := True;
    end;
  finally
    Reg.Free;
  end;
end;

procedure TProduct.UpdateSearchPaths(const APlatform, AProjectDir: string; const APlatformConfig: TManifestPlatform);
var
  Reg: TRegistry;
  RegPath: string;
  Existing: string;
  ExistingList: TStringList;
  Added: TStringList;
  NewPath: string;

  procedure AppendPaths(APaths: TList<string>; const ARegValue: string);
  begin
    if APaths.IsEmpty then
      Exit;

    if Reg.ValueExists(ARegValue) then
      Existing := Reg.ReadString(ARegValue)
    else
      Existing := '';

    ExistingList := TStringList.Create;
    Added := TStringList.Create;
    try
      ExistingList.StrictDelimiter := True;
      ExistingList.Delimiter := ';';
      ExistingList.DelimitedText := Existing;

      // Remove empty entries left by trailing semicolons
      for var J := ExistingList.Count - 1 downto 0 do
        if ExistingList[J] = '' then
          ExistingList.Delete(J);

      for var LPath in APaths do
      begin
        NewPath := TPath.Combine(AProjectDir, LPath);
        if ExistingList.IndexOf(NewPath) < 0 then
        begin
          ExistingList.Add(NewPath);
          Added.Add(NewPath);
        end;
      end;

      if Added.Count > 0 then
      begin
        Reg.WriteString(ARegValue, ExistingList.DelimitedText);
        for var J := 0 to Added.Count - 1 do
          TConsole.WriteLine(Format('    + [%s] %s', [ARegValue, Added[J]]), clDkGray);
      end;
    finally
      Added.Free;
      ExistingList.Free;
    end;
  end;

begin
  RegPath := 'Software\Embarcadero\BDS\' + FBdsVersion + '\Library\' + APlatform;

  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKey(RegPath, False) then
      Exit;

    AppendPaths(APlatformConfig.SourcePath, 'Search Path');
    AppendPaths(APlatformConfig.BrowsingPath, 'Browsing Path');
    AppendPaths(APlatformConfig.DebugDCUPath, 'Debug DCU Path');

    Reg.CloseKey;
  finally
    Reg.Free;
  end;
end;

procedure TProduct.BuildPackages(
    const AProjectDir, APackageFolder: string;
    const APackages: TManifestPackageList;
    const APlatforms: TSupportedPlatforms
);
begin
  var BdsDir := FRootDir;
  var BdsCommonDir :=
      TPath.Combine(GetEnvironmentVariable('PUBLIC'), TPath.Combine('Documents\Embarcadero\Studio', FBdsVersion));
  var MsBuild := GetMsBuildPath;
  var PackagesPath := TPath.Combine(TPath.Combine(AProjectDir, 'packages'), APackageFolder);

  // Set Delphi environment variables inherited by child processes
  SetEnvironmentVariable('BDS', PChar(BdsDir));
  SetEnvironmentVariable('BDSINCLUDE', PChar(BdsDir + '\include'));
  SetEnvironmentVariable('BDSCOMMONDIR', PChar(BdsCommonDir));
  SetEnvironmentVariable('LANGDIR', 'EN');
  SetEnvironmentVariable('PLATFORM', '');

  // Prepend BDS bin dirs to PATH (no duplicates)
  var CurPath := GetEnvironmentVariable('PATH');
  var NewPath := CurPath;
  for var BinDir in [BdsDir + '\bin64', BdsDir + '\bin'] do
    if Pos(BinDir, NewPath) = 0 then
      NewPath := BinDir + ';' + NewPath;
  if NewPath <> CurPath then
    SetEnvironmentVariable('PATH', PChar(NewPath));

  // Verify all platforms are installed before starting
  for var LPlatformPair in APlatforms do
    if not TestPlatformInstalled(LPlatformPair.Key) then
      raise Exception.CreateFmt('Platform "%s" is not installed for %s.', [LPlatformPair.Key, FDisplayName]);

  var PlatformNames := TStringList.Create;
  try
    for var LPlatformPair in APlatforms do
      PlatformNames.Add(LPlatformPair.Key);

    TConsole.WriteLine('Compiling packages...', clCyan);
    TConsole.WriteLine('  MSBuild   : ' + MsBuild);
    TConsole.WriteLine('  BDS       : ' + BdsDir);
    TConsole.WriteLine('  Packages  : ' + PackagesPath);
    TConsole.WriteLine('  Platforms : ' + PlatformNames.CommaText);
    TConsole.WriteLine;
  finally
    PlatformNames.Free;
  end;

  for var LPlatformPair in APlatforms do
  begin
    var Plat := LPlatformPair.Value;

    TConsole.WriteLine('  [' + LPlatformPair.Key + ']', clDkCyan);

    for var Pkg in APackages do
    begin
      var PkgName := Pkg.Name;
      var TypeStr := string.Join(', ', Pkg.&Type.ToArray);

      var DprojPath := TPath.Combine(PackagesPath, PkgName + '.dproj');
      if not TFile.Exists(DprojPath) then
        raise Exception.CreateFmt('Package not found: %s', [DprojPath]);

      TConsole.Write(Format('    Building %s [%s]...', [PkgName, TypeStr]));

      var CmdLine :=
          Format(
              '"%s" "%s" /t:Make /p:config=Release /p:platform=%s /nologo /v:quiet',
              [MsBuild, DprojPath, LPlatformPair.Key]
          );

      var Output: string;
      var ExitCode := RunProcessWithOutput(CmdLine, Output);

      if ExitCode = 0 then
        TConsole.WriteLine(' OK', clGreen)
      else
      begin
        TConsole.WriteLine(' FAILED', clRed);
        var Lines := Output.Split([sLineBreak, #13, #10], TStringSplitOptions.ExcludeEmpty);
        for var Line in Lines do
          if ContainsText(Line, 'error') then
            TConsole.WriteLine('      ' + Line, clRed);
        raise Exception.CreateFmt('Compilation failed on package "%s" for platform "%s".', [PkgName, LPlatformPair.Key]);
      end;
    end;

    UpdateSearchPaths(LPlatformPair.Key, AProjectDir, Plat);
  end;

  TConsole.WriteLine;
  TConsole.WriteLine('All packages compiled successfully.', clGreen);
end;

procedure TProduct.Install(
    const ADependencySpec: string;
    ADatabase: TDatabase;
    ASilent, AOverwrite: Boolean;
    ADepth: Integer = 0
);
var
  DepId, ReqCommit: string;
  InstalledSha: string;
begin
  var Indent := StringOfChar(' ', (ADepth + 1) * 2);

  // Parse "owner/repo@commitsha"
  if ADependencySpec.Contains('@') then
  begin
    DepId := Trim(ADependencySpec.Split(['@'])[0]);
    ReqCommit := Trim(ADependencySpec.Split(['@'])[1]);
  end
  else
  begin
    DepId := Trim(ADependencySpec);
    ReqCommit := '';
  end;

  var Manifest := TManifest.Load(DepId);
  try
    TConsole.WriteLine(Indent + '--- ' + DepId + ' / ' + Manifest.Application.Name + ' ---', clWhite);

    // Check if already installed in the database
    InstalledSha := ADatabase.InstalledCommit(DepId, FVersionName);
    if InstalledSha <> '' then
    begin
      if (ReqCommit = '') or SameText(InstalledSha, ReqCommit) then
      begin
        TConsole.WriteLine(Indent + '[WARN] Already installed', clYellow);
        Exit;
      end
      else
      begin
        TConsole
            .WriteLine(Format('%s[WARN] Installed @ %s, required: %s', [Indent, InstalledSha, ReqCommit]), clYellow);
        if ASilent then
        begin
          TConsole.WriteLine(Indent + 'Continuing with installed version (-Silent).', clYellow);
          Exit;
        end;
        TConsole.WriteLine(Indent + '  [S] Stop');
        TConsole.WriteLine(Indent + '  [K] Keep installed version and continue');
        TConsole.WriteLine(Indent + '  [I] Install required version');
        TConsole.Write(Indent + 'Choice: ');
        var Choice := TConsole.ReadLine;
        case UpCase(Trim(Choice)[1]) of
          'K': Exit;
          'I': {continue with installation};
        else
          raise Exception.CreateFmt('Dependency commit mismatch: %s', [DepId]);
        end;
      end;
    end;

    // Recurse into sub-dependencies first
    for var LDependency in Manifest.Dependencies do
      Install(LDependency, ADatabase, ASilent, AOverwrite, ADepth + 1);

    // Resolve package folder for this Delphi version
    var PackageFolder := GetPackageFolder(Manifest.PackageOptions.PackageFolders);

    // Resolve commit (fetch latest if not pinned)
    var Parts := DepId.Split(['.']);
    var Owner := Parts[0];
    var Repo := Parts[1];
    if ReqCommit = '' then
    begin
      var RepoInfo := THttpUtils.GetGitHubInfo(Manifest.Application.Url);
      ReqCommit := RepoInfo.LatestCommit;
      Owner := RepoInfo.Owner;
      Repo := RepoInfo.Repo;
      TConsole.WriteLine(Indent + 'Using latest commit: ' + ReqCommit);
    end;

    // Download and extract
    var ZipUrl := THttpUtils.GetGitHubZipUrl(Owner, Repo, ReqCommit);
    var ProjectDir := THttpUtils.DownloadAndExtract(ZipUrl, TWorkspace.WorkDir, Manifest.Application.Name, AOverwrite, ASilent);

    // Compile
    BuildPackages(ProjectDir, PackageFolder, Manifest.Packages, Manifest.SupportedPlatforms);

    // Register in database
    ADatabase.Update(Manifest.Application.Id, ReqCommit, FVersionName);

    TConsole.WriteLine(Indent + '[DONE] ' + DepId, clGreen);
  finally
    Manifest.Free;
  end;
end;

end.
