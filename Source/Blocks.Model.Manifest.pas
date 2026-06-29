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
unit Blocks.Model.Manifest;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  Blocks.Core,
  Blocks.JSON;

type
  EManfestError = class(Exception)
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
    FSourcePath: TStringList;
    FReleaseDCUPath: TStringList;
    FDebugDCUPath: TStringList;
    FRuntimeOnly: Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    property SourcePath: TStringList read FSourcePath;
    property ReleaseDCUPath: TStringList read FReleaseDCUPath;
    property DebugDCUPath: TStringList read FDebugDCUPath;
    /// <summary>When <c>True</c>, design-time packages are skipped when installing this platform.</summary>
    property RuntimeOnly: Boolean read FRuntimeOnly write FRuntimeOnly;
  end;

  // -----------------------------------------------------------------------
  // Platform map: name -> TManifestPlatform
  //
  // A manifest key may list two or more platform names separated by commas
  // (e.g. "Win64,Linux64"); FromJSON expands such a key into one dictionary
  // entry per platform name. ToJSON does not (yet) reverse this compaction:
  // identical platforms are written back out as separate keys.
  // -----------------------------------------------------------------------
  TSupportedPlatforms = class(TObjectOrderedDictionary<string, TManifestPlatform>)
  public
    function ToJSON: TJSONValue;
    procedure FromJSON(AJSONObject: TJSONValue);

    constructor Create;
  end;

  // -----------------------------------------------------------------------
  // Dependency map: name -> version
  // -----------------------------------------------------------------------
  TDependencyMap = class(TOrderedDictionary<string, string>)
  public
    constructor Create;
  end;

  // -----------------------------------------------------------------------
  // A Delphi package
  // -----------------------------------------------------------------------
  TManifestPackage = class
  private
    FName: string;
    FType: TStringList;
    FProducts: TStringList;
  public
    constructor Create;
    destructor Destroy; override;

    function IsDesignTime: Boolean;
    function IsRuntime: Boolean;

    /// <summary>Returns <c>True</c> if this package is compatible with the given Delphi product.</summary>
    /// <param name="AProductName">Internal product version name (e.g. <c>delphi13</c>).</param>
    /// <remarks>
    ///  An empty <c>products</c> list means the package supports every product. Each entry is
    ///  matched exactly, unless it ends with <c>+</c>, which means "from that version onward".
    /// </remarks>
    function SupportsProduct(const AProductName: string): Boolean;

    property Name: string read FName write FName;
    property &Type: TStringList read FType;
    /// <summary>Products the package is compatible with; empty means all products.</summary>
    property Products: TStringList read FProducts;
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
  TManifestPackageFolders = class(TOrderedDictionary<string, string>)
  end;

  // -----------------------------------------------------------------------
  // Package options
  // -----------------------------------------------------------------------
  TManifestPackageOptions = class
  private
    FRootFolder: string;
    FFolders: TManifestPackageFolders;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Root folder (relative to the project directory) that contains the
    ///   package subfolders. Defaults to <c>packages</c>. Combined with the
    ///   version-specific entry from <see cref="Folders"/> to locate the <c>.dproj</c> files.</summary>
    [JsonName('rootFolder')]
    property RootFolder: string read FRootFolder write FRootFolder;
    property Folders: TManifestPackageFolders read FFolders;
  end;

  /// <summary>Base class for the typed <c>args</c> of a manifest script. Each
  ///   command name maps to a concrete subclass via
  ///   <see cref="TManifest.RegisterScriptManifest"/>; the subclass constructor
  ///   decodes the raw <c>args</c> JSON (which may be a string, object, array or
  ///   absent) into strongly-typed properties. Commands retrieve their own type
  ///   through <see cref="GetAs"/>.</summary>
  TManifestScriptArguments = class
  private
    FJSONValue: TJSONValue;
  public
    /// <summary>Casts these arguments to the concrete type the command expects,
    ///   raising <c>EManfestError</c> when the instance is nil (i.e. the script
    ///   declared no <c>args</c>). Lets a command fail with a clear message
    ///   instead of dereferencing nil.</summary>
    function GetAs<T: class>(): T;
    /// <summary>Decodes <paramref name="AValue"/> (the raw <c>args</c> JSON node,
    ///   possibly nil) into typed fields, and keeps a private clone of it for
    ///   <see cref="JSONValue"/>. Subclasses override to parse their own shape.</summary>
    constructor Create(AValue: TJSONValue); virtual;
    destructor Destroy; override;

    /// <summary>The raw <c>args</c> JSON node these arguments were decoded from,
    ///   as a clone owned by this object. Lets a script round-trip back to JSON
    ///   without re-encoding each command's typed fields. Nil when the script
    ///   declared no <c>args</c>.</summary>
    property JSONValue: TJSONValue read FJSONValue;
  end;

  TManifestScriptArgumentsClass = class of TManifestScriptArguments;

  /// <summary>Fallback argument type for commands that take no <c>args</c>.</summary>
  TManifestNoArguments = class(TManifestScriptArguments);

  /// <summary>Arguments for the <c>compile</c> command. The <c>args</c> JSON is an
  ///   object: <c>{ "projectFile": "...", "platforms": ["Win32", "Win64"] }</c>.
  ///   <c>platforms</c> is mandatory.</summary>
  TManifestCompileArguments = class(TManifestScriptArguments)
  private
    FProjectFile: string;
    FPlatforms: TArray<string>;
  public
    property ProjectFile: string read FProjectFile;
    property Platforms: TArray<string> read FPlatforms;

    constructor Create(AValue: TJSONValue); override;
  end;

  /// <summary>Arguments for the <c>echo</c> command. The <c>args</c> JSON is a plain
  ///   string holding the message to print (still subject to <c>$(VAR)</c>
  ///   expansion at run time).</summary>
  TManifestEchoArguments = class(TManifestScriptArguments)
  private
    FMessage: string;
  public
    property Message: string read FMessage;

    constructor Create(AValue: TJSONValue); override;
  end;

  /// <summary>Arguments for the <c>expert</c> command: the <c>compile</c> arguments
  ///   plus an optional <c>description</c> used as the registered expert's label
  ///   (defaults to the <c>.dll</c> file name when empty).</summary>
  TManifestExpertArguments = class(TManifestCompileArguments)
  private
    FDescription: string;
  public
    property Description: string read FDescription;
    constructor Create(AValue: TJSONValue); override;
  end;

  // -----------------------------------------------------------------------
  // A script to run during the install pipeline (e.g. on "afterCompile")
  // -----------------------------------------------------------------------
  TManifestScript = class
  private
    FDescription: string;
    FEvent: string;
    FCommand: string;
    FArgs: TManifestScriptArguments;
  public
    constructor Create;
    destructor Destroy; override;

    function ToJSON: TJSONValue;
    /// <summary>Populates the script from a manifest <c>scripts</c> entry. The
    ///   concrete <see cref="Args"/> type is chosen from <see cref="Command"/> via
    ///   the registry, so <c>command</c> must be read before <c>args</c>; an
    ///   unregistered command falls back to <see cref="TManifestNoArguments"/>.</summary>
    procedure FromJSON(AJSONObject: TJSONValue);
    procedure FromJSONString(const AValue: string);

    property Description: string read FDescription write FDescription;
    property Event: string read FEvent write FEvent;
    property Command: string read FCommand write FCommand;
    /// <summary>Typed arguments, owned by this script. Nil until
    ///   <see cref="FromJSON"/> runs (a script built by hand has no args).</summary>
    property Args: TManifestScriptArguments read FArgs;
  end;

  // -----------------------------------------------------------------------
  // Script list
  // -----------------------------------------------------------------------
  TManifestScriptList = class(TObjectList<TManifestScript>)
  public
    constructor Create;
  end;

  TManifestRepositoryConfig = class
  protected
    FValue: TJSONValue;
  public
    function ToString: string; override;

    constructor Create(AValue: TJSONValue);
  end;

  TNoneConfig = class(TManifestRepositoryConfig)
  end;

  TGitHubConfig = class(TManifestRepositoryConfig)
  private
    function GetUrl: string;
  public
    function ToString: string; override;
    property Url: string read GetUrl;
  end;

  TBitBucketConfig = class(TManifestRepositoryConfig)
  private
    function GetUrl: string;
  public
    function ToString: string; override;
    property Url: string read GetUrl;
  end;

  TLocalConfig = class(TManifestRepositoryConfig)
  private
    function GetUrl: string;
  public
    function ToString: string; override;
    property Url: string read GetUrl;
  end;

  /// <summary>Repository cloned with the git CLI. <c>tag</c>, <c>commit</c> and
  ///   <c>branch</c> are optional and mutually exclusive.</summary>
  TGitConfig = class(TManifestRepositoryConfig)
  private
    function GetUrl: string;
    function GetTag: string;
    function GetCommit: string;
    function GetBranch: string;
  public
    function ToString: string; override;
    /// <summary>The single git ref to fetch (tag, commit or branch), or an empty
    ///   string when none is specified (meaning the remote default branch).</summary>
    /// <exception cref="EManfestError">Raised when more than one of tag/commit/branch is set.</exception>
    function GitRef: string;
    property Url: string read GetUrl;
    property Tag: string read GetTag;
    property Commit: string read GetCommit;
    property Branch: string read GetBranch;
  end;

  // -----------------------------------------------------------------------
  // Manifest repository information
  // -----------------------------------------------------------------------

  TManifestRepository = class
    const
      RepoTypeNone = 'none';
  private
    FJSONObject: TJSONObject;
    FRepoType: string;
    FConfig: TManifestRepositoryConfig;
  public

    function ToJSON: TJSONValue;
    procedure FromJSON(AJSONObject: TJSONValue);
    function Config<T: TManifestRepositoryConfig>: T;
    function ToString: string; override;

    constructor Create;
    destructor Destroy; override;

    property RepoType: string read FRepoType write FRepoType;
  end;

  // -----------------------------------------------------------------------
  // Root manifest configuration
  // -----------------------------------------------------------------------
  TManifest = class
  private
    FRepository: TManifestRepository;
    FPlatforms: TSupportedPlatforms;
    FPackages: TManifestPackageList;
    FPackageOptions: TManifestPackageOptions;
    FDependencies: TDependencyMap;
    FScripts: TManifestScriptList;
    FId: string;
    FVersion: string;
    FName: string;
    FLicense: string;
    FDescription: string;
    FHomepage: string;
    FAuthor: string;
    FKeywords: TStringList;
    function GetIsMeta: Boolean;
  private
    class var
      FRegistry: TDictionary<string, TManifestScriptArgumentsClass>;
  public
    class function GetManifest(const APackageName, APackageVersion: string): TManifest;
    /// <summary>Returns all available versions of a package, sorted ascending.</summary>
    /// <param name="APackageName">Package identifier in the form <c>vendor.name</c>.</param>
    class function GetVersions(const APackageName: string): TArray<TSemVer>;
    /// <summary>Maps a script command name to the class that decodes its <c>args</c>.
    ///   Built-in commands register in this unit's <c>initialization</c>; the test
    ///   suite registers its own. Keep in sync with the command registry in
    ///   <c>Blocks.Service.Script</c>.</summary>
    class procedure RegisterScriptManifest(const AName: string; AClass: TManifestScriptArgumentsClass);

    class constructor Create;
    class destructor Destroy;

  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Returns <c>True</c> when the package can be built for the given Delphi product.</summary>
    /// <param name="AProductName">Internal product version name (e.g. <c>delphi13</c>).</param>
    /// <remarks>
    ///  When <c>packageOptions.folders</c> is empty the <c>.dproj</c> files live directly under the
    ///  root folder, so every product is supported. Otherwise the product is supported only when at
    ///  least one folder key is at or below it, mirroring the resolution done by
    ///  <c>TProduct.GetPackageFolder</c>.
    /// </remarks>
    function IsProductSupported(const AProductName: string): Boolean;

    [JsonIgnore]
    property IsMeta: Boolean read GetIsMeta;

    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property Version: string read FVersion write FVersion;
    property Description: string read FDescription write FDescription;
    property License: string read FLicense write FLicense;
    property Homepage: string read FHomepage write FHomepage;
    property Repository: TManifestRepository read FRepository;
    property Author: string read FAuthor write FAuthor;
    property Keywords: TStringList read FKeywords;

    property Platforms: TSupportedPlatforms read FPlatforms;
    property Packages: TManifestPackageList read FPackages;
    [JsonName('packageOptions')]
    property PackageOptions: TManifestPackageOptions read FPackageOptions;
    property Dependencies: TDependencyMap read FDependencies;
    property Scripts: TManifestScriptList read FScripts;
  end;

  // -----------------------------------------------------------------------
  // Repository index entry — minimal info for search/lookup
  // -----------------------------------------------------------------------
  TRepositoryIndexEntry = class
  private
    FId: string;
    FName: string;
    FDescription: string;
    FKeywords: TStringList;
    FVersions: TStringList;
  public
    constructor Create;
    destructor Destroy; override;

    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property Description: string read FDescription write FDescription;
    property Keywords: TStringList read FKeywords;
    /// <summary>Available versions, sorted descending (index 0 is the latest).</summary>
    property Versions: TStringList read FVersions;
  end;

  TRepositoryIndexEntryList = class(TObjectList<TRepositoryIndexEntry>)
  public
    constructor Create;
  end;

  // -----------------------------------------------------------------------
  // Repository index — searchable cache of all packages in the local repo
  // -----------------------------------------------------------------------
  TRepositoryIndex = class
  private
    FEntries: TRepositoryIndexEntryList;
    FIndexPath: string;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Scans the workspace repository folder and returns a populated index.</summary>
    /// <remarks>For each package, reads only the latest version's manifest.</remarks>
    class function Build: TRepositoryIndex;

    /// <summary>Load the index from <c>{BlocksDir}\repository\index.json</c>.</summary>
    procedure Load;
    /// <summary>Save the index to <c>{BlocksDir}\repository\index.json</c>.</summary>
    procedure Save;

    /// <summary>Returns entries whose id, name, description or any keyword contains <paramref name="APattern"/> (case insensitive).</summary>
    /// <param name="APattern">Substring to look for; empty matches all entries.</param>
    function Search(const APattern: string): TArray<TRepositoryIndexEntry>;

    /// <summary>Returns entries whose <c>Name</c> matches <paramref name="AName"/> exactly (case insensitive).</summary>
    /// <param name="AName">Package name to look up; package names are not guaranteed to be unique.</param>
    function FindByName(const AName: string): TArray<TRepositoryIndexEntry>;

    property Entries: TRepositoryIndexEntryList read FEntries;
  end;

implementation

uses
  System.StrUtils,
  Blocks.Console,
  Blocks.Http,
  Blocks.Service.Workspace;

const
  ManifestSchemaUrl = 'https://delphi-blocks.dev/schema/package.v1.json';
  RepositoryIndexSchemaUrl = 'https://delphi-blocks.dev/schema/repository-index.v1.json';

{ TDependencyMap }

constructor TDependencyMap.Create;
begin
  // Package ids are case-insensitive, so use a case-insensitive comparer: lookups
  // (TryGetValue / ContainsKey / the indexer) then match regardless of casing.
  inherited Create(TIStringComparer.Ordinal);
end;

{ TManifestPlatform }

constructor TManifestPlatform.Create;
begin
  inherited Create;
  FSourcePath := TStringList.Create;
  FReleaseDCUPath := TStringList.Create;
  FDebugDCUPath := TStringList.Create;
end;

destructor TManifestPlatform.Destroy;
begin
  FSourcePath.Free;
  FReleaseDCUPath.Free;
  FDebugDCUPath.Free;
  inherited;
end;

{ TSupportedPlatforms }

constructor TSupportedPlatforms.Create;
begin
  inherited Create([doOwnsValues]);
end;

procedure TSupportedPlatforms.FromJSON(AJSONObject: TJSONValue);
begin
  if AJSONObject is TJSONObject then
  begin
    for var LJSONPair in TJSONObject(AJSONObject) do
    begin
      var LPlatforms := LJSONPair.JsonString.Value.Split([',']);
      for var LPlatform in LPlatforms do
      begin
        Add(LPlatform, TJsonHelper.JSONToObject<TManifestPlatform>(LJSONPair.JsonValue));
      end;
    end;
  end;
end;

function TSupportedPlatforms.ToJSON: TJSONValue;
begin
  // TODO: this method should compact the platform. If two platforms are
  // identical is should create a single row both platforms:
  // "win32,win64": {
  //   ...
  // }
  // Now Blocks never write the manifest so this feature it's not yet implemented
  var LJSONObject := TJSONObject.Create;
  try
    for var LPlatform in Self do
    begin
      LJSONObject.AddPair(LPlatform.Key, TJsonHelper.ObjectToJSON(LPlatform.Value));
    end;
  except
    LJSONObject.Free;
    raise;
  end;
  Result := LJSONObject;
end;

{ TManifestPackage }

constructor TManifestPackage.Create;
begin
  inherited Create;
  FType := TStringList.Create;
  FProducts := TStringList.Create;
end;

destructor TManifestPackage.Destroy;
begin
  FType.Free;
  FProducts.Free;
  inherited;
end;

function TManifestPackage.IsDesignTime: Boolean;
begin
  Result := &Type.Contains('designtime');
end;

function TManifestPackage.IsRuntime: Boolean;
begin
  Result := &Type.Contains('runtime');
end;

function TManifestPackage.SupportsProduct(const AProductName: string): Boolean;

  function VersionRank(const AVersionName: string): Integer;
  begin
    for var I := Low(VersionOrder) to High(VersionOrder) do
      if SameText(VersionOrder[I], AVersionName) then
        Exit(I);
    Result := -1;
  end;

begin
  // No "products" constraint means the package is compatible with every product.
  if FProducts.Count = 0 then
    Exit(True);

  var LProductRank := VersionRank(AProductName);

  for var LEntry in FProducts do
  begin
    var LName := LEntry.Trim;
    if LName.EndsWith('+') then
    begin
      // "from this version onward": product must rank at or above the listed one.
      var LBaseRank := VersionRank(TrimRight(LName, ['+']));
      if (LBaseRank >= 0) and (LProductRank >= LBaseRank) then
        Exit(True);
    end
    else if SameText(LName, AProductName) then
      Exit(True);
  end;

  Result := False;
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
  FRootFolder := 'packages';
  FFolders := TManifestPackageFolders.Create;
end;

destructor TManifestPackageOptions.Destroy;
begin
  FFolders.Free;
  inherited;
end;

{ TManifestScript }

constructor TManifestScript.Create;
begin
  inherited Create;
  FArgs := nil;
end;

destructor TManifestScript.Destroy;
begin
  FArgs.Free;
  inherited;
end;

procedure TManifestScript.FromJSON(AJSONObject: TJSONValue);
var
  LArguments: TJSONValue;
begin
  if not Assigned(AJSONObject) then
    Exit;

  FCommand := AJSONObject.GetValue<string>('command');
  FDescription := AJSONObject.GetValue<string>('description', '');
  FEvent := AJSONObject.GetValue<string>('event');

  if not AJSONObject.TryGetValue<TJSONValue>('args', LArguments) then
    LArguments := nil;

  var LScriptArgumentsClass: TManifestScriptArgumentsClass;
  if not TManifest.FRegistry.TryGetValue(FCommand, LScriptArgumentsClass) then
    LScriptArgumentsClass := TManifestNoArguments;

  FreeAndNil(FArgs);
  FArgs := LScriptArgumentsClass.Create(LArguments);
end;

procedure TManifestScript.FromJSONString(const AValue: string);
begin
  var LJSONValue := TJSONObject.ParseJSONValue(AValue, True, True);
  try
    FromJSON(LJSONValue);
  finally
    LJSONValue.Free;
  end;
end;

function TManifestScript.ToJSON: TJSONValue;
begin
  var LResult := TJSONObject.Create;
  LResult.AddPair('command', FCommand);
  if FDescription <> '' then
    LResult.AddPair('description', FDescription);
  LResult.AddPair('event', FEvent);
  // The args are stored verbatim; clone so the result owns its copy and the
  // arguments object keeps ownership of its own JSONValue.
  if Assigned(FArgs) and Assigned(FArgs.JSONValue) then
    LResult.AddPair('args', FArgs.JSONValue.Clone as TJSONValue);
  Result := LResult;
end;

{ TManifestScriptList }

constructor TManifestScriptList.Create;
begin
  inherited Create(True);
end;

{ TManifest }

constructor TManifest.Create;
begin
  inherited Create;
  FRepository := TManifestRepository.Create;
  FKeywords := TStringList.Create;
  FPlatforms := TSupportedPlatforms.Create;
  FPackages := TManifestPackageList.Create;
  FPackageOptions := TManifestPackageOptions.Create;
  FDependencies := TDependencyMap.Create;
  FScripts := TManifestScriptList.Create;
end;

class constructor TManifest.Create;
begin
  FRegistry := TDictionary<string, TManifestScriptArgumentsClass>.Create;
end;

destructor TManifest.Destroy;
begin
  FRepository.Free;
  FKeywords.Free;
  FPlatforms.Free;
  FPackages.Free;
  FPackageOptions.Free;
  FDependencies.Free;
  FScripts.Free;
  inherited;
end;

function TManifest.GetIsMeta: Boolean;
begin
  Result := SameText(FRepository.RepoType, TManifestRepository.RepoTypeNone);
end;

function TManifest.IsProductSupported(const AProductName: string): Boolean;

  function VersionRank(const AVersionName: string): Integer;
  begin
    for var I := Low(VersionOrder) to High(VersionOrder) do
      if SameText(VersionOrder[I], AVersionName) then
        Exit(I);
    Result := -1;
  end;

begin
  // With no per-version folders the .dproj files live directly under the root
  // folder, so the package is buildable for every product.
  if FPackageOptions.Folders.Count = 0 then
    Exit(True);

  var LProductRank := VersionRank(AProductName);

  // Supported when at least one folder key is at or below the product version
  // (mirrors TProduct.GetPackageFolder's greatest-lower-bound resolution).
  for var LKey in FPackageOptions.Folders.Keys do
  begin
    var LKeyRank := VersionRank(TrimRight(LKey, ['+']));
    if (LKeyRank >= 0) and (LKeyRank <= LProductRank) then
      Exit(True);
  end;

  Result := False;
end;

class procedure TManifest.RegisterScriptManifest(const AName: string; AClass: TManifestScriptArgumentsClass);
begin
  FRegistry.AddOrSetValue(AName, AClass);
end;

class destructor TManifest.Destroy;
begin
  FRegistry.Free;
end;

class function TManifest.GetManifest(const APackageName, APackageVersion: string): TManifest;
begin
  var LPackagePair := APackageName.Split(['.']);
  if Length(LPackagePair) <> 2 then
    raise Exception.Create('Package id should be "vendor.name"');

  var LVersions := GetVersions(APackageName);

  var LBest: TSemVer;
  if not TSemVer.BestMatch(LVersions, APackageVersion, LBest) then
  begin
    if APackageVersion = '' then
      raise Exception.CreateFmt('No versions found for package "%s". Try to update the repository', [APackageName])
    else
      raise Exception.CreateFmt(
          'No version matching "%s" found for package "%s". Try to update the repository',
          [APackageVersion, APackageName]);
  end;

  var LVersionsDir := TPath.Combine(TWorkspace.BlocksDir, 'repository', LPackagePair[0], LPackagePair[1]);
  var LFullPath :=
      TPath.Combine(LVersionsDir, LBest.ToString, LPackagePair[0] + '.' + LPackagePair[1] + '.manifest.json');
  if not FileExists(LFullPath) then
    raise Exception.CreateFmt('Manifest file not found: %s', [LFullPath]);

  var LJSON := TJSONObject.ParseJSONValue(TFile.ReadAllText(LFullPath), False, True);
  try
    TJsonHelper.CheckSchema(LJSON, ManifestSchemaUrl);
    Result := TJsonHelper.JSONToObject<TManifest>(LJSON);
  finally
    LJSON.Free;
  end;
end;

class function TManifest.GetVersions(const APackageName: string): TArray<TSemVer>;
var
  LResult: TArray<TSemVer>;
begin
  var LPackagePair := APackageName.Split(['.']);
  if Length(LPackagePair) <> 2 then
    raise Exception.Create('Package id should be "vendor.name"');

  var LVersionsDir := TPath.Combine(TWorkspace.BlocksDir, 'repository', LPackagePair[0], LPackagePair[1]);
  if not TDirectory.Exists(LVersionsDir) then
    raise Exception.CreateFmt('Package "%s" not found in repository. Try to update the repository', [APackageName]);

  LResult := [];
  for var LDir in TDirectory.GetDirectories(LVersionsDir) do
  begin
    var LVer: TSemVer;
    if TSemVer.TryParse(TPath.GetFileName(LDir), LVer) then
      LResult := LResult + [LVer];
  end;

  TArray.Sort<TSemVer>(
      LResult,
      TComparer<TSemVer>.Construct(function(const A, B: TSemVer): Integer begin Result := A.CompareTo(B); end)
  );

  Result := LResult;
end;

{ TRepositoryIndexEntry }

constructor TRepositoryIndexEntry.Create;
begin
  inherited Create;
  FKeywords := TStringList.Create;
  FVersions := TStringList.Create;
end;

destructor TRepositoryIndexEntry.Destroy;
begin
  FKeywords.Free;
  FVersions.Free;
  inherited;
end;

{ TRepositoryIndexEntryList }

constructor TRepositoryIndexEntryList.Create;
begin
  inherited Create(True);
end;

{ TRepositoryIndex }

constructor TRepositoryIndex.Create;
begin
  inherited Create;
  FEntries := TRepositoryIndexEntryList.Create;
  FIndexPath := TPath.Combine(TPath.Combine(TWorkspace.BlocksDir, 'repository'), 'index.json');
end;

destructor TRepositoryIndex.Destroy;
begin
  FEntries.Free;
  inherited;
end;

procedure TRepositoryIndex.Save;
begin
  var LJSON := TJsonHelper.ObjectToJSON(Self) as TJSONObject;
  try
    LJSON.AddPair('$schema', RepositoryIndexSchemaUrl);
    TFile.WriteAllText(FIndexPath, TJsonHelper.PrettyPrint(LJSON));
  finally
    LJSON.Free;
  end;
end;

procedure TRepositoryIndex.Load;
begin
  if FileExists(FIndexPath) then
  begin
    FEntries.Clear;
    var LJSON := TJSONObject.ParseJSONValue(TFile.ReadAllText(FIndexPath), False, True);
    try
      TJsonHelper.CheckSchema(LJSON, RepositoryIndexSchemaUrl);
      TJsonHelper.JSONToObject(Self, LJSON);
    finally
      LJSON.Free;
    end;
  end;
end;

class function TRepositoryIndex.Build: TRepositoryIndex;
begin
  Result := TRepositoryIndex.Create;
  try
    var LRepoDir := TPath.Combine(TWorkspace.BlocksDir, 'repository');
    if not TDirectory.Exists(LRepoDir) then
      Exit;

    for var LOwnerDir in TDirectory.GetDirectories(LRepoDir) do
    begin
      var LOwner := TPath.GetFileName(LOwnerDir);
      for var LPackageDir in TDirectory.GetDirectories(LOwnerDir) do
      begin
        var LPackage := TPath.GetFileName(LPackageDir);
        var LId := LOwner + '.' + LPackage;

        var LSemVers: TArray<TSemVer> := [];
        for var LVersionDir in TDirectory.GetDirectories(LPackageDir) do
        begin
          var LVer: TSemVer;
          if TSemVer.TryParse(TPath.GetFileName(LVersionDir), LVer) then
            LSemVers := LSemVers + [LVer];
        end;
        if Length(LSemVers) = 0 then
          Continue;

        // Sort descending — latest first
        TArray.Sort<TSemVer>(
            LSemVers,
            TComparer<TSemVer>.Construct(function(const A, B: TSemVer): Integer begin Result := B.CompareTo(A); end)
        );

        var LLatestManifestPath :=
            TPath.Combine(TPath.Combine(LPackageDir, LSemVers[0].ToString), LId + '.manifest.json');
        if not FileExists(LLatestManifestPath) then
        begin
          raise EManfestError.CreateFmt('Manifest "%s" not found', [LLatestManifestPath]);
        end;

        var LManifest: TManifest;
        var LJSON := TJSONObject.ParseJSONValue(TFile.ReadAllText(LLatestManifestPath), False, True);
        try
          TJsonHelper.CheckSchema(LJSON, ManifestSchemaUrl);
          LManifest := TJsonHelper.JSONToObject<TManifest>(LJSON);
        finally
          LJSON.Free;
        end;

        try
          var LEntry := TRepositoryIndexEntry.Create;
          LEntry.Id := LId;
          LEntry.Name := LManifest.Name;
          LEntry.Description := LManifest.Description;
          LEntry.Keywords.AddStrings(LManifest.Keywords);
          for var LSubVer in LSemVers do
            LEntry.Versions.Add(LSubVer.ToString);
          Result.Entries.Add(LEntry);
        finally
          LManifest.Free;
        end;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TRepositoryIndex.Search(const APattern: string): TArray<TRepositoryIndexEntry>;
begin
  Result := [];
  for var LEntry in FEntries do
  begin
    if ContainsText(LEntry.Id, APattern)
        or ContainsText(LEntry.Name, APattern)
        or ContainsText(LEntry.Description, APattern) then
    begin
      Result := Result + [LEntry];
      Continue;
    end;

    for var LKeyword in LEntry.Keywords do
      if ContainsText(LKeyword, APattern) then
      begin
        Result := Result + [LEntry];
        Break;
      end;
  end;
end;

function TRepositoryIndex.FindByName(const AName: string): TArray<TRepositoryIndexEntry>;
begin
  Result := [];
  for var LEntry in FEntries do
    if SameText(LEntry.Name, AName) then
      Result := Result + [LEntry];
end;

{ TManifestCompileArguments }

constructor TManifestCompileArguments.Create(AValue: TJSONValue);
begin
  inherited;
  if not Assigned(AValue) or (AValue is not TJSONObject) then
    Exit;

  FProjectFile := AValue.GetValue<string>('projectFile', '');
  FPlatforms := [];

  var LPlatforms := AValue.GetValue<TJSONArray>('platforms', nil);
  if not Assigned(LPlatforms) then
    raise Exception.Create('Manifest error: platform required for "compile" and "expert" script');
  for var LPlatform in LPlatforms do
  begin
    FPlatforms := FPlatforms + [LPlatform.Value];
  end;
end;

{ TManifestScriptArguments }

constructor TManifestScriptArguments.Create(AValue: TJSONValue);
begin
  inherited Create;
  // Keep our own copy: the caller (FromJSON) owns AValue and frees it once
  // parsing is done, but ToJSON needs it later to rebuild the script's JSON.
  if Assigned(AValue) then
    FJSONValue := AValue.Clone as TJSONValue;
end;

destructor TManifestScriptArguments.Destroy;
begin
  FJSONValue.Free;
  inherited;
end;

function TManifestScriptArguments.GetAs<T>: T;
begin
  if not Assigned(Self) then
    raise EManfestError.Create('Invalid arguments');
  Result := Self as T;
end;

{ TManifestEchoArguments }

constructor TManifestEchoArguments.Create(AValue: TJSONValue);
begin
  inherited;
  if not Assigned(AValue) or (AValue is not TJSONString) then
    Exit;

  FMessage := (AValue as TJSONString).Value;
end;

{ TManifestExpertArguments }

constructor TManifestExpertArguments.Create(AValue: TJSONValue);
begin
  inherited;
  if not Assigned(AValue) or (AValue is not TJSONObject) then
    Exit;
  FDescription := AValue.GetValue<string>('description', '');
end;

{ TManifestRepository }

function TManifestRepository.Config<T>: T;
begin
  Result := FConfig as T;
end;

constructor TManifestRepository.Create;
begin
  inherited;
  FRepoType := RepoTypeNone;
  // Start with a valid, empty "none" config so Config<T>/ToString/ToJSON are safe
  // to call even before FromJSON deserializes a real repository.
  FJSONObject := TJSONObject.Create;
  FConfig := TNoneConfig.Create(FJSONObject);
end;

destructor TManifestRepository.Destroy;
begin
  FConfig.Free;
  FJSONObject.Free;
  inherited;
end;

procedure TManifestRepository.FromJSON(AJSONObject: TJSONValue);
begin
  // Release the config/JSON set up by the constructor (or a previous call) before
  // replacing them, so re-deserializing the same instance does not leak.
  FreeAndNil(FConfig);
  FreeAndNil(FJSONObject);

  // Meta-packet doesn't have the repository node
  if not Assigned(AJSONObject) then
    FJSONObject := TJSONObject.Create
  else
    FJSONObject := AJSONObject.Clone as TJSONObject;

  FRepoType := FJSONObject.GetValue<string>('type', 'none');

  if SameText(FRepoType, 'none') then
    FConfig := TNoneConfig.Create(FJSONObject)
  else if SameText(FRepoType, 'github') then
    FConfig := TGitHubConfig.Create(FJSONObject)
  else if SameText(FRepoType, 'bitbucket') then
    FConfig := TBitBucketConfig.Create(FJSONObject)
  else if SameText(FRepoType, 'local') then
    FConfig := TLocalConfig.Create(FJSONObject)
  else if SameText(FRepoType, 'git') then
    FConfig := TGitConfig.Create(FJSONObject)
  else
    raise EManfestError.CreateFmt('Wrong repository type: "%s"', [FRepoType]);
end;

function TManifestRepository.ToJSON: TJSONValue;
begin
  // Return a clone: the caller (serializer) owns the result and frees it with the
  // parent tree, while FJSONObject stays owned by this instance.
  if Assigned(FJSONObject) then
    Result := FJSONObject.Clone as TJSONValue
  else
    Result := TJSONObject.Create;
end;

function TManifestRepository.ToString: string;
begin
  Result := FConfig.ToString;
end;

{ TGitHubConfig }

function TGitHubConfig.GetUrl: string;
begin
  Result := FValue.GetValue<string>('url', '');
end;

function TGitHubConfig.ToString: string;
begin
  Result := GetUrl;
end;

{ TManifestRepositoryConfig }

constructor TManifestRepositoryConfig.Create(AValue: TJSONValue);
begin
  inherited Create;
  FValue := AValue;
end;

function TManifestRepositoryConfig.ToString: string;
begin
  Result := FValue.GetValue<string>('type', '');
end;

{ TBitBucketConfig }

function TBitBucketConfig.GetUrl: string;
begin
  Result := FValue.GetValue<string>('url', '');
end;

function TBitBucketConfig.ToString: string;
begin
  Result := GetUrl;
end;

{ TLocalConfig }

function TLocalConfig.GetUrl: string;
begin
  Result := FValue.GetValue<string>('url', '');
end;

function TLocalConfig.ToString: string;
begin
  Result := GetUrl;
end;

{ TGitConfig }

function TGitConfig.GetUrl: string;
begin
  Result := FValue.GetValue<string>('url', '');
end;

function TGitConfig.GetTag: string;
begin
  Result := FValue.GetValue<string>('tag', '');
end;

function TGitConfig.GetCommit: string;
begin
  Result := FValue.GetValue<string>('commit', '');
end;

function TGitConfig.GetBranch: string;
begin
  Result := FValue.GetValue<string>('branch', '');
end;

function TGitConfig.GitRef: string;
begin
  Result := '';
  var LCount := 0;

  if GetTag <> '' then
  begin
    Result := GetTag;
    Inc(LCount);
  end;
  if GetCommit <> '' then
  begin
    Result := GetCommit;
    Inc(LCount);
  end;
  if GetBranch <> '' then
  begin
    Result := GetBranch;
    Inc(LCount);
  end;

  if LCount > 1 then
    raise EManfestError.Create('Specify only one of "tag", "commit" or "branch" in the git repository.');
end;

function TGitConfig.ToString: string;
begin
  Result := GetUrl;
end;

end.
