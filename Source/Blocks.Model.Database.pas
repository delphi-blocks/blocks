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
  public
    property Id: string read FId write FId;
    property Version: string read FVersion write FVersion;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
  end;

  TDatabase = class
  private
    FPackages: TDictionary<string, TInstalledPackage>;
    FDatabasePath: string;
    FRepositoryUpdated: TDateTime;
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
    /// <remarks>Any existing entry for the same package is replaced.</remarks>
    procedure Update(const LibraryId, AVersion: string);

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

procedure TDatabase.Update(const LibraryId, AVersion: string);
begin
  var LInstalledPackage := TInstalledPackage.Create;
  try
    LInstalledPackage.Id := LibraryId;
    LInstalledPackage.Version := AVersion;
    LInstalledPackage.Timestamp := Now;
    FPackages.AddOrSetValue(LibraryId, LInstalledPackage);
    TConsole.WriteLine('Database updated: ' + LibraryId + '@' + AVersion, clDkGray);
    Save;
  except
    LInstalledPackage.Free;
    raise;
  end;
end;

end.
