unit Blocks.Http;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Zip,
  System.JSON,
  System.Net.HttpClient,
  Blocks.Consts;

/// <summary>Static HTTP helpers and GitHub API client.</summary>
type
  THttpUtils = class
  public
    /// <summary>Performs an HTTP GET request and returns the response body as a UTF-8 string.</summary>
    /// <param name="Url">The URL to fetch.</param>
    /// <returns>The response body decoded as UTF-8.</returns>
    /// <exception cref="Exception">Raised when the HTTP status code is 400 or higher.</exception>
    class function GetAsString(const Url: string): string; static;

    /// <summary>Downloads a URL to a local file, following redirects.</summary>
    /// <param name="Url">The URL to download.</param>
    /// <param name="DestPath">Destination file path; the file is created or overwritten.</param>
    class procedure DownloadFile(const Url, DestPath: string); static;

    /// <summary>Queries the GitHub API for a repository's default branch and latest commit SHA.</summary>
    /// <param name="RepoUrl">GitHub repository URL in the form <c>https://github.com/owner/repo</c>.</param>
    /// <returns>A <see cref="TGitHubInfo"/> record with owner, repo name, default branch,
    ///   and the latest commit SHA on that branch.</returns>
    class function GetGitHubInfo(const RepoUrl: string): TGitHubInfo; static;

    /// <summary>Returns the GitHub zipball download URL for a specific commit.</summary>
    /// <param name="Owner">Repository owner login.</param>
    /// <param name="Repo">Repository name.</param>
    /// <param name="CommitSha">Full commit SHA to download.</param>
    /// <returns>URL pointing to the zipball archive for the given commit.</returns>
    class function GetGitHubZipUrl(const Owner, Repo, CommitSha: string): string; static;

    /// <summary>Downloads and extracts a GitHub zipball archive into the workspace.</summary>
    /// <param name="ZipUrl">URL of the GitHub zipball archive to download.</param>
    /// <param name="DestinationDir">Workspace root; the extracted project is placed at
    ///   <c>DestinationDir\ProjectName</c>. The temporary download directory is created under
    ///   <c>DestinationDir\.blocks\download\</c> and removed after extraction.</param>
    /// <param name="ProjectName">Name of the target subfolder for the extracted project.</param>
    /// <param name="Overwrite">When <c>True</c>, an existing project directory is silently deleted
    ///   before the archive is extracted.</param>
    /// <param name="Silent">When <c>True</c>, raises an exception instead of prompting the user
    ///   when a directory conflict is detected and <c>Overwrite</c> is <c>False</c>.</param>
    /// <returns>Full path to the final extracted project directory.</returns>
    /// <remarks>GitHub wraps repository content in a generated top-level folder
    ///   (e.g. <c>owner-repo-abc1234/</c>); this function unwraps it automatically.</remarks>
    class function DownloadAndExtract(const ZipUrl, DestinationDir, ProjectName: string; Overwrite, Silent: Boolean): string; static;

  end;

implementation

uses
  Winapi.Windows,
  Blocks.Console;

// -- HTTP primitives -----------------------------------------------------------

class function THttpUtils.GetAsString(const Url: string): string;
begin
  var Client := THTTPClient.Create;
  try
    Client.CustomHeaders['User-Agent'] := 'BLOCKS/1.0';
    var Response := Client.Get(Url);
    if Response.StatusCode >= 400 then
      raise Exception.CreateFmt('HTTP %d for %s', [Response.StatusCode, Url]);
    Result := Response.ContentAsString(TEncoding.UTF8);
  finally
    Client.Free;
  end;
end;

class function THttpUtils.DownloadAndExtract(const ZipUrl, DestinationDir,
  ProjectName: string; Overwrite, Silent: Boolean): string;
begin
  var BlocksDir := TPath.Combine(DestinationDir, '.blocks');
  var DownloadDir := TPath.Combine(BlocksDir, 'download');
  var ZipPath := TPath.Combine(DownloadDir, 'download.zip');

  if TDirectory.Exists(DownloadDir) then
    TDirectory.Delete(DownloadDir, True);
  TDirectory.CreateDirectory(DownloadDir);

  TConsole.WriteLine('Downloading...', clCyan);
  THttpUtils.DownloadFile(ZipUrl, ZipPath);

  TConsole.WriteLine('Extracting...', clCyan);
  var ExtractDir := TPath.Combine(DownloadDir, 'extract');
  TDirectory.CreateDirectory(ExtractDir);
  TZipFile.ExtractZipFile(ZipPath, ExtractDir);

  // GitHub places content inside a single subdirectory (e.g. "owner-repo-abc1234")
  var InnerDirs := TDirectory.GetDirectories(ExtractDir);
  if Length(InnerDirs) = 0 then
    raise Exception.Create('Unexpected zip structure: no subdirectory found.');
  var InnerDir := InnerDirs[0];

  var FinalPath := TPath.Combine(DestinationDir, ProjectName);

  if TDirectory.Exists(FinalPath) then
  begin
    if Overwrite then
    begin
      TDirectory.Delete(FinalPath, True);
      TConsole.WriteLine(Format('Directory "%s" removed.', [FinalPath]), clYellow);
    end
    else if Silent then
      raise Exception.CreateFmt('Directory "%s" already exists. Use -Overwrite to replace it.', [FinalPath])
    else
    begin
      TConsole.WriteLine(Format('Directory "%s" already exists.', [FinalPath]), clYellow);
      TConsole.Write('Overwrite? [Y/N] (default: N): ');
      var Confirm := TConsole.ReadLine;
      if not SameText(Trim(Confirm), 'Y') then
        raise Exception.Create('Operation cancelled by user.');
      TDirectory.Delete(FinalPath, True);
      TConsole.WriteLine('Directory removed.', clYellow);
    end;
  end;

  if not MoveFileEx(PChar(InnerDir), PChar(FinalPath), MOVEFILE_COPY_ALLOWED) then
    RaiseLastOSError;

  TDirectory.Delete(DownloadDir, True);

  Result := FinalPath;
end;

class procedure THttpUtils.DownloadFile(const Url, DestPath: string);
begin
  var Client := THTTPClient.Create;
  try
    Client.CustomHeaders['User-Agent'] := 'BLOCKS/1.0';
    Client.HandleRedirects := True;
    var FS := TFileStream.Create(DestPath, fmCreate);
    try
      Client.Get(Url, FS);
    finally
      FS.Free;
    end;
  finally
    Client.Free;
  end;
end;

// -- GitHub API ----------------------------------------------------------------

class function THttpUtils.GetGitHubInfo(const RepoUrl: string): TGitHubInfo;
var
  DefaultBranch: string;
begin
  // 'https://github.com/owner/repo' ? Split('/') ? [https:, '', github.com, owner, repo]
  var Parts := TrimRight(RepoUrl, ['/']).Split(['/']);
  if Length(Parts) < 5 then
    raise Exception.Create('Invalid GitHub URL: ' + RepoUrl);
  var Owner := Parts[3];
  var Repo := Parts[4];

  var JsonStr := THttpUtils.GetAsString('https://api.github.com/repos/' + Owner + '/' + Repo);
  var Json := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
  try
    DefaultBranch := Json.GetValue<string>('default_branch');
  finally
    Json.Free;
  end;

  JsonStr := THttpUtils.GetAsString('https://api.github.com/repos/' + Owner + '/' + Repo + '/commits/' + DefaultBranch);
  Json := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
  try
    Result.LatestCommit := Json.GetValue<string>('sha');
  finally
    Json.Free;
  end;

  Result.Owner := Owner;
  Result.Repo := Repo;
  Result.DefaultBranch := DefaultBranch;
end;

class function THttpUtils.GetGitHubZipUrl(const Owner, Repo, CommitSha: string): string;
begin
  Result := 'https://api.github.com/repos/' + Owner + '/' + Repo + '/zipball/' + CommitSha;
end;

end.
