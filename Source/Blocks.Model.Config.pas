unit Blocks.Model.Config;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  /// <summary>Compiler tools architecture MSBuild should use (Delphi 13+). Maps to the
  ///   <c>DCC_PreferredToolArchitecture</c> MSBuild property: <c>x32</c> uses the 32-bit
  ///   compiler tools, <c>x64</c> the 64-bit ones (which give the compiler more memory).
  ///   It only affects the tools, not the produced binary. <c>default</c> (the default)
  ///   leaves the choice to Delphi: the property is not passed to MSBuild at all.</summary>
  TToolArchitecture = (default, x32, x64);
  {$SCOPEDENUMS OFF}

  TConfig = class(TObject)
  private
    FSources: TStringList;
    FPlatforms: TStringList;
    FProduct: string;
    FRegistryKey: string;
    FWorkspaceDir: string;
    FUpdateDCPSearchPath: Boolean;
    FToolArchitecture: TToolArchitecture;
    function ConfigPath: string;
  public
    property Sources: TStringList read FSources;
    /// <summary>Platforms this workspace targets. An empty list means "all platforms
    ///   supported by the configured Delphi version" (see <c>IsPlatformEnabled</c>).</summary>
    property Platforms: TStringList read FPlatforms;

    property Product: string read FProduct write FProduct;
    property RegistryKey: string read FRegistryKey write FRegistryKey;
    /// <summary>When True, "init" registers the blocks DCP output directory on the
    ///   Delphi library Search Path (see <c>TProduct.CheckDCPPath</c>). Default False.</summary>
    property UpdateDCPSearchPath: Boolean read FUpdateDCPSearchPath write FUpdateDCPSearchPath;
    /// <summary>Tools architecture passed to MSBuild as
    ///   <c>/p:DCC_PreferredToolArchitecture=&lt;x32|x64&gt;</c> (Delphi 13+). When
    ///   <c>default</c> (the default) the property is not passed to MSBuild at all.</summary>
    property ToolArchitecture: TToolArchitecture read FToolArchitecture write FToolArchitecture;

    /// <summary>Returns True when <paramref name="APlatform"/> is enabled for this
    ///   workspace, i.e. the <c>Platforms</c> list is empty (all) or contains it.</summary>
    function IsPlatformEnabled(const APlatform: string): Boolean;

    procedure Load;
    procedure Save;
    function ToJson: string;

    function GetValue(const AKey: string): string;
    procedure SetValue(const AKey, AValue: string);
    procedure Add(const AKey, AValue: string);
    procedure Delete(const AKey, AValue: string);

    constructor Create(const AWorkspaceDir: string);
    destructor Destroy; override;
  end;

/// <summary>Returns the MSBuild value (<c>x32</c>/<c>x64</c>) for an architecture.</summary>
function ToolArchitectureToStr(const AValue: TToolArchitecture): string;

/// <summary>Parses <c>x32</c>/<c>x64</c> (case-insensitive); raises on anything else.</summary>
function StrToToolArchitecture(const AValue: string): TToolArchitecture;

implementation

uses
  Blocks.JSON,
  Blocks.Core;

const
  WorkspaceSchemaUrl = 'https://delphi-blocks.dev/schema/workspace.v1.json';
  DefaultBlocksRepositoryUrl = 'https://github.com/delphi-blocks/blocks-repository';

function ToolArchitectureToStr(const AValue: TToolArchitecture): string;
begin
  case AValue of
    TToolArchitecture.x32: Result := 'x32';
    TToolArchitecture.x64: Result := 'x64';
  else
    Result := 'default';
  end;
end;

function StrToToolArchitecture(const AValue: string): TToolArchitecture;
begin
  if SameText(AValue, 'default') then
    Result := TToolArchitecture.default
  else if SameText(AValue, 'x32') then
    Result := TToolArchitecture.x32
  else if SameText(AValue, 'x64') then
    Result := TToolArchitecture.x64
  else
    raise Exception.CreateFmt('Invalid value "%s" for "toolArchitecture" (use default, x32 or x64)', [AValue]);
end;

{ TConfig }

procedure TConfig.SetValue(const AKey, AValue: string);
begin
  if SameText(AKey, 'sources') then
  begin
    var LSources := AValue.Split([',']);
    FSources.Clear;
    for var S in LSources do
      FSources.Add(S);
  end
  else if SameText(AKey, 'platforms') then
  begin
    FPlatforms.Clear;
    // An empty value clears the list, restoring the "all platforms" default.
    if AValue <> '' then
      for var LPlatform in AValue.Split([',']) do
        FPlatforms.Add(LPlatform);
  end
  else if SameText(AKey, 'product') then
    FProduct := AValue
  else if SameText(AKey, 'registrykey') then
    FRegistryKey := AValue
  else if SameText(AKey, 'updatedcpsearchpath') then
  begin
    if SameText(AValue, 'true') then
      FUpdateDCPSearchPath := True
    else if SameText(AValue, 'false') then
      FUpdateDCPSearchPath := False
    else
      raise Exception.CreateFmt('Invalid boolean value "%s" for "%s" (use true or false)', [AValue, AKey]);
  end
  else if SameText(AKey, 'toolarchitecture') then
    FToolArchitecture := StrToToolArchitecture(AValue)
  else
    raise Exception.CreateFmt('Config "%s" does not exists', [AKey]);
end;

procedure TConfig.Add(const AKey, AValue: string);
begin
  if SameText(AKey, 'sources') then
    FSources.Add(AValue)
  else if SameText(AKey, 'platforms') then
    FPlatforms.Add(AValue)
  else
    raise Exception.CreateFmt('Config "%s" does not exists or doesn''t support /ADD', [AKey]);
end;

procedure TConfig.Delete(const AKey, AValue: string);
begin
  if SameText(AKey, 'sources') then
  begin
    var LIndex := FSources.IndexOf(AValue);
    if LIndex < 0 then
      raise Exception.CreateFmt('Value "%s" not found in "%s"', [AValue, AKey]);
    FSources.Delete(LIndex);
  end
  else if SameText(AKey, 'platforms') then
  begin
    var LIndex := FPlatforms.IndexOf(AValue);
    if LIndex < 0 then
      raise Exception.CreateFmt('Value "%s" not found in "%s"', [AValue, AKey]);
    FPlatforms.Delete(LIndex);
  end
  else
    raise Exception.CreateFmt('Config "%s" does not exists or doesn''t support /DELETE', [AKey]);
end;

function TConfig.ConfigPath: string;
begin
  var LBlocksDir := TPath.Combine(FWorkspaceDir, '.blocks');
  ForceDirectories(LBlocksDir);
  Result := TPath.Combine(LBlocksDir, 'workspace.json');
end;

constructor TConfig.Create(const AWorkspaceDir: string);
begin
  inherited Create;
  FWorkspaceDir := AWorkspaceDir;
  FSources := TStringList.Create;
  FSources.Add(DefaultBlocksRepositoryUrl);
  FPlatforms := TStringList.Create;
  FRegistryKey := 'BDS';
  FUpdateDCPSearchPath := False;
  FToolArchitecture := TToolArchitecture.default;
end;

destructor TConfig.Destroy;
begin
  FSources.Free;
  FPlatforms.Free;
  inherited;
end;

function TConfig.IsPlatformEnabled(const APlatform: string): Boolean;
begin
  Result := PlatformInList(FPlatforms.ToStringArray, APlatform);
end;

function TConfig.GetValue(const AKey: string): string;
begin
  if SameText(AKey, 'sources') then
    Result := string.Join(',', FSources.ToStringArray)
  else if SameText(AKey, 'platforms') then
    Result := string.Join(',', FPlatforms.ToStringArray)
  else if SameText(AKey, 'product') then
    Result := FProduct
  else if SameText(AKey, 'registrykey') then
    Result := FRegistryKey
  else if SameText(AKey, 'updatedcpsearchpath') then
  begin
    if FUpdateDCPSearchPath then
      Result := 'true'
    else
      Result := 'false';
  end
  else if SameText(AKey, 'toolarchitecture') then
    Result := ToolArchitectureToStr(FToolArchitecture)
  else
    raise Exception.CreateFmt('Config "%s" does not exists', [AKey]);
end;

procedure TConfig.Load;
begin
  if FileExists(ConfigPath) then
  begin
    var LJSON := TJSONObject.ParseJSONValue(TFile.ReadAllText(ConfigPath), False, True);
    try
      TJsonHelper.CheckSchema(LJSON, WorkspaceSchemaUrl);
      TJsonHelper.JSONToObject(Self, LJSON);
    finally
      LJSON.Free;
    end;
  end;
end;

procedure TConfig.Save;
begin
  var LJSON := TJsonHelper.ObjectToJSON(Self) as TJSONObject;
  try
    LJSON.AddPair('$schema', WorkspaceSchemaUrl);
    TFile.WriteAllText(ConfigPath, TJsonHelper.PrettyPrint(LJSON));
  finally
    LJSON.Free;
  end;
end;

function TConfig.ToJson: string;
begin
  var LJSON := TJsonHelper.ObjectToJSON(Self) as TJSONObject;
  try
    LJSON.AddPair('$schema', WorkspaceSchemaUrl);
    Result := TJsonHelper.PrettyPrint(LJSON.ToJSON);
  finally
    LJSON.Free;
  end;
end;

end.
