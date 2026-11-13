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
unit Blocks.Model.ManifestValidator;

interface

uses
  System.Classes,
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  TValidationSeverity = (vsError, vsWarning);

  /// <summary>A single problem found while validating a manifest.</summary>
  TValidationMessage = record
    Severity: TValidationSeverity;
    /// <summary>JSON path of the offending node (e.g. <c>packages[0].type</c>);
    ///   empty for problems concerning the whole document.</summary>
    Path: string;
    Text: string;
    function ToString: string;
  end;

  /// <summary>Checks a package manifest (<c>vendor.name.manifest.json</c>)
  ///   against the rules Blocks relies on: mandatory fields, supported schema,
  ///   id/name format, repository type and URL, package types and Delphi version
  ///   keys. Works on the raw JSON so it can report every problem at once instead
  ///   of stopping at the first deserialization error.</summary>
  TManifestValidator = class
  private
    FMessages: TList<TValidationMessage>;
    procedure AddMessage(ASeverity: TValidationSeverity; const APath, AText: string);
    procedure AddError(const APath, AText: string);
    procedure AddWarning(const APath, AText: string);

    function ReadRequiredString(AObject: TJSONObject; const AName: string; out AValue: string): Boolean;
    procedure CheckOptionalString(AObject: TJSONObject; const AName: string);
    procedure CheckStringArray(AValue: TJSONValue; const APath: string);

    procedure ValidateSchema(ARoot: TJSONObject);
    procedure ValidateId(ARoot: TJSONObject; out AId: string);
    procedure ValidateName(ARoot: TJSONObject);
    procedure ValidateVersion(ARoot: TJSONObject);
    procedure ValidateRepository(ARoot: TJSONObject; out AIsMeta: Boolean);
    procedure ValidateRepositoryUrl(const ARepoType, AUrl: string);
    procedure ValidatePlatforms(ARoot: TJSONObject; AIsMeta: Boolean);
    procedure ValidatePackages(ARoot: TJSONObject; AIsMeta: Boolean);
    procedure ValidatePackage(AValue: TJSONValue; const APath: string);
    procedure ValidatePackageOptions(ARoot: TJSONObject);
    procedure ValidateDependencies(ARoot: TJSONObject; AIsMeta: Boolean);
    function GetErrorCount: Integer;
    function GetWarningCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Validates an already parsed manifest. Messages accumulate across
    ///   calls; use <see cref="Clear"/> to reset them.</summary>
    /// <param name="AJSON">Manifest root; anything but a JSON object is an error.</param>
    /// <param name="AFileName">Optional manifest file name, used to check that it
    ///   matches the <c>id</c> (<c>&lt;id&gt;.manifest.json</c>).</param>
    procedure Validate(AJSON: TJSONValue; const AFileName: string = '');
    /// <summary>Reads, parses and validates a manifest file. A missing file or
    ///   malformed JSON is reported as an error, not raised.</summary>
    procedure ValidateFile(const AFileName: string);
    procedure Clear;

    /// <summary>Returns <c>True</c> when <paramref name="AValue"/> can be used as a
    ///   Windows file name: not empty, no reserved characters
    ///   (<c>&lt; &gt; : " / \ | ? *</c>) or control characters, no trailing dot or
    ///   space and not a reserved device name (<c>CON</c>, <c>NUL</c>, <c>COM1</c>, ...).</summary>
    class function IsValidFileName(const AValue: string): Boolean; static;
    /// <summary>Returns <c>True</c> for a package id in <c>vendor.name</c> form: a
    ///   single dot and two non-empty parts that are valid file names.</summary>
    class function IsValidPackageId(const AValue: string): Boolean; static;
    /// <summary>Returns <c>True</c> for a Delphi version key such as <c>delphi12</c>
    ///   or <c>delphi12+</c> (a supported internal version name, optionally
    ///   followed by <c>+</c>).</summary>
    class function IsValidProductKey(const AValue: string): Boolean; static;
    /// <summary>Returns <c>True</c> when <paramref name="AValue"/> is an absolute URL
    ///   with a host whose scheme is one of <paramref name="ASchemes"/>.</summary>
    class function IsValidUrl(const AValue: string; const ASchemes: array of string): Boolean; static;

    property Messages: TList<TValidationMessage> read FMessages;
    property ErrorCount: Integer read GetErrorCount;
    property WarningCount: Integer read GetWarningCount;
  end;

const
  /// <summary>Manifest schemas accepted by this version of Blocks.</summary>
  SupportedManifestSchemas: array[0..0] of string = ('https://delphi-blocks.dev/schema/package.v1.json');

  RepoTypeNone = 'none';
  RepoTypeGitHub = 'github';
  RepoTypeBitbucket = 'bitbucket';
  RepoTypeGit = 'git';
  RepoTypeSvn = 'svn';
  RepoTypeLocal = 'local';

  SupportedRepositoryTypes: array[0..5] of string =
      (RepoTypeNone, RepoTypeGitHub, RepoTypeBitbucket, RepoTypeGit, RepoTypeSvn, RepoTypeLocal);

  PackageTypeRuntime = 'runtime';
  PackageTypeDesignTime = 'designtime';

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  Blocks.Core;

const
  ManifestFileSuffix = '.manifest.json';
  InvalidFileNameChars = ['<', '>', ':', '"', '/', '\', '|', '?', '*'];
  ReservedDeviceNames: array[0..21] of string = (
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9'
  );
  // MAJOR.MINOR.PATCH with an optional fourth (build) number, as used by the repository.
  VersionPattern = '^\d+\.\d+\.\d+(\.\d+)?$';
  // scheme://host[...] - the host part must be present and contain no whitespace.
  UrlPattern = '^([a-zA-Z][a-zA-Z0-9+.\-]*)://([^\s/?#@]+@)?[^\s/?#@:]+(:\d+)?([/?#]\S*)?$';
  // file:///path has an empty host.
  FileUrlPattern = '^(file)://(/\S+)$';
  // scp-like git syntax: user@host:path
  ScpLikeGitPattern = '^[A-Za-z0-9._\-]+@[A-Za-z0-9.\-]+:[^\s]+$';

  HttpSchemes: array[0..1] of string = ('http', 'https');
  GitSchemes: array[0..4] of string = ('http', 'https', 'ssh', 'git', 'file');
  SvnSchemes: array[0..4] of string = ('http', 'https', 'svn', 'svn+ssh', 'file');
  GitRefNames: array[0..2] of string = ('tag', 'commit', 'branch');
  PlatformPathLists: array[0..2] of string = ('sourcePath', 'releaseDCUPath', 'debugDCUPath');

{ TValidationMessage }

function TValidationMessage.ToString: string;
begin
  if Path = '' then
    Result := Text
  else
    Result := Path + ': ' + Text;
end;

{ TManifestValidator }

constructor TManifestValidator.Create;
begin
  inherited Create;
  FMessages := TList<TValidationMessage>.Create;
end;

destructor TManifestValidator.Destroy;
begin
  FMessages.Free;
  inherited;
end;

procedure TManifestValidator.Clear;
begin
  Messages.Clear;
end;

procedure TManifestValidator.AddMessage(ASeverity: TValidationSeverity; const APath, AText: string);
var
  LMessage: TValidationMessage;
begin
  LMessage.Severity := ASeverity;
  LMessage.Path := APath;
  LMessage.Text := AText;
  Messages.Add(LMessage);
end;

procedure TManifestValidator.AddError(const APath, AText: string);
begin
  AddMessage(vsError, APath, AText);
end;

procedure TManifestValidator.AddWarning(const APath, AText: string);
begin
  AddMessage(vsWarning, APath, AText);
end;

function TManifestValidator.GetErrorCount: Integer;
begin
  Result := 0;
  for var LMessage in Messages do
    if LMessage.Severity = vsError then
      Inc(Result);
end;

function TManifestValidator.GetWarningCount: Integer;
begin
  Result := 0;
  for var LMessage in Messages do
    if LMessage.Severity = vsWarning then
      Inc(Result);
end;

class function TManifestValidator.IsValidFileName(const AValue: string): Boolean;
begin
  if AValue = '' then
    Exit(False);

  for var LChar in AValue do
    if CharInSet(LChar, InvalidFileNameChars) or (LChar < ' ') then
      Exit(False);

  if CharInSet(AValue[AValue.Length], ['.', ' ']) then
    Exit(False);

  // Device names are reserved even when followed by an extension (e.g. "nul.txt").
  var LBaseName := AValue;
  var LDotPos := LBaseName.IndexOf('.');
  if LDotPos >= 0 then
    LBaseName := LBaseName.Substring(0, LDotPos);
  Result := not MatchText(LBaseName.Trim, ReservedDeviceNames);
end;

class function TManifestValidator.IsValidPackageId(const AValue: string): Boolean;
begin
  var LParts := AValue.Split(['.']);
  Result := (Length(LParts) = 2) and IsValidFileName(LParts[0]) and IsValidFileName(LParts[1]);
end;

class function TManifestValidator.IsValidProductKey(const AValue: string): Boolean;
begin
  var LName := AValue;
  if LName.EndsWith('+') then
    LName := LName.Substring(0, LName.Length - 1);
  Result := MatchText(LName, VersionOrder);
end;

class function TManifestValidator.IsValidUrl(const AValue: string; const ASchemes: array of string): Boolean;
begin
  var LMatch := TRegEx.Match(AValue, UrlPattern);
  if not LMatch.Success then
    LMatch := TRegEx.Match(AValue, FileUrlPattern);
  Result := LMatch.Success and MatchText(LMatch.Groups[1].Value, ASchemes);
end;

function TManifestValidator.ReadRequiredString(AObject: TJSONObject; const AName: string; out AValue: string): Boolean;
begin
  AValue := '';
  var LValue := AObject.GetValue(AName);
  if not Assigned(LValue) then
  begin
    AddError(AName, 'required field is missing');
    Exit(False);
  end;
  if not (LValue is TJSONString) then
  begin
    AddError(AName, 'must be a string');
    Exit(False);
  end;
  AValue := LValue.Value;
  if AValue.Trim = '' then
  begin
    AddError(AName, 'must not be empty');
    Exit(False);
  end;
  Result := True;
end;

procedure TManifestValidator.CheckOptionalString(AObject: TJSONObject; const AName: string);
begin
  var LValue := AObject.GetValue(AName);
  if Assigned(LValue) and not (LValue is TJSONString) then
    AddError(AName, 'must be a string');
end;

procedure TManifestValidator.CheckStringArray(AValue: TJSONValue; const APath: string);
begin
  if not (AValue is TJSONArray) then
  begin
    AddError(APath, 'must be an array of strings');
    Exit;
  end;
  for var I := 0 to TJSONArray(AValue).Count - 1 do
    if not (TJSONArray(AValue).Items[I] is TJSONString) then
      AddError(Format('%s[%d]', [APath, I]), 'must be a string');
end;

procedure TManifestValidator.ValidateFile(const AFileName: string);
begin
  if not TFile.Exists(AFileName) then
  begin
    AddError('', Format('File not found: "%s"', [AFileName]));
    Exit;
  end;

  var LJSON: TJSONValue;
  try
    LJSON := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFileName), False, True);
  except
    on E: Exception do
    begin
      AddError('', 'Invalid JSON: ' + E.Message);
      Exit;
    end;
  end;

  try
    Validate(LJSON, AFileName);
  finally
    LJSON.Free;
  end;
end;

procedure TManifestValidator.Validate(AJSON: TJSONValue; const AFileName: string);
var
  LId: string;
  LIsMeta: Boolean;
begin
  if not (AJSON is TJSONObject) then
  begin
    AddError('', 'The manifest must be a JSON object');
    Exit;
  end;

  var LRoot := TJSONObject(AJSON);
  ValidateSchema(LRoot);
  ValidateId(LRoot, LId);
  ValidateName(LRoot);
  ValidateVersion(LRoot);

  CheckOptionalString(LRoot, 'description');
  CheckOptionalString(LRoot, 'license');
  CheckOptionalString(LRoot, 'author');
  CheckOptionalString(LRoot, 'homepage');
  var LHomepage := LRoot.GetValue('homepage');
  if (LHomepage is TJSONString) and (LHomepage.Value <> '') and not IsValidUrl(LHomepage.Value, HttpSchemes) then
    AddError('homepage', Format('"%s" is not a valid http(s) URL', [LHomepage.Value]));
  var LKeywords := LRoot.GetValue('keywords');
  if Assigned(LKeywords) then
    CheckStringArray(LKeywords, 'keywords');

  ValidateRepository(LRoot, LIsMeta);
  ValidatePlatforms(LRoot, LIsMeta);
  ValidatePackages(LRoot, LIsMeta);
  ValidatePackageOptions(LRoot);
  ValidateDependencies(LRoot, LIsMeta);

  if (AFileName <> '') and (LId <> '') then
  begin
    var LExpected := LId + ManifestFileSuffix;
    if not SameText(TPath.GetFileName(AFileName), LExpected) then
      AddWarning('', Format('The file name should be "%s" to match the id', [LExpected]));
  end;
end;

procedure TManifestValidator.ValidateSchema(ARoot: TJSONObject);
var
  LSchema: string;
begin
  if not ReadRequiredString(ARoot, '$schema', LSchema) then
    Exit;
  if not MatchStr(LSchema, SupportedManifestSchemas) then
    AddError(
        '$schema',
        Format('unsupported schema "%s" (accepted: %s)', [LSchema, string.Join(', ', SupportedManifestSchemas)])
    );
end;

procedure TManifestValidator.ValidateId(ARoot: TJSONObject; out AId: string);
begin
  if not ReadRequiredString(ARoot, 'id', AId) then
    Exit;
  if not IsValidPackageId(AId) then
  begin
    AddError(
        'id',
        Format(
            '"%s" must be in the form vendor.name: a single dot and two non-empty parts '
                + 'made of characters valid in a file name',
            [AId]
        )
    );
    AId := '';
  end;
end;

procedure TManifestValidator.ValidateName(ARoot: TJSONObject);
var
  LName: string;
begin
  if not ReadRequiredString(ARoot, 'name', LName) then
    Exit;
  if LName.Contains('.') then
    AddError('name', Format('"%s" must not contain a dot', [LName]))
  else if not IsValidFileName(LName) then
    AddError('name', Format('"%s" is not a valid file name', [LName]));
end;

procedure TManifestValidator.ValidateVersion(ARoot: TJSONObject);
var
  LVersion: string;
begin
  if not ReadRequiredString(ARoot, 'version', LVersion) then
    Exit;
  if not TRegEx.IsMatch(LVersion, VersionPattern) then
    AddError('version', Format('"%s" must be in the form MAJOR.MINOR.PATCH', [LVersion]));
end;

procedure TManifestValidator.ValidateRepository(ARoot: TJSONObject; out AIsMeta: Boolean);
var
  LRepoType: string;
begin
  AIsMeta := False;
  var LValue := ARoot.GetValue('repository');
  if not Assigned(LValue) then
  begin
    // The loader treats a missing repository as a meta-package (type "none").
    AIsMeta := True;
    AddWarning('repository', 'missing: the manifest is treated as a meta-package (type "none")');
    Exit;
  end;
  if not (LValue is TJSONObject) then
  begin
    AddError('repository', 'must be an object');
    Exit;
  end;

  var LRepository := TJSONObject(LValue);
  var LTypeValue := LRepository.GetValue('type');
  if not Assigned(LTypeValue) then
  begin
    AddError('repository.type', 'required field is missing');
    Exit;
  end;
  if not (LTypeValue is TJSONString) then
  begin
    AddError('repository.type', 'must be a string');
    Exit;
  end;

  LRepoType := LTypeValue.Value;
  if not MatchText(LRepoType, SupportedRepositoryTypes) then
  begin
    AddError(
        'repository.type',
        Format('unsupported type "%s" (accepted: %s)', [LRepoType, string.Join(', ', SupportedRepositoryTypes)])
    );
    Exit;
  end;

  AIsMeta := SameText(LRepoType, RepoTypeNone);
  if AIsMeta then
    Exit;

  var LUrlValue := LRepository.GetValue('url');
  if not Assigned(LUrlValue) then
    AddError('repository.url', 'required field is missing')
  else if not (LUrlValue is TJSONString) then
    AddError('repository.url', 'must be a string')
  else if LUrlValue.Value.Trim = '' then
    AddError('repository.url', 'must not be empty')
  else
    ValidateRepositoryUrl(LRepoType, LUrlValue.Value);

  if SameText(LRepoType, RepoTypeGit) then
  begin
    var LRefCount := 0;
    for var LRefName in GitRefNames do
    begin
      var LRef := LRepository.GetValue(LRefName);
      if not Assigned(LRef) then
        Continue;
      if LRef is TJSONString then
        Inc(LRefCount)
      else
        AddError('repository.' + LRefName, 'must be a string');
    end;
    if LRefCount > 1 then
      AddError('repository', 'specify only one of "tag", "commit" or "branch"');
  end
  else if SameText(LRepoType, RepoTypeSvn) then
  begin
    var LRevision := LRepository.GetValue('revision');
    if Assigned(LRevision) and not ((LRevision is TJSONString) or (LRevision is TJSONNumber)) then
      AddError('repository.revision', 'must be a number or a string');
  end;
end;

procedure TManifestValidator.ValidateRepositoryUrl(const ARepoType, AUrl: string);
const
  InvalidUrlMessage = '"%s" is not a valid %s URL';
begin
  if SameText(ARepoType, RepoTypeGitHub) or SameText(ARepoType, RepoTypeBitbucket) then
  begin
    if not IsValidUrl(AUrl, HttpSchemes) then
      AddError('repository.url', Format(InvalidUrlMessage, [AUrl, 'http(s)']));
  end
  else if SameText(ARepoType, RepoTypeGit) then
  begin
    if not IsValidUrl(AUrl, GitSchemes) and not TRegEx.IsMatch(AUrl, ScpLikeGitPattern) then
      AddError('repository.url', Format(InvalidUrlMessage, [AUrl, 'git']));
  end
  else if SameText(ARepoType, RepoTypeSvn) then
  begin
    if not IsValidUrl(AUrl, SvnSchemes) then
      AddError('repository.url', Format(InvalidUrlMessage, [AUrl, 'svn']));
  end
  else if SameText(ARepoType, RepoTypeLocal) then
  begin
    // A filesystem path, not a URL: only reject characters a path can never hold.
    for var LChar in AUrl do
      if CharInSet(LChar, ['<', '>', '"', '|', '?', '*']) or (LChar < ' ') then
      begin
        AddError('repository.url', Format('"%s" is not a valid path', [AUrl]));
        Break;
      end;
  end;
end;

procedure TManifestValidator.ValidatePlatforms(ARoot: TJSONObject; AIsMeta: Boolean);
begin
  var LValue := ARoot.GetValue('platforms');
  if not Assigned(LValue) then
  begin
    if not AIsMeta then
      AddError('platforms', 'required field is missing');
    Exit;
  end;
  if not (LValue is TJSONObject) then
  begin
    AddError('platforms', 'must be an object');
    Exit;
  end;
  if not AIsMeta and (TJSONObject(LValue).Count = 0) then
    AddError('platforms', 'at least one platform is required');

  for var LPair in TJSONObject(LValue) do
  begin
    var LPath := 'platforms.' + LPair.JsonString.Value;
    if not (LPair.JsonValue is TJSONObject) then
    begin
      AddError(LPath, 'must be an object');
      Continue;
    end;
    for var LListName in PlatformPathLists do
    begin
      var LList := TJSONObject(LPair.JsonValue).GetValue(LListName);
      if Assigned(LList) then
        CheckStringArray(LList, LPath + '.' + LListName);
    end;
    var LRuntimeOnly := TJSONObject(LPair.JsonValue).GetValue('runtimeOnly');
    if Assigned(LRuntimeOnly) and not (LRuntimeOnly is TJSONBool) then
      AddError(LPath + '.runtimeOnly', 'must be a boolean');
  end;
end;

procedure TManifestValidator.ValidatePackages(ARoot: TJSONObject; AIsMeta: Boolean);
begin
  var LValue := ARoot.GetValue('packages');
  if not Assigned(LValue) then
  begin
    if not AIsMeta then
      AddError('packages', 'required field is missing');
    Exit;
  end;
  if not (LValue is TJSONArray) then
  begin
    AddError('packages', 'must be an array');
    Exit;
  end;
  if not AIsMeta and (TJSONArray(LValue).Count = 0) then
    AddError('packages', 'at least one package is required');

  for var I := 0 to TJSONArray(LValue).Count - 1 do
    ValidatePackage(TJSONArray(LValue).Items[I], Format('packages[%d]', [I]));
end;

procedure TManifestValidator.ValidatePackage(AValue: TJSONValue; const APath: string);
begin
  if not (AValue is TJSONObject) then
  begin
    AddError(APath, 'must be an object');
    Exit;
  end;
  var LPackage := TJSONObject(AValue);

  var LName := LPackage.GetValue('name');
  if not Assigned(LName) then
    AddError(APath + '.name', 'required field is missing')
  else if not (LName is TJSONString) or (LName.Value.Trim = '') then
    AddError(APath + '.name', 'must be a non-empty string');

  var LType := LPackage.GetValue('type');
  if not Assigned(LType) then
    AddError(APath + '.type', 'required field is missing')
  else if not (LType is TJSONArray) then
    AddError(APath + '.type', 'must be an array of strings')
  else
  begin
    var LHasKnownType := False;
    for var I := 0 to TJSONArray(LType).Count - 1 do
    begin
      var LItem := TJSONArray(LType).Items[I];
      var LItemPath := Format('%s.type[%d]', [APath, I]);
      if not (LItem is TJSONString) then
        AddError(LItemPath, 'must be a string')
      else if MatchText(LItem.Value, [PackageTypeRuntime, PackageTypeDesignTime]) then
        LHasKnownType := True
      else
        // Extra tags (e.g. "FMX") are tolerated: Blocks only looks at runtime/designtime.
        AddWarning(LItemPath, Format('unknown package type "%s" is ignored', [LItem.Value]));
    end;
    if not LHasKnownType then
      AddError(APath + '.type', Format('must contain "%s" and/or "%s"', [PackageTypeRuntime, PackageTypeDesignTime]));
  end;

  var LProducts := LPackage.GetValue('products');
  if not Assigned(LProducts) then
    Exit;
  if not (LProducts is TJSONArray) then
  begin
    AddError(APath + '.products', 'must be an array of strings');
    Exit;
  end;
  for var I := 0 to TJSONArray(LProducts).Count - 1 do
  begin
    var LItem := TJSONArray(LProducts).Items[I];
    var LItemPath := Format('%s.products[%d]', [APath, I]);
    if not (LItem is TJSONString) then
      AddError(LItemPath, 'must be a string')
    else if not IsValidProductKey(LItem.Value) then
      AddError(LItemPath, Format('unsupported Delphi version "%s"', [LItem.Value]));
  end;
end;

procedure TManifestValidator.ValidatePackageOptions(ARoot: TJSONObject);
begin
  var LValue := ARoot.GetValue('packageOptions');
  if not Assigned(LValue) then
    Exit;
  if not (LValue is TJSONObject) then
  begin
    AddError('packageOptions', 'must be an object');
    Exit;
  end;

  var LRootFolder := TJSONObject(LValue).GetValue('rootFolder');
  if Assigned(LRootFolder) and not (LRootFolder is TJSONString) then
    AddError('packageOptions.rootFolder', 'must be a string');

  var LFolders := TJSONObject(LValue).GetValue('folders');
  if not Assigned(LFolders) then
    Exit;
  if not (LFolders is TJSONObject) then
  begin
    AddError('packageOptions.folders', 'must be an object');
    Exit;
  end;

  for var LPair in TJSONObject(LFolders) do
  begin
    var LKey := LPair.JsonString.Value;
    var LPath := 'packageOptions.folders.' + LKey;
    if not IsValidProductKey(LKey) then
      AddError(
          LPath,
          Format(
              'unsupported Delphi version "%s" (accepted: %s, optionally followed by "+")',
              [LKey, string.Join(', ', VersionOrder)]
          )
      );
    if not (LPair.JsonValue is TJSONString) then
      AddError(LPath, 'must be a string');
  end;
end;

procedure TManifestValidator.ValidateDependencies(ARoot: TJSONObject; AIsMeta: Boolean);
begin
  var LValue := ARoot.GetValue('dependencies');
  if not Assigned(LValue) then
  begin
    if AIsMeta then
      AddWarning('dependencies', 'a meta-package (repository type "none") without dependencies does nothing');
    Exit;
  end;
  if not (LValue is TJSONObject) then
  begin
    AddError('dependencies', 'must be an object');
    Exit;
  end;

  for var LPair in TJSONObject(LValue) do
  begin
    var LKey := LPair.JsonString.Value;
    var LPath := 'dependencies.' + LKey;
    if not IsValidPackageId(LKey) then
      AddError(LPath, Format('"%s" is not a valid package id (vendor.name)', [LKey]));
    if not (LPair.JsonValue is TJSONString) then
      AddError(LPath, 'version constraint must be a string');
  end;
end;

end.
