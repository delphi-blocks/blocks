unit Blocks.Manifest;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,

  Blocks.Types,
  Blocks.JSON;

type
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

    [JsonList(System.TypeInfo(string))]
    property SourcePath: TJsonStringList read FSourcePath;
    [JsonList(System.TypeInfo(string))]
    property BrowsingPath: TJsonStringList read FBrowsingPath;
    [JsonList(System.TypeInfo(string))]
    property DebugDCUPath: TJsonStringList read FDebugDCUPath;
  end;

  // -----------------------------------------------------------------------
  // Platform map: name -> TManifestPlatform
  // -----------------------------------------------------------------------
  TSupportedPlatforms = class(TObjectDictionary<string, TManifestPlatform>)
  public
    constructor Create;
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

    property Name: string read FName write FName;
    [JsonList(System.TypeInfo(string))]
    property &Type: TJsonStringList read FType;
  end;

  // -----------------------------------------------------------------------
  // Package list
  // -----------------------------------------------------------------------
  TManifestPackageList = class(TObjectList<TManifestPackage>)
  public
    constructor Create;
  end;

  // -----------------------------------------------------------------------
  // Package folders: Delphi version -> folder name
  // -----------------------------------------------------------------------
  TManifestPackageFolders = class(TDictionary<string, string>)
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

    [JsonName('package folders')]
    [JsonDictionary(System.TypeInfo(string))]
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

    property Application: TApplicationInfo read FApplication;
    [JsonDictionary(System.TypeInfo(TManifestPlatform))]
    property SupportedPlatforms: TSupportedPlatforms read FSupportedPlatforms;
    [JsonList(System.TypeInfo(TManifestPackage))]
    property Packages: TManifestPackageList read FPackages;
    [JsonName('package options')]
    property PackageOptions: TManifestPackageOptions read FPackageOptions;
    [JsonList(System.TypeInfo(string))]
    property Dependencies: TJsonStringList read FDependencies;
  end;

implementation

uses
  Blocks.Console,
  Blocks.Http,
  Blocks.Workspace;

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

{ TSupportedPlatforms }

constructor TSupportedPlatforms.Create;
begin
  inherited Create([doOwnsValues]);
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

{ TManifestPackageList }

constructor TManifestPackageList.Create;
begin
  inherited Create(True);
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

  Result := TJsonHelper.JSONToObject<TManifest>(Json);
end;

end.

