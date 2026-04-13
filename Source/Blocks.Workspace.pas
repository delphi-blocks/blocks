unit Blocks.Workspace;

interface

uses
  System.Classes, System.SysUtils, System.IOUtils, System.Generics.Collections,
  System.Types, System.Zip,

  Blocks.Database,
  Blocks.JSON,
  Blocks.Types;

type
  TConfig = class;

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
    class constructor Create;
    class destructor  Destroy;
  public
    /// <summary>Get a refernce to the database of installed packages.</summary>
    class property Database: TDatabase read GetDatabase;
    /// <summary>Get a refernce to the workspace configuration.</summary>
    class property Config: TConfig read GetConfig;
    /// <summary>Initialises a directory as a Blocks workspace and sets <see cref="WorkDir"/>.</summary>
    /// <param name="AWorkDir">Directory to initialise as the workspace root.</param>
    /// <remarks>
    ///   Performs the following steps in order:
    ///   1. Sets <see cref="WorkDir"/> to <c>AWorkDir</c> and creates <see cref="BlocksDir"/> if absent.
    ///   2. Downloads the package repository archive from the canonical GitHub source
    ///      (<see cref="BlocksRepositoryUrl"/>).
    ///   3. Extracts the archive and installs <c>repository\</c> under <see cref="BlocksDir"/>.
    ///   Prompts the user before overwriting an existing repository folder.
    /// </remarks>
    class procedure Initialize(const AWorkDir: string); static;

    /// <summary>Downloads, compiles and registers a package in the workspace.</summary>
    /// <param name="APackageName">Package identifier (without version suffix).</param>
    /// <param name="AVersionConstraint">Version constraint string (e.g. <c>1.2.0</c>, <c>>=1.0.0</c>); empty for any version.</param>
    /// <param name="AProduct">Target Delphi version name (e.g. <c>delphi13</c>); empty to select interactively.</param>
    /// <param name="AOverwrite">Overwrite the project directory if it already exists.</param>
    /// <param name="ABuildOnly">Skip download; compile the already-extracted project.</param>
    /// <param name="ASilent">Skip non-critical interactive prompts.</param>
    /// <param name="AForce">When <c>True</c>, log a warning on version conflict and continue instead of raising an exception.</param>
    class procedure Install(const APackageName, AVersionConstraint, AProduct: string;
        AOverwrite, ABuildOnly, ASilent, AForce: Boolean); static;

    /// <summary>Removes a previously installed package from the workspace and the database.</summary>
    /// <param name="APackageName">Package identifier or manifest path/URL.</param>
    /// <param name="AProduct">Target Delphi version name; empty to select interactively.</param>
    class procedure Uninstall(const APackageName, AProduct: string); static;

    /// <summary>Root directory of the current workspace.</summary>
    /// <remarks>
    ///   Returns the value set by the last call to <see cref="Initialize"/> or an explicit
    ///   property assignment. Defaults to the process current directory when not set.
    /// </remarks>
    class property WorkDir: string read GetWorkDir write SetWorkDir;

    /// <summary>Path to the Blocks settings directory (<c>WorkDir\.blocks</c>).</summary>
    class property BlocksDir: string read GetBlocksDir;
  end;

  TConfig = class(TObject)
  private
    FSources: TJSONStringList;
    function ConfigPath: string;
  public
    [JsonList(System.TypeInfo(string))]
    property Sources: TJSONStringList read FSources;

    procedure Load;
    procedure Save;

    function Get(const AKey: string): string;
    procedure &Set(const AKey, AValue: string);
    procedure Add(const AKey, AValue: string);

    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  Blocks.Consts,
  Blocks.Console,
  Blocks.Http,
  Blocks.Manifest,
  Blocks.Product;

const
  DefaultBlocksRepositoryUrl = 'https://github.com/lminuti/blocks-repository';

{ TWorkspace }

class function TWorkspace.GetConfig: TConfig;
begin
  if not Assigned(FConfig) then
  begin
    FConfig := TConfig.Create;
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

class function TWorkspace.GetBlocksDir: string;
begin
  Result := TPath.Combine(GetWorkDir, '.blocks');
end;

class procedure TWorkspace.SetWorkDir(const AValue: string);
begin
  FWorkDir := ExcludeTrailingPathDelimiter(AValue);
end;

class procedure TWorkspace.Initialize(const AWorkDir: string);
begin
  SetWorkDir(AWorkDir);

  if not TDirectory.Exists(GetBlocksDir) then
  begin
    TDirectory.CreateDirectory(GetBlocksDir);
    TConsole.WriteLine('Created: ' + GetBlocksDir, clGreen);
  end;

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
    var RepoInfo := THttpUtils.GetGitHubInfo(ASource);
    TConsole.WriteLine('  Branch : ' + RepoInfo.DefaultBranch);
    TConsole.WriteLine('  Latest : ' + RepoInfo.LatestCommit);
    TConsole.WriteLine;

    var ZipUrl := THttpUtils.GetGitHubZipUrl(RepoInfo.Owner, RepoInfo.Repo, RepoInfo.LatestCommit);

    TConsole.WriteLine('Downloading repository...', clCyan);
    THttpUtils.DownloadFile(ZipUrl, ZipPath);

    TConsole.WriteLine('Extracting...', clCyan);
    var ExtractDir := TPath.Combine(DownloadDir, 'extract');
    TDirectory.CreateDirectory(ExtractDir);
    TZipFile.ExtractZipFile(ZipPath, ExtractDir);

    // GitHub wraps content in a subdirectory (e.g. "lminuti-blocks-repository-abc1234")
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

class procedure TWorkspace.Install(const APackageName, AVersionConstraint, AProduct: string;
    AOverwrite, ABuildOnly, ASilent, AForce: Boolean);
begin
  var LManifest := TManifest.GetManifest(APackageName, AVersionConstraint);
  try
    TConsole.WriteLine('Config: ' + APackageName, clDkGray);
    TConsole.WriteLine;

    TConsole.WriteLine('Workspace: ' + WorkDir, clDkGray);
    TConsole.WriteLine;

    // Step 3 — Delphi version
    var LSelectedProduct := TProduct.Select(AProduct);
    TConsole.WriteLine('Selected version: ' + LSelectedProduct.DisplayName, clGreen);
    TConsole.WriteLine;

    // Step 4 — Version compatibility check (unless -Overwrite or -BuildOnly)
    if not AOverwrite and not ABuildOnly then
    begin
      var LInstalledVer := Database.InstalledVersion(LManifest.Id, LSelectedProduct.VersionName);
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
        TWorkspace.Install(LDependency.Key, LDependency.Value, LSelectedProduct.VersionName, AOverwrite, ABuildOnly, ASilent, AForce);
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
      var LZipUrl := THttpUtils.GetGitHubZipUrl(LRepoParts[3], LRepoParts[4], LRepoParts[6]);
      LProjectDir := THttpUtils.DownloadAndExtract(LZipUrl, WorkDir, LManifest.Name, AOverwrite, ASilent);
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
    LSelectedProduct.BuildPackages(LProjectDir, LPackageFolder, LManifest.Packages, LManifest.Platforms);

    // Step 9 — Update database
    if not ABuildOnly then
      Database.Update(LManifest.Id, LManifest.Version, LSelectedProduct.VersionName);

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

class procedure TWorkspace.Uninstall(const APackageName, AProduct: string);
begin
  TConsole.WriteLine('Config: ' + APackageName, clDkGray);
  TConsole.WriteLine;

  TConsole.WriteLine('Workspace: ' + WorkDir, clDkGray);
  TConsole.WriteLine;

  // Step 3 — Delphi version
  var LSelectedProduct := TProduct.Select(AProduct);
  TConsole.WriteLine('Selected version: ' + LSelectedProduct.DisplayName, clGreen);
  TConsole.WriteLine;

  // Step 4 — Check that the package is actually installed
  var LInstalledVer := Database.InstalledVersion(APackageName, LSelectedProduct.VersionName);
  if LInstalledVer = '' then
  begin
    TConsole.WriteWarning('Not installed: ' + APackageName);
    TConsole.WriteLine;
    Exit;
  end;

  var LManifest := TManifest.GetManifest(APackageName, LInstalledVer);
  try
    // Step 5 — Remove project directory
    var LProjectDir := TPath.Combine(WorkDir, LManifest.Name);
    if TDirectory.Exists(LProjectDir) then
    begin
      TDirectory.Delete(LProjectDir, True);
      TConsole.WriteLine('Removed: ' + LProjectDir, clYellow);
    end
    else
      TConsole.WriteLine('Directory not found: ' + LProjectDir, clYellow);

    // Step 6 — Remove from database
    Database.RemoveEntry(LManifest.Id, LSelectedProduct.VersionName);

    TConsole.WriteLine;
    TConsole.WriteLine('Uninstalled: ' + LManifest.Name + ' ' + LInstalledVer, clGreen);
    TConsole.WriteLine;
  finally
    LManifest.Free;
  end;
end;

{ TConfig }

procedure TConfig.&Set(const AKey, AValue: string);
begin
  if SameText(AKey, 'sources') then
  begin
    var LSources := AValue.Split([',']);
    FSources.Clear;
    for var S in LSources do
      FSources.Add(S);
  end
  else
    raise Exception.CreateFmt('Config "%s" does not exists', [AKey]);
end;

procedure TConfig.Add(const AKey, AValue: string);
begin
  if SameText(AKey, 'sources') then
  begin
    FSources.Add(AValue)
  end
  else
    raise Exception.CreateFmt('Config "%s" does not exists', [AKey]);
end;

function TConfig.ConfigPath: string;
begin
  var LWorkDir := TWorkspace.BlocksDir;
  ForceDirectories(LWorkDir);
  Result := TPath.Combine(LWorkDir, 'workspace.json');
end;


constructor TConfig.Create;
begin
  inherited;
  FSources := TJSONStringList.Create;
  FSources.Add(DefaultBlocksRepositoryUrl);
end;

destructor TConfig.Destroy;
begin
  FSources.Free;
  inherited;
end;

function TConfig.Get(const AKey: string): string;
begin
  if SameText(AKey, 'sources') then
    Result := string.Join(',', FSources.ToArray)
  else
    raise Exception.CreateFmt('Config "%s" does not exists', [AKey]);
end;

procedure TConfig.Load;
begin
  if FileExists(ConfigPath) then
  begin
    var LJSON := TFile.ReadAllText(ConfigPath);
    TJsonHelper.JSONToObject(Self, LJSON);
  end
  else
    Save;
end;

procedure TConfig.Save;
begin
  var LJsonString := TJsonHelper.ObjectToJSONString(Self);
  TFile.WriteAllText(ConfigPath, LJsonString);
end;

end.
