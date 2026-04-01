unit Blocks.Workspace;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.Types,
  System.Zip;

type
  TWorkspace = class
  private
    class var
      FWorkDir: string;
    class function GetWorkDir: string; static;
    class function GetBlocksDir: string; static;
    class procedure SetWorkDir(const AValue: string); static;
  public
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

    /// <summary>Root directory of the current workspace.</summary>
    /// <remarks>
    ///   Returns the value set by the last call to <see cref="Initialize"/> or an explicit
    ///   property assignment. Defaults to the process current directory when not set.
    /// </remarks>
    class property WorkDir: string read GetWorkDir write SetWorkDir;

    /// <summary>Path to the Blocks settings directory (<c>WorkDir\.blocks</c>).</summary>
    class property BlocksDir: string read GetBlocksDir;
  end;

implementation

uses
  Blocks.Consts,
  Blocks.Console,
  Blocks.Http;

class function TWorkspace.GetWorkDir: string;
begin
  if FWorkDir <> '' then
    Result := FWorkDir
  else
    Result := GetCurrentDir;
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

  var DownloadDir := TPath.Combine(GetBlocksDir, 'download');
  var ZipPath := TPath.Combine(DownloadDir, 'repository.zip');
  var RepoDir := TPath.Combine(GetBlocksDir, 'repository');

  if not TDirectory.Exists(GetBlocksDir) then
  begin
    TDirectory.CreateDirectory(GetBlocksDir);
    TConsole.WriteLine('Created: ' + GetBlocksDir, clGreen);
  end;

  if TDirectory.Exists(DownloadDir) then
    TDirectory.Delete(DownloadDir, True);
  TDirectory.CreateDirectory(DownloadDir);

  TConsole.WriteLine('Fetching repository info...', clCyan);
  var RepoInfo := THttpUtils.GetGitHubInfo(BlocksRepositoryUrl);
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
  var InnerDir := InnerDirs[0];

  var SourceRepo := TPath.Combine(InnerDir, '.blocks\repository');
  if not TDirectory.Exists(SourceRepo) then
    raise Exception.Create('Repository folder not found in downloaded archive: .blocks\repository');

  if TDirectory.Exists(RepoDir) then
  begin
    TConsole.WriteLine(Format('Directory "%s" already exists.', [RepoDir]), clYellow);
    TConsole.Write('Overwrite? [Y/N] (default: N): ');
    var Confirm := TConsole.ReadLine;
    if not SameText(Trim(Confirm), 'Y') then
    begin
      TConsole.WriteLine('Operation cancelled.', clYellow);
      TDirectory.Delete(DownloadDir, True);
      Exit;
    end;
    TDirectory.Delete(RepoDir, True);
  end;

  TDirectory.Copy(SourceRepo, RepoDir);
  TConsole.WriteLine('Repository updated: ' + RepoDir, clGreen);

  TDirectory.Delete(DownloadDir, True);
end;

end.
