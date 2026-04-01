unit Blocks.Database;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections;

/// <summary>Manages the per-workspace, per-Delphi-version package database.</summary>
/// <remarks>
///   Each database file is a JSON object with a <c>blocks</c> array of strings
///   in the form <c>owner.package@fullcommitsha</c>, stored at
///   <c>TWorkspace.BlocksDir\{version}-database.json</c>.
/// </remarks>
type
  TDatabase = class
  public
    /// <summary>Removes the database entry for a package from a specific Delphi version database.</summary>
    /// <param name="LibraryId">Library identifier.</param>
    /// <param name="DelphiVersionName">Internal Delphi version name (e.g. <c>delphi12</c>) that
    ///   identifies which database file to update.</param>
    /// <remarks>Reads the database from <c>TWorkspace.BlocksDir</c>.</remarks>
    procedure RemoveEntry(const LibraryId, DelphiVersionName: string);

    /// <summary>Returns all package entries for the given Delphi version as an array of <c>owner.package@commitsha</c> strings.</summary>
    /// <param name="DelphiVersionName">Internal Delphi version name (e.g. <c>delphi12</c>).</param>
    /// <returns>Array of entry strings, or an empty array if the database file does not exist or is empty.</returns>
    function ListEntries(const DelphiVersionName: string): TArray<string>;

    /// <summary>Returns <c>True</c> if a package is already recorded in the database for the given Delphi version.</summary>
    /// <param name="LibraryId">Library identifier to look up.</param>
    /// <param name="DelphiVersionName">Internal Delphi version name (e.g. <c>delphi12</c>).</param>
    /// <remarks>Commit SHA of the installed package is ignored; only presence is checked.</remarks>
    function IsInstalled(const LibraryId, DelphiVersionName: string): Boolean;

    /// <summary>Returns the commit SHA of an installed package, or an empty string if not installed.</summary>
    /// <param name="LibraryId">Library identifier to look up.</param>
    /// <param name="DelphiVersionName">Internal Delphi version name (e.g. <c>delphi12</c>).</param>
    /// <returns>The full commit SHA recorded in the database, or <c>''</c> if the package is not present.</returns>
    function InstalledCommit(const LibraryId, DelphiVersionName: string): string;

    /// <summary>Inserts or updates the <c>owner.package@commitsha</c> entry in the package database.</summary>
    /// <param name="LibraryId">Library identifier.</param>
    /// <param name="CommitSha">Full commit SHA of the installed version.</param>
    /// <param name="DelphiVersionName">Internal Delphi version name (e.g. <c>delphi12</c>) that
    ///   identifies which database file to update.</param>
    /// <remarks>Any existing entry for the same package (regardless of commit) is replaced.
    ///   Writes to <c>TWorkspace.BlocksDir</c>.</remarks>
    procedure Update(const LibraryId, CommitSha, DelphiVersionName: string);
  end;

implementation

uses
  Blocks.Console,
  Blocks.Workspace;

// -- Database helpers ----------------------------------------------------------

function DbPath(const DelphiVersionName: string): string;
begin
  Result := TPath.Combine(TWorkspace.BlocksDir, DelphiVersionName + '-database.json');
end;

// -- TDatabase -----------------------------------------------------------------

procedure TDatabase.RemoveEntry(const LibraryId, DelphiVersionName: string);
var
  Path: string;
  Db: TJSONObject;
  BlocksArr: TJSONArray;
  NormId: string;
  I, Before: Integer;
  NewArr: TJSONArray;
begin
  Path := DbPath(DelphiVersionName);
  if not TFile.Exists(Path) then
  begin
    TConsole.WriteWarning('Database not found: ' + Path);
    Exit;
  end;

  Db := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8)) as TJSONObject;
  try
    BlocksArr := Db.GetValue('blocks') as TJSONArray;
    NormId := LibraryId;
    Before := BlocksArr.Count;
    NewArr := TJSONArray.Create;

    for I := 0 to BlocksArr.Count - 1 do
    begin
      var EntryId := (BlocksArr.Items[I] as TJSONString).Value.Split(['@'])[0];
      if not SameText(EntryId, NormId) then
        NewArr.AddElement(TJSONString.Create((BlocksArr.Items[I] as TJSONString).Value));
    end;

    Db.RemovePair('blocks').Free;
    Db.AddPair('blocks', NewArr);
    TFile.WriteAllText(Path, Db.ToString, TEncoding.UTF8);

    if NewArr.Count < Before then
      TConsole.WriteLine('Removed from database: ' + NormId, clDkGray)
    else
      TConsole.WriteLine('Entry not found in database: ' + NormId, clYellow);
  finally
    Db.Free;
  end;
end;

function TDatabase.ListEntries(const DelphiVersionName: string): TArray<string>;
var
  Path: string;
  Db: TJSONObject;
  BlocksArr: TJSONArray;
  I: Integer;
begin
  Result := [];
  Path := DbPath(DelphiVersionName);
  if not TFile.Exists(Path) then
    Exit;

  Db := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8)) as TJSONObject;
  try
    BlocksArr := Db.GetValue('blocks') as TJSONArray;
    if not Assigned(BlocksArr) then
      Exit;
    SetLength(Result, BlocksArr.Count);
    for I := 0 to BlocksArr.Count - 1 do
      Result[I] := (BlocksArr.Items[I] as TJSONString).Value;
  finally
    Db.Free;
  end;
end;

function TDatabase.IsInstalled(const LibraryId, DelphiVersionName: string): Boolean;
var
  Path: string;
  Db: TJSONObject;
  BlocksArr: TJSONArray;
  I: Integer;
begin
  Result := False;
  Path := DbPath(DelphiVersionName);
  if not TFile.Exists(Path) then
    Exit;

  Db := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8)) as TJSONObject;
  try
    BlocksArr := Db.GetValue('blocks') as TJSONArray;
    if not Assigned(BlocksArr) then
      Exit;
    for I := 0 to BlocksArr.Count - 1 do
    begin
      var EntryId := (BlocksArr.Items[I] as TJSONString).Value.Split(['@'])[0];
      if SameText(EntryId, LibraryId) then
        Exit(True);
    end;
  finally
    Db.Free;
  end;
end;

function TDatabase.InstalledCommit(const LibraryId, DelphiVersionName: string): string;
var
  Path: string;
  Db: TJSONObject;
  BlocksArr: TJSONArray;
  I: Integer;
  Parts: TArray<string>;
begin
  Result := '';
  Path := DbPath(DelphiVersionName);
  if not TFile.Exists(Path) then
    Exit;

  Db := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8)) as TJSONObject;
  try
    BlocksArr := Db.GetValue('blocks') as TJSONArray;
    if not Assigned(BlocksArr) then
      Exit;
    for I := 0 to BlocksArr.Count - 1 do
    begin
      Parts := (BlocksArr.Items[I] as TJSONString).Value.Split(['@']);
      if (Length(Parts) >= 2) and SameText(Parts[0], LibraryId) then
        Exit(Parts[1]);
    end;
  finally
    Db.Free;
  end;
end;

procedure TDatabase.Update(const LibraryId, CommitSha, DelphiVersionName: string);
var
  Path: string;
  Db: TJSONObject;
  BlocksArr: TJSONArray;
  NormId: string;
  Entry: string;
  I: Integer;
  NewArr: TJSONArray;
begin
  Path := DbPath(DelphiVersionName);
  NormId := LibraryId;
  Entry := NormId + '@' + CommitSha;

  if TFile.Exists(Path) then
    Db := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8)) as TJSONObject
  else
    Db := TJSONObject.Create;

  try
    if Db.GetValue('blocks') = nil then
      Db.AddPair('blocks', TJSONArray.Create);

    BlocksArr := Db.GetValue('blocks') as TJSONArray;

    // Remove any existing entry for the same package (regardless of commit)
    NewArr := TJSONArray.Create;
    for I := 0 to BlocksArr.Count - 1 do
    begin
      var EntryId := (BlocksArr.Items[I] as TJSONString).Value.Split(['@'])[0];
      if not SameText(EntryId, NormId) then
        NewArr.AddElement(TJSONString.Create((BlocksArr.Items[I] as TJSONString).Value));
    end;
    NewArr.AddElement(TJSONString.Create(Entry));

    Db.RemovePair('blocks').Free;
    Db.AddPair('blocks', NewArr);
    TFile.WriteAllText(Path, Db.ToString, TEncoding.UTF8);

    TConsole.WriteLine('Database updated: ' + Entry, clDkGray);
  finally
    Db.Free;
  end;
end;

end.
