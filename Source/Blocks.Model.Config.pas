unit Blocks.Model.Config;

interface

uses
  System.Classes, System.SysUtils, System.IOUtils, System.JSON;

type
  TConfig = class(TObject)
  private
    FSources: TStringList;
    FProduct: string;
    FRegistryKey: string;
    FWorkspaceDir: string;
    function ConfigPath: string;
  public
    property Sources: TStringList read FSources;

    property Product: string read FProduct write FProduct;
    property RegistryKey: string read FRegistryKey write FRegistryKey;

    procedure Load;
    procedure Save;
    function ToJson: string;

    function Get(const AKey: string): string;
    procedure &Set(const AKey, AValue: string);
    procedure Add(const AKey, AValue: string);

    constructor Create(const AWorkspaceDir: string);
    destructor Destroy; override;
  end;

implementation

uses
  Blocks.JSON;

const
  WorkspaceSchemaUrl = 'https://delphi-blocks.dev/schema/workspace.v1.json';
  DefaultBlocksRepositoryUrl = 'https://github.com/delphi-blocks/blocks-repository';

{ TConfig }

procedure TConfig.&Set(const AKey, AValue: string);
begin
  if SameText(AKey, 'sources') then
  begin
    var LSources := AValue.Split([',']);
    FSources.Clear;
    for var S in LSources do
      FSources.Add(S);
  end
  else if SameText(AKey, 'product') then
    FProduct := AValue
  else if SameText(AKey, 'registrykey') then
    FRegistryKey := AValue
  else
    raise Exception.CreateFmt('Config "%s" does not exists', [AKey]);
end;

procedure TConfig.Add(const AKey, AValue: string);
begin
  if SameText(AKey, 'sources') then
    FSources.Add(AValue)
  else
    raise Exception.CreateFmt('Config "%s" does not exists or doesn''t support /ADD', [AKey]);
end;

function TConfig.ConfigPath: string;
begin
  ForceDirectories(FWorkspaceDir);
  Result := TPath.Combine(FWorkspaceDir, 'workspace.json');
end;

constructor TConfig.Create(const AWorkspaceDir: string);
begin
  inherited Create;
  FWorkspaceDir := AWorkspaceDir;
  FSources := TStringList.Create;
  FSources.Add(DefaultBlocksRepositoryUrl);
  FRegistryKey := 'BDS';
end;

destructor TConfig.Destroy;
begin
  FSources.Free;
  inherited;
end;

function TConfig.Get(const AKey: string): string;
begin
  if SameText(AKey, 'sources') then
    Result := string.Join(',', FSources.ToStringArray)
  else if SameText(AKey, 'product') then
    Result := FProduct
  else if SameText(AKey, 'registrykey') then
    Result := FRegistryKey
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
  end
  else
    Save;
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
