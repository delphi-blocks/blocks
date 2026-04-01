unit Blocks.Manifest;

interface

uses
  System.Generics.Collections;

/// <summary>Application metadata section of a package manifest.</summary>
type
  TManifestApplication = record
    /// <summary>Canonical library identifier in the form <c>owner.package</c>.</summary>
    Id: string;
    /// <summary>Human-readable package name used as the project directory name.</summary>
    Name: string;
    /// <summary>Short description of the package.</summary>
    Description: string;
    /// <summary>GitHub repository URL (e.g. <c>https://github.com/owner/repo</c>).</summary>
    Url: string;
  end;

  /// <summary>Per-platform path configuration declared in a package manifest.</summary>
  TManifestPlatform = record
    /// <summary>Platform identifier, e.g. <c>Win32</c> or <c>Win64</c>.</summary>
    Name: string;
    /// <summary>Paths to add to the Delphi <c>Search Path</c> library setting.</summary>
    SourcePath: TArray<string>;
    /// <summary>Paths to add to the Delphi <c>Browsing Path</c> library setting.</summary>
    BrowsingPath: TArray<string>;
    /// <summary>Paths to add to the Delphi <c>Debug DCU Path</c> library setting.</summary>
    DebugDCUPath: TArray<string>;
  end;

  /// <summary>Describes a single <c>.dproj</c> package file declared in a manifest.</summary>
  TManifestPackage = record
    /// <summary>Package file name without extension, matching a <c>.dproj</c> under the packages folder.</summary>
    Name: string;
    /// <summary>Package type tags (e.g. <c>runtime</c>, <c>designtime</c>).</summary>
    PackageTypes: TArray<string>;
  end;

  /// <summary>Loaded representation of a package manifest JSON file.</summary>
  /// <remarks>
  ///   Use <see cref="Load"/> to resolve a source (ID, file path, or URL) and parse it in one step.
  ///   The caller is responsible for freeing the returned instance.
  /// </remarks>
  TManifest = class
  private
    FApplication: TManifestApplication;
    FPlatforms: TArray<TManifestPlatform>;
    FPackages: TArray<TManifestPackage>;
    FPackageFolders: TDictionary<string, string>;
    FDependencies: TArray<string>;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Populates all fields by parsing a JSON manifest string.</summary>
    /// <param name="AJson">UTF-8 JSON string conforming to the Blocks manifest schema.</param>
    /// <exception cref="Exception">Raised when <c>AJson</c> is not valid JSON.</exception>
    procedure FromJson(const AJson: string);

    /// <summary>Serialises the manifest back to a JSON string.</summary>
    /// <returns>JSON representation of the manifest, suitable for writing to a file.</returns>
    function ToJson: string;

    /// <summary>Resolves a source, loads its JSON content, and returns an initialised manifest.</summary>
    /// <param name="Source">Accepted forms:
    ///   <list type="bullet">
    ///     <item><c>owner.package</c> or <c>owner/package</c> — resolved to
    ///       <c>&lt;cwd&gt;\.blocks\repository\owner\package.json</c>.</item>
    ///     <item>A local file path ending in <c>.json</c>.</item>
    ///     <item>An <c>http://</c> or <c>https://</c> URL.</item>
    ///   </list>
    /// </param>
    /// <returns>A new <see cref="TManifest"/> instance. The caller must free it.</returns>
    /// <exception cref="Exception">Raised when the source cannot be resolved or the JSON is invalid.</exception>
    class function Load(const Source: string): TManifest;

    /// <summary>Application metadata parsed from the <c>application</c> JSON section.</summary>
    property Application: TManifestApplication read FApplication;
    /// <summary>Supported platform configurations parsed from <c>supportedPlatforms</c>.</summary>
    property Platforms: TArray<TManifestPlatform> read FPlatforms;
    /// <summary>Package descriptors parsed from the <c>packages</c> JSON array.</summary>
    property Packages: TArray<TManifestPackage> read FPackages;
    /// <summary>Version-key to folder-name map parsed from <c>package options.package folders</c>.</summary>
    property PackageFolders: TDictionary<string, string> read FPackageFolders;
    /// <summary>Dependency identifiers parsed from the <c>dependencies</c> JSON array.</summary>
    property Dependencies: TArray<string> read FDependencies;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Blocks.Console,
  Blocks.Http,
  Blocks.Workspace;

// -- helpers ------------------------------------------------------------------

function ReadStringArray(Obj: TJSONObject; const Key: string): TArray<string>;
begin
  Result := [];
  var Arr := Obj.GetValue(Key) as TJSONArray;
  if not Assigned(Arr) then
    Exit;
  SetLength(Result, Arr.Count);
  for var I := 0 to Arr.Count - 1 do
    Result[I] := (Arr.Items[I] as TJSONString).Value;
end;

function BuildStringArray(const Values: TArray<string>): TJSONArray;
begin
  Result := TJSONArray.Create;
  for var I := 0 to High(Values) do
    Result.Add(Values[I]);
end;

// -- TManifest ----------------------------------------------------------------

constructor TManifest.Create;
begin
  inherited;
  FPackageFolders := TDictionary<string, string>.Create;
end;

destructor TManifest.Destroy;
begin
  FPackageFolders.Free;
  inherited;
end;

procedure TManifest.FromJson(const AJson: string);
var
  Root: TJSONObject;
  AppObj: TJSONObject;
  PlatformsObj: TJSONObject;
  PkgsArr: TJSONArray;
  PkgOptionsObj: TJSONObject;
  FoldersObj: TJSONObject;
  DepsArr: TJSONArray;
  I: Integer;
  Plat: TManifestPlatform;
  Pkg: TManifestPackage;
  PlatConfig: TJSONObject;
  PkgObj: TJSONObject;
begin
  Root := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if not Assigned(Root) then
    raise Exception.Create('Invalid manifest JSON.');
  try
    // application
    AppObj := Root.GetValue('application') as TJSONObject;
    if Assigned(AppObj) then
    begin
      FApplication.Id := AppObj.GetValue<string>('id', '');
      FApplication.Name := AppObj.GetValue<string>('name', '');
      FApplication.Description := AppObj.GetValue<string>('description', '');
      FApplication.Url := AppObj.GetValue<string>('url', '');
    end;

    // supportedPlatforms
    PlatformsObj := Root.GetValue('supportedPlatforms') as TJSONObject;
    if Assigned(PlatformsObj) then
    begin
      SetLength(FPlatforms, PlatformsObj.Count);
      for I := 0 to PlatformsObj.Count - 1 do
      begin
        PlatConfig := PlatformsObj.Pairs[I].JsonValue as TJSONObject;
        Plat.Name := PlatformsObj.Pairs[I].JsonString.Value;
        Plat.SourcePath := ReadStringArray(PlatConfig, 'sourcePath');
        Plat.BrowsingPath := ReadStringArray(PlatConfig, 'browsingPath');
        Plat.DebugDCUPath := ReadStringArray(PlatConfig, 'debugDCUPath');
        FPlatforms[I] := Plat;
      end;
    end;

    // packages
    PkgsArr := Root.GetValue('packages') as TJSONArray;
    if Assigned(PkgsArr) then
    begin
      SetLength(FPackages, PkgsArr.Count);
      for I := 0 to PkgsArr.Count - 1 do
      begin
        PkgObj := PkgsArr.Items[I] as TJSONObject;
        Pkg.Name := PkgObj.GetValue<string>('name', '');
        Pkg.PackageTypes := ReadStringArray(PkgObj, 'type');
        FPackages[I] := Pkg;
      end;
    end;

    // package options -> package folders
    FPackageFolders.Clear;
    PkgOptionsObj := Root.GetValue('package options') as TJSONObject;
    if Assigned(PkgOptionsObj) then
    begin
      FoldersObj := PkgOptionsObj.GetValue('package folders') as TJSONObject;
      if Assigned(FoldersObj) then
        for I := 0 to FoldersObj.Count - 1 do
          FPackageFolders
              .Add(FoldersObj.Pairs[I].JsonString.Value, (FoldersObj.Pairs[I].JsonValue as TJSONString).Value);
    end;

    // dependencies
    DepsArr := Root.GetValue('dependencies') as TJSONArray;
    if Assigned(DepsArr) then
    begin
      SetLength(FDependencies, DepsArr.Count);
      for I := 0 to DepsArr.Count - 1 do
        FDependencies[I] := (DepsArr.Items[I] as TJSONString).Value;
    end;
  finally
    Root.Free;
  end;
end;

function TManifest.ToJson: string;
var
  Root: TJSONObject;
  AppObj: TJSONObject;
  PlatformsObj: TJSONObject;
  PlatObj: TJSONObject;
  PkgsArr: TJSONArray;
  PkgObj: TJSONObject;
  TypeArr: TJSONArray;
  PkgOptionsObj: TJSONObject;
  FoldersObj: TJSONObject;
  DepsArr: TJSONArray;
  I: Integer;
  Plat: TManifestPlatform;
  Pkg: TManifestPackage;
  Key: string;
begin
  Root := TJSONObject.Create;
  try
    // application
    AppObj := TJSONObject.Create;
    AppObj.AddPair('id', FApplication.Id);
    AppObj.AddPair('name', FApplication.Name);
    AppObj.AddPair('description', FApplication.Description);
    AppObj.AddPair('url', FApplication.Url);
    Root.AddPair('application', AppObj);

    // supportedPlatforms
    PlatformsObj := TJSONObject.Create;
    for Plat in FPlatforms do
    begin
      PlatObj := TJSONObject.Create;
      if Length(Plat.SourcePath) > 0 then
        PlatObj.AddPair('sourcePath', BuildStringArray(Plat.SourcePath));
      if Length(Plat.BrowsingPath) > 0 then
        PlatObj.AddPair('browsingPath', BuildStringArray(Plat.BrowsingPath));
      if Length(Plat.DebugDCUPath) > 0 then
        PlatObj.AddPair('debugDCUPath', BuildStringArray(Plat.DebugDCUPath));
      PlatformsObj.AddPair(Plat.Name, PlatObj);
    end;
    Root.AddPair('supportedPlatforms', PlatformsObj);

    // packages
    PkgsArr := TJSONArray.Create;
    for Pkg in FPackages do
    begin
      PkgObj := TJSONObject.Create;
      TypeArr := TJSONArray.Create;
      for I := 0 to High(Pkg.PackageTypes) do
        TypeArr.Add(Pkg.PackageTypes[I]);
      PkgObj.AddPair('name', Pkg.Name);
      PkgObj.AddPair('type', TypeArr);
      PkgsArr.AddElement(PkgObj);
    end;
    Root.AddPair('packages', PkgsArr);

    // package options -> package folders
    FoldersObj := TJSONObject.Create;
    for Key in FPackageFolders.Keys do
      FoldersObj.AddPair(Key, FPackageFolders[Key]);
    PkgOptionsObj := TJSONObject.Create;
    PkgOptionsObj.AddPair('package folders', FoldersObj);
    Root.AddPair('package options', PkgOptionsObj);

    // dependencies
    DepsArr := TJSONArray.Create;
    for I := 0 to High(FDependencies) do
      DepsArr.Add(FDependencies[I]);
    Root.AddPair('dependencies', DepsArr);

    Result := Root.ToJSON;
  finally
    Root.Free;
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
    Result.FromJson(Json);
  except
    Result.Free;
    raise;
  end;
end;

end.
