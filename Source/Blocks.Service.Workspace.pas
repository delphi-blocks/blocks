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
unit Blocks.Service.Workspace;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.Types,
  System.Zip,
  Blocks.Model.Database,
  Blocks.Model.Config,
  Blocks.Model.Manifest,
  Blocks.JSON,
  Blocks.Core,
  Blocks.Service.Product;

type
  /// <summary>Options shared by the install/build/update/uninstall pipeline. Passed as a set so
  ///   call sites read as <c>[woOverwrite, woSilent]</c> instead of a row of positional booleans.
  ///   Not every option is meaningful for every entry point (e.g. <c>woBuildOnly</c> only applies to
  ///   install/build); the irrelevant ones are simply ignored.</summary>
  /// <remarks>
  ///   <c>woOverwrite</c>: replace the project directory if it already exists (propagates to dependencies).
  ///   <c>woBuildOnly</c>: skip the download and compile the already-extracted project.
  ///   <c>woSilent</c>: skip non-critical interactive prompts, taking the defaults.
  ///   <c>woForce</c>: on install, skip a conflicting dependency instead of raising; on uninstall, skip the
  ///   dependents confirmation prompt.
  /// </remarks>
  TWorkspaceOption = (woOverwrite, woBuildOnly, woSilent, woForce);
  TWorkspaceOptions = set of TWorkspaceOption;

  TWorkspace = class
  private
    class var
      FWorkDir: string;
      FConfig: TConfig;
      FDatabase: TDatabase;
      FDelphiRunningContinue: Boolean;
    class function GetWorkDir: string; static;
    class function GetBlocksDir: string; static;
    class procedure SetWorkDir(const AValue: string); static;

    class function GetConfig: TConfig; static;
    class function GetDatabase: TDatabase; static;
    class procedure InitializeFromSource(const ASource: string); static;
    /// <summary>Ensures <paramref name="ADir"/> does not exist before a fetch, applying the
    ///   overwrite/prompt policy when it does.</summary>
    class procedure EnsureCleanDir(const ADir: string; AOptions: TWorkspaceOptions); static;
    /// <summary>Rebuilds <c>.blocks\repository\index.json</c> from the local repository.</summary>
    class procedure RebuildIndex; static;
    /// <summary>Resolves an install/uninstall argument to a package id (<c>vendor.name</c>).</summary>
    /// <remarks>
    ///   If <paramref name="AArg"/> contains a dot it is assumed to already be an id and
    ///   returned unchanged. Otherwise the repository index is searched by name; ambiguous
    ///   matches are resolved interactively (or raise when <paramref name="ASilent"/> is true).
    /// </remarks>
    class function ResolvePackageId(const AArg: string; ASilent: Boolean = False): string; static;
    class procedure TestDelphiRunning(AProduct: TProduct); static;
    /// <summary>Resolves the Delphi product configured for the workspace.</summary>
    class function GetWorkspaceProduct: TProduct; static;
    /// <summary>Recursively installs the direct dependencies declared in a manifest.</summary>
    class procedure ResolveDependencies(AManifest: TManifest; AOptions: TWorkspaceOptions); static;
    /// <summary>Fetches (unless build-only), compiles, registers the search paths and records
    ///   in the database a single already-resolved package. Does NOT resolve dependencies.</summary>
    class procedure BuildAndRegisterPackage(
        AManifest: TManifest;
        AProduct: TProduct;
        AOptions: TWorkspaceOptions
    ); static;
    /// <summary>Returns the ids of installed packages that declare <paramref name="APackageId"/>
    ///   among their direct dependencies (reverse dependencies).</summary>
    class function FindDependents(const APackageId: string): TArray<string>; static;
    /// <summary>Returns every installed package that depends on <paramref name="APackageId"/>
    ///   directly or transitively, in topological order (a package always comes after the
    ///   dependencies it requires within the set). The visited set also guards against cycles.</summary>
    class function FindAllDependents(const APackageId: string): TArray<string>; static;
    class constructor Create;
    class destructor Destroy;
  public
    /// <summary>Get a refernce to the database of installed packages.</summary>
    class property Database: TDatabase read GetDatabase;
    /// <summary>Get a refernce to the workspace configuration.</summary>
    class property Config: TConfig read GetConfig;
    /// <summary>Initialises a directory as a Blocks workspace and sets <see cref="WorkDir"/>.</summary>
    /// <param name="AWorkDir">Directory to initialise as the workspace root.</param>
    /// <param name="AProduct">Target Delphi version name (e.g. <c>delphi13</c>); empty to select interactively.</param>
    /// <param name="ASources">Comma-separated package source URL(s) to use; empty keeps the configured/default source.</param>
    /// <param name="APlatforms">Comma-separated platform names to target; empty means "all" (and, when the
    ///   Delphi version is chosen interactively, the user is prompted to pick a subset).</param>
    /// <remarks>
    ///   Performs the following steps in order:
    ///   1. Sets <see cref="WorkDir"/> to <c>AWorkDir</c> and creates <see cref="BlocksDir"/> if absent.
    ///   2. Selects the target Delphi version and persists it in the workspace configuration.
    ///   3. Downloads the package repository archive from the canonical GitHub source
    ///      (<see cref="BlocksRepositoryUrl"/>).
    ///   4. Extracts the archive and installs <c>repository\</c> under <see cref="BlocksDir"/>.
    ///   Prompts the user before overwriting an existing repository folder.
    /// </remarks>
    class procedure Initialize(
        const AWorkDir, AProduct, ARegistryKey: string;
        const ASources: string = '';
        const APlatforms: string = ''
    ); static;

    /// <summary>Refreshes the local repository cache by re-downloading the package list.</summary>
    class procedure UpdateRepositoryCache(const AWorkDir: string); static;

    /// <summary>Downloads, compiles and registers a package in the workspace.</summary>
    /// <param name="APackageName">Package id (<c>vendor.name</c>) or package name; resolved via the repository index.</param>
    /// <param name="AVersionConstraint">Version constraint string (e.g. <c>1.2.0</c>, <c>>=1.0.0</c>); empty for any version.</param>
    /// <param name="AOptions">Install options (see <see cref="TWorkspaceOption"/>): <c>woOverwrite</c>,
    ///   <c>woBuildOnly</c>, <c>woSilent</c>, <c>woForce</c>.</param>
    /// <param name="AIsDependency">When <c>True</c> the call is a transitive dependency resolution, not a
    ///   top-level install; suppresses the "use update" hint on a version conflict (where switching the
    ///   installed version would break another dependent rather than fix anything).</param>
    class procedure Install(
        const APackageName, AVersionConstraint: string;
        AOptions: TWorkspaceOptions;
        AIsDependency: Boolean = False
    ); static;

    /// <summary>Removes a previously installed package from the workspace and the database.</summary>
    /// <param name="APackageName">Package id (<c>vendor.name</c>) or package name; resolved via the repository index.</param>
    /// <param name="AOptions">Uninstall options (see <see cref="TWorkspaceOption"/>); only <c>woForce</c>
    ///   is relevant here: it skips the confirmation prompt shown when other installed packages still
    ///   depend on this one, removing it anyway.</param>
    class procedure Uninstall(const APackageName: string; AOptions: TWorkspaceOptions); static;

    /// <summary>Updates an already-installed package to a new version, then recompiles its
    ///   dependents so their DCUs are rebuilt against the new version.</summary>
    /// <param name="APackageName">Package id (<c>vendor.name</c>) or package name; must be installed.</param>
    /// <param name="AVersionConstraint">Target version/constraint; empty proposes the highest release
    ///   within the installed major version (interactively, unless <c>woSilent</c> is set).</param>
    /// <param name="AOptions">Update options (see <see cref="TWorkspaceOption"/>); only <c>woSilent</c> is
    ///   relevant: it skips the interactive version prompt, taking the proposed version.</param>
    /// <remarks>When the compatibility checks report problems the update is refused (the user
    ///   must uninstall or update the conflicting packages first); it never leaves the workspace
    ///   in an invalid state. On success every direct and transitive dependent is recompiled.</remarks>
    class procedure Update(const APackageName, AVersionConstraint: string; AOptions: TWorkspaceOptions); static;

    /// <summary>Root directory of the current workspace.</summary>
    /// <remarks>
    ///   Returns the value set by the last call to <see cref="Initialize"/> or an explicit
    ///   property assignment. Defaults to the process current directory when not set.
    /// </remarks>
    class property WorkDir: string read GetWorkDir write SetWorkDir;

    /// <summary>Path to the Blocks settings directory (<c>WorkDir\.blocks</c>).</summary>
    class property BlocksDir: string read GetBlocksDir;

    class function Exists: Boolean;
  end;

implementation

uses
  System.JSON,
  System.Generics.Defaults,
  Blocks.Console,
  Blocks.Http,
  Blocks.GitHub,
  Blocks.Service.Fetcher,
  Blocks.Service.Script,
  Blocks.Model.Package;

procedure NormalizePath(var APaths: TArray<string>; const ABasePath: string; AEnvironmentVariable: TStrings);
begin
  for var I := Low(APaths) to High(APaths) do
  begin
    APaths[I] := ExpandVariables(APaths[I], AEnvironmentVariable);
    if TPath.IsRelativePath(APaths[I]) then
    begin
      APaths[I] := ExpandFileName(TPath.Combine(ABasePath, APaths[I]));
    end;
  end;
end;

function GetDProjPath(
    const AProjectDir: string;
    AProduct: TProduct;
    AManifest: TManifest;
    APackageName: string
): string;
begin
  var LPackagesPath := AProduct.GetPackagesPath(AProjectDir, AManifest);
  Result := TPath.Combine(LPackagesPath, AProduct.ExpandPackageName(APackageName) + '.dproj');
end;

function GetPlatformPaths(
    const AManifest: TManifest;
    const ADprojName, AProjectDir, APlatform: string;
    AEnvironmentVariable: TStrings
): TPlatformPaths;
begin
  var LPlatformManifest := AManifest.Platforms[APlatform];
  var LPackage := TPackageProject.LoadFromFile(ADprojName);
  try
    AEnvironmentVariable.Values['Platform'] := APlatform;
    var LDLLSuffix := LPackage.LibSuffix;
    if SameText(LDLLSuffix, 'AUTO') then
      LDLLSuffix := AEnvironmentVariable.Values['PackageVersion'];

    AEnvironmentVariable.Values['DllSuffix'] := LDLLSuffix;

    var LSourcePath := LPlatformManifest.SourcePath.ToStringArray;
    NormalizePath(LSourcePath, AProjectDir, AEnvironmentVariable);

    // DCU paths are registered using the IDE's $(BLOCKSDIR) environment variable
    // (the workspace's .blocks folder) instead of an absolute path:
    //   $(BLOCKSDIR)\lib\<manifest name>\<Platform>[\debug]
    var LDcuBase := '$(BLOCKSDIR)\lib\' + AManifest.Name;

    Result.SourcePath := LSourcePath;
    Result.ReleaseDCUPath := [LDcuBase + '\' + APlatform];
    Result.DebugDCUPath := [LDcuBase + '\' + APlatform + '\debug'];
  finally
    LPackage.Free;
  end;
end;

// Runs the manifest scripts registered for an install/uninstall event
// (beforeInstall / afterInstall / beforeUninstall / afterUninstall), once per
// manifest. At this level only the workspace- and project-level paths are
// meaningful, so only those variables are exposed.
procedure RunManifestScripts(
    const AManifest: TManifest;
    const AEvent, AWorkspaceDir, AProjectDir: string;
    AProduct: TProduct;
    AConfig: TConfig
);
begin
  var LEnv := TStringList.Create;
  try
    LEnv.Values['WORKSPACE_PATH'] := AWorkspaceDir;
    LEnv.Values['PROJECT_PATH'] := AProjectDir;
    // The package-version suffix lets scripts target .dproj names that embed it
    // (e.g. $(PACKAGE_VERSION) in the "compile" command's path).
    LEnv.Values['PACKAGE_VERSION'] := AProduct.PackageVersionSuffix;
    // AProduct implements IScriptHelper, giving commands like "compile" a compiler;
    // AConfig carries the tool architecture a "compile" command needs.
    TScriptRunner.RunEvent(AManifest, AEvent, LEnv, AProduct, AConfig);
  finally
    LEnv.Free;
  end;
end;

{ TWorkspace }

class function TWorkspace.GetConfig: TConfig;
begin
  if not Assigned(FConfig) then
  begin
    FConfig := TConfig.Create(WorkDir);
    FConfig.Load;
  end;
  Result := FConfig;
end;

class function TWorkspace.GetDatabase: TDatabase;
begin
  if not Assigned(FDatabase) then
  begin
    FDatabase := TDatabase.Create;
    FDatabase.Load;
  end;
  Result := FDatabase;
end;

class function TWorkspace.GetWorkDir: string;
begin
  if FWorkDir <> '' then
    Result := FWorkDir
  else
    Result := GetCurrentDir;
end;

class constructor TWorkspace.Create;
begin
  FConfig := nil;
  FDatabase := nil;
end;

class destructor TWorkspace.Destroy;
begin
  FConfig.Free;
  FDatabase.Free;
end;

class function TWorkspace.Exists: Boolean;
begin
  Result :=
      TDirectory.Exists(TWorkspace.BlocksDir) and TFile.Exists(TPath.Combine(TWorkspace.BlocksDir, 'workspace.json'));
end;

class function TWorkspace.GetBlocksDir: string;
begin
  Result := TPath.Combine(GetWorkDir, '.blocks');
end;

class procedure TWorkspace.SetWorkDir(const AValue: string);
begin
  FWorkDir := ExcludeTrailingPathDelimiter(AValue);
end;

class function TWorkspace.ResolvePackageId(const AArg: string; ASilent: Boolean): string;
begin
  if AArg.Contains('.') then
    Exit(AArg);

  var LIndex := TRepositoryIndex.Create;
  try
    LIndex.Load;
    var LMatches := LIndex.FindByName(AArg);
    if Length(LMatches) = 0 then
      raise Exception.CreateFmt('Package "%s" not found in repository. Try to update the repository', [AArg]);
    if Length(LMatches) = 1 then
      Exit(LMatches[0].Id);

    if ASilent then
      raise Exception.CreateFmt(
          'Package name "%s" is ambiguous: %d matches. Use the full id (vendor.name)',
          [AArg, Length(LMatches)]);

    TConsole.WriteLine(Format('Multiple packages match name "%s":', [AArg]), clYellow);
    for var I := 0 to High(LMatches) do
      TConsole.WriteLine(Format('  [%d] %s', [I + 1, LMatches[I].Id]));
    TConsole.WriteLine;
    TConsole.Write(Format('Select [1-%d]: ', [Length(LMatches)]));
    var LInput := Trim(TConsole.ReadLine);
    var LIdx: Integer;
    if not (TryStrToInt(LInput, LIdx) and (LIdx >= 1) and (LIdx <= Length(LMatches))) then
      raise Exception.Create('Invalid selection');
    Result := LMatches[LIdx - 1].Id;
  finally
    LIndex.Free;
  end;
end;

class procedure TWorkspace.EnsureCleanDir(const ADir: string; AOptions: TWorkspaceOptions);
begin
  if not TDirectory.Exists(ADir) then
    Exit;

  if woOverwrite in AOptions then
  begin
    TDirectory.Delete(ADir, True);
    TConsole.WriteLine(Format('Directory "%s" removed.', [ADir]), clYellow);
  end
  else if woSilent in AOptions then
    raise Exception.CreateFmt('Directory "%s" already exists. Use /overwrite to replace it.', [ADir])
  else
  begin
    TConsole.WriteLine(Format('Directory "%s" already exists.', [ADir]), clYellow);
    TConsole.Write('Overwrite? [Y/N] (default: N): ');
    var LConfirm := TConsole.ReadLine;
    if not SameText(Trim(LConfirm), 'Y') then
      raise Exception.Create('Operation cancelled by user.');
    TDirectory.Delete(ADir, True);
    TConsole.WriteLine('Directory removed.', clYellow);
  end;
end;

class procedure TWorkspace.Initialize(
    const AWorkDir, AProduct, ARegistryKey: string;
    const ASources: string;
    const APlatforms: string
);
begin
  SetWorkDir(AWorkDir);

  if not TDirectory.Exists(GetBlocksDir) then
  begin
    TDirectory.CreateDirectory(GetBlocksDir);
    TConsole.WriteLine('Created: ' + GetBlocksDir, clGreen);
  end;

  if ASources <> '' then
    Config.SetValue('sources', ASources);

  // Select Delphi version: explicit /product wins; else reuse the one already
  // saved in the workspace config; else prompt interactively.
  var LProductName := AProduct;
  var LRegistryKey := ARegistryKey;
  if LProductName = '' then
  begin
    LProductName := Config.Product;
    if LRegistryKey = '' then
      LRegistryKey := Config.RegistryKey;
  end;

  var LProductChosenInteractively := LProductName = '';
  var LSelectedProduct: TProduct;
  if LProductChosenInteractively then
    LSelectedProduct := TProduct.Choose
  else
    LSelectedProduct :=
        TProduct.Find(
            LProductName,
            if LRegistryKey = '' then 'BDS'
            else LRegistryKey
        );
  Config.Product := LSelectedProduct.VersionName;
  Config.RegistryKey := LSelectedProduct.RegistryKey;
  TConsole.WriteLine('Selected version: ' + LSelectedProduct.DisplayName, clGreen);
  if not SameText(LSelectedProduct.RegistryKey, 'BDS') then
    TConsole.WriteLine('Registry key    : ' + LSelectedProduct.RegistryKey, clGreen);
  TConsole.WriteLine;

  // Select target platforms: explicit /platforms wins; otherwise, when the Delphi
  // version was chosen interactively and no platforms are configured yet, prompt
  // for a subset. An empty list means "all platforms".
  if APlatforms <> '' then
  begin
    var LPlatforms := LSelectedProduct.NormalizePlatforms(APlatforms.Split([',']));
    Config.Platforms.Clear;
    for var LPlatform in LPlatforms do
      Config.Platforms.Add(LPlatform);
  end
  else if LProductChosenInteractively and (Config.Platforms.Count = 0) then
  begin
    var LPlatforms := LSelectedProduct.ChoosePlatforms;
    Config.Platforms.Clear;
    for var LPlatform in LPlatforms do
      Config.Platforms.Add(LPlatform);
    TConsole.WriteLine;
  end;

  if Config.Platforms.Count = 0 then
    TConsole.WriteLine('Selected platforms: all', clGreen)
  else
    TConsole.WriteLine('Selected platforms: ' + string.Join(', ', Config.Platforms.ToStringArray), clGreen);
  TConsole.WriteLine;

  if Config.Sources.Count = 0 then
    raise Exception.Create('No sources configured. Use "blocks config /add sources=<url>" to add one.');

  var RepoDir := TPath.Combine(GetBlocksDir, 'repository');
  if TDirectory.Exists(RepoDir) then
  begin
    TConsole.WriteLine('Workspace already initialised, updating repository...', clCyan);
    TDirectory.Delete(RepoDir, True);
  end;

  for var LSource in Config.Sources do
    InitializeFromSource(LSource);

  RebuildIndex;

  if Config.UpdateDCPSearchPath then
    LSelectedProduct.CheckDCPPath(AWorkDir);

  LSelectedProduct.CheckEnvironment(AWorkDir);

  Config.Save;
  Database.TouchRepository;
end;

class procedure TWorkspace.RebuildIndex;
begin
  TConsole.WriteLine('Building repository index...', clCyan);
  var LIndex := TRepositoryIndex.Build;
  try
    LIndex.Save;
    TConsole.WriteLine(Format('Index built: %d packages', [LIndex.Entries.Count]), clGreen);
  finally
    LIndex.Free;
  end;
end;

class procedure TWorkspace.InitializeFromSource(const ASource: string);
begin
  var RepoDir := TPath.Combine(GetBlocksDir, 'repository');
  var DownloadDir := '';
  var SourceRepo: string;

  if ASource.StartsWith('http', True) then
  begin
    DownloadDir := TPath.Combine(GetBlocksDir, 'download');
    var ZipPath := TPath.Combine(DownloadDir, 'repository.zip');

    TFileUtils.SafeDeleteDirectory(DownloadDir);
    TDirectory.CreateDirectory(DownloadDir);

    TConsole.WriteLine(Format('Fetching repository info from "%s"...', [ASource]), clCyan);
    var RepoInfo := TGitHub.GetGitHubInfo(ASource);
    TConsole.WriteLine('  Branch : ' + RepoInfo.DefaultBranch);
    TConsole.WriteLine('  Latest : ' + RepoInfo.LatestCommit);
    TConsole.WriteLine;

    var ZipUrl := TGitHub.GetGitHubZipUrl(RepoInfo.Owner, RepoInfo.Repo, RepoInfo.LatestCommit);

    TConsole.WriteLine('Downloading repository...', clCyan);
    THttpUtils.DownloadFile(ZipUrl, ZipPath);

    TConsole.WriteLine('Extracting...', clCyan);
    var ExtractDir := TPath.Combine(DownloadDir, 'extract');
    TDirectory.CreateDirectory(ExtractDir);
    TZipFile.ExtractZipFile(ZipPath, ExtractDir);

    // GitHub wraps content in a subdirectory (e.g. "my-blocks-repository-abc1234")
    var InnerDirs := TDirectory.GetDirectories(ExtractDir);
    if Length(InnerDirs) = 0 then
      raise Exception.Create('Unexpected zip structure: no subdirectory found.');

    SourceRepo := TPath.Combine(InnerDirs[0], '.blocks\repository');
    if not TDirectory.Exists(SourceRepo) then
      raise Exception.Create('Repository folder not found in downloaded archive: .blocks\repository');
  end
  else
  begin
    SourceRepo := TPath.Combine(ASource, '.blocks\repository');
    if not TDirectory.Exists(SourceRepo) then
      raise Exception.CreateFmt('Source folder not found: %s', [SourceRepo]);
    TConsole.WriteLine('Using local repository: ' + SourceRepo, clCyan);
    TConsole.WriteLine;
  end;

  TDirectory.Copy(SourceRepo, RepoDir);
  TConsole.WriteLine('Repository updated: ' + RepoDir, clGreen);

  if DownloadDir <> '' then
    TFileUtils.SafeDeleteDirectory(DownloadDir);
end;

class procedure TWorkspace.TestDelphiRunning(AProduct: TProduct);
begin
  if FDelphiRunningContinue then
    Exit;

  if not AProduct.IsRunning then
    Exit;

  TConsole.WriteLine;
  TConsole.WriteWarning('The following Delphi instance is currently open:');
  TConsole.WriteLine('  - ' + AProduct.DisplayName, clYellow);
  TConsole.WriteLine('  Closing Delphi before continuing is strongly recommended,', clYellow);
  TConsole.WriteLine('  otherwise the installation may not work correctly.', clYellow);
  TConsole.WriteLine;
  TConsole.Write('Continue anyway? [y/N]: ');
  var LAnswer := Trim(TConsole.ReadLine);
  if (LAnswer = '') or not SameText(Copy(LAnswer, 1, 1), 'y') then
  begin
    TConsole.WriteLine('Aborted.', clYellow);
    Halt(1);
  end;

  FDelphiRunningContinue := True;
end;

class function TWorkspace.GetWorkspaceProduct: TProduct;
begin
  var LProduct := Config.Product;
  if LProduct = '' then
    raise Exception.Create('No Delphi version configured. Run "blocks init /product <version>" first.');
  Result := TProduct.Find(LProduct, Config.RegistryKey);
  TestDelphiRunning(Result);
end;

class function TWorkspace.FindDependents(const APackageId: string): TArray<string>;
begin
  Result := [];
  // Dependencies uses a case-insensitive comparer, so ContainsKey matches the id
  // regardless of casing.
  for var LEntry in Database.Packages do
    if not SameText(LEntry.Key, APackageId) and LEntry.Value.Dependencies.ContainsKey(APackageId) then
      Result := Result + [LEntry.Key];
end;

class function TWorkspace.FindAllDependents(const APackageId: string): TArray<string>;
var
  LClosure: TDictionary<string, Boolean>;
  LVisited: TDictionary<string, Boolean>;
  LOrdered: TList<string>;

  // Reverse-transitive closure: collect every package that depends on AId, then
  // their dependents, and so on. The closure membership check stops cycles.
  procedure CollectClosure(const AId: string);
  begin
    for var LDependent in FindDependents(AId) do
      if not LClosure.ContainsKey(LDependent) then
      begin
        LClosure.Add(LDependent, True);
        CollectClosure(LDependent);
      end;
  end;

  // Post-order DFS over the forward dependency edges restricted to the closure:
  // a package is emitted only after the dependencies it requires within the set,
  // yielding a topological order (dependencies before dependents).
  procedure TopoVisit(const AId: string);
  begin
    if LVisited.ContainsKey(AId) then
      Exit;
    LVisited.Add(AId, True);
    for var LDep in Database.Packages[AId].Dependencies.Keys do
      if LClosure.ContainsKey(LDep) then
        TopoVisit(LDep);
    LOrdered.Add(AId);
  end;

begin
  LClosure := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  LVisited := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  LOrdered := TList<string>.Create;
  try
    CollectClosure(APackageId);
    for var LId in LClosure.Keys do
      TopoVisit(LId);
    Result := LOrdered.ToArray;
  finally
    LOrdered.Free;
    LVisited.Free;
    LClosure.Free;
  end;
end;

class procedure TWorkspace.ResolveDependencies(AManifest: TManifest; AOptions: TWorkspaceOptions);
begin
  if AManifest.Dependencies.IsEmpty then
    Exit;

  TConsole.WriteLine('Resolving dependencies...', clCyan);
  for var LDependency in AManifest.Dependencies do
    TWorkspace.Install(LDependency.Key, LDependency.Value, AOptions, True);
  TConsole.WriteLine;
end;

class procedure TWorkspace.BuildAndRegisterPackage(
    AManifest: TManifest;
    AProduct: TProduct;
    AOptions: TWorkspaceOptions
);
begin
  var LProjectDir := TPath.Combine(WorkDir, AManifest.Name);

  // beforeInstall scripts
  RunManifestScripts(AManifest, TScriptRunner.EventBeforeInstall, WorkDir, LProjectDir, AProduct, Config);

  if not (woBuildOnly in AOptions) then
  begin
    // Fetch the package sources according to the repository type
    TConsole.WriteLine('--- ' + AManifest.Id + ' / ' + AManifest.Name + ' ---', clWhite);
    TConsole.WriteLine('Version: ' + AManifest.Version, clCyan);
    EnsureCleanDir(LProjectDir, AOptions);
    var LFetcher := TRepositoryFetcher.ForRepository(AManifest.Repository);
    LFetcher.FetchTo(AManifest.Repository, LProjectDir);
    TConsole.WriteLine('Project downloaded to: ' + LProjectDir, clGreen);
    TConsole.WriteLine;
  end
  else
  begin
    if not TDirectory.Exists(LProjectDir) then
      raise Exception.CreateFmt('Build-only mode: project directory not found: %s', [LProjectDir]);
    TConsole.WriteLine;
  end;

  // Compile (restricted to the workspace's enabled platforms, if any)
  AProduct.BuildPackages(WorkDir, LProjectDir, AManifest, Config);

  // Update product paths
  var LEnvironmentVariables := TStringList.Create;
  try
    AProduct.FillEnvironmentVariables(LEnvironmentVariables);
    for var LPlatformPair in AManifest.Platforms do
    begin
      // Skip platforms the workspace does not target (empty filter = all).
      if not Config.IsPlatformEnabled(LPlatformPair.Key) then
        Continue;

      var LPackagesPath := AProduct.GetPackagesPath(LProjectDir, AManifest);

      for var LPackage in AManifest.Packages do
      begin
        // Packages that do not target this product were never built, so skip their paths too.
        if not LPackage.SupportsProduct(AProduct.VersionName) then
          Continue;

        // Design-time packages are not built on runtime-only platforms, so skip their paths too.
        if LPlatformPair.Value.RuntimeOnly and LPackage.IsDesignTime then
          Continue;

        var DprojPath := TPath.Combine(LPackagesPath, AProduct.ExpandPackageName(LPackage.Name) + '.dproj');
        var LPlatformPaths :=
            GetPlatformPaths(AManifest, DprojPath, LProjectDir, LPlatformPair.Key, LEnvironmentVariables);
        AProduct.UpdateSearchPaths(LPlatformPair.Key, LProjectDir, LPlatformPaths);
      end;
    end;
  finally
    LEnvironmentVariables.Free;
  end;

  // Update database (record the direct dependencies too)
  if not (woBuildOnly in AOptions) then
    Database.Update(AManifest.Id, AManifest.Version, AManifest.Dependencies);

  // afterInstall scripts
  RunManifestScripts(AManifest, TScriptRunner.EventAfterInstall, WorkDir, LProjectDir, AProduct, Config);

  TConsole.WriteLine;
  TConsole.WriteLine('============================================', clGreen);
  TConsole.WriteLine('  Done!', clGreen);
  TConsole.WriteLine('  Project  : ' + LProjectDir, clGreen);
  TConsole.WriteLine('  Packages : ' + AProduct.GetPackagesPath(LProjectDir, AManifest), clGreen);
  TConsole.WriteLine('============================================', clGreen);
  TConsole.WriteLine;
end;

class procedure TWorkspace.Install(
    const APackageName, AVersionConstraint: string;
    AOptions: TWorkspaceOptions;
    AIsDependency: Boolean
);
begin
  var LPackageId := ResolvePackageId(APackageName, woSilent in AOptions);
  var LManifest := TManifest.GetManifest(LPackageId, AVersionConstraint);
  try
    TConsole.WriteLine('Config: ' + LPackageId, clDkGray);
    TConsole.WriteLine;

    TConsole.WriteLine('Workspace: ' + WorkDir, clDkGray);
    TConsole.WriteLine;

    // Step 3 — Delphi version (read from workspace configuration)
    var LSelectedProduct := GetWorkspaceProduct;

    // Step 4 — In build-only mode the package must already be installed
    if woBuildOnly in AOptions then
    begin
      if Database.InstalledVersion(LManifest.Id) = '' then
        raise Exception.CreateFmt(
            'Cannot build %s: the package is not installed. Run "blocks install %s" first.',
            [LManifest.Id, LManifest.Id]);
    end
    // Step 4b — Version compatibility check (unless -Overwrite)
    else if not (woOverwrite in AOptions) then
    begin
      var LInstalledVer := Database.InstalledVersion(LManifest.Id);
      if LInstalledVer <> '' then
      begin
        var LInstalledSemVer: TSemVer;
        if TSemVer.TryParse(LInstalledVer, LInstalledSemVer)
            and LInstalledSemVer.MatchesConstraint(AVersionConstraint) then
        begin
          TConsole.WriteLine('Already installed: ' + LManifest.Id + ' ' + LInstalledVer, clGreen);
          TConsole.WriteLine;
          Exit;
        end
        else
        begin
          if woForce in AOptions then
          begin
            TConsole.WriteWarning(
                Format(
                    'Version conflict: %s installed %s, required %s — skipping (/force)',
                    [LManifest.Id, LInstalledVer, AVersionConstraint]
                )
            );
            TConsole.WriteLine;
            Exit;
          end
          else
          begin
            var LMessage :=
                Format(
                    'Version conflict: %s installed %s, required %s',
                    [LManifest.Id, LInstalledVer, AVersionConstraint]
                );
            // Only suggest "update" for a top-level install: there switching the
            // installed version is what the user wants. For a transitive dependency
            // the conflict is structural (another dependent pinned it), so update
            // would not help and the hint would be misleading.
            if not AIsDependency then
              LMessage :=
                  LMessage
                      + sLineBreak
                      + Format(
                          'To change the installed version run: blocks update %s@%s',
                          [LManifest.Id, AVersionConstraint]);
            raise Exception.Create(LMessage);
          end;
        end;
      end;
    end;

    // Step 5 — Make sure the package targets the selected Delphi version before
    // downloading anything, so an unsupported version fails fast.
    if not LManifest.IsProductSupported(LSelectedProduct.VersionName) then
      raise Exception
          .CreateFmt('No compatible package found for "%s". Delphi version too old?', [LSelectedProduct.DisplayName]);

    // Step 6 — Dependencies
    ResolveDependencies(LManifest, AOptions);

    // Steps 6.5–11 — fetch, compile, register search paths, record in database,
    // run scripts and print the completion banner for this package.
    BuildAndRegisterPackage(LManifest, LSelectedProduct, AOptions);
  finally
    LManifest.Free;
  end;
end;

class procedure TWorkspace.Uninstall(const APackageName: string; AOptions: TWorkspaceOptions);
begin
  var LPackageId := ResolvePackageId(APackageName, woSilent in AOptions);
  TConsole.WriteLine('Config: ' + LPackageId, clDkGray);
  TConsole.WriteLine;

  TConsole.WriteLine('Workspace: ' + WorkDir, clDkGray);
  TConsole.WriteLine;

  // Step 3 — Delphi version (read from workspace configuration)
  var LSelectedProduct := GetWorkspaceProduct;

  // Step 4 — Check that the package is actually installed
  var LInstalledVer := Database.InstalledVersion(LPackageId);
  if LInstalledVer = '' then
  begin
    TConsole.WriteWarning('Not installed: ' + LPackageId);
    TConsole.WriteLine;
    Exit;
  end;

  // Step 4.4 — Warn if other installed packages still depend on this one. The
  // dependency is removed anyway if the user confirms (or /force is given): a
  // dependency may also be used directly, so removal is always the user's call.
  var LDependents := FindDependents(LPackageId);

  if Length(LDependents) > 0 then
  begin
    TConsole.WriteWarning(Format('%s is required by: %s', [LPackageId, string.Join(', ', LDependents)]));
    if woForce in AOptions then
      TConsole.WriteLine('Removing anyway (/force).', clYellow)
    else
    begin
      TConsole.Write('Remove it anyway? [y/N]: ');
      var LAnswer := Trim(TConsole.ReadLine);
      if (LAnswer = '') or not SameText(Copy(LAnswer, 1, 1), 'y') then
      begin
        TConsole.WriteLine('Aborted.', clYellow);
        TConsole.WriteLine;
        Exit;
      end;
    end;
    TConsole.WriteLine;
  end;

  var LManifest := TManifest.GetManifest(LPackageId, LInstalledVer);
  try
    var LProjectDir := TPath.Combine(WorkDir, LManifest.Name);

    // Step 4.5 — beforeUninstall scripts (project files still present)
    RunManifestScripts(LManifest, TScriptRunner.EventBeforeUninstall, WorkDir, LProjectDir, LSelectedProduct, Config);

    // Step 5 - Unregister all packages
    var LEnvironmentVariables := TStringList.Create;
    try
      LSelectedProduct.FillEnvironmentVariables(LEnvironmentVariables);
      for var LPackage in LManifest.Packages do
      begin
        // Packages that do not target this product were never installed, so skip unregistering them.
        if not LPackage.SupportsProduct(LSelectedProduct.VersionName) then
          Continue;

        var LPackagesPath := LSelectedProduct.GetPackagesPath(LProjectDir, LManifest);
        var DprojPath := TPath.Combine(LPackagesPath, LSelectedProduct.ExpandPackageName(LPackage.Name) + '.dproj');
        var LPackageProject := TPackageProject.LoadFromFile(DprojPath);
        try
          for var LPlatformPair in LManifest.Platforms do
          begin
            // Skip platforms the workspace does not target (empty filter = all),
            // mirroring the install-time filter so we only clean what we built.
            if not Config.IsPlatformEnabled(LPlatformPair.Key) then
              Continue;

            // Mirror the install/build filter: only platforms that were actually
            // buildable (active + compiler installed) ever produced output to
            // clean up, so skip the rest to avoid spurious delete warnings.
            if not LSelectedProduct.IsPlatformBuildable(LPlatformPair.Key) then
              Continue;

            if LPackage.IsDesignTime and (not LSelectedProduct.DesignTimeSupport(LPlatformPair.Key)) then
              Continue;

            if LPackage.IsDesignTime then
              LSelectedProduct.UninstallPackage(LPackage, WorkDir, DprojPath, LPlatformPair);

            var LPlatformPaths :=
                GetPlatformPaths(LManifest, DprojPath, LProjectDir, LPlatformPair.Key, LEnvironmentVariables);
            LSelectedProduct.DeleteSearchPaths(LPlatformPair.Key, LProjectDir, LPlatformPaths);

            LSelectedProduct.RemovePackage(WorkDir, LPackageProject, LPlatformPair);
          end;
        finally
          LPackageProject.Free;
        end;
      end;
    finally
      LEnvironmentVariables.Free;
    end;

    // Step 5.5 — Unregister any IDE experts pointing into this package's blocks lib folder
    LSelectedProduct.UnregisterExperts(WorkDir, LManifest.Name);

    // Step 6 — Remove project directory
    if TDirectory.Exists(LProjectDir) then
    begin
      TDirectory.Delete(LProjectDir, True);
      TConsole.WriteLine('Removed: ' + LProjectDir);
    end
    else
      TConsole.WriteLine('Directory not found: ' + LProjectDir, clYellow);

    // Step 6.5 — Remove the package's DCU output folder (.blocks\lib\<name>).
    // RemovePackage only deletes the bpl/dcp/rsm artifacts, so the DCU tree
    // produced under $(BLOCKSDIR)\lib\<name> would otherwise be left orphaned.
    var LDcuDir := TPath.Combine([WorkDir, '.blocks', 'lib', LManifest.Name]);
    if TDirectory.Exists(LDcuDir) then
    begin
      TDirectory.Delete(LDcuDir, True);
      TConsole.WriteLine('Removed: ' + LDcuDir);
    end;

    // Step 7 — Remove from database
    Database.RemoveEntry(LManifest.Id);

    // Step 8 — afterUninstall scripts
    RunManifestScripts(LManifest, TScriptRunner.EventAfterUninstall, WorkDir, LProjectDir, LSelectedProduct, Config);

    TConsole.WriteLine;
    TConsole.WriteLine('Uninstalled: ' + LManifest.Name + ' ' + LInstalledVer, clGreen);
    TConsole.WriteLine;
  finally
    LManifest.Free;
  end;
end;

class procedure TWorkspace.Update(const APackageName, AVersionConstraint: string; AOptions: TWorkspaceOptions);
begin
  var LPackageId := ResolvePackageId(APackageName, woSilent in AOptions);
  TConsole.WriteLine('Config: ' + LPackageId, clDkGray);
  TConsole.WriteLine;
  TConsole.WriteLine('Workspace: ' + WorkDir, clDkGray);
  TConsole.WriteLine;

  // Step 1 — The package must already be installed
  var LInstalledVer := Database.InstalledVersion(LPackageId);
  if LInstalledVer = '' then
    raise Exception.CreateFmt(
        'Cannot update %s: the package is not installed. Run "blocks install %s" first.',
        [LPackageId, LPackageId]);
  var LInstalledSemVer := TSemVer.Parse(LInstalledVer);

  // Step 2 — Delphi version (resolved quietly; the delegated uninstall/install print it)
  var LSelectedProduct := GetWorkspaceProduct;

  // Step 3 — Determine the target version
  var LTargetVer: string;
  if AVersionConstraint <> '' then
  begin
    // Explicit @version/constraint: resolve to the best matching available version
    // (a downgrade is allowed too).
    var LResolved := TManifest.GetManifest(LPackageId, AVersionConstraint);
    try
      LTargetVer := LResolved.Version;
    finally
      LResolved.Free;
    end;
  end
  else
  begin
    // No version given: propose the highest release within the installed major.
    var LVersions := TManifest.GetVersions(LPackageId);
    var LMaxSameMajor: TSemVer;
    if not TSemVer.BestMatch(LVersions, IntToStr(LInstalledSemVer.Major) + '.*', LMaxSameMajor) then
      LMaxSameMajor := LInstalledSemVer;

    // Inform when a newer major exists, so the user can target it explicitly.
    var LMaxOverall: TSemVer;
    if TSemVer.BestMatch(LVersions, '*', LMaxOverall) and (LMaxOverall.Major > LInstalledSemVer.Major) then
      TConsole.WriteWarning(
          Format(
              'A newer major version is available: %s. Use "%s@%s" to target it.',
              [LMaxOverall.ToString, LPackageId, LMaxOverall.ToString]
          )
      );

    TConsole.WriteLine(Format('Installed: %s %s', [LPackageId, LInstalledVer]), clCyan);

    // Nothing newer within the installed major: don't prompt for a no-op update.
    if LMaxSameMajor <= LInstalledSemVer then
    begin
      TConsole.WriteLine(
          Format('Already at the latest version within major %d (%s).', [LInstalledSemVer.Major, LInstalledVer]),
          clGreen
      );
      TConsole.WriteLine;
      Exit;
    end;

    TConsole.WriteLine(Format('Latest within major %d: %s', [LInstalledSemVer.Major, LMaxSameMajor.ToString]), clCyan);

    if woSilent in AOptions then
      LTargetVer := LMaxSameMajor.ToString
    else
    begin
      TConsole.Write(Format('Update to %s? [Y to confirm / version / N to cancel]: ', [LMaxSameMajor.ToString]));
      var LInput := Trim(TConsole.ReadLine);
      if (LInput = '') or SameText(LInput, 'Y') then
        LTargetVer := LMaxSameMajor.ToString
      else if SameText(LInput, 'N') then
      begin
        TConsole.WriteLine('Cancelled.', clYellow);
        TConsole.WriteLine;
        Exit;
      end
      else
      begin
        // Treat the input as a manually typed version/constraint.
        var LResolved := TManifest.GetManifest(LPackageId, LInput);
        try
          LTargetVer := LResolved.Version;
        finally
          LResolved.Free;
        end;
      end;
    end;
  end;

  // Nothing to do when already at the target version.
  if TSemVer.Parse(LTargetVer) = LInstalledSemVer then
  begin
    TConsole.WriteLine(Format('Already at version %s.', [LInstalledVer]), clGreen);
    TConsole.WriteLine;
    Exit;
  end;
  TConsole.WriteLine;

  var LNewManifest := TManifest.GetManifest(LPackageId, LTargetVer);
  try
    // Step 4 — Compatibility checks (collect every problem before deciding)
    var LProblems: TArray<string> := [];

    // Downward: dependencies required by the new version. A missing dependency is
    // fine (it will be installed); a present-but-incompatible one is a problem.
    for var LDep in LNewManifest.Dependencies do
    begin
      var LDepInstalled := Database.InstalledVersion(LDep.Key);
      if LDepInstalled = '' then
        Continue;
      var LDepSemVer: TSemVer;
      if TSemVer.TryParse(LDepInstalled, LDepSemVer) and not LDepSemVer.MatchesConstraint(LDep.Value) then
        LProblems :=
            LProblems + [Format('  dependency %s %s does not satisfy %s', [LDep.Key, LDepInstalled, LDep.Value])];
    end;

    // Upward: installed packages that depend on this one and whose constraint the
    // target version would no longer satisfy.
    var LTargetSemVer := TSemVer.Parse(LTargetVer);
    for var LDependent in FindDependents(LPackageId) do
    begin
      var LConstraint: string;
      if Database.Packages[LDependent].Dependencies.TryGetValue(LPackageId, LConstraint)
          and not LTargetSemVer.MatchesConstraint(LConstraint) then
        LProblems :=
            LProblems
                + [
                    Format(
                        '  %s requires %s %s (not satisfied by %s)',
                        [LDependent, LPackageId, LConstraint, LTargetVer]
                    )];
    end;

    if Length(LProblems) > 0 then
    begin
      TConsole.WriteWarning(Format('Cannot update %s to %s — compatibility problems:', [LPackageId, LTargetVer]));
      for var LProblem in LProblems do
        TConsole.WriteLine(LProblem, clYellow);
      TConsole.WriteLine;
      TConsole.WriteLine('Resolve them first (uninstall or update the packages listed above), then retry.', clYellow);
      TConsole.WriteLine;
      Exit;
    end;

    // Step 5 — Make sure the new version targets the selected Delphi version.
    if not LNewManifest.IsProductSupported(LSelectedProduct.VersionName) then
      raise Exception
          .CreateFmt('No compatible package found for "%s". Delphi version too old?', [LSelectedProduct.DisplayName]);

    TConsole.WriteLine(Format('Updating %s: %s -> %s', [LPackageId, LInstalledVer, LTargetVer]), clWhite);
    TConsole.WriteLine;

    // Step 6 — Remove the currently installed version first. A plain in-place
    // rebuild would leave residues behind: version-suffixed artifacts
    // (bpl/dcp/rsm), the IDE design-time registration and the DCU folder of the
    // old version. Uninstalling (forced, so the dependents warning is skipped)
    // gives a clean slate; the dependents are recompiled below.
    Uninstall(LPackageId, [woForce]);

    // Step 7 — Install the new version. Its missing dependencies are downloaded and
    // already-compatible ones are skipped by the install gate; overwrite stays off
    // so dependencies are not needlessly re-downloaded. The checks above guarantee
    // there are no version conflicts, so no force is needed. Only woSilent is carried over.
    Install(LPackageId, LTargetVer, AOptions * [woSilent]);

    // Step 8 — Recompile every dependent (direct and transitive) so their DCUs are
    // rebuilt against the new version (in Delphi DCUs are tied to the version they
    // were compiled with). The list is in topological order, so a package is rebuilt
    // after the dependencies it requires. No compatibility check is needed here: the
    // checks above already passed, and recompiling never changes a package's version.
    var LDependents := FindAllDependents(LPackageId);
    if Length(LDependents) > 0 then
    begin
      TConsole.WriteLine(Format('Recompiling dependents: %s', [string.Join(', ', LDependents)]), clCyan);
      TConsole.WriteLine;
      for var LDependent in LDependents do
      begin
        var LDependentManifest := TManifest.GetManifest(LDependent, Database.InstalledVersion(LDependent));
        try
          BuildAndRegisterPackage(LDependentManifest, LSelectedProduct, [woBuildOnly] + (AOptions * [woSilent]));
        finally
          LDependentManifest.Free;
        end;
      end;
    end;

    TConsole.WriteLine;
    TConsole.WriteLine('============================================', clGreen);
    TConsole.WriteLine(Format('  Updated: %s %s -> %s', [LPackageId, LInstalledVer, LTargetVer]), clGreen);
    TConsole.WriteLine('============================================', clGreen);
    TConsole.WriteLine;
  finally
    LNewManifest.Free;
  end;
end;

class procedure TWorkspace.UpdateRepositoryCache(const AWorkDir: string);
begin
  var RepoDir := TPath.Combine(GetBlocksDir, 'repository');
  if not TDirectory.Exists(RepoDir) then
    raise Exception.Create('Repository not found.');

  for var LSource in Config.Sources do
    InitializeFromSource(LSource);

  RebuildIndex;

  var LProduct := Config.Product;
  if LProduct = '' then
    raise Exception.Create('No Delphi version configured. Run "blocks init /product <version>" first.');
  var LSelectedProduct := TProduct.Find(LProduct, Config.RegistryKey);
  LSelectedProduct.CheckEnvironment(AWorkDir);

  Database.TouchRepository;

  if Config.UpdateDCPSearchPath then
    LSelectedProduct.CheckDCPPath(AWorkDir);
end;

end.
