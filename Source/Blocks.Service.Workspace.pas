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
  System.Classes, System.SysUtils, System.IOUtils, System.Generics.Collections,
  System.RegularExpressions, System.Types, System.Zip,

  Blocks.Model.Database,
  Blocks.Model.Config,
  Blocks.JSON,
  Blocks.Core;

type
  TWorkspace = class
  private
    class var
      FWorkDir: string;
      FConfig: TConfig;
      FDatabase: TDatabase;
    class function GetWorkDir: string; static;
    class function GetBlocksDir: string; static;
    class procedure SetWorkDir(const AValue: string); static;

    class function GetConfig: TConfig; static;
    class function GetDatabase: TDatabase; static;
    class procedure InitializeFromSource(const ASource: string); static;
    /// <summary>Rebuilds <c>.blocks\repository\index.json</c> from the local repository.</summary>
    class procedure RebuildIndex; static;
    /// <summary>Resolves an install/uninstall argument to a package id (<c>vendor.name</c>).</summary>
    /// <remarks>
    ///   If <paramref name="AArg"/> contains a dot it is assumed to already be an id and
    ///   returned unchanged. Otherwise the repository index is searched by name; ambiguous
    ///   matches are resolved interactively (or raise when <paramref name="ASilent"/> is true).
    /// </remarks>
    class function ResolvePackageId(const AArg: string; ASilent: Boolean = False): string; static;
    class constructor Create;
    class destructor  Destroy;
  public
    /// <summary>Get a refernce to the database of installed packages.</summary>
    class property Database: TDatabase read GetDatabase;
    /// <summary>Get a refernce to the workspace configuration.</summary>
    class property Config: TConfig read GetConfig;
    /// <summary>Initialises a directory as a Blocks workspace and sets <see cref="WorkDir"/>.</summary>
    /// <param name="AWorkDir">Directory to initialise as the workspace root.</param>
    /// <param name="AProduct">Target Delphi version name (e.g. <c>delphi13</c>); empty to select interactively.</param>
    /// <remarks>
    ///   Performs the following steps in order:
    ///   1. Sets <see cref="WorkDir"/> to <c>AWorkDir</c> and creates <see cref="BlocksDir"/> if absent.
    ///   2. Selects the target Delphi version and persists it in the workspace configuration.
    ///   3. Downloads the package repository archive from the canonical GitHub source
    ///      (<see cref="BlocksRepositoryUrl"/>).
    ///   4. Extracts the archive and installs <c>repository\</c> under <see cref="BlocksDir"/>.
    ///   Prompts the user before overwriting an existing repository folder.
    /// </remarks>
    class procedure Initialize(const AWorkDir, AProduct, ARegistryKey: string); static;

    /// <summary>Update the workspace by downloading the package list.</summary>
    class procedure Update(const AWorkDir: string); static;

    /// <summary>Downloads, compiles and registers a package in the workspace.</summary>
    /// <param name="APackageName">Package id (<c>vendor.name</c>) or package name; resolved via the repository index.</param>
    /// <param name="AVersionConstraint">Version constraint string (e.g. <c>1.2.0</c>, <c>>=1.0.0</c>); empty for any version.</param>
    /// <param name="AOverwrite">Overwrite the project directory if it already exists.</param>
    /// <param name="ABuildOnly">Skip download; compile the already-extracted project.</param>
    /// <param name="ASilent">Skip non-critical interactive prompts.</param>
    /// <param name="AForce">When <c>True</c>, log a warning on version conflict and continue instead of raising an exception.</param>
    class procedure Install(const APackageName, AVersionConstraint: string;
        AOverwrite, ABuildOnly, ASilent, AForce: Boolean); static;

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
  Blocks.Service.Product,
  Blocks.GitHub, Blocks.Model.Package;

procedure ExpandMacros(var APath: string; AEnvironmentVariable: TStrings);
begin
  APath := RegExReplace(APath, '\$\(([^)]+)\)',
    function(const AMatch: TMatch): string
    begin
      // Unknown macros resolve to '' — same as stripping the residual.
      Result := AEnvironmentVariable.Values[AMatch.Groups[1].Value];
    end);
end;

procedure NormalizePath(var APaths: TArray<string>; const ABasePath: string; AEnvironmentVariable: TStrings);
begin
  for var I := Low(APaths) to High(APaths) do
  begin
    ExpandMacros(APaths[I], AEnvironmentVariable);
    if TPath.IsRelativePath(APaths[I]) then
    begin
      APaths[I] := ExpandFileName(TPath.Combine(ABasePath, APaths[I]));
    end;
  end;
end;

function GetDProjPath(const AProjectDir: string; AProduct: TProduct; AManifest: TManifest; APackageName: string): string;
begin
  var LPackageFolder := AProduct.GetPackageFolder(AManifest.PackageOptions.Folders);
  var LPackagesPath := TPath.Combine(TPath.Combine(AProjectDir, 'packages'), LPackageFolder);
  Result := TPath.Combine(LPackagesPath, APackageName + '.dproj');
end;

function GetPlatformPaths(const AManifest: TManifest; const ADprojName, AProjectDir, APlatform: string;
    AEnvironmentVariable: TStrings): TPlatformPaths;
begin
  var LPlatformManifest := AManifest.Platforms[APlatform];
  var LPackage := TPackageProject.LoadFromFile(ADprojName);
  try
    var LDprojDir := ExtractFilePath(ADprojName);
    AEnvironmentVariable.Values['Platform'] := APlatform;
    var LDLLSuffix := LPackage.LibSuffix;
    if SameText(LDLLSuffix, 'AUTO') then
      LDLLSuffix := AEnvironmentVariable.Values['PackageVersion'];

    AEnvironmentVariable.Values['DllSuffix'] := LDLLSuffix;

    var LSourcePath := LPlatformManifest.SourcePath.ToStringArray;
    NormalizePath(LSourcePath, AProjectDir, AEnvironmentVariable);

    var LDebugDcuPath: TArray<string>;
    var LReleaseDcuPath: TArray<string>;

    if AManifest.PackageOptions.KeepProjectDcuPaths then
    begin
      LDebugDcuPath := LPackage.GetProperty(TPackageProject.DCCDcuOutput, 'Debug', APlatform).Split([';']);
      AEnvironmentVariable.Values['Config'] := 'Debug';
      NormalizePath(LDebugDcuPath, LDprojDir, AEnvironmentVariable);

      LReleaseDcuPath := LPackage.GetProperty(TPackageProject.DCCDcuOutput, 'Release', APlatform).Split([';']);
      AEnvironmentVariable.Values['Config'] := 'Release';
      NormalizePath(LReleaseDcuPath, LDprojDir, AEnvironmentVariable);
    end
    else
    begin
      LReleaseDcuPath := [TPath.Combine(AProjectDir, 'lib', APlatform)];
      LDebugDcuPath := [TPath.Combine(AProjectDir, 'lib', APlatform, 'debug')];
    end;
    Result.SourcePath := LSourcePath;
    Result.ReleaseDCUPath := LReleaseDcuPath;
    Result.DebugDCUPath := LDebugDcuPath;
  finally
    LPackage.Free;
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
  Result := TDirectory.Exists(TWorkspace.BlocksDir) and TFile.Exists(TPath.Combine(TWorkspace.BlocksDir, 'workspace.json'));
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
      raise Exception.CreateFmt('Package name "%s" is ambiguous: %d matches. Use the full id (vendor.name)', [AArg, Length(LMatches)]);

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

class procedure TWorkspace.Initialize(const AWorkDir, AProduct, ARegistryKey: string);
begin
  SetWorkDir(AWorkDir);

  if not TDirectory.Exists(GetBlocksDir) then
  begin
    TDirectory.CreateDirectory(GetBlocksDir);
    TConsole.WriteLine('Created: ' + GetBlocksDir, clGreen);
  end;

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
    LSelectedProduct := TProduct.Select('')
  else
    LSelectedProduct := TProduct.FindByNameAndKey(
        LProductName,
        if LRegistryKey = '' then 'BDS' else LRegistryKey
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
    TConsole.WriteLine(Format('Directory "%s" already exists.', [RepoDir]), clYellow);
    TConsole.Write('Overwrite? [Y/N] (default: N): ');
    var Confirm := TConsole.ReadLine;
    if not SameText(Trim(Confirm), 'Y') then
    begin
      TConsole.WriteLine('Operation cancelled.', clYellow);
      Exit;
    end;
    TDirectory.Delete(RepoDir, True);
  end;

  for var LSource in Config.Sources do
    InitializeFromSource(LSource);

  RebuildIndex;
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

    if TDirectory.Exists(DownloadDir) then
      TDirectory.Delete(DownloadDir, True);
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
    TDirectory.Delete(DownloadDir, True);
end;

class procedure TWorkspace.Install(const APackageName, AVersionConstraint: string;
    AOverwrite, ABuildOnly, ASilent, AForce: Boolean);
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
      raise Exception.Create(
          'No Delphi version configured. Run "blocks init /product <version>" first.');
    var LSelectedProduct := TProduct.FindByNameAndKey(LProduct, Config.RegistryKey);
    TConsole.WriteLine('Selected version: ' + LSelectedProduct.DisplayName, clGreen);
    if not SameText(LSelectedProduct.RegistryKey, 'BDS') then
      TConsole.WriteLine('Registry key    : ' + LSelectedProduct.RegistryKey, clGreen);
    TConsole.WriteLine;

    // Step 4 — Version compatibility check (unless -Overwrite or -BuildOnly)
    if not AOverwrite and not ABuildOnly then
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
                Format('Version conflict: %s installed %s, required %s — skipping (/force)',
                [LManifest.Id, LInstalledVer, AVersionConstraint]));
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

    // Step 5 — Resolve package folder for selected Delphi version
    var LPackageFolder := LSelectedProduct.GetPackageFolder(LManifest.PackageOptions.Folders);

    // Step 6 — Dependencies
    if not LManifest.Dependencies.IsEmpty then
    begin
      TConsole.WriteLine('Resolving dependencies...', clCyan);
      for var LDependency in LManifest.Dependencies do
        TWorkspace.Install(LDependency.Key, LDependency.Value, AOverwrite, ABuildOnly, ASilent, AForce);
      TConsole.WriteLine;
    end;

    var LProjectDir: string;
    if not ABuildOnly then
    begin
      // Step 7 — Build zip URL from repository URL and download
      // Repository URL format: https://github.com/owner/repo/tree/ref
      TConsole.WriteLine('--- ' + LManifest.Id + ' / ' + LManifest.Name + ' ---', clWhite);
      TConsole.WriteLine('Version: ' + LManifest.Version, clCyan);
      var LRepoParts := TrimRight(LManifest.Repository.Url, ['/']).Split(['/']);
      if Length(LRepoParts) < 7 then
        raise Exception.CreateFmt('Cannot parse repository URL: %s', [LManifest.Repository.Url]);
      var LZipUrl := TGitHub.GetGitHubZipUrl(LRepoParts[3], LRepoParts[4], LRepoParts[6]);
      LProjectDir := TGitHub.DownloadAndExtract(LZipUrl, WorkDir, LManifest.Name, AOverwrite, ASilent);
      TConsole.WriteLine('Project downloaded to: ' + LProjectDir, clGreen);
      TConsole.WriteLine;
    end
    else
    begin
      LProjectDir := TPath.Combine(WorkDir, LManifest.Name);
      if not TDirectory.Exists(LProjectDir) then
        raise Exception.CreateFmt('Build-only mode: project directory not found: %s', [LProjectDir]);
      TConsole.WriteLine('Build-only mode. Using existing directory: ' + LProjectDir, clYellow);
      TConsole.WriteLine;
    end;

    // Step 8 — Compile
    LSelectedProduct.BuildPackages(WorkDir, LProjectDir, LPackageFolder, LManifest);

    // Step 9 — Update product paths
    var LEnvironmentVariables := TStringList.Create;
    try
      LSelectedProduct.FillEnvironmentVariables(LEnvironmentVariables);
      for var LPlatformPair in LManifest.Platforms do
      begin
        var LPackagesPath := TPath.Combine(TPath.Combine(LProjectDir, 'packages'), LPackageFolder);

        for var LPackage in LManifest.Packages do
        begin
          var DprojPath := TPath.Combine(LPackagesPath, LPackage.Name + '.dproj');
          var LPlatformPaths := GetPlatformPaths(LManifest, DprojPath, LProjectDir, LPlatformPair.Key, LEnvironmentVariables);
          LSelectedProduct.UpdateSearchPaths(LPlatformPair.Key, LProjectDir, LPlatformPaths);
        end;
      end;
    finally
      LEnvironmentVariables.Free;
    end;

    // Step 10 — Update database
    if not ABuildOnly then
      Database.Update(LManifest.Id, LManifest.Version);

    TConsole.WriteLine;
    TConsole.WriteLine('============================================', clGreen);
    TConsole.WriteLine('  Done!', clGreen);
    TConsole.WriteLine('  Project  : ' + LProjectDir, clGreen);
    TConsole.WriteLine('  Packages : ' + TPath.Combine(LProjectDir, 'packages\' + LPackageFolder), clGreen);
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
    raise Exception.Create(
        'No Delphi version configured. Run "blocks init /product <version>" first.');
  var LSelectedProduct := TProduct.FindByNameAndKey(LProduct, Config.RegistryKey);
  TConsole.WriteLine('Selected version: ' + LSelectedProduct.DisplayName, clGreen);
  if not SameText(LSelectedProduct.RegistryKey, 'BDS') then
    TConsole.WriteLine('Registry key    : ' + LSelectedProduct.RegistryKey, clGreen);
  TConsole.WriteLine;

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

    // Step 5 - Unregister all packages
    var LEnvironmentVariables := TStringList.Create;
    try
      LSelectedProduct.FillEnvironmentVariables(LEnvironmentVariables);
      for var LPackage in LManifest.Packages do
      begin
        for var LPlatformPair in LManifest.Platforms do
        begin
          var LPackageFolder := LSelectedProduct.GetPackageFolder(LManifest.PackageOptions.Folders);
          var LPackagesPath := TPath.Combine(TPath.Combine(LProjectDir, 'packages'), LPackageFolder);
          var DprojPath := TPath.Combine(LPackagesPath, LPackage.Name + '.dproj');

          if LPackage.IsDesignTime then
            LSelectedProduct.UninstallPackage(LPackage, WorkDir, DprojPath, LPlatformPair);

          var LPlatformPaths := GetPlatformPaths(LManifest, DprojPath, LProjectDir, LPlatformPair.Key, LEnvironmentVariables);
          LSelectedProduct.DeleteSearchPaths(LPlatformPair.Key, LProjectDir, LPlatformPaths);
        end;
      end;
    finally
      LEnvironmentVariables.Free;
    end;

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
end;

end.
