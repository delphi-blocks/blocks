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
unit Blocks.Bitbucket;

interface

type
  TBitbucket = class
  public
    /// <summary>Returns the Bitbucket Cloud archive download URL for a specific ref.</summary>
    /// <param name="Owner">Repository owner (workspace) login.</param>
    /// <param name="Repo">Repository name.</param>
    /// <param name="Ref">Branch, tag or commit hash to download.</param>
    /// <returns>URL pointing to the ZIP archive for the given ref.</returns>
    class function GetBitbucketZipUrl(const Owner, Repo, Ref: string): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TBitbucket }

class function TBitbucket.GetBitbucketZipUrl(const Owner, Repo, Ref: string): string;
begin
  // Bitbucket Cloud wraps the archive in a single subdirectory
  // (e.g. "owner-repo-<commit>"), like GitHub's zipball.
  Result := Format('https://bitbucket.org/%s/%s/get/%s.zip', [Owner, Repo, Ref]);
end;

end.
