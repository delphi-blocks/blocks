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
unit Blocks.Service.Fetcher;

interface

uses
  System.SysUtils,
  Blocks.Model.Manifest;

type
  /// <summary>Fetches the package sources described by a manifest repository
  ///   into a destination directory. Implementations choose the transport
  ///   (GitHub archive, local path, ...) based on the repository type.</summary>
  IRepositoryFetcher = interface
    ['{7E3A6B2C-1D4F-4C8A-9B5E-2F6A0C1D3E47}']
    /// <summary>Populates <paramref name="ADestinationDir"/> with the package
    ///   sources. The destination must not already exist; the caller is
    ///   responsible for clearing it beforehand.</summary>
    procedure FetchTo(ARepository: TManifestRepository; const ADestinationDir: string);
  end;

  TRepositoryFetcher = class
  public
    /// <summary>Returns the fetcher matching <c>ARepository.RepoType</c>.
    ///   Raises when the type is empty or unsupported.</summary>
    class function ForRepository(ARepository: TManifestRepository): IRepositoryFetcher; static;
  end;

implementation

uses
  System.IOUtils,
  System.Zip,
  Blocks.Core,
  Blocks.Http,
  Blocks.Console,
  Blocks.GitHub,
  Blocks.Bitbucket;

type
  /// <summary>Base class for fetchers that download a ZIP archive whose content
  ///   is wrapped in a single subdirectory (e.g. "owner-repo-abc1234"), as both
  ///   GitHub and Bitbucket Cloud archives are. Subclasses only build the URL.</summary>
  TArchiveFetcher = class(TInterfacedObject, IRepositoryFetcher)
  protected
    /// <summary>Builds the archive download URL from the manifest repository.</summary>
    function BuildZipUrl(ARepository: TManifestRepository): string; virtual; abstract;
  public
    procedure FetchTo(ARepository: TManifestRepository; const ADestinationDir: string);
  end;

  TGitHubFetcher = class(TArchiveFetcher)
  protected
    function BuildZipUrl(ARepository: TManifestRepository): string; override;
  end;

  TBitbucketFetcher = class(TArchiveFetcher)
  protected
    function BuildZipUrl(ARepository: TManifestRepository): string; override;
  end;

  TLocalFetcher = class(TInterfacedObject, IRepositoryFetcher)
  public
    procedure FetchTo(ARepository: TManifestRepository; const ADestinationDir: string);
  end;

{ TRepositoryFetcher }

class function TRepositoryFetcher.ForRepository(ARepository: TManifestRepository): IRepositoryFetcher;
begin
  if SameText(ARepository.RepoType, 'github') then
    Result := TGitHubFetcher.Create
  else if SameText(ARepository.RepoType, 'bitbucket') then
    Result := TBitbucketFetcher.Create
  else if SameText(ARepository.RepoType, 'local') then
    Result := TLocalFetcher.Create
  else
    raise Exception.CreateFmt('Unsupported repository type: "%s"', [ARepository.RepoType]);
end;

{ TArchiveFetcher }

procedure TArchiveFetcher.FetchTo(ARepository: TManifestRepository; const ADestinationDir: string);
begin
  var LZipUrl := BuildZipUrl(ARepository);

  // Keep the temp download on the same volume as the destination so the final
  // directory move is a rename rather than a cross-volume copy.
  var LWorkDir := TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(ADestinationDir));
  var LDownloadDir := TPath.Combine(LWorkDir, TPath.Combine('.blocks', 'download'));
  TFileUtils.SafeDeleteDirectory(LDownloadDir);
  TDirectory.CreateDirectory(LDownloadDir);
  try
    var LZipPath := TPath.Combine(LDownloadDir, 'download.zip');
    TConsole.WriteLine('Downloading...', clCyan);
    THttpUtils.DownloadFile(LZipUrl, LZipPath);

    TConsole.WriteLine('Extracting...', clCyan);
    var LExtractDir := TPath.Combine(LDownloadDir, 'extract');
    TDirectory.CreateDirectory(LExtractDir);
    TZipFile.ExtractZipFile(LZipPath, LExtractDir);

    // The archive wraps content in a single subdirectory (e.g. "owner-repo-abc1234").
    var LInnerDirs := TDirectory.GetDirectories(LExtractDir);
    if Length(LInnerDirs) = 0 then
      raise Exception.Create('Unexpected zip structure: no subdirectory found.');

    TFileUtils.SafeMove(LInnerDirs[0], ADestinationDir);
  finally
    TFileUtils.SafeDeleteDirectory(LDownloadDir);
  end;
end;

{ TGitHubFetcher }

function TGitHubFetcher.BuildZipUrl(ARepository: TManifestRepository): string;
begin
  // Repository URL format: https://github.com/owner/repo/tree/ref
  var LRepoParts := TrimRight(ARepository.Url, ['/']).Split(['/']);
  if Length(LRepoParts) < 7 then
    raise Exception.CreateFmt('Cannot parse repository URL: %s', [ARepository.Url]);
  Result := TGitHub.GetGitHubZipUrl(LRepoParts[3], LRepoParts[4], LRepoParts[6]);
end;

{ TBitbucketFetcher }

function TBitbucketFetcher.BuildZipUrl(ARepository: TManifestRepository): string;
begin
  // Repository URL format: https://bitbucket.org/owner/repo/src/ref
  var LRepoParts := TrimRight(ARepository.Url, ['/']).Split(['/']);
  if Length(LRepoParts) < 7 then
    raise Exception.CreateFmt('Cannot parse repository URL: %s', [ARepository.Url]);
  Result := TBitbucket.GetBitbucketZipUrl(LRepoParts[3], LRepoParts[4], LRepoParts[6]);
end;

{ TLocalFetcher }

procedure TLocalFetcher.FetchTo(ARepository: TManifestRepository; const ADestinationDir: string);
begin
  if not TDirectory.Exists(ARepository.Url) then
    raise Exception.CreateFmt('Local repository path not found: %s', [ARepository.Url]);
  TConsole.WriteLine('Copying from local path...', clCyan);
  TDirectory.Copy(ARepository.Url, ADestinationDir);
end;

end.
