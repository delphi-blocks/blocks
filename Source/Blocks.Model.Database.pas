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
unit Blocks.Model.Database;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  Blocks.Model.Manifest,
  Blocks.JSON;

/// <summary>Manages the per-workspace package database.</summary>
/// <remarks>
///   The database is a single JSON file at <c>TWorkspace.BlocksDir\database.json</c>.
///   It maps library identifiers to their installed version strings.
/// </remarks>
type
  TInstalledPackage = class
  private
    FId: string;
    FVersion: string;
    FTimestamp: TDateTime;
    FDependencies: TDependencyMap;
  public
    constructor Create;
    destructor Destroy; override;

    property Id: string read FId write FId;
    property Version: string read FVersion write FVersion;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    /// <summary>Direct dependencies recorded at install time, as a map of
    ///   <c>vendor.name -> version constraint</c> (a copy of the manifest's
    ///   <c>dependencies</c>). Empty for entries written before this field
    ///   existed; populated on the next install/build of the package.</summary>
    property Dependencies: TDependencyMap read FDependencies;
  end;

  TDatabase = class
  private
    FPackages: TDictionary<string, TInstalledPackage>;
    FDatabasePath: string;
    FRepositoryUpdated: TDateTime;
    FReleaseChecked: TDateTime;
  public
    property Packages: TDictionary<string, TInstalledPackage> read FPackages;

    /// <summary>Timestamp of the last repository refresh (<see cref="TWorkspace.Initialize"/>
    ///   or <see cref="TWorkspace.Update"/>); zero when the repository was never refreshed.</summary>
    property RepositoryUpdated: TDateTime read FRepositoryUpdated write FRepositoryUpdated;

    /// <summary>Records <c>Now</c> as the repository refresh time and persists the database.</summary>
    procedure TouchRepository;

    /// <summary>Returns <c>True</c> when the repository has not been refreshed within the last
    ///   <paramref name="AMaxAgeDays"/> days (or was never refreshed).</summary>
    /// <param name="AMaxAgeDays">Maximum acceptable age, expressed in days.</param>
    function IsRepositoryStale(AMaxAgeDays: Double): Boolean;

    /// <summary>Timestamp of the last check for a newer blocks release on GitHub;
    ///   zero when no check was ever performed.</summary>
    property ReleaseChecked: TDateTime read FReleaseChecked write FReleaseChecked;

    /// <summary>Records <c>Now</c> as the last release-check time and persists the database.</summary>
    procedure TouchReleaseCheck;

    /// <summary>Returns <c>True</c> when no release check has happened within the last
    ///   <paramref name="AMaxAgeDays"/> days (or never happened).</summary>
    /// <param name="AMaxAgeDays">Maximum acceptable age, expressed in days.</param>
    function IsReleaseCheckStale(AMaxAgeDays: Double): Boolean;

    /// <summary>Removes the database entry for a package.</summary>
    /// <param name="LibraryId">Library identifier.</param>
    procedure RemoveEntry(const LibraryId: string);

    /// <summary>Returns all package entries as an array of <c>owner.package@version</c> strings.</summary>
    /// <returns>Array of entry strings, or an empty array if no packages are recorded.</returns>
    function ListEntries: TArray<string>;

    /// <summary>Returns <c>True</c> if a package is already recorded in the database.</summary>
    /// <param name="LibraryId">Library identifier to look up.</param>
    function IsInstalled(const LibraryId: string): Boolean;

    /// <summary>Returns the installed version of a package, or an empty string if not installed.</summary>
    /// <param name="LibraryId">Library identifier to look up.</param>
    /// <returns>The version string recorded in the database, or <c>''</c> if the package is not present.</returns>
    function InstalledVersion(const LibraryId: string): string;

    /// <summary>Inserts or updates the package version entry in the database.</summary>
    /// <param name="LibraryId">Library identifier.</param>
    /// <param name="AVersion">Version string of the installed package.</param>
    /// <param name="ADependencies">Direct dependencies to record (the manifest's
    ///   <c>dependencies</c> map); copied into the entry. Pass <c>nil</c> for none.</param>
    /// <remarks>Any existing entry for the same package is replaced.</remarks>
    procedure Update(const LibraryId, AVersion: string; ADependencies: TDependencyMap);

    /// <summary>Load the package database from systems.</summary>
    procedure Load;
    /// <summary>Save the package database to systems.</summary>
    procedure Save;

    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  System.JSON,
  Blocks.Console,
  Blocks.Service.Workspace;

const
  DatabaseSchemaUrl = 'https://delphi-blocks.dev/schema/database.v1.json';

// -- TInstalledPackage ---------------------------------------------------------

constructor TInstalledPackage.Create;
begin
  inherited;
  FDependencies := TDependencyMap.Create;
end;

destructor TInstalledPackage.Destroy;
begin
  FDependencies.Free;
  inherited;
end;

// -- TDatabase -----------------------------------------------------------------

procedure TDatabase.RemoveEntry(const LibraryId: string);
begin
  if FPackages.ContainsKey(LibraryId) then
  begin
    FPackages.Remove(LibraryId);
    TConsole.WriteLine('Removed from database: ' + LibraryId, clDkGray);
    Save;
  end
  else
    TConsole.WriteLine('Entry not found in database: ' + LibraryId, clYellow);
end;

procedure TDatabase.Save;
begin
  var LJSON := TJsonHelper.ObjectToJSON(Self) as TJSONObject;
  try
    LJSON.AddPair('$schema', DatabaseSchemaUrl);
    TFile.WriteAllText(FDatabasePath, TJsonHelper.PrettyPrint(LJSON));
  finally
    LJSON.Free;
  end;
end;

function TDatabase.ListEntries: TArray<string>;
var
  I: Integer;
  LPair: TPair<string, TInstalledPackage>;
begin
  SetLength(Result, FPackages.Count);
  I := 0;
  for LPair in FPackages do
  begin
    Result[I] := LPair.Key + '@' + LPair.Value.Version;
    Inc(I);
  end;
end;

procedure TDatabase.Load;
begin
  if FileExists(FDatabasePath) then
  begin
    var LJSON := TJSONObject.ParseJSONValue(TFile.ReadAllText(FDatabasePath), False, True);
    try
      TJsonHelper.CheckSchema(LJSON, DatabaseSchemaUrl);
      TJsonHelper.JSONToObject(Self, LJSON);
    finally
      LJSON.Free;
    end;
  end
  else
    Save;
end;

function TDatabase.IsInstalled(const LibraryId: string): Boolean;
begin
  Result := FPackages.ContainsKey(LibraryId);
end;

procedure TDatabase.TouchRepository;
begin
  FRepositoryUpdated := Now;
  Save;
end;

function TDatabase.IsRepositoryStale(AMaxAgeDays: Double): Boolean;
begin
  Result := (FRepositoryUpdated = 0) or (Now - FRepositoryUpdated > AMaxAgeDays);
end;

procedure TDatabase.TouchReleaseCheck;
begin
  FReleaseChecked := Now;
  Save;
end;

function TDatabase.IsReleaseCheckStale(AMaxAgeDays: Double): Boolean;
begin
  Result := (FReleaseChecked = 0) or (Now - FReleaseChecked > AMaxAgeDays);
end;

constructor TDatabase.Create;
begin
  inherited;
  FPackages := TObjectDictionary<string, TInstalledPackage>.Create([doOwnsValues]);
  FDatabasePath := TPath.Combine(TWorkspace.BlocksDir, 'database.json')
end;

destructor TDatabase.Destroy;
begin
  FPackages.Free;
  inherited;
end;

function TDatabase.InstalledVersion(const LibraryId: string): string;
begin
  var LInstalledPackage: TInstalledPackage := nil;

  if FPackages.TryGetValue(LibraryId, LInstalledPackage) then
    Result := LInstalledPackage.Version
  else
    Result := '';
end;

procedure TDatabase.Update(const LibraryId, AVersion: string; ADependencies: TDependencyMap);
begin
  var LInstalledPackage := TInstalledPackage.Create;
  try
    LInstalledPackage.Id := LibraryId;
    LInstalledPackage.Version := AVersion;
    LInstalledPackage.Timestamp := Now;
    if Assigned(ADependencies) then
      for var LDependency in ADependencies do
        LInstalledPackage.Dependencies.Add(LDependency.Key, LDependency.Value);
    FPackages.AddOrSetValue(LibraryId, LInstalledPackage);
    TConsole.WriteLine('Database updated: ' + LibraryId + '@' + AVersion, clDkGray);
    Save;
  except
    LInstalledPackage.Free;
    raise;
  end;
end;

end.
