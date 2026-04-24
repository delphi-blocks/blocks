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
unit Blocks.Model.Package;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,

  Xml.XMLIntf,
  Xml.XMLDoc;

type
  /// <summary>A single <c>&lt;DCCReference&gt;</c> entry inside an
  ///   <c>&lt;ItemGroup&gt;</c>.</summary>
  TPackageReference = class
  private
    FInclude: string;
    FFormName: string;
    FFormType: string;
  public
    function HasForm: Boolean;

    property Include: string read FInclude write FInclude;
    property FormName: string read FFormName write FFormName;
    property FormType: string read FFormType write FFormType;
  end;

  TPackageReferenceList = class(TObjectList<TPackageReference>)
  public
    constructor Create;
  end;

  /// <summary>One <c>&lt;PropertyGroup&gt;</c> from a .dproj file: every
  ///   child element becomes a string key/value pair (last value wins on
  ///   duplicates). The original MSBuild <c>Condition</c> attribute is kept
  ///   verbatim. Lookup is case-insensitive (MSBuild property names are
  ///   case-insensitive).</summary>
  TPropertyGroup = class(TDictionary<string, string>)
  private
    FCondition: string;
  public
    constructor Create;

    function IsActive(AVariables: TDictionary<string, string>; const AConfig, APlatform: string): Boolean;

    property Condition: string read FCondition write FCondition;
  end;

  TPropertyGroupList = class(TObjectList<TPropertyGroup>)
  public
    constructor Create;
  end;

  /// <summary>Flat view of a Delphi MSBuild package project (.dproj) XML
  ///   file. The file is read once; <c>&lt;PropertyGroup&gt;</c>s and
  ///   <c>&lt;DCCReference&gt;</c>s are stored as they appear, with the
  ///   original <c>Condition</c> attributes preserved verbatim. Use
  ///   <see cref="GetProperty"/> to resolve the effective value of a
  ///   property for a given Config/Platform by simulating the MSBuild
  ///   cascade.</summary>
  TPackageProject = class
  public const
    // Project identity
    ProjectGuid          = 'ProjectGuid';
    ProjectVersion       = 'ProjectVersion';
    ProjectName          = 'ProjectName';
    SanitizedProjectName = 'SanitizedProjectName';
    MainSource           = 'MainSource';
    FrameworkType        = 'FrameworkType';
    AppType              = 'AppType';

    // Output
    DCCExeOutput = 'DCC_ExeOutput';
    DCCDcuOutput = 'DCC_DcuOutput';
    DllSuffix    = 'DllSuffix';

    // Compiler / package
    DCCDescription    = 'DCC_Description';
    DCCDefine         = 'DCC_Define';
    DCCNamespace      = 'DCC_Namespace';
    DCCUsePackage     = 'DCC_UsePackage';
    DCCUnitSearchPath = 'DCC_UnitSearchPath';
    DesignOnlyPackage = 'DesignOnlyPackage';
  private
    FPropertyGroups: TPropertyGroupList;
    FReferences: TPackageReferenceList;
    FDirectives: TStringList;

    procedure ReadPropertyGroup(const ANode: IXMLNode);
    procedure ReadItemGroup(const ANode: IXMLNode);
    procedure ReadDccReference(const ANode: IXMLNode);
    procedure ParseDpkDirectives(const ADpkFileName: string);
    function GetName: string;
    function GetDirectiveValue(const AName: string): string;
    function GetDescription: string;
    function GetLibSuffix: string;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Resolves an MSBuild property's effective value for the given
    ///   build state by simulating the MSBuild cascade.</summary>
    /// <remarks>Walks <see cref="PropertyGroups"/> in document order; groups
    ///   whose <c>Condition</c> evaluates to true (against the accumulated
    ///   values plus <c>AConfig</c>/<c>APlatform</c>) layer their key/values
    ///   on top — last write wins. <c>AConfig</c> and <c>APlatform</c> are
    ///   seeded as <c>Config</c> and <c>Platform</c> and are not overridden
    ///   by groups that happen to define them.</remarks>
    /// <param name="AName">Property name to read (case-insensitive).</param>
    /// <param name="AConfig">Build configuration (e.g. <c>Debug</c>, <c>Release</c>).</param>
    /// <param name="APlatform">Target platform (e.g. <c>Win32</c>, <c>Win64</c>).</param>
    /// <returns>The resolved value, or an empty string when the property is
    ///   never set by any active group.</returns>
    function GetProperty(const AName, AConfig, APlatform: string): string;

    class function LoadFromFile(const AFileName: string): TPackageProject;
    class function LoadFromStream(AStream: TStream; AEncodingType: TXMLEncodingType = xetUnknown): TPackageProject;
    class function LoadFromXML(AXML: IXMLDocument): TPackageProject;
    class function LoadFromString(const AString: string): TPackageProject;

    property Description: string read GetDescription;
    property LibSuffix: string read GetLibSuffix;
    property PropertyGroups: TPropertyGroupList read FPropertyGroups;
    property References: TPackageReferenceList read FReferences;
    /// <summary>Compiler directives parsed from the companion <c>.dpk</c>,
    ///   when the instance was created via <see cref="LoadFromFile"/>.
    ///   Stored as <c>NAME=VALUE</c> with uppercased names; flag-only
    ///   directives (e.g. <c>{$DESIGNONLY}</c>) have an empty value.
    ///   Empty when no <c>.dpk</c> is found next to the <c>.dproj</c>.</summary>
    property Directives: TStringList read FDirectives;
    property Name: string read GetName;
  end;

implementation

uses
  System.RegularExpressions,
  System.Bindings.EvalProtocol,
  System.Bindings.Evaluator,
  System.Bindings.EvalSys;

const
  DefaultPlatform = 'Win32';

// Translates an MSBuild Condition expression into the syntax accepted by the
// Delphi bindings evaluator. We only need to handle the shapes the IDE emits
// (no manually edited oddities), so three rewrites are enough:
//   '$(Name)' → Name      (variable reference)
//   ==        → =         (equality)
//   !=        → <>        (inequality)
function ConvertMSBuildExpression(const AExpression: string): string;
begin
  Result := TRegEx.Replace(AExpression, '''\$\(([^)]+)\)''', '$1');
  Result := StringReplace(Result, '==', '=',  [rfReplaceAll]);
  Result := StringReplace(Result, '!=', '<>', [rfReplaceAll]);
end;

{ TPackageReference }

function TPackageReference.HasForm: Boolean;
begin
  Result := FFormName <> '';
end;

{ TPackageReferenceList }

constructor TPackageReferenceList.Create;
begin
  inherited Create(True);
end;

{ TPropertyGroup }

function TPropertyGroup.IsActive(AVariables: TDictionary<string, string>;
  const AConfig, APlatform: string): Boolean;
begin
  if FCondition = '' then
    Exit(True);

  var LDictScope := TDictionaryScope.Create;
  var LScope: IScope := LDictScope;

  // MSBuild treats undefined properties as ''. Pre-bind every $(Name) referenced
  // in this Condition to '' so the lookup never fails; real values override below.
  for var LMatch in TRegEx.Matches(FCondition, '\$\(([^)]+)\)') do
    LDictScope.Map.AddOrSetValue(LMatch.Groups[1].Value, TValueWrapper.Create(''));

  LDictScope.Map.AddOrSetValue('Config',   TValueWrapper.Create(AConfig));
  LDictScope.Map.AddOrSetValue('Platform', TValueWrapper.Create(APlatform));
  for var LPair in AVariables do
    LDictScope.Map.AddOrSetValue(LPair.Key, TValueWrapper.Create(LPair.Value));

  LScope := TNestedScope.Create(BasicOperators, LScope);

  var LExpr := ConvertMSBuildExpression(FCondition);
  var LCompiled := Compile(LExpr, LScope);
  Result := LCompiled.Evaluate(LScope, nil, nil).GetValue.AsBoolean;
end;

constructor TPropertyGroup.Create;
begin
  inherited Create(TIStringComparer.Ordinal);
end;

{ TPropertyGroupList }

constructor TPropertyGroupList.Create;
begin
  inherited Create(True);
end;

{ TPackageProject }

constructor TPackageProject.Create;
begin
  inherited Create;
  FPropertyGroups := TPropertyGroupList.Create;
  FReferences := TPackageReferenceList.Create;
  FDirectives := TStringList.Create;
end;

destructor TPackageProject.Destroy;
begin
  FPropertyGroups.Free;
  FReferences.Free;
  FDirectives.Free;
  inherited;
end;

function TPackageProject.GetDirectiveValue(const AName: string): string;
begin
  Result := FDirectives.Values[AName.ToUpper];
end;

function TPackageProject.GetDescription: string;
begin
  Result := GetDirectiveValue('DESCRIPTION');
  if Result = '' then
    Result := GetProperty(TPackageProject.DCCDescription, 'Release', DefaultPlatform);
  if Result = '' then
    Result := GetProperty(TPackageProject.DCCDescription, 'Debug', DefaultPlatform);
end;

function TPackageProject.GetLibSuffix: string;
begin
  Result := GetDirectiveValue('LIBSUFFIX');
  if Result = '' then
    Result := GetProperty(TPackageProject.DllSuffix, 'Release', DefaultPlatform);
  if Result = '' then
    Result := GetProperty(TPackageProject.DllSuffix, 'Debug', DefaultPlatform);
end;

function TPackageProject.GetName: string;
begin
  Result := ChangeFileExt(GetProperty('MainSource', '', ''), '');
end;

function TPackageProject.GetProperty(const AName, AConfig, APlatform: string): string;
begin
  var LVariables := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  try
    LVariables.AddOrSetValue('Config', AConfig);
    LVariables.AddOrSetValue('Platform', APlatform);
    for var LPropertyGroup in PropertyGroups do
      if LPropertyGroup.IsActive(LVariables, AConfig, APlatform) then
        for var LPair in LPropertyGroup do
        begin
          if SameText(LPair.Key, 'Config') or SameText(LPair.Key, 'Platform') then
            Continue;

          LVariables.AddOrSetValue(LPair.Key, LPair.Value);
        end;

    if not LVariables.TryGetValue(AName, Result) then
      Result := '';
  finally
    LVariables.Free;
  end;
end;

class function TPackageProject.LoadFromFile(const AFileName: string): TPackageProject;
begin
  if not TFile.Exists(AFileName) then
    raise Exception.CreateFmt('Package project file not found: %s', [AFileName]);

  var LDoc: IXMLDocument := TXMLDocument.Create(nil);
  LDoc.LoadFromFile(AFileName);
  Result := TPackageProject.LoadFromXML(LDoc);
  try
    var LDpkFile := ChangeFileExt(AFileName, '.dpk');
    if TFile.Exists(LDpkFile) then
      Result.ParseDpkDirectives(LDpkFile);
  except
    Result.Free;
    raise;
  end;
end;

class function TPackageProject.LoadFromStream(
  AStream: TStream; AEncodingType: TXMLEncodingType): TPackageProject;
begin
  if not Assigned(AStream) then
    raise Exception.Create('Package stream not found');

  var LDoc: IXMLDocument := TXMLDocument.Create(nil);
  LDoc.LoadFromStream(AStream, AEncodingType);
  Result := TPackageProject.LoadFromXML(LDoc);
end;

class function TPackageProject.LoadFromString(
  const AString: string): TPackageProject;
begin
  var LDoc: IXMLDocument := TXMLDocument.Create(nil);
  LDoc.LoadFromXML(AString);
  Result := TPackageProject.LoadFromXML(LDoc);
end;

class function TPackageProject.LoadFromXML(AXML: IXMLDocument): TPackageProject;
begin
  if not Assigned(AXML) then
    raise Exception.Create('Package project empty XML');

  Result := TPackageProject.Create;
  try
    var LRoot := AXML.DocumentElement;
    if (LRoot = nil) or not SameText(LRoot.LocalName, 'Project') then
      raise Exception.Create('Invalid project file (missing <Project> root)');

    for var I := 0 to LRoot.ChildNodes.Count - 1 do
    begin
      var LNode := LRoot.ChildNodes[I];
      if SameText(LNode.LocalName, 'PropertyGroup') then
        Result.ReadPropertyGroup(LNode)
      else if SameText(LNode.LocalName, 'ItemGroup') then
        Result.ReadItemGroup(LNode);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TPackageProject.ReadPropertyGroup(const ANode: IXMLNode);
begin
  var LGroup := TPropertyGroup.Create;
  try
    if ANode.HasAttribute('Condition') then
      LGroup.Condition := ANode.Attributes['Condition'];

    for var I := 0 to ANode.ChildNodes.Count - 1 do
    begin
      var LChild := ANode.ChildNodes[I];
      LGroup.AddOrSetValue(LChild.LocalName, LChild.Text);
    end;

    FPropertyGroups.Add(LGroup);
  except
    LGroup.Free;
    raise;
  end;
end;

procedure TPackageProject.ReadItemGroup(const ANode: IXMLNode);
begin
  for var I := 0 to ANode.ChildNodes.Count - 1 do
  begin
    var LChild := ANode.ChildNodes[I];
    if SameText(LChild.LocalName, 'DCCReference') then
      ReadDccReference(LChild);
  end;
end;

procedure TPackageProject.ParseDpkDirectives(const ADpkFileName: string);
begin
  FDirectives.Clear;

  var LContent := TFile.ReadAllText(ADpkFileName);
  var LPos := 0;
  while LPos < LContent.Length do
  begin
    LPos := LContent.IndexOf('{$', LPos);
    if LPos < 0 then
      Break;
    var LEnd := LContent.IndexOf('}', LPos + 2);
    if LEnd < 0 then
      Break;

    var LDirective := LContent.Substring(LPos + 2, LEnd - LPos - 2).Trim;
    var LSepPos := LDirective.IndexOf(' ');
    var LName, LValue: string;
    if LSepPos < 0 then
    begin
      LName  := LDirective;
      LValue := '';
    end
    else
    begin
      LName  := LDirective.Substring(0, LSepPos);
      LValue := LDirective.Substring(LSepPos + 1).Trim;
      if (LValue.Length >= 2) and (LValue.Chars[0] = '''') and
          (LValue.Chars[LValue.Length - 1] = '''') then
        LValue := LValue.Substring(1, LValue.Length - 2);
    end;
    FDirectives.Add(LName.ToUpper + '=' + LValue);
    LPos := LEnd + 1;
  end;
end;

procedure TPackageProject.ReadDccReference(const ANode: IXMLNode);
begin
  var LRef := TPackageReference.Create;
  try
    if ANode.HasAttribute('Include') then
      LRef.Include := ANode.Attributes['Include'];

    for var I := 0 to ANode.ChildNodes.Count - 1 do
    begin
      var LChild := ANode.ChildNodes[I];
      if SameText(LChild.LocalName, 'Form') then
        LRef.FormName := LChild.Text
      else if SameText(LChild.LocalName, 'FormType') then
        LRef.FormType := LChild.Text;
    end;

    FReferences.Add(LRef);
  except
    LRef.Free;
    raise;
  end;
end;

end.
