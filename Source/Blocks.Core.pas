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
unit Blocks.Core;

interface

uses
  System.Classes, System.SysUtils, System.RegularExpressions,
  System.Generics.Collections,
  Winapi.Windows;

type
  // -----------------------------------------------------------------------
  // Semantic version (major.minor.patch)
  // -----------------------------------------------------------------------
  TSemVer = record
  public
    Major: Integer;
    Minor: Integer;
    Patch: Integer;
    class function TryParse(const S: string; out V: TSemVer): Boolean; static;
    class function Parse(const S: string): TSemVer; static;
    /// <summary>Returns the highest version in AVersions that satisfies AConstraint.
    /// Returns False if no version matches.</summary>
    class function BestMatch(const AVersions: TArray<TSemVer>; const AConstraint: string; out ABest: TSemVer): Boolean; static;
    class operator Implicit(const AVersion: TSemVer): string;
    class operator Implicit(const AVersionStr: string): TSemVer;
    function CompareTo(const Other: TSemVer): Integer;
    function MatchesConstraint(const AConstraint: string): Boolean;
    function ToString: string;
  end;

  TAppVersion = class
  public
    class function GetFileVersion(const AFileName: string): TSemVer; static;
    class function GetCurrentVersion: TSemVer; static;
  end;

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

/// <summary>Extra version numer from a string assuming is in SemVer format.</summary>
function ExtractVersionNumber(const S: string): string;

implementation

function ExtractVersionNumber(const S: string): string;
var
  Match: TMatch;
begin
  Result := '';
  Match := TRegEx.Match(S, '\d+(\.\d+)*');
  if Match.Success then
    Result := Match.Value;
end;

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

procedure InitializeVersionConstant;
begin
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
end;

procedure FinalizeVersionConstant;
begin
  BdsToVersion.Free;
  VersionNames.Free;
  PackageVersion.Free;
end;

{ TSemVer }

class function TSemVer.TryParse(const S: string; out V: TSemVer): Boolean;
begin
  V := Default(TSemVer);
  var LParts := S.Trim.Split(['.']);
  if Length(LParts) < 1 then
    Exit(False);
  if not TryStrToInt(LParts[0], V.Major) then
    Exit(False);
  if (Length(LParts) >= 2) and not TryStrToInt(LParts[1], V.Minor) then
    Exit(False);
  if (Length(LParts) >= 3) and not TryStrToInt(LParts[2], V.Patch) then
    Exit(False);
  Result := True;
end;

class function TSemVer.Parse(const S: string): TSemVer;
begin
  if not TryParse(S, Result) then
    raise Exception.CreateFmt('Invalid version: "%s"', [S]);
end;

class function TSemVer.BestMatch(const AVersions: TArray<TSemVer>;
  const AConstraint: string; out ABest: TSemVer): Boolean;
begin
  Result := False;
  for var LVer in AVersions do
  begin
    if not LVer.MatchesConstraint(AConstraint) then
      Continue;
    if not Result or (LVer.CompareTo(ABest) > 0) then
      ABest := LVer;
    Result := True;
  end;
end;

class operator TSemVer.Implicit(const AVersion: TSemVer): string;
begin
  Result := AVersion.ToString;
end;

function TSemVer.CompareTo(const Other: TSemVer): Integer;
begin
  if Major <> Other.Major then Exit(Major - Other.Major);
  if Minor <> Other.Minor then Exit(Minor - Other.Minor);
  Result := Patch - Other.Patch;
end;

class operator TSemVer.Implicit(const AVersionStr: string): TSemVer;
begin
  Result := TSemVer.Parse(AVersionStr);
end;

function TSemVer.MatchesConstraint(const AConstraint: string): Boolean;
var
  LConstraint: string;
  LVer, LUpper: TSemVer;
begin
  LConstraint := Trim(AConstraint);

  if (LConstraint = '') or (LConstraint = '*') then
    Exit(True);

  // Explicit range: two or more space-separated constraints (implicit AND)
  // e.g. ">=1.2.0 <2.0.0"
  if LConstraint.Contains(' ') then
  begin
    for var LPart in LConstraint.Split([' ']) do
      if not MatchesConstraint(Trim(LPart)) then
        Exit(False);
    Exit(True);
  end;

  // Wildcards: 1.* or 1.2.*
  if LConstraint.Contains('*') then
  begin
    var LParts := LConstraint.Split(['.']);
    var LMajor, LMinor: Integer;
    if (Length(LParts) >= 1) and (LParts[0] <> '*') then
      if not TryStrToInt(LParts[0], LMajor) or (Major <> LMajor) then
        Exit(False);
    if (Length(LParts) >= 2) and (LParts[1] <> '*') then
      if not TryStrToInt(LParts[1], LMinor) or (Minor <> LMinor) then
        Exit(False);
    Exit(True);
  end;

  if LConstraint.StartsWith('>=') then
  begin
    if not TSemVer.TryParse(Copy(LConstraint, 3, MaxInt), LVer) then Exit(False);
    Exit(CompareTo(LVer) >= 0);
  end;
  if LConstraint.StartsWith('<=') then
  begin
    if not TSemVer.TryParse(Copy(LConstraint, 3, MaxInt), LVer) then Exit(False);
    Exit(CompareTo(LVer) <= 0);
  end;
  if LConstraint.StartsWith('>') then
  begin
    if not TSemVer.TryParse(Copy(LConstraint, 2, MaxInt), LVer) then Exit(False);
    Exit(CompareTo(LVer) > 0);
  end;
  if LConstraint.StartsWith('<') then
  begin
    if not TSemVer.TryParse(Copy(LConstraint, 2, MaxInt), LVer) then Exit(False);
    Exit(CompareTo(LVer) < 0);
  end;
  if LConstraint.StartsWith('^') then
  begin
    if not TSemVer.TryParse(Copy(LConstraint, 2, MaxInt), LVer) then Exit(False);
    LUpper := Default(TSemVer);
    LUpper.Major := LVer.Major + 1;
    Exit((CompareTo(LVer) >= 0) and (CompareTo(LUpper) < 0));
  end;
  if LConstraint.StartsWith('~') then
  begin
    if not TSemVer.TryParse(Copy(LConstraint, 2, MaxInt), LVer) then Exit(False);
    LUpper := Default(TSemVer);
    LUpper.Major := LVer.Major;
    LUpper.Minor := LVer.Minor + 1;
    Exit((CompareTo(LVer) >= 0) and (CompareTo(LUpper) < 0));
  end;

  // Exact match
  if TSemVer.TryParse(LConstraint, LVer) then
    Exit(CompareTo(LVer) = 0);

  Result := False;
end;

function TSemVer.ToString: string;
begin
  Result := Format('%d.%d.%d', [Major, Minor, Patch]);
end;

{ TAppVersion }

class function TAppVersion.GetFileVersion(const AFileName: string): TSemVer;
var
  LHandle: DWORD;
  LSize: DWORD;
  LBuffer: TBytes;
  LInfo: Pointer;
  LLen: UINT;
  LFixed: PVSFixedFileInfo;
begin
  Result := Default(TSemVer);
  LHandle := 0;
  LSize := GetFileVersionInfoSize(PChar(AFileName), LHandle);
  if LSize = 0 then
    Exit;
  SetLength(LBuffer, LSize);
  if not GetFileVersionInfo(PChar(AFileName), LHandle, LSize, @LBuffer[0]) then
    Exit;
  LInfo := nil;
  if not VerQueryValue(@LBuffer[0], '\', LInfo, LLen) then
    Exit;
  LFixed := PVSFixedFileInfo(LInfo);
  Result.Major := HiWord(LFixed.dwFileVersionMS);
  Result.Minor := LoWord(LFixed.dwFileVersionMS);
  Result.Patch := HiWord(LFixed.dwFileVersionLS);
end;

class function TAppVersion.GetCurrentVersion: TSemVer;
begin
  Result := GetFileVersion(ParamStr(0));
end;

initialization
  AppExeName := ExtractFileName(ChangeFileExt(ParamStr(0), ''));
  InitializeVersionConstant;

finalization

  FinalizeVersionConstant;

end.
