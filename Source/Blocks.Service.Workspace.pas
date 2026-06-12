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
  Blocks.JSON,
  Blocks.Core,
  Blocks.Service.Product;

type
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
    class procedure EnsureCleanDir(const ADir: string; AOverwrite, ASilent: Boolean); static;
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
    /// <remarks>
    ///   Performs the following steps in order:
    ///   1. Sets <see cref="WorkDir"/> to <c>AWorkDir</c> and creates <see cref="BlocksDir"/> if absent.
    ///   2. Selects the target Delphi version and persists it in the workspace configuration.
    ///   3. Downloads the package repository archive from the canonical GitHub source
    ///      (<see cref="BlocksRepositoryUrl"/>).
    ///   4. Extracts the archive and installs <c>repository\</c> under <see cref="BlocksDir"/>.
    ///   Prompts the user before overwriting an existing repository folder.
    /// </remarks>
    class procedure Initialize(const AWorkDir, AProduct, ARegistryKey: string; const ASources: string = ''); static;

    /// <summary>Update the workspace by downloading the package list.</summary>
    class procedure Update(const AWorkDir: string); static;

    /// <summary>Downloads, compiles and registers a package in the workspace.</summary>
    /// <param name="APackageName">Package id (<c>vendor.name</c>) or package name; resolved via the repository index.</param>
    /// <param name="AVersionConstraint">Version constraint string (e.g. <c>1.2.0</c>, <c>>=1.0.0</c>); empty for any version.</param>
    /// <param name="AOverwrite">Overwrite the project directory if it already exists.</param>
    /// <param name="ABuildOnly">Skip download; compile the already-extracted project.</param>
    /// <param name="ASilent">Skip non-critical interactive prompts.</param>
    /// <param name="AForce">When <c>True</c>, log a warning on version conflict and continue instead of raising an exception.</param>
    class procedure Install(
        const APackageName, AVersionConstraint: string;
        AOverwrite, ABuildOnly, ASilent, AForce: Boolean
    ); static;

    /// <summary>Removes a previously installed package from the workspace and the database.</summary>
    /// <param name="APackageName">Package id (<c>vendor.name</c>) or package name; resolved via the repository index.</param>
    class procedure Uninstall(const APackageName: string); static;

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
  Blocks.Console,
  Blocks.Http,
  Blocks.Model.Manifest,
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
    AProduct: TProduct
);
begin
  var LEnv := TStringList.Create;
  try
    LEnv.Values['WORKSPACE_PATH'] := AWorkspaceDir;
    LEnv.Values['PROJECT_PATH'] := AProjectDir;
    // The package-version suffix lets scripts target .dproj names that embed it
    // (e.g. $(PACKAGE_VERSION) in the "compile" command's path).
    LEnv.Values['PACKAGE_VERSION'] := AProduct.PackageVersionSuffix;
    // AProduct implements IScriptHelper, giving commands like "compile" a compiler.
    TScriptRunner.RunEvent(AManifest, AEvent, LEnv, AProduct);
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

class procedure TWorkspace.EnsureCleanDir(const ADir: string; AOverwrite, ASilent: Boolean);
begin
  if not TDirectory.Exists(ADir) then
    Exit;

  if AOverwrite then
  begin
    TDirectory.Delete(ADir, True);
    TConsole.WriteLine(Format('Directory "%s" removed.', [ADir]), clYellow);
  end
  else if ASilent then
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

class procedure TWorkspace.Initialize(const AWorkDir, AProduct, ARegistryKey: string; const ASources: string);
begin
  SetWorkDir(AWorkDir);

  if not TDirectory.Exists(GetBlocksDir) then
  begin
    TDirectory.CreateDirectory(GetBlocksDir);
    TConsole.WriteLine('Created: ' + GetBlocksDir, clGreen);
  end;

  if ASources <> '' then
    Config.&Set('sources', ASources);

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

  var LSelectedProduct: TProduct;
  if LProductName = '' then
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
  Config.Save;
  TConsole.WriteLine('Selected version: ' + LSelectedProduct.DisplayName, clGreen);
  if not SameText(LSelectedProduct.RegistryKey, 'BDS') then
    TConsole.WriteLine('Registry key    : ' + LSelectedProduct.RegistryKey, clGreen);
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

class procedure TWorkspace.Install(
    const APackageName, AVersionConstraint: string;
    AOverwrite, ABuildOnly, ASilent, AForce: Boolean
);
begin
  var LPackageId := ResolvePackageId(APackageName, ASilent);
  var LManifest := TManifest.GetManifest(LPackageId, AVersionConstraint);
  try
    TConsole.WriteLine('Config: ' + LPackageId, clDkGray);
    TConsole.WriteLine;

    TConsole.WriteLine('Workspace: ' + WorkDir, clDkGray);
    TConsole.WriteLine;

    // Step 3 — Delphi version (read from workspace configuration)
    var LProduct := Config.Product;
    if LProduct = '' then
      raise Exception.Create('No Delphi version configured. Run "blocks init /product <version>" first.');
    var LSelectedProduct := TProduct.Find(LProduct, Config.RegistryKey);
    TConsole.WriteLine('Selected version: ' + LSelectedProduct.DisplayName, clGreen);
    if not SameText(LSelectedProduct.RegistryKey, 'BDS') then
      TConsole.WriteLine('Registry key    : ' + LSelectedProduct.RegistryKey, clGreen);
    TConsole.WriteLine;
    TestDelphiRunning(LSelectedProduct);

    // Step 4 — In build-only mode the package must already be installed
    if ABuildOnly then
    begin
      if Database.InstalledVersion(LManifest.Id) = '' then
        raise Exception.CreateFmt(
            'Cannot build %s: the package is not installed. Run "blocks install %s" first.',
            [LManifest.Id, LManifest.Id]);
    end
    // Step 4b — Version compatibility check (unless -Overwrite)
    else if not AOverwrite then
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
          if AForce then
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
            raise Exception.CreateFmt(
                'Version conflict: %s installed %s, required %s',
                [LManifest.Id, LInstalledVer, AVersionConstraint]);
        end;
      end;
    end;

    // Step 5 — Make sure the package targets the selected Delphi version before
    // downloading anything, so an unsupported version fails fast.
    if not LManifest.IsProductSupported(LSelectedProduct.VersionName) then
      raise Exception
          .CreateFmt('No compatible package found for "%s". Delphi version too old?', [LSelectedProduct.DisplayName]);

    // Step 6 — Dependencies
    if not LManifest.Dependencies.IsEmpty then
    begin
      TConsole.WriteLine('Resolving dependencies...', clCyan);
      for var LDependency in LManifest.Dependencies do
        TWorkspace.Install(LDependency.Key, LDependency.Value, AOverwrite, ABuildOnly, ASilent, AForce);
      TConsole.WriteLine;
    end;

    var LProjectDir := TPath.Combine(WorkDir, LManifest.Name);

    // Step 6.5 — beforeInstall scripts
    RunManifestScripts(LManifest, TScriptRunner.EventBeforeInstall, WorkDir, LProjectDir, LSelectedProduct);

    if not ABuildOnly then
    begin
      // Step 7 — Fetch the package sources according to the repository type
      TConsole.WriteLine('--- ' + LManifest.Id + ' / ' + LManifest.Name + ' ---', clWhite);
      TConsole.WriteLine('Version: ' + LManifest.Version, clCyan);
      EnsureCleanDir(LProjectDir, AOverwrite, ASilent);
      var LFetcher := TRepositoryFetcher.ForRepository(LManifest.Repository);
      LFetcher.FetchTo(LManifest.Repository, LProjectDir);
      TConsole.WriteLine('Project downloaded to: ' + LProjectDir, clGreen);
      TConsole.WriteLine;
    end
    else
    begin
      if not TDirectory.Exists(LProjectDir) then
        raise Exception.CreateFmt('Build-only mode: project directory not found: %s', [LProjectDir]);
      TConsole.WriteLine;
    end;

    // Step 8 — Compile
    LSelectedProduct.BuildPackages(WorkDir, LProjectDir, LManifest);

    // Step 9 — Update product paths
    var LEnvironmentVariables := TStringList.Create;
    try
      LSelectedProduct.FillEnvironmentVariables(LEnvironmentVariables);
      for var LPlatformPair in LManifest.Platforms do
      begin
        var LPackagesPath := LSelectedProduct.GetPackagesPath(LProjectDir, LManifest);

        for var LPackage in LManifest.Packages do
        begin
          // Packages that do not target this product were never built, so skip their paths too.
          if not LPackage.SupportsProduct(LSelectedProduct.VersionName) then
            Continue;

          // Design-time packages are not built on runtime-only platforms, so skip their paths too.
          if LPlatformPair.Value.RuntimeOnly and LPackage.IsDesignTime then
            Continue;

          var DprojPath := TPath.Combine(LPackagesPath, LSelectedProduct.ExpandPackageName(LPackage.Name) + '.dproj');
          var LPlatformPaths :=
              GetPlatformPaths(LManifest, DprojPath, LProjectDir, LPlatformPair.Key, LEnvironmentVariables);
          LSelectedProduct.UpdateSearchPaths(LPlatformPair.Key, LProjectDir, LPlatformPaths);
        end;
      end;
    finally
      LEnvironmentVariables.Free;
    end;

    // Step 10 — Update database
    if not ABuildOnly then
      Database.Update(LManifest.Id, LManifest.Version);

    // Step 11 — afterInstall scripts
    RunManifestScripts(LManifest, TScriptRunner.EventAfterInstall, WorkDir, LProjectDir, LSelectedProduct);

    TConsole.WriteLine;
    TConsole.WriteLine('============================================', clGreen);
    TConsole.WriteLine('  Done!', clGreen);
    TConsole.WriteLine('  Project  : ' + LProjectDir, clGreen);
    TConsole.WriteLine('  Packages : ' + LSelectedProduct.GetPackagesPath(LProjectDir, LManifest), clGreen);
    TConsole.WriteLine('============================================', clGreen);
    TConsole.WriteLine;
  finally
    LManifest.Free;
  end;
end;

class procedure TWorkspace.Uninstall(const APackageName: string);
begin
  var LPackageId := ResolvePackageId(APackageName);
  TConsole.WriteLine('Config: ' + LPackageId, clDkGray);
  TConsole.WriteLine;

  TConsole.WriteLine('Workspace: ' + WorkDir, clDkGray);
  TConsole.WriteLine;

  // Step 3 — Delphi version (read from workspace configuration)
  var LProduct := Config.Product;
  if LProduct = '' then
    raise Exception.Create('No Delphi version configured. Run "blocks init /product <version>" first.');
  var LSelectedProduct := TProduct.Find(LProduct, Config.RegistryKey);
  TConsole.WriteLine('Selected version: ' + LSelectedProduct.DisplayName, clGreen);
  if not SameText(LSelectedProduct.RegistryKey, 'BDS') then
    TConsole.WriteLine('Registry key    : ' + LSelectedProduct.RegistryKey, clGreen);
  TConsole.WriteLine;
  TestDelphiRunning(LSelectedProduct);

  // Step 4 — Check that the package is actually installed
  var LInstalledVer := Database.InstalledVersion(LPackageId);
  if LInstalledVer = '' then
  begin
    TConsole.WriteWarning('Not installed: ' + LPackageId);
    TConsole.WriteLine;
    Exit;
  end;

  var LManifest := TManifest.GetManifest(LPackageId, LInstalledVer);
  try
    var LProjectDir := TPath.Combine(WorkDir, LManifest.Name);

    // Step 4.5 — beforeUninstall scripts (project files still present)
    RunManifestScripts(LManifest, TScriptRunner.EventBeforeUninstall, WorkDir, LProjectDir, LSelectedProduct);

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
      TConsole.WriteLine('Removed: ' + LProjectDir, clYellow);
    end
    else
      TConsole.WriteLine('Directory not found: ' + LProjectDir, clYellow);

    // Step 7 — Remove from database
    Database.RemoveEntry(LManifest.Id);

    // Step 8 — afterUninstall scripts
    RunManifestScripts(LManifest, TScriptRunner.EventAfterUninstall, WorkDir, LProjectDir, LSelectedProduct);

    TConsole.WriteLine;
    TConsole.WriteLine('Uninstalled: ' + LManifest.Name + ' ' + LInstalledVer, clGreen);
    TConsole.WriteLine;
  finally
    LManifest.Free;
  end;
end;

class procedure TWorkspace.Update(const AWorkDir: string);
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
end;

end.
