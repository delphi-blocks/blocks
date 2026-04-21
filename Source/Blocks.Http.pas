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
unit Blocks.Http;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  System.Net.HttpClient,
  System.Net.URLClient,
  Blocks.Core;

/// <summary>Static HTTP helpers and GitHub API client.</summary>
type
  EHttpError = class(Exception)
  public
    constructor Create(AResponse: IHTTPResponse; const AUrl: string);
  end;

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

    /// <summary>Extract the file name from full URL.</summary>
    class function ExtractFileName(const Url: string): string; static;

  end;

implementation

uses
  Blocks.Console;

class function THttpUtils.ExtractFileName(const Url: string): string;
begin
  var P := Url.LastIndexOf('/');
  if P < 0 then
    Result := Url
  else
    Result := Url.Substring(P + 1);
end;

class function THttpUtils.GetAsString(const Url: string): string;
begin
  var Client := THTTPClient.Create;
  try
    Client.ReceiveDataExCallback :=
      procedure (const Sender: TObject; AContentLength, AReadCount: Int64; AChunk: Pointer; AChunkLength: Cardinal; var AAbort: Boolean)
      begin
        TConsole.StdOut.WriteProgress(AReadCount, AContentLength);
      end;
    Client.CustomHeaders['User-Agent'] := 'BLOCKS/1.0';
    var Response := Client.Get(Url);
    TConsole.WriteLine;
    if Response.StatusCode >= 400 then
      raise EHttpError.Create(Response, Url);
    Result := Response.ContentAsString(TEncoding.UTF8);
  finally
    Client.Free;
  end;
end;

class procedure THttpUtils.DownloadFile(const Url, DestPath: string);
begin
  var Client := THttpClient.Create;
  try
    Client.ReceiveDataExCallback :=
      procedure (const Sender: TObject; AContentLength, AReadCount: Int64; AChunk: Pointer; AChunkLength: Cardinal; var AAbort: Boolean)
      begin
        TConsole.StdOut.WriteProgress(AReadCount, AContentLength);
      end;
    Client.CustomHeaders['User-Agent'] := 'BLOCKS/1.0';
    Client.HandleRedirects := True;
    var FS := TFileStream.Create(DestPath, fmCreate);
    try
      var LHttpResponse := Client.Get(Url, FS);
      if LHttpResponse.StatusCode >= 400 then
        raise EHttpError.Create(LHttpResponse, Url);

      TConsole.WriteLine;
    finally
      FS.Free;
    end;
  finally
    Client.Free;
  end;
end;

{ EHttpError }

constructor EHttpError.Create(AResponse: IHTTPResponse; const AUrl: string);
begin
  inherited CreateFmt('HTTP %d for %s', [AResponse.StatusCode, AUrl]);
end;

end.
