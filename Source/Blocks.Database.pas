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
unit Blocks.Database;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,

  Blocks.JSON;

/// <summary>Manages the per-workspace package database.</summary>
/// <remarks>
///   The database is a single JSON file at <c>TWorkspace.BlocksDir\database.json</c>.
///   It is keyed by Delphi version name (e.g. <c>delphi12</c>), and each value is an
///   object mapping library identifiers to their installed version strings.
/// </remarks>
type
  TProductPackages = class
  private
    FPackages: TDictionary<string, string>;
  public
    [JsonDictionary(System.TypeInfo(string))]
    property Packages: TDictionary<string, string> read FPackages;

    constructor Create;
    destructor Destroy; override;
  end;

  TDatabase = class
  private
    FProducts: TObjectDictionary<string, TProductPackages>;
    FDatabasePath: string;
  public
    [JsonDictionary(System.TypeInfo(TProductPackages))]
    property Products: TObjectDictionary<string, TProductPackages> read FProducts;

    /// <summary>Removes the database entry for a package from a specific Delphi version.</summary>
    /// <param name="LibraryId">Library identifier.</param>
    /// <param name="DelphiVersionName">Internal Delphi version name (e.g. <c>delphi12</c>).</param>
    procedure RemoveEntry(const LibraryId, DelphiVersionName: string);

    /// <summary>Returns all package entries for the given Delphi version as an array of <c>owner.package@version</c> strings.</summary>
    /// <param name="DelphiVersionName">Internal Delphi version name (e.g. <c>delphi12</c>).</param>
    /// <returns>Array of entry strings, or an empty array if no packages are recorded.</returns>
    function ListEntries(const DelphiVersionName: string): TArray<string>;

    /// <summary>Returns <c>True</c> if a package is already recorded in the database for the given Delphi version.</summary>
    /// <param name="LibraryId">Library identifier to look up.</param>
    /// <param name="DelphiVersionName">Internal Delphi version name (e.g. <c>delphi12</c>).</param>
    function IsInstalled(const LibraryId, DelphiVersionName: string): Boolean;

    /// <summary>Returns the installed version of a package, or an empty string if not installed.</summary>
    /// <param name="LibraryId">Library identifier to look up.</param>
    /// <param name="DelphiVersionName">Internal Delphi version name (e.g. <c>delphi12</c>).</param>
    /// <returns>The version string recorded in the database, or <c>''</c> if the package is not present.</returns>
    function InstalledVersion(const LibraryId, DelphiVersionName: string): string;

    /// <summary>Inserts or updates the package version entry in the database.</summary>
    /// <param name="LibraryId">Library identifier.</param>
    /// <param name="AVersion">Version string of the installed package.</param>
    /// <param name="DelphiVersionName">Internal Delphi version name (e.g. <c>delphi12</c>).</param>
    /// <remarks>Any existing entry for the same package is replaced.</remarks>
    procedure Update(const LibraryId, AVersion, DelphiVersionName: string);

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
  Blocks.Workspace;

const
  DatabaseSchemaUrl = 'https://delphi-blocks.dev/schema/database.v1.json';

// -- TDatabase -----------------------------------------------------------------

procedure TDatabase.RemoveEntry(const LibraryId, DelphiVersionName: string);
var
  LProducts: TProductPackages;
begin
  if not FProducts.TryGetValue(DelphiVersionName, LProducts) then
  begin
    TConsole.WriteWarning('Entry not found in database: ' + LibraryId);
    Exit;
  end;

  if LProducts.Packages.ContainsKey(LibraryId) then
  begin
    LProducts.Packages.Remove(LibraryId);
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
    TFile.WriteAllText(FDatabasePath, LJSON.ToJSON);
  finally
    LJSON.Free;
  end;
end;

function TDatabase.ListEntries(const DelphiVersionName: string): TArray<string>;
var
  LProducts: TProductPackages;
  I: Integer;
  LPair: TPair<string, string>;
begin
  Result := [];
  if not FProducts.TryGetValue(DelphiVersionName, LProducts) then
    Exit;

  SetLength(Result, LProducts.Packages.Count);
  I := 0;
  for LPair in LProducts.Packages do
  begin
    Result[I] := LPair.Key + '@' + LPair.Value;
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

function TDatabase.IsInstalled(const LibraryId, DelphiVersionName: string): Boolean;
var
  LProducts: TProductPackages;
begin
  Result := False;
  if not FProducts.TryGetValue(DelphiVersionName, LProducts) then
    Exit;
  Result := LProducts.Packages.ContainsKey(LibraryId);
end;

constructor TDatabase.Create;
begin
  inherited;
  FProducts := TObjectDictionary<string, TProductPackages>.Create([doOwnsValues]);
  FDatabasePath := TPath.Combine(TWorkspace.BlocksDir, 'database.json')
end;

destructor TDatabase.Destroy;
begin
  FProducts.Free;
  inherited;
end;

function TDatabase.InstalledVersion(const LibraryId, DelphiVersionName: string): string;
var
  LProducts: TProductPackages;
begin
  Result := '';
  if not FProducts.TryGetValue(DelphiVersionName, LProducts) then
    Exit;
  LProducts.Packages.TryGetValue(LibraryId, Result);
end;

procedure TDatabase.Update(const LibraryId, AVersion, DelphiVersionName: string);
var
  LProducts: TProductPackages;
begin
  if not FProducts.TryGetValue(DelphiVersionName, LProducts) then
  begin
    LProducts := TProductPackages.Create;
    FProducts.Add(DelphiVersionName, LProducts);
  end;

  LProducts.Packages.AddOrSetValue(LibraryId, AVersion);
  TConsole.WriteLine('Database updated: ' + LibraryId + '@' + AVersion, clDkGray);
  Save;
end;

{ TProductPackages }

constructor TProductPackages.Create;
begin
  FPackages := TDictionary<string, string>.Create;
end;

destructor TProductPackages.Destroy;
begin
  FPackages.Free;
  inherited;
end;

end.
