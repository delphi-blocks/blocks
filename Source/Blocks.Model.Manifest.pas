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
  public
    constructor Create;
    destructor Destroy; override;

    property SourcePath: TStringList read FSourcePath;
    property ReleaseDCUPath: TStringList read FReleaseDCUPath;
    property DebugDCUPath: TStringList read FDebugDCUPath;
  end;

  // -----------------------------------------------------------------------
  // Platform map: name -> TManifestPlatform
  // -----------------------------------------------------------------------
  TSupportedPlatforms = class(TObjectDictionary<string, TManifestPlatform>)
  public
    constructor Create;
  end;

  // -----------------------------------------------------------------------
  // Dependency map: name -> version
  // -----------------------------------------------------------------------
  TDependencyMap = class(TDictionary<string, string>)
  end;

  // -----------------------------------------------------------------------
  // A Delphi package
  // -----------------------------------------------------------------------
  TManifestPackage = class
  private
    FName: string;
    FType: TStringList;
  public
    constructor Create;
    destructor Destroy; override;

    function IsDesignTime: Boolean;
    function IsRuntime: Boolean;

    property Name: string read FName write FName;
    property &Type: TStringList read FType;
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
    FFolders: TManifestPackageFolders;
    FKeepProjectDcuPaths: Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    property Folders: TManifestPackageFolders read FFolders;
    property KeepProjectDcuPaths: Boolean read FKeepProjectDcuPaths write FKeepProjectDcuPaths;
  end;

  // -----------------------------------------------------------------------
  // Manifest repository information
  // -----------------------------------------------------------------------

  TManifestRepository = class
  private
    FRepoType: string;
    FUrl: string;
  public
    [JsonName('type')]
    property RepoType: string read FRepoType write FRepoType;
    property Url: string read FUrl write FUrl;
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
    FId: string;
    FVersion: string;
    FName: string;
    FLicense: string;
    FDescription: string;
    FHomepage: string;
    FAuthor: string;
    FKeywords: TStringList;
  public
    class function GetManifest(const APackageName, APackageVersion: string): TManifest;
    /// <summary>Returns all available versions of a package, sorted ascending.</summary>
    /// <param name="APackageName">Package identifier in the form <c>vendor.name</c>.</param>
    class function GetVersions(const APackageName: string): TArray<TSemVer>;
  public
    constructor Create;
    destructor Destroy; override;

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

{ TManifestPlatform }

constructor TManifestPlatform.Create;
begin
  inherited Create;
  FSourcePath   := TStringList.Create;
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

{ TManifestPackage }

constructor TManifestPackage.Create;
begin
  inherited Create;
  FType := TStringList.Create;
end;

destructor TManifestPackage.Destroy;
begin
  FType.Free;
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

{ TManifestPackageList }

constructor TManifestPackageList.Create;
begin
  inherited Create(True);
end;

{ TManifestPackageOptions }

constructor TManifestPackageOptions.Create;
begin
  inherited Create;
  FFolders := TManifestPackageFolders.Create;
end;

destructor TManifestPackageOptions.Destroy;
begin
  FFolders.Free;
  inherited;
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
end;

destructor TManifest.Destroy;
begin
  FRepository.Free;
  FKeywords.Free;
  FPlatforms.Free;
  FPackages.Free;
  FPackageOptions.Free;
  FDependencies.Free;
  inherited;
end;

class function TManifest.GetManifest(const APackageName,
  APackageVersion: string): TManifest;
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
      raise Exception.CreateFmt('No version matching "%s" found for package "%s". Try to update the repository', [APackageVersion, APackageName]);
  end;

  var LVersionsDir := TPath.Combine(TWorkspace.BlocksDir, 'repository', LPackagePair[0], LPackagePair[1]);
  var LFullPath := TPath.Combine(LVersionsDir, LBest.ToString, LPackagePair[0] + '.' + LPackagePair[1] + '.manifest.json');
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

  TArray.Sort<TSemVer>(LResult, TComparer<TSemVer>.Construct(
    function(const A, B: TSemVer): Integer
    begin
      Result := A.CompareTo(B);
    end));

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
        TArray.Sort<TSemVer>(LSemVers, TComparer<TSemVer>.Construct(
          function(const A, B: TSemVer): Integer
          begin
            Result := B.CompareTo(A);
          end));

        var LLatestManifestPath := TPath.Combine(
            TPath.Combine(LPackageDir, LSemVers[0].ToString),
            LId + '.manifest.json');
        if not FileExists(LLatestManifestPath) then
          Continue;

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

end.

