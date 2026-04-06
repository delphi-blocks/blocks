unit Blocks.App;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  Winapi.Windows;

type
  TOptions = class
    Silent, Overwrite, BuildOnly, Uninstall, ListProducts, List, Init, Help: Boolean;
    Product, Install, Commit, ProjectFolder, WorkspacePath: string;
  end;

  TApp = class
  private
    FOptions: TOptions;

    procedure ParseArgs;
    procedure TestDelphiRunning;
    procedure ShowHelp;
    procedure ShowInstalledVersions;
    procedure ShowInstalledPackages(const Product: string);
  public
    procedure Run;

  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Entry point for the Blocks package manager CLI.</summary>
    /// <remarks>
    ///   Parses command-line arguments and dispatches to the appropriate command:
    ///   <c>-Install</c>, <c>-Init</c>, <c>-List</c>, <c>-Uninstall</c>,
    ///   <c>-ListProducts</c>, or <c>-Help</c>.
    ///   Exits with an unhandled exception on any fatal error.
    /// </remarks>
    class procedure RunBlocks; static;
  end;

implementation

uses
  Blocks.Consts,
  Blocks.Console,
  Blocks.Database,
  Blocks.Product,
  Blocks.Http,
  Blocks.Manifest,
  Blocks.Workspace;

constructor TApp.Create;
begin
  inherited;
  FOptions := TOptions.Create;
end;

destructor TApp.Destroy;
begin
  FOptions.Free;
  inherited;
end;

procedure TApp.ParseArgs;
var
  I: Integer;
  Arg: string;

  function NextArg: string;
  begin
    Inc(I);
    if I <= ParamCount then
      Result := ParamStr(I)
    else
      raise Exception.Create('Missing value after ' + Arg);
  end;

begin
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);

    if SameText(Arg, '-Silent') then
      FOptions.Silent := True
    else if SameText(Arg, '-Overwrite') then
      FOptions.Overwrite := True
    else if SameText(Arg, '-BuildOnly') then
      FOptions.BuildOnly := True
    else if SameText(Arg, '-Uninstall') then
      FOptions.Uninstall := True
    else if SameText(Arg, '-ListProducts') then
      FOptions.ListProducts := True
    else if SameText(Arg, '-List') then
      FOptions.List := True
    else if SameText(Arg, '-Init') then
      FOptions.Init := True
    else if SameText(Arg, '-Help') or (Arg = '-?') or (Arg = '/?') then
      FOptions.Help := True
    else if SameText(Arg, '-Product') then
      FOptions.Product := NextArg
    else if SameText(Arg, '-Install') then
      FOptions.Install := NextArg
    else if SameText(Arg, '-Commit') then
      FOptions.Commit := NextArg
    else if SameText(Arg, '-ProjectFolder') then
      FOptions.ProjectFolder := NextArg
    else if SameText(Arg, '-WorkspacePath') then
      FOptions.WorkspacePath :=
          NextArg
              // First positional argument without a flag prefix = Install
    else if (FOptions.Install = '') and not Arg.StartsWith('-') then
      FOptions.Install := Arg;

    Inc(I);
  end;
end;

// -- Delphi running check ------------------------------------------------------

procedure TApp.TestDelphiRunning;
begin
  var Running := TStringList.Create;
  try
    for var P in TProduct.Products do
      if P.IsRunning then
        Running.Add(P.DisplayName);

    if Running.Count = 0 then
      Exit;

    TConsole.WriteLine;
    TConsole.WriteWarning('The following Delphi instance(s) are currently open:');
    for var Name in Running do
      TConsole.WriteLine('  - ' + Name, clYellow);
    TConsole
        .WriteLine('  Please close Delphi before continuing, or the installation may not work correctly.', clYellow);
    TConsole.WriteLine;
    TConsole.Write('Press ENTER to continue anyway, or close Delphi and then press ENTER: ');
    var Confirm := TConsole.ReadLine;
  finally
    Running.Free;
  end;
end;

// -- Banner, app name and description -----------------------------------------

procedure ShowBanner(const AppName, Description: string);
var
  BoxWidth: Integer;

  function BoxLn(const T: string): string;
  var
    S: string;
  begin
    S := #$2502 + T;
    while Length(S) < BoxWidth + 1 do
      S := S + ' ';
    Result := S + #$2502;
  end;

var
  Line, Top, Sep, Bot: string;
begin
  BoxWidth := 50;
  if Length(Description) > BoxWidth then
    BoxWidth := Length(Description) + 15;

  Line := StringOfChar(#$2500, BoxWidth);
  Top := #$256D + Line + #$256E;
  Sep := #$251C + Line + #$2524;
  Bot := #$2570 + Line + #$256F;

  TConsole.WriteLine;
  TConsole.WriteLine(Top, clCyan);
  TConsole.WriteLine(BoxLn('  ____  _     ___   ____  _  __ ____   '), clCyan);
  TConsole.WriteLine(BoxLn(' | __ )| |   / _ \ / ___|| |/ // ___|  '), clCyan);
  TConsole.WriteLine(BoxLn(' |  _ \| |  | | | | |    | '' / \___ \  '), clCyan);
  TConsole.WriteLine(BoxLn(' | |_) | |__| |_| | |___ | . \  ___) | '), clCyan);
  TConsole.WriteLine(BoxLn(' |____/|_____\___/ \____||_|\_\|____/   '), clCyan);
  TConsole.WriteLine(Sep, clDkCyan);
  TConsole.WriteLine(BoxLn('  '#$25C6'  Delphi Package Installer'), clDkCyan);

  if AppName <> '' then
  begin
    TConsole.WriteLine(Sep, clDkCyan);
    TConsole.WriteLine(BoxLn('  Package  '#$25B8'  ' + AppName), clWhite);
    if Description <> '' then
      TConsole.WriteLine(BoxLn('  About    '#$25B8'  ' + Description), clGray);
  end;

  TConsole.WriteLine(Bot, clCyan);
  TConsole.WriteLine;
end;

// -- Help and listing ----------------------------------------------------------

procedure TApp.ShowHelp;
const
  OptionLength = 26;

  procedure WriteOption(const AOption, AText: string); overload;
  begin
    TConsole.Write('  ' + AOption + StringOfChar(' ', OptionLength - Length(AOption) - 3), clCyan);
    TConsole.WriteLine(AText, clGray);
  end;

  procedure WriteOption(const AText: string); overload;
  begin
    TConsole.WriteLine(AText);
  end;


begin
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('-Init','Initialise the workspace: create .blocks\ and download the repository.');
  WriteOption('-Install <path|url>','Load configuration from a local file, remote URL, or package ID.');
  WriteOption('-Uninstall','Remove the project directory and its database entry.');
  WriteOption('-Silent','Skip all non-critical prompts (uses defaults).');
  WriteOption('', 'Critical prompts (Delphi version, overwrite) are still shown.');
  WriteOption('-Overwrite', 'Automatically overwrite existing project directory without asking.');
  WriteOption('-Product <version>','Select Delphi version by its internal name (no quoting needed).');
  WriteOption('', 'Use -ListProducts to see available values.');
  WriteOption('-Commit <sha>','Download a specific commit SHA instead of the latest.');
  WriteOption('-WorkspacePath <dir>','Working directory (default: current directory).');
  WriteOption('-ProjectFolder <dir>','Override the project directory name (default: application name).');
  WriteOption('-BuildOnly','Skip download; assume project is already in place and build only.');
  WriteOption('', 'Use -WorkspacePath to target a different directory.');
  WriteOption('-ListProducts','Show installed Delphi versions and exit.');
  WriteOption('-List','Show packages installed in the current workspace (all versions).');
  WriteOption('', 'Use -Product to filter by Delphi version.');
  WriteOption('', 'Use -WorkspacePath to target a different workspace.');
  WriteOption('-Help','Show this help message.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName);
  TConsole.WriteLine('  ' + AppExeName + ' -Silent -Overwrite');
  TConsole.WriteLine('  ' + AppExeName + ' -Product delphi12 -Overwrite');
  TConsole.WriteLine('  ' + AppExeName + ' -BuildOnly -Silent -Product delphi13');
  TConsole.WriteLine('  ' + AppExeName + ' -Install C:\repository\mylib.json');
  TConsole.WriteLine('  ' + AppExeName + ' -Install https://example.com/repository/mylib.json');
  TConsole.WriteLine;
end;

procedure TApp.ShowInstalledVersions;
begin
  if TProduct.Products.Count = 0 then
  begin
    TConsole.WriteWarning('No Delphi versions found in the registry.');
    Exit;
  end;
  TConsole.WriteLine;
  TConsole.WriteLine('Installed Delphi versions:', clWhite);
  TConsole.WriteLine;
  for var P in TProduct.Products do
    TConsole.WriteLine(Format('  %-20s %s', [P.VersionName, P.DisplayName]));
  TConsole.WriteLine;
end;

procedure TApp.ShowInstalledPackages(const Product: string);
begin
  if (Product <> '') and (TProduct.Products.Count > 0) then
  begin
    var Found := False;
    for var P in TProduct.Products do
      if SameText(P.DisplayName, Product) or SameText(P.VersionName, Product) then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      raise Exception.CreateFmt('Product "%s" not found.', [Product]);
  end;

  var HasOutput := False;
  for var P in TProduct.Products do
  begin
    if (Product <> '') and not SameText(P.DisplayName, Product) and not SameText(P.VersionName, Product) then
      Continue;

    var DbPath := TPath.Combine(TWorkspace.BlocksDir, P.VersionName + '-database.json');
    if not TFile.Exists(DbPath) then
      Continue;

    var Db := TJSONObject.ParseJSONValue(TFile.ReadAllText(DbPath, TEncoding.UTF8)) as TJSONObject;
    try
      var BlocksArr := Db.GetValue('blocks') as TJSONArray;
      if (BlocksArr = nil) or (BlocksArr.Count = 0) then
        Continue;

      HasOutput := True;
      TConsole.WriteLine;
      TConsole.WriteLine('  ' + P.DisplayName, clCyan);
      TConsole.WriteLine;
      for var I := 0 to BlocksArr.Count - 1 do
      begin
        var Entry := (BlocksArr.Items[I] as TJSONString).Value;
        var Parts := Entry.Split(['@'], 2);
        if Length(Parts) = 2 then
        begin
          var Id := Parts[0];
          var Commit := Copy(Parts[1], 1, Min(7, Length(Parts[1])));
          TConsole.WriteLine(Format('    %-35s %s', [Id, Commit]));
        end
        else
          TConsole.WriteLine('    ' + Entry);
      end;
    finally
      Db.Free;
    end;
  end;

  if not HasOutput then
  begin
    TConsole.WriteLine;
    TConsole.WriteWarning('  No packages installed.');
  end;
  TConsole.WriteLine;
end;

procedure TApp.Run;
begin
  ParseArgs;

  // No meaningful arguments ? show help
  if not (FOptions.Help or FOptions.ListProducts or FOptions.List or FOptions.Init or FOptions.Uninstall)
      and (FOptions.Install = '') then
  begin
    ShowBanner('', '');
    ShowHelp;
    Exit;
  end;

  if FOptions.Help then
  begin
    ShowBanner('', '');
    ShowHelp;
    Exit;
  end;

  if FOptions.ListProducts then
  begin
    ShowBanner('', '');
    ShowInstalledVersions;
    Exit;
  end;

  if FOptions.List then
  begin
    ShowBanner('', '');
    TWorkspace.WorkDir := IfThen(FOptions.WorkspacePath <> '', FOptions.WorkspacePath, GetCurrentDir);
    TConsole.WriteLine('Installed packages in: ' + TWorkspace.WorkDir, clWhite);
    ShowInstalledPackages(FOptions.Product);
    Exit;
  end;

  if FOptions.Init then
  begin
    ShowBanner('', '');
    TWorkspace.Initialize(IfThen(FOptions.WorkspacePath <> '', FOptions.WorkspacePath, GetCurrentDir));
    TConsole.WriteLine('Initialising workspace: ' + TWorkspace.WorkDir, clWhite);
    TConsole.WriteLine;
    TConsole.WriteLine('Workspace initialised.', clGreen);
    TConsole.WriteLine;
    Exit;
  end;

  if FOptions.Uninstall and (FOptions.Install = '') then
    raise Exception.Create('-Uninstall requires a package ID, path, or URL.');

  // Step 1 — Working directory
  if FOptions.WorkspacePath <> '' then
  begin
    if not TDirectory.Exists(FOptions.WorkspacePath) then
      TDirectory.CreateDirectory(FOptions.WorkspacePath);
    TWorkspace.WorkDir := FOptions.WorkspacePath;
  end;

  // Offer to initialise if .blocks\ is absent
  if not TDirectory.Exists(TWorkspace.BlocksDir) then
  begin
    TConsole.WriteLine;
    TConsole.WriteWarning('The current directory is not a valid Blocks workspace.');
    TConsole.WriteLine('Proceeding will initialise it by downloading the package repository.', clYellow);
    TConsole.WriteLine;
    TConsole.Write('Initialise workspace now? [Y/N] (default: N): ');
    var Confirm := TConsole.ReadLine;
    if not SameText(Trim(Confirm), 'Y') then
      raise Exception.Create('Operation cancelled. Run "blocks -Init" to initialise the workspace first.');
    TWorkspace.Initialize(TWorkspace.WorkDir);
    TConsole.WriteLine;
  end;

  // Step 2 — Extract optional @commit suffix from -Install (e.g. "owner.pkg@abc1234")
  var InstallSource := FOptions.Install;
  var InstallCommit := '';
  if ContainsStr(FOptions.Install, '@') then
  begin
    var Parts := FOptions.Install.Split(['@'], 2);
    InstallSource := Trim(Parts[0]);
    InstallCommit := Trim(Parts[1]);
  end;

  var Database := TDatabase.Create;
  var Manifest := TManifest.Load(InstallSource);
  try
    ShowBanner(Manifest.Application.Name, Manifest.Application.Description);

    TConsole.WriteLine('Config: ' + FOptions.Install, clDkGray);
    TConsole.WriteLine;

    TestDelphiRunning;

    TConsole.WriteLine('Workspace: ' + TWorkspace.WorkDir, clDkGray);
    TConsole.WriteLine;

    // Step 3 — Delphi version
    var SelectedProduct := TProduct.Select(FOptions.Product);
    TConsole.WriteLine('Selected version: ' + SelectedProduct.DisplayName, clGreen);
    TConsole.WriteLine;

    // Step 4 — Uninstall path
    if FOptions.Uninstall then
    begin
      var DirName := IfThen(FOptions.ProjectFolder <> '', FOptions.ProjectFolder, Manifest.Application.Name);
      var ProjectDir := TPath.Combine(TWorkspace.WorkDir, DirName);

      if TDirectory.Exists(ProjectDir) then
      begin
        TDirectory.Delete(ProjectDir, True);
        TConsole.WriteLine('Removed: ' + ProjectDir, clYellow);
      end
      else
        TConsole.WriteLine('Directory not found: ' + ProjectDir, clYellow);

      Database.RemoveEntry(Manifest.Application.Id, SelectedProduct.VersionName);

      TConsole.WriteLine;
      TConsole.WriteLine('Uninstalled: ' + Manifest.Application.Name, clGreen);
      TConsole.WriteLine;
      Exit;
    end;

    // Step 5 — Skip if already installed (unless -Overwrite or -BuildOnly)
    if not FOptions.Overwrite
        and not FOptions.BuildOnly
        and Database.IsInstalled(Manifest.Application.Id, SelectedProduct.VersionName) then
    begin
      TConsole.WriteWarning('Already installed: ' + Manifest.Application.Id);
      TConsole.WriteLine;
      Exit;
    end;

    // Step 6 — Resolve package folder for selected Delphi version
    var PackageFolder := SelectedProduct.GetPackageFolder(Manifest.PackageOptions.PackageFolders);

    // Step 7 — Dependencies
    if not Manifest.Dependencies.IsEmpty then
    begin
      TConsole.WriteLine('Resolving dependencies...', clCyan);
      for var LDependency in Manifest.Dependencies do
        SelectedProduct.Install(LDependency, Database, FOptions.Silent, FOptions.Overwrite);
      TConsole.WriteLine;
    end;

    var CommitSha: string;
    var ProjectDir: string;
    if not FOptions.BuildOnly then
    begin
      // Step 8 — Resolve commit and download
      TConsole.WriteLine('--- ' + Manifest.Application.Id + ' / ' + Manifest.Application.Name + ' ---', clWhite);
      TConsole.WriteLine('Fetching repository info...', clCyan);
      var RepoInfo := THttpUtils.GetGitHubInfo(Manifest.Application.Url);
      TConsole.WriteLine('  Branch : ' + RepoInfo.DefaultBranch);
      TConsole.WriteLine('  Latest : ' + RepoInfo.LatestCommit);
      TConsole.WriteLine;

      if InstallCommit <> '' then
      begin
        CommitSha := InstallCommit;
        TConsole.WriteLine('Commit: ' + CommitSha + ' (from @)');
      end
      else if FOptions.Commit <> '' then
      begin
        CommitSha := Trim(FOptions.Commit);
        TConsole.WriteLine('Commit: ' + CommitSha + ' (from -Commit)');
      end
      else
      begin
        CommitSha := RepoInfo.LatestCommit;
        TConsole.WriteLine('Commit: ' + CommitSha + ' (latest)');
      end;
      TConsole.WriteLine;

      var ZipUrl := THttpUtils.GetGitHubZipUrl(RepoInfo.Owner, RepoInfo.Repo, CommitSha);
      var DirName := IfThen(FOptions.ProjectFolder <> '', FOptions.ProjectFolder, Manifest.Application.Name);
      ProjectDir := THttpUtils.DownloadAndExtract(ZipUrl, TWorkspace.WorkDir, DirName, FOptions.Overwrite, FOptions.Silent);
      TConsole.WriteLine('Project downloaded to: ' + ProjectDir, clGreen);
      TConsole.WriteLine;
    end
    else
    begin
      var DirName := IfThen(FOptions.ProjectFolder <> '', FOptions.ProjectFolder, Manifest.Application.Name);
      ProjectDir := TPath.Combine(TWorkspace.WorkDir, DirName);
      if not TDirectory.Exists(ProjectDir) then
        raise Exception.CreateFmt('Build-only mode: project directory not found: %s', [ProjectDir]);
      TConsole.WriteLine('Build-only mode. Using existing directory: ' + ProjectDir, clYellow);
      TConsole.WriteLine;
      CommitSha := '';
    end;

    // Step 9 — Compile
    SelectedProduct.BuildPackages(ProjectDir, PackageFolder, Manifest.Packages, Manifest.SupportedPlatforms);

    // Step 10 — Update database
    if not FOptions.BuildOnly then
      Database.Update(Manifest.Application.Id, CommitSha, SelectedProduct.VersionName);

    TConsole.WriteLine;
    TConsole.WriteLine('============================================', clGreen);
    TConsole.WriteLine('  Done!', clGreen);
    TConsole.WriteLine('  Project  : ' + ProjectDir, clGreen);
    TConsole.WriteLine('  Packages : ' + TPath.Combine(ProjectDir, 'packages\' + PackageFolder), clGreen);
    TConsole.WriteLine('============================================', clGreen);
    TConsole.WriteLine;
  finally
    Manifest.Free;
    Database.Free;
  end;
end;

class procedure TApp.RunBlocks;
begin
  var LApp := TApp.Create;
  try
    LApp.Run;
  finally
    LApp.Free;
  end;
end;

end.
