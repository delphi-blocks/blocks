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
unit Blocks.Consts;

interface

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections;

// -- Application constants ----------------------------------------------------

const
  VersionOrder: array[0..10] of string = (
      'delphixe6',
      'delphixe7',
      'delphixe8',
      'delphi10',
      'delphi101',
      'delphi102',
      'delphi103',
      'delphi104',
      'delphi11',
      'delphi12',
      'delphi13'
  );

// -- Shared types -------------------------------------------------------------

var
  AppExeName: string;

// -- Version maps (populated in initialization) -------------------------------

var
  BdsToVersion: TDictionary<string, string>;
  VersionNames: TDictionary<string, string>;
  PackageVersion: TDictionary<string, string>;

// -- Utility ------------------------------------------------------------------

/// <summary>Removes trailing characters belonging to a specified set from a string.</summary>
/// <param name="S">The input string.</param>
/// <param name="Chars">The set of characters to strip from the right end of <c>S</c>.</param>
/// <returns>A copy of <c>S</c> with all trailing characters in <c>Chars</c> removed.</returns>
/// <remarks>Overloads <c>System.SysUtils.TrimRight</c>, which only removes whitespace.</remarks>
function TrimRight(const S: string; const Chars: array of Char): string; overload;

implementation

function TrimRight(const S: string; const Chars: array of Char): string;
var
  Found: Boolean;
begin
  var Len := Length(S);
  while Len > 0 do
  begin
    Found := False;
    for var I := Low(Chars) to High(Chars) do
      if S[Len] = Chars[I] then
      begin
        Found := True;
        Break;
      end;
    if Found then
      Dec(Len)
    else
      Break;
  end;
  Result := Copy(S, 1, Len);
end;

initialization
  BdsToVersion := TDictionary<string, string>.Create;
  BdsToVersion.Add('14.0', 'delphixe6');
  BdsToVersion.Add('15.0', 'delphixe7');
  BdsToVersion.Add('16.0', 'delphixe8');
  BdsToVersion.Add('17.0', 'delphi10');
  BdsToVersion.Add('18.0', 'delphi101');
  BdsToVersion.Add('19.0', 'delphi102');
  BdsToVersion.Add('20.0', 'delphi103');
  BdsToVersion.Add('21.0', 'delphi104');
  BdsToVersion.Add('22.0', 'delphi11');
  BdsToVersion.Add('23.0', 'delphi12');
  BdsToVersion.Add('37.0', 'delphi13');

  VersionNames := TDictionary<string, string>.Create;
  VersionNames.Add('delphixe6', 'Delphi XE6');
  VersionNames.Add('delphixe7', 'Delphi XE7');
  VersionNames.Add('delphixe8', 'Delphi XE8');
  VersionNames.Add('delphi10', 'Delphi 10 Seattle');
  VersionNames.Add('delphi101', 'Delphi 10.1 Berlin');
  VersionNames.Add('delphi102', 'Delphi 10.2 Tokyo');
  VersionNames.Add('delphi103', 'Delphi 10.3 Rio');
  VersionNames.Add('delphi104', 'Delphi 10.4 Sydney');
  VersionNames.Add('delphi11', 'Delphi 11 Alexandria');
  VersionNames.Add('delphi12', 'Delphi 12 Athens');
  VersionNames.Add('delphi13', 'Delphi 13');

  PackageVersion := TDictionary<string, string>.Create;
  PackageVersion.Add('delphixe6', '200');
  PackageVersion.Add('delphixe7', '210');
  PackageVersion.Add('delphixe8', '220');
  PackageVersion.Add('delphi10', '230');
  PackageVersion.Add('delphi101', '240');
  PackageVersion.Add('delphi102', '250');
  PackageVersion.Add('delphi103', '260');
  PackageVersion.Add('delphi104', '270');
  PackageVersion.Add('delphi11', '280');
  PackageVersion.Add('delphi12', '290');
  PackageVersion.Add('delphi13', '370');

  AppExeName := ExtractFileName(ChangeFileExt(ParamStr(0), ''));

finalization
  BdsToVersion.Free;
  VersionNames.Free;
  PackageVersion.Free;

end.
