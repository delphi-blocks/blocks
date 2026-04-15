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
      'delphiberlin',
      'delphitokyo',
      'delphirio',
      'delphisydney',
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
  BdsToVersion.Add('18.0', 'delphiberlin');
  BdsToVersion.Add('19.0', 'delphitokyo');
  BdsToVersion.Add('20.0', 'delphirio');
  BdsToVersion.Add('21.0', 'delphisydney');
  BdsToVersion.Add('22.0', 'delphi11');
  BdsToVersion.Add('23.0', 'delphi12');
  BdsToVersion.Add('37.0', 'delphi13');

  VersionNames := TDictionary<string, string>.Create;
  VersionNames.Add('delphixe6', 'Delphi XE6');
  VersionNames.Add('delphixe7', 'Delphi XE7');
  VersionNames.Add('delphixe8', 'Delphi XE8');
  VersionNames.Add('delphi10', 'Delphi 10 Seattle');
  VersionNames.Add('delphiberlin', 'Delphi 10.1 Berlin');
  VersionNames.Add('delphitokyo', 'Delphi 10.2 Tokyo');
  VersionNames.Add('delphirio', 'Delphi 10.3 Rio');
  VersionNames.Add('delphisydney', 'Delphi 10.4 Sydney');
  VersionNames.Add('delphi11', 'Delphi 11 Alexandria');
  VersionNames.Add('delphi12', 'Delphi 12 Athens');
  VersionNames.Add('delphi13', 'Delphi 13');

  AppExeName := ExtractFileName(ChangeFileExt(ParamStr(0), ''));

finalization
  BdsToVersion.Free;
  VersionNames.Free;

end.
