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
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Winapi.Windows;

type
  // -----------------------------------------------------------------------
  // Semantic version (major.minor.patch[.build])
  // -----------------------------------------------------------------------
  TSemVer = record
  public
    Major: Integer;
    Minor: Integer;
    Patch: Integer;
    Build: Integer;
    class function TryParse(const S: string; out V: TSemVer): Boolean; static;
    class function Parse(const S: string): TSemVer; static;
    /// <summary>Returns the highest version in AVersions that satisfies AConstraint.
    /// Returns False if no version matches.</summary>
    class function BestMatch(
        const AVersions: TArray<TSemVer>;
        const AConstraint: string;
        out ABest: TSemVer
    ): Boolean; static;
    class operator Implicit(const AVersion: TSemVer): string;
    class operator Implicit(const AVersionStr: string): TSemVer;
    class operator LessThan(const A, B: TSemVer): Boolean;
    class operator GreaterThan(const A, B: TSemVer): Boolean;
    class operator LessThanOrEqual(const A, B: TSemVer): Boolean;
    class operator GreaterThanOrEqual(const A, B: TSemVer): Boolean;
    class operator Equal(const A, B: TSemVer): Boolean;
    class operator NotEqual(const A, B: TSemVer): Boolean;
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

type
  TMatchEvaluatorFunc = reference to function(const AMatch: TMatch): string;

/// <summary>Like <c>TRegEx.Replace</c> with an evaluator, but accepts an anonymous
///   method/closure instead of an <c>of object</c> method pointer.</summary>
/// <remarks>Wraps the closure in a temporary object so it can be passed where
///   <c>TMatchEvaluator</c> is required.</remarks>
function RegExReplace(const AInput, APattern: string; const AEvaluator: TMatchEvaluatorFunc): string;

/// <summary>Expands variable references in <paramref name="AValue"/> using
///   <paramref name="AEnvironmentVariables"/>, with the Delphi/MSBuild
///   <c>$(VAR)</c> syntax. The legacy <c>%VAR%</c> syntax is still recognised for
///   backward compatibility. Unknown variables resolve to an empty string.</summary>
function ExpandVariables(const AValue: string; AEnvironmentVariables: TStrings): string;

/// <summary>Returns True if <paramref name="APlatform"/> is a POSIX target
///   (Linux, Android or iOS/macOS), as opposed to a Windows target.</summary>
function IsPosix(const APlatform: string): Boolean;

/// <summary>Returns True if <paramref name="APlatform"/> is an Apple/Darwin
///   target (macOS or iOS). These produce <c>.dylib</c> libraries instead of
///   the <c>.so</c> used by the other POSIX targets.</summary>
function IsApple(const APlatform: string): Boolean;

/// <summary>Returns True when <paramref name="APlatform"/> is allowed by the
///   list <paramref name="AList"/>. An empty list means "all platforms", so it
///   always returns True; otherwise the match is case-insensitive.</summary>
function PlatformInList(const AList: TArray<string>; const APlatform: string): Boolean;

/// <summary>Runs <paramref name="ACmdLine"/> hidden (no console window), capturing its
///   merged stdout/stderr into <paramref name="AOutput"/> and returning the process
///   exit code.</summary>
/// <exception cref="EOSError">Raised when the process cannot be started (e.g. the
///   executable is not found).</exception>
function RunProcess(const ACmdLine: string; out AOutput: string): Integer;

type
  // -- Filesystem helpers (resilient to transient AV/indexer locks) -----------
  TFileUtils = class
  public
    /// <summary>Moves a file or directory like WinAPI <c>MoveFileEx</c> (with
    ///   <c>MOVEFILE_COPY_ALLOWED</c>), retrying briefly on transient
    ///   sharing/access errors.</summary>
    /// <remarks>Antivirus real-time scanning or the Search Indexer routinely
    ///   hold a freshly written file/directory open for a few hundred
    ///   milliseconds, making the move fail intermittently with
    ///   <c>ERROR_ACCESS_DENIED</c> or <c>ERROR_SHARING_VIOLATION</c>. Those
    ///   errors are retried with a short increasing back-off; any other error
    ///   fails immediately.</remarks>
    /// <exception cref="EOSError">Raised on a non-transient error, or when the
    ///   move still fails after the retry budget is exhausted.</exception>
    class procedure SafeMove(const ASource, ADestination: string); static;

    /// <summary>Recursively deletes a directory, retrying briefly on the same
    ///   transient sharing/access errors as <see cref="SafeMove"/>. A missing
    ///   directory is treated as success.</summary>
    class procedure SafeDeleteDirectory(const APath: string); static;
  end;

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

type
  TMatchEvaluatorWrapper = class
  private
    FEvaluator: TMatchEvaluatorFunc;
    function Evaluate(const AMatch: TMatch): string;
  end;

function TMatchEvaluatorWrapper.Evaluate(const AMatch: TMatch): string;
begin
  Result := FEvaluator(AMatch);
end;

function RegExReplace(const AInput, APattern: string; const AEvaluator: TMatchEvaluatorFunc): string;
begin
  var LWrapper := TMatchEvaluatorWrapper.Create;
  try
    LWrapper.FEvaluator := AEvaluator;
    Result := TRegEx.Replace(AInput, APattern, LWrapper.Evaluate);
  finally
    LWrapper.Free;
  end;
end;

function ExpandVariables(const AValue: string; AEnvironmentVariables: TStrings): string;
var
  LLookup: TMatchEvaluatorFunc;
begin
  LLookup :=
      function(const AMatch: TMatch): string
      begin
        // Unknown variables resolve to '' (Values returns '' for absent keys).
        Result := AEnvironmentVariables.Values[AMatch.Groups[1].Value];
      end;
  // $(VAR) is the Delphi/MSBuild macro syntax; the legacy %VAR% form is still
  // accepted for backward compatibility. Each pass uses a single capture group
  // so the matched variable name is always Groups[1].
  Result := RegExReplace(AValue, '%([^%]+)%', LLookup);
  Result := RegExReplace(Result, '\$\(([^)]+)\)', LLookup);
end;

function IsPosix(const APlatform: string): Boolean;
const
  PosixPlatforms: array[0..5] of string = ('Linux64', 'Android', 'Android64', 'iOSDevice64', 'OSX64', 'OSXARM64');
begin
  Result := False;
  for var LPlatform in PosixPlatforms do
    if SameText(APlatform, LPlatform) then
      Exit(True);
end;

function IsApple(const APlatform: string): Boolean;
const
  ApplePlatforms: array[0..2] of string = ('OSX64', 'OSXARM64', 'iOSDevice64');
begin
  Result := False;
  for var LPlatform in ApplePlatforms do
    if SameText(APlatform, LPlatform) then
      Exit(True);
end;

function PlatformInList(const AList: TArray<string>; const APlatform: string): Boolean;
begin
  // An empty list is the "all platforms" sentinel.
  if Length(AList) = 0 then
    Exit(True);

  Result := False;
  for var LPlatform in AList do
    if SameText(APlatform, LPlatform) then
      Exit(True);
end;

function RunProcess(const ACmdLine: string; out AOutput: string): Integer;
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  hRead, hWrite: THandle;
  Buffer: array[0..4095] of Byte;
  BytesRead: DWORD;
  ExitCode: DWORD;
  MS: TMemoryStream;
  Bytes: TBytes;
begin
  AOutput := '';

  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;

  if not CreatePipe(hRead, hWrite, @SA, 0) then
    RaiseLastOSError;
  SetHandleInformation(hRead, HANDLE_FLAG_INHERIT, 0);

  ZeroMemory(@SI, SizeOf(SI));
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESTDHANDLES;
  SI.hStdOutput := hWrite;
  SI.hStdError := hWrite;
  SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);

  ZeroMemory(@PI, SizeOf(PI));

  if not CreateProcess(nil, PChar(ACmdLine), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
  begin
    CloseHandle(hRead);
    CloseHandle(hWrite);
    RaiseLastOSError;
  end;

  CloseHandle(hWrite);

  MS := TMemoryStream.Create;
  try
    while ReadFile(hRead, Buffer[0], SizeOf(Buffer), BytesRead, nil) and (BytesRead > 0) do
      MS.Write(Buffer[0], BytesRead);

    SetLength(Bytes, MS.Size);
    if MS.Size > 0 then
    begin
      MS.Position := 0;
      MS.Read(Bytes[0], MS.Size);
    end;
    AOutput := TEncoding.Default.GetString(Bytes);
  finally
    MS.Free;
  end;

  WaitForSingleObject(PI.hProcess, INFINITE);
  GetExitCodeProcess(PI.hProcess, ExitCode);
  Result := Integer(ExitCode);

  CloseHandle(PI.hProcess);
  CloseHandle(PI.hThread);
  CloseHandle(hRead);
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

const
  // A just-written file held open by antivirus/Search Indexer surfaces as one of
  // these; both clear within a few hundred ms, so a short retry is worthwhile.
  FSRetryAttempts = 5;
  FSRetryBaseDelayMs = 150;

function IsTransientFSError(AError: Cardinal): Boolean;
begin
  Result := (AError = ERROR_ACCESS_DENIED) or (AError = ERROR_SHARING_VIOLATION);
end;

class procedure TFileUtils.SafeMove(const ASource, ADestination: string);
begin
  for var LAttempt := 1 to FSRetryAttempts do
  begin
    if MoveFileEx(PChar(ASource), PChar(ADestination), MOVEFILE_COPY_ALLOWED) then
      Exit;

    var LErr := GetLastError;
    if (LAttempt = FSRetryAttempts) or not IsTransientFSError(LErr) then
    begin
      SetLastError(LErr);
      RaiseLastOSError;
    end;
    Sleep(FSRetryBaseDelayMs * LAttempt);
  end;
end;

class procedure TFileUtils.SafeDeleteDirectory(const APath: string);
begin
  if not TDirectory.Exists(APath) then
    Exit;

  for var LAttempt := 1 to FSRetryAttempts do
  begin
    try
      TDirectory.Delete(APath, True);
      Exit;
    except
      on E: Exception do
      begin
        if LAttempt = FSRetryAttempts then
          raise;
        Sleep(FSRetryBaseDelayMs * LAttempt);
      end;
    end;
  end;
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
  if (Length(LParts) >= 4) and not TryStrToInt(LParts[3], V.Build) then
    Exit(False);
  Result := True;
end;

class function TSemVer.Parse(const S: string): TSemVer;
begin
  if not TryParse(S, Result) then
    raise Exception.CreateFmt('Invalid version: "%s"', [S]);
end;

class function TSemVer.BestMatch(
    const AVersions: TArray<TSemVer>;
    const AConstraint: string;
    out ABest: TSemVer
): Boolean;
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
  if Major <> Other.Major then
    Exit(Major - Other.Major);
  if Minor <> Other.Minor then
    Exit(Minor - Other.Minor);
  if Patch <> Other.Patch then
    Exit(Patch - Other.Patch);
  Result := Build - Other.Build;
end;

class operator TSemVer.Implicit(const AVersionStr: string): TSemVer;
begin
  Result := TSemVer.Parse(AVersionStr);
end;

class operator TSemVer.LessThan(const A, B: TSemVer): Boolean;
begin
  Result := A.CompareTo(B) < 0;
end;

class operator TSemVer.GreaterThan(const A, B: TSemVer): Boolean;
begin
  Result := A.CompareTo(B) > 0;
end;

class operator TSemVer.LessThanOrEqual(const A, B: TSemVer): Boolean;
begin
  Result := A.CompareTo(B) <= 0;
end;

class operator TSemVer.GreaterThanOrEqual(const A, B: TSemVer): Boolean;
begin
  Result := A.CompareTo(B) >= 0;
end;

class operator TSemVer.Equal(const A, B: TSemVer): Boolean;
begin
  Result := A.CompareTo(B) = 0;
end;

class operator TSemVer.NotEqual(const A, B: TSemVer): Boolean;
begin
  Result := A.CompareTo(B) <> 0;
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
    if not TSemVer.TryParse(Copy(LConstraint, 3, MaxInt), LVer) then
      Exit(False);
    Exit(CompareTo(LVer) >= 0);
  end;
  if LConstraint.StartsWith('<=') then
  begin
    if not TSemVer.TryParse(Copy(LConstraint, 3, MaxInt), LVer) then
      Exit(False);
    Exit(CompareTo(LVer) <= 0);
  end;
  if LConstraint.StartsWith('>') then
  begin
    if not TSemVer.TryParse(Copy(LConstraint, 2, MaxInt), LVer) then
      Exit(False);
    Exit(CompareTo(LVer) > 0);
  end;
  if LConstraint.StartsWith('<') then
  begin
    if not TSemVer.TryParse(Copy(LConstraint, 2, MaxInt), LVer) then
      Exit(False);
    Exit(CompareTo(LVer) < 0);
  end;
  if LConstraint.StartsWith('^') then
  begin
    if not TSemVer.TryParse(Copy(LConstraint, 2, MaxInt), LVer) then
      Exit(False);
    LUpper := Default(TSemVer);
    // Caret allows changes that do not modify the left-most non-zero element.
    // For 0.x versions the minor (or patch) takes the role of the major.
    if LVer.Major <> 0 then
      LUpper.Major := LVer.Major + 1
    else if LVer.Minor <> 0 then
      LUpper.Minor := LVer.Minor + 1
    else
      LUpper.Patch := LVer.Patch + 1;
    Exit((CompareTo(LVer) >= 0) and (CompareTo(LUpper) < 0));
  end;
  if LConstraint.StartsWith('~') then
  begin
    if not TSemVer.TryParse(Copy(LConstraint, 2, MaxInt), LVer) then
      Exit(False);
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
  if Build <> 0 then
    Result := Format('%d.%d.%d.%d', [Major, Minor, Patch, Build])
  else
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
  Result.Build := LoWord(LFixed.dwFileVersionLS);
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
