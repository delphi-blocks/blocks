unit Blocks.Manifest;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections;

type

  // -----------------------------------------------------------------------
  // JSON-aware string list
  // -----------------------------------------------------------------------
  TJsonStringList = class(TList<string>)
  public
    procedure FromJson(LJSON: TJSONValue);
    function ToJson: TJSONArray;
  end;

  // -----------------------------------------------------------------------
  // Application info
  // -----------------------------------------------------------------------
  TApplicationInfo = class
  private
    FId: string;
    FName: string;
    FDescription: string;
    FUrl: string;
  public
    procedure FromJson(LJSON: TJSONValue);
    function ToJson: TJSONObject;

    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property Description: string read FDescription write FDescription;
    property Url: string read FUrl write FUrl;
  end;

  // -----------------------------------------------------------------------
  // Supported platform (es. Win32, Win64, Linux, ...)
  // -----------------------------------------------------------------------
  TManifestPlatform = class
  private
    FSourcePath: TJsonStringList;
    FBrowsingPath: TJsonStringList;
    FDebugDCUPath: TJsonStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure FromJson(LJSON: TJSONValue);
    function ToJson: TJSONObject;
    property SourcePath: TJsonStringList read FSourcePath;
    property BrowsingPath: TJsonStringList read FBrowsingPath;
    property DebugDCUPath: TJsonStringList read FDebugDCUPath;
  end;

  // -----------------------------------------------------------------------
  // Platform map: name -> TManifestPlatform
  // -----------------------------------------------------------------------
  TSupportedPlatforms = class(TObjectDictionary<string, TManifestPlatform>)
  public
    constructor Create;
    procedure FromJson(LJSON: TJSONValue);
    function ToJson: TJSONObject;
  end;

  // -----------------------------------------------------------------------
  // A Delphi package
  // -----------------------------------------------------------------------
  TManifestPackage = class
  private
    FName: string;
    FType: TJsonStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure FromJson(LJSON: TJSONValue);
    function ToJson: TJSONObject;
    property Name: string read FName write FName;
    property &Type: TJsonStringList read FType;
  end;

  // -----------------------------------------------------------------------
  // Package list
  // -----------------------------------------------------------------------
  TManifestPackageList = class(TObjectList<TManifestPackage>)
  public
    constructor Create;
    procedure FromJson(LJSON: TJSONValue);
    function ToJson: TJSONArray;
  end;

  // -----------------------------------------------------------------------
  // Package folders: Delphi version -> folder name
  // -----------------------------------------------------------------------
  TManifestPackageFolders = class(TDictionary<string, string>)
  public
    procedure FromJson(LJSON: TJSONValue);
    function ToJson: TJSONObject;
  end;

  // -----------------------------------------------------------------------
  // Package options
  // -----------------------------------------------------------------------
  TManifestPackageOptions = class
  private
    FPackageFolders: TManifestPackageFolders;
  public
    constructor Create;
    destructor Destroy; override;
    procedure FromJson(LJSON: TJSONValue);
    function ToJson: TJSONObject;
    property PackageFolders: TManifestPackageFolders read FPackageFolders;
  end;

  // -----------------------------------------------------------------------
  // Root manifest configuration
  // -----------------------------------------------------------------------
  TManifest = class
  private
    FApplication: TApplicationInfo;
    FSupportedPlatforms: TSupportedPlatforms;
    FPackages: TManifestPackageList;
    FPackageOptions: TManifestPackageOptions;
    FDependencies: TJsonStringList;
  public
    class function Load(const Source: string): TManifest; static;
  public
    constructor Create;
    destructor Destroy; override;
    procedure FromJson(LJSON: TJSONValue);
    function ToJson: TJSONObject;
    procedure FromJsonString(const AJson: string);
    function ToJsonString: string;

    property Application: TApplicationInfo read FApplication;
    property SupportedPlatforms: TSupportedPlatforms read FSupportedPlatforms;
    property Packages: TManifestPackageList read FPackages;
    property PackageOptions: TManifestPackageOptions read FPackageOptions;
    property Dependencies: TJsonStringList read FDependencies;
  end;

implementation

uses
  Blocks.Console,
  Blocks.Http,
  Blocks.Workspace;

{ TJsonStringList }

procedure TJsonStringList.FromJson(LJSON: TJSONValue);
var
  LItem: TJSONValue;
begin
  if not Assigned(LJSON) then
    Exit;
  for LItem in (LJSON as TJSONArray) do
    Add(LItem.Value);
end;

function TJsonStringList.ToJson: TJSONArray;
var
  LValue: string;
begin
  Result := TJSONArray.Create;
  for LValue in Self do
    Result.Add(LValue);
end;

{ TApplicationInfo }

procedure TApplicationInfo.FromJson(LJSON: TJSONValue);
begin
  if not Assigned(LJSON) then
    Exit;
  FId := LJSON.GetValue<string>('id', '');
  FName := LJSON.GetValue<string>('name', '');
  FDescription := LJSON.GetValue<string>('description', '');
  FUrl := LJSON.GetValue<string>('url', '');
end;

function TApplicationInfo.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('name', FName);
  Result.AddPair('description', FDescription);
  Result.AddPair('url', FUrl);
end;

{ TManifestPlatform }

constructor TManifestPlatform.Create;
begin
  inherited Create;
  FSourcePath   := TJsonStringList.Create;
  FBrowsingPath := TJsonStringList.Create;
  FDebugDCUPath := TJsonStringList.Create;
end;

destructor TManifestPlatform.Destroy;
begin
  FSourcePath.Free;
  FBrowsingPath.Free;
  FDebugDCUPath.Free;
  inherited;
end;

procedure TManifestPlatform.FromJson(LJSON: TJSONValue);
begin
  if not Assigned(LJSON) then
    Exit;
  FSourcePath.FromJson(LJSON.FindValue('sourcePath'));
  FBrowsingPath.FromJson(LJSON.FindValue('browsingPath'));
  FDebugDCUPath.FromJson(LJSON.FindValue('debugDCUPath'));
end;

function TManifestPlatform.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('sourcePath',   FSourcePath.ToJson);
  Result.AddPair('browsingPath', FBrowsingPath.ToJson);
  Result.AddPair('debugDCUPath', FDebugDCUPath.ToJson);
end;

{ TSupportedPlatforms }

constructor TSupportedPlatforms.Create;
begin
  inherited Create([doOwnsValues]);
end;

procedure TSupportedPlatforms.FromJson(LJSON: TJSONValue);
var
  LPair: TJSONPair;
  LPlatform: TManifestPlatform;
begin
  if not Assigned(LJSON) then
    Exit;
  for LPair in (LJSON as TJSONObject) do
  begin
    LPlatform := TManifestPlatform.Create;
    LPlatform.FromJson(LPair.JsonValue);
    Add(LPair.JsonString.Value, LPlatform);
  end;
end;

function TSupportedPlatforms.ToJson: TJSONObject;
var
  LPair: TPair<string, TManifestPlatform>;
begin
  Result := TJSONObject.Create;
  for LPair in Self do
    Result.AddPair(LPair.Key, LPair.Value.ToJson);
end;

{ TManifestPackage }

constructor TManifestPackage.Create;
begin
  inherited Create;
  FType := TJsonStringList.Create;
end;

destructor TManifestPackage.Destroy;
begin
  FType.Free;
  inherited;
end;

procedure TManifestPackage.FromJson(LJSON: TJSONValue);
begin
  if not Assigned(LJSON) then
    Exit;
  FName := LJSON.GetValue<string>('name', '');
  FType.FromJson(LJSON.FindValue('type'));
end;

function TManifestPackage.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', FName);
  Result.AddPair('type', FType.ToJson);
end;

{ TManifestPackageList }

constructor TManifestPackageList.Create;
begin
  inherited Create(True);
end;

procedure TManifestPackageList.FromJson(LJSON: TJSONValue);
var
  LItem: TJSONValue;
  LPackage: TManifestPackage;
begin
  if not Assigned(LJSON) then
    Exit;
  for LItem in (LJSON as TJSONArray) do
  begin
    LPackage := TManifestPackage.Create;
    LPackage.FromJson(LItem);
    Add(LPackage);
  end;
end;

function TManifestPackageList.ToJson: TJSONArray;
var
  LPackage: TManifestPackage;
begin
  Result := TJSONArray.Create;
  for LPackage in Self do
    Result.AddElement(LPackage.ToJson);
end;

{ TManifestPackageFolders }

procedure TManifestPackageFolders.FromJson(LJSON: TJSONValue);
var
  LPair: TJSONPair;
begin
  if not Assigned(LJSON) then
    Exit;
  for LPair in (LJSON as TJSONObject) do
    Add(LPair.JsonString.Value, LPair.JsonValue.Value);
end;

function TManifestPackageFolders.ToJson: TJSONObject;
var
  LPair: TPair<string, string>;
begin
  Result := TJSONObject.Create;
  for LPair in Self do
    Result.AddPair(LPair.Key, LPair.Value);
end;

{ TManifestPackageOptions }

constructor TManifestPackageOptions.Create;
begin
  inherited Create;
  FPackageFolders := TManifestPackageFolders.Create;
end;

destructor TManifestPackageOptions.Destroy;
begin
  FPackageFolders.Free;
  inherited;
end;

procedure TManifestPackageOptions.FromJson(LJSON: TJSONValue);
begin
  if not Assigned(LJSON) then
    Exit;
  FPackageFolders.FromJson(LJSON.FindValue('package folders'));
end;

function TManifestPackageOptions.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('package folders', FPackageFolders.ToJson);
end;

{ TManifest }

constructor TManifest.Create;
begin
  inherited Create;
  FApplication := TApplicationInfo.Create;
  FSupportedPlatforms := TSupportedPlatforms.Create;
  FPackages := TManifestPackageList.Create;
  FPackageOptions := TManifestPackageOptions.Create;
  FDependencies := TJsonStringList.Create;
end;

destructor TManifest.Destroy;
begin
  FApplication.Free;
  FSupportedPlatforms.Free;
  FPackages.Free;
  FPackageOptions.Free;
  FDependencies.Free;
  inherited;
end;

procedure TManifest.FromJson(LJSON: TJSONValue);
begin
  if not Assigned(LJSON) then
    Exit;
  FApplication.FromJson(LJSON.FindValue('application'));
  FSupportedPlatforms.FromJson(LJSON.FindValue('supportedPlatforms'));
  FPackages.FromJson(LJSON.FindValue('packages'));
  FPackageOptions.FromJson(LJSON.FindValue('package options'));
  FDependencies.FromJson(LJSON.FindValue('dependencies'));
end;

function TManifest.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('application', FApplication.ToJson);
  Result.AddPair('supportedPlatforms', FSupportedPlatforms.ToJson);
  Result.AddPair('packages', FPackages.ToJson);
  Result.AddPair('package options', FPackageOptions.ToJson);
  Result.AddPair('dependencies', FDependencies.ToJson);
end;

procedure TManifest.FromJsonString(const AJson: string);
var
  LJSON: TJSONValue;
begin
  LJSON := TJSONObject.ParseJSONValue(AJson);
  try
    FromJson(LJSON);
  finally
    LJSON.Free;
  end;
end;

class function TManifest.Load(const Source: string): TManifest;
var
  Parts: TArray<string>;
  SubPath: string;
  FilePath: string;
  Json: string;
begin
  if Source = '' then
    raise Exception.Create('-Install is required. Use -Help for usage information.');

  if not Source.StartsWith('http://', True)
      and not Source.StartsWith('https://', True)
      and not Source.EndsWith('.json', True) then
  begin
    Parts := Source.Split(['.', '/'], 2);
    SubPath := Parts[0] + '\' + Parts[1] + '.json';
    FilePath := TPath.Combine(TWorkspace.BlocksDir, 'repository\' + SubPath);
    TConsole.WriteLine('Resolving ID to: ' + FilePath, clDkGray);
  end
  else
    FilePath := Source;

  if FilePath.StartsWith('http://', True) or FilePath.StartsWith('https://', True) then
    Json := THttpUtils.GetAsString(FilePath)
  else
  begin
    if not TFile.Exists(FilePath) then
      raise Exception.CreateFmt('Config file not found: %s', [FilePath]);
    Json := TFile.ReadAllText(FilePath, TEncoding.UTF8);
  end;

  Result := TManifest.Create;
  try
    Result.FromJsonString(Json);
  except
    Result.Free;
    raise;
  end;
end;

function TManifest.ToJsonString: string;
var
  LJSON: TJSONObject;
begin
  LJSON := ToJson;
  try
    Result := LJSON.ToJSON;
  finally
    LJSON.Free;
  end;
end;

end.

