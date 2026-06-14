unit Blocks.Model.Config;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.JSON;

type
  TConfig = class(TObject)
  private
    FSources: TStringList;
    FPlatforms: TStringList;
    FProduct: string;
    FRegistryKey: string;
    FWorkspaceDir: string;
    FUpdateDCPSearchPath: Boolean;
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

implementation

uses
  Blocks.JSON,
  Blocks.Core;

const
  WorkspaceSchemaUrl = 'https://delphi-blocks.dev/schema/workspace.v1.json';
  DefaultBlocksRepositoryUrl = 'https://github.com/delphi-blocks/blocks-repository';

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
