unit Blocks.App;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.TypInfo,
  System.Rtti,
  System.JSON,
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  Winapi.Windows;

type
  TApp = class
  public
    class procedure RunBlocks; static;
  end;

  ParamAttribute = class(TCustomAttribute)
  private
    FParamName: string;
  public
    property ParamName: string read FParamName;
    constructor Create(const AParamName: string = '');
  end;

  TCommand = class;
  TCommandClass = class of TCommand;

  TCommand = class(TObject)
  strict private
    class var FRegistry: TDictionary<string, TCommandClass>;
    class var FDefaultCommand: TCommandClass;
    class var FContext: TRttiContext;
    constructor InnerCreate;
    class procedure InjectArgs(ACommand: TCommand);
  protected
    procedure ShowBanner(const AppName, Description: string);
    procedure WriteOption(const AOption, AText: string); overload;
    procedure WriteOption(const AText: string); overload;
    procedure CheckWorkspace;
    procedure TestDelphiRunning;
  public
    class constructor Create;
    class destructor Destroy;
    class procedure RegisterCommand(const AName: string; AClass: TCommandClass; ADefault: Boolean = False);
    class function Create(const ACommandName: string): TCommand;
  public
    procedure Execute; virtual;
    procedure ShowHelp; virtual;
  end;

  THelpCommand = class(TCommand)
  private
    [Param]
    FCommandName: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TListCommand = class(TCommand)
  private
    [Param('product')]
    FProduct: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TListProductsCommand = class(TCommand)
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TInitCommand = class(TCommand)
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TInstallCommand = class(TCommand)
  private
    [Param('product')]
    FProduct: string;
    [Param('overwrite')]
    FOverwrite: Boolean;
    [Param('buildonly')]
    FBuildOnly: Boolean;
    [Param('silent')]
    FSilent: Boolean;
    [Param]
    FPackageName: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TUninstallCommand = class(TCommand)
  private
    [Param('product')]
    FProduct: string;
    [Param]
    FPackageName: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
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

const
  OptionLength = 26;

// -- Help and listing ----------------------------------------------------------

class procedure TApp.RunBlocks;
begin
  var LCommand := TCommand.Create(ParamStr(1));
  try
    LCommand.Execute;
  finally
    LCommand.Free;
  end;
end;

{ THelpCommand }

procedure THelpCommand.Execute;
begin
  inherited;
  ShowBanner('', '');

  if FCommandName = '' then
  begin
    ShowHelp;
    Exit;
  end;

  var LCommand := TCommand.Create(FCommandName);
  try
    LCommand.ShowHelp;
  finally
    LCommand.Free;
  end;
end;

procedure THelpCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Delphi package manager: download, compile and register packages from a');
  TConsole.WriteLine('GitHub-hosted repository into your Delphi/RAD Studio installation.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' <command> [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Commands:', clWhite);
  WriteOption('install <source>', 'Install a package from a file path, URL, or registry ID.');
  WriteOption('uninstall <source>', 'Remove a package from the workspace and database.');
  WriteOption('init', 'Initialise the workspace and download the package repository.');
  WriteOption('list', 'List packages installed in the current workspace.');
  WriteOption('listproducts', 'List detected Delphi installations.');
  WriteOption('help [command]', 'Show this message, or detailed help for a specific command.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package');
  TConsole.WriteLine('  ' + AppExeName + ' install C:\path\to\manifest.json /overwrite');
  TConsole.WriteLine('  ' + AppExeName + ' install https://example.com/manifest.json /silent');
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package /product delphi12');
  TConsole.WriteLine('  ' + AppExeName + ' uninstall owner.package');
  TConsole.WriteLine('  ' + AppExeName + ' list /product delphi12');
  TConsole.WriteLine('  ' + AppExeName + ' help install');
  TConsole.WriteLine;
end;

{ TCommand }

class constructor TCommand.Create;
begin
  FRegistry := TDictionary<string, TCommandClass>.Create;
  FContext := TRttiContext.Create;
end;

procedure TCommand.CheckWorkspace;
begin
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
end;

class function TCommand.Create(const ACommandName: string): TCommand;
begin
  var LCommandClass: TCommandClass := nil;
  for var LPair in FRegistry do
  begin
    if SameText(LPair.Key, ACommandName) then
    begin
      LCommandClass := LPair.Value;
      Break;
    end;
  end;
  if not Assigned(LCommandClass) then
  begin
    TConsole.WriteError(Format('Command "%s" not found', [ACommandName]));
    LCommandClass := FDefaultCommand;
    if not Assigned(LCommandClass) then
      Abort;
  end;
  Result := LCommandClass.InnerCreate;
end;

class destructor TCommand.Destroy;
begin
  FRegistry.Free;
  FContext.Free;
end;

procedure TCommand.Execute;
begin
  TCommand.InjectArgs(Self);
end;

// Parse params like this:
// blocks install /verbose /product package.name
// and inject in a classdecorated with way:
// [Param('verbose')]
// FVerbose: Boolean;
// [Param('product')]
// FProduct: string;
// [Param]
// FPackageName: string; // This is an unnamed param (now only one is supported)
class procedure TCommand.InjectArgs(ACommand: TCommand);

  function FindClassFieldByParamName(const AParamName: string; out AUnnamedParam: Boolean): TRttiField;
  begin
    var LDefaultParam: TRttiField := nil;
    AUnnamedParam := False;
    var LRttiType := FContext.GetType(ACommand.ClassType);
    for var F in LRttiType.GetFields do
    begin
      var LAttr := F.GetAttribute<ParamAttribute>;
      if Assigned(LAttr) then
      begin
        // If it finds an unnamed param set the LDefaultParam
        if LAttr.ParamName = '' then
          LDefaultParam := F;

        if SameText('/' + LAttr.ParamName, AParamName) then
         Exit(F);
      end;
    end;
    if AParamName.StartsWith('/') or not Assigned(LDefaultParam) then
      raise Exception.CreateFmt('Param "%s" not found', [AParamName]);
    Result := LDefaultParam;
    AUnnamedParam := True;
  end;

begin
  var I := 2;
  var LUnnamedParam: Boolean;
  while I <= ParamCount do
  begin
    var LField := FindClassFieldByParamName(ParamStr(I), LUnnamedParam);
    if LField.DataType.TypeKind = tkEnumeration then // boolean expected
      LField.SetValue(ACommand, True)
    else if LField.DataType.TypeKind = tkUString then
    begin
      if not LUnnamedParam then
        Inc(I);
      LField.SetValue(ACommand, ParamStr(I));
    end
    else
      raise Exception.Create('Param type not supported');
    Inc(I);
  end;
end;

constructor TCommand.InnerCreate;
begin
  inherited;
end;

class procedure TCommand.RegisterCommand(const AName: string; AClass: TCommandClass; ADefault: Boolean = False);
begin
  FRegistry.Add(AName, AClass);
  if ADefault then
    FDefaultCommand := AClass;
end;

// -- Banner, app name and description -----------------------------------------
procedure TCommand.ShowBanner(const AppName, Description: string);
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

procedure TCommand.ShowHelp;
begin

end;

// -- Delphi running check ------------------------------------------------------

procedure TCommand.TestDelphiRunning;
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

procedure TCommand.WriteOption(const AText: string);
begin
  TConsole.WriteLine(AText);
end;

procedure TCommand.WriteOption(const AOption, AText: string);
begin
  TConsole.Write('  ' + AOption + StringOfChar(' ', OptionLength - Length(AOption) - 3), clCyan);
  TConsole.WriteLine(AText, clGray);
end;

{ TListCommand }

procedure TListCommand.Execute;
begin
  inherited;
  if (FProduct <> '') and (TProduct.Products.Count > 0) then
  begin
    var Found := False;
    for var P in TProduct.Products do
      if SameText(P.DisplayName, FProduct) or SameText(P.VersionName, FProduct) then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      raise Exception.CreateFmt('Product "%s" not found.', [FProduct]);
  end;

  var HasOutput := False;
  for var P in TProduct.Products do
  begin
    if (FProduct <> '') and not SameText(P.DisplayName, FProduct) and not SameText(P.VersionName, FProduct) then
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

procedure TListCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Lists all packages installed in the current workspace.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' list [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/product <version>', 'Filter by Delphi version (e.g. delphi12, delphi13).');
  WriteOption('', 'Run "' + AppExeName + ' listproducts" to see valid values.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' list');
  TConsole.WriteLine('  ' + AppExeName + ' list /product delphi12');
  TConsole.WriteLine;
end;

{ TListProductsCommand }

procedure TListProductsCommand.Execute;
begin
  inherited;
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

procedure TListProductsCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Lists all Delphi installations detected in the Windows registry.');
  TConsole.WriteLine('Use the version name shown here as the /product argument for other commands.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' listproducts', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Example:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' listproducts');
  TConsole.WriteLine;
end;

{ TInitCommand }

procedure TInitCommand.Execute;
begin
  inherited;
  ShowBanner('', '');
  TWorkspace.Initialize(GetCurrentDir);
  TConsole.WriteLine('Initialising workspace: ' + TWorkspace.WorkDir, clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Workspace initialised.', clGreen);
  TConsole.WriteLine;
  Exit;
end;

procedure TInitCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Creates the .blocks\ directory in the current folder and downloads');
  TConsole.WriteLine('the remote package repository. Run this once before using install.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' init', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Example:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' init');
  TConsole.WriteLine;
end;

{ TInstallCommand }

procedure TInstallCommand.Execute;
begin
  inherited;
  CheckWorkspace;
  var InstallSource := FPackageName;
  var InstallCommit := '';
  if ContainsStr(FPackageName, '@') then
  begin
    var Parts := FPackageName.Split(['@'], 2);
    InstallSource := Trim(Parts[0]);
    InstallCommit := Trim(Parts[1]);
  end;

  var Database := TDatabase.Create;
  var Manifest := TManifest.Load(InstallSource);
  try
    //ShowBanner(Manifest.Application.Name, Manifest.Application.Description);

    TConsole.WriteLine('Config: ' + FPackageName, clDkGray);
    TConsole.WriteLine;

    TestDelphiRunning;

    TConsole.WriteLine('Workspace: ' + TWorkspace.WorkDir, clDkGray);
    TConsole.WriteLine;

    // Step 3 — Delphi version
    var SelectedProduct := TProduct.Select(FProduct);
    TConsole.WriteLine('Selected version: ' + SelectedProduct.DisplayName, clGreen);
    TConsole.WriteLine;

    // Step 4 — Skip if already installed (unless -Overwrite or -BuildOnly)
    if not FOverwrite
        and not FBuildOnly
        and Database.IsInstalled(Manifest.Application.Id, SelectedProduct.VersionName) then
    begin
      TConsole.WriteWarning('Already installed: ' + Manifest.Application.Id);
      TConsole.WriteLine;
      Exit;
    end;

    // Step 5 — Resolve package folder for selected Delphi version
    var PackageFolder := SelectedProduct.GetPackageFolder(Manifest.PackageOptions.PackageFolders);

    // Step 6 — Dependencies
    if not Manifest.Dependencies.IsEmpty then
    begin
      TConsole.WriteLine('Resolving dependencies...', clCyan);
      for var LDependency in Manifest.Dependencies do
        SelectedProduct.Install(LDependency, Database, FSilent, FOverwrite);
      TConsole.WriteLine;
    end;

    var CommitSha: string;
    var ProjectDir: string;
    if not FBuildOnly then
    begin
      // Step 7 — Resolve commit and download
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
      else
      begin
        CommitSha := RepoInfo.LatestCommit;
        TConsole.WriteLine('Commit: ' + CommitSha + ' (latest)');
      end;
      TConsole.WriteLine;

      var ZipUrl := THttpUtils.GetGitHubZipUrl(RepoInfo.Owner, RepoInfo.Repo, CommitSha);
      var DirName := Manifest.Application.Name;
      ProjectDir := THttpUtils.DownloadAndExtract(ZipUrl, TWorkspace.WorkDir, DirName, FOverwrite, FSilent);
      TConsole.WriteLine('Project downloaded to: ' + ProjectDir, clGreen);
      TConsole.WriteLine;
    end
    else
    begin
      var DirName := Manifest.Application.Name;
      ProjectDir := TPath.Combine(TWorkspace.WorkDir, DirName);
      if not TDirectory.Exists(ProjectDir) then
        raise Exception.CreateFmt('Build-only mode: project directory not found: %s', [ProjectDir]);
      TConsole.WriteLine('Build-only mode. Using existing directory: ' + ProjectDir, clYellow);
      TConsole.WriteLine;
      CommitSha := '';
    end;

    // Step 8 — Compile
    SelectedProduct.BuildPackages(ProjectDir, PackageFolder, Manifest.Packages, Manifest.SupportedPlatforms);

    // Step 9 — Update database
    if not FBuildOnly then
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

procedure TInstallCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Downloads, compiles and registers a Delphi package into the active');
  TConsole.WriteLine('Delphi installation. The source can be a registry ID, a local file, or a URL.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' install <source> [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Arguments:', clWhite);
  WriteOption('<source>', 'Package ID, local file path, or remote URL of a manifest (.json).');
  WriteOption('', 'Append @<sha> to pin a specific commit  (e.g. owner.pkg@abc1234).');
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/product <version>', 'Target Delphi version (e.g. delphi12, delphi13).');
  WriteOption('', 'If omitted you will be prompted to choose.');
  WriteOption('/overwrite', 'Overwrite the project directory if it already exists.');
  WriteOption('/buildonly', 'Skip download; compile the already-extracted project.');
  WriteOption('/silent', 'Skip non-critical interactive prompts (use defaults).');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package');
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package@abc1234');
  TConsole.WriteLine('  ' + AppExeName + ' install C:\repos\mylib.json /overwrite');
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package /product delphi12 /silent');
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package /buildonly /product delphi13');
  TConsole.WriteLine;
end;

{ TUninstallCommand }

procedure TUninstallCommand.Execute;
begin
  inherited;
  CheckWorkspace;
  var InstallSource := FPackageName;
  var InstallCommit := '';
  if ContainsStr(FPackageName, '@') then
  begin
    var Parts := FPackageName.Split(['@'], 2);
    InstallSource := Trim(Parts[0]);
    InstallCommit := Trim(Parts[1]);
  end;

  var Database := TDatabase.Create;
  var Manifest := TManifest.Load(InstallSource);
  try
    //ShowBanner(Manifest.Application.Name, Manifest.Application.Description);

    TConsole.WriteLine('Config: ' + FPackageName, clDkGray);
    TConsole.WriteLine;

    TestDelphiRunning;

    TConsole.WriteLine('Workspace: ' + TWorkspace.WorkDir, clDkGray);
    TConsole.WriteLine;

    // Step 3 — Delphi version
    var SelectedProduct := TProduct.Select(FProduct);
    TConsole.WriteLine('Selected version: ' + SelectedProduct.DisplayName, clGreen);
    TConsole.WriteLine;

    // Step 4 — Uninstall path
    var DirName := Manifest.Application.Name;
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
  finally
    Manifest.Free;
    Database.Free;
  end;
end;

procedure TUninstallCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Removes a previously installed package: deletes its project directory');
  TConsole.WriteLine('and the corresponding entry from the local database.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' uninstall <source> [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Arguments:', clWhite);
  WriteOption('<source>', 'Package ID, local file path, or remote URL of a manifest (.json).');
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/product <version>', 'Target Delphi version (e.g. delphi12, delphi13).');
  WriteOption('', 'If omitted you will be prompted to choose.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' uninstall owner.package');
  TConsole.WriteLine('  ' + AppExeName + ' uninstall owner.package /product delphi12');
  TConsole.WriteLine;
end;

{ ParamAttribute }

constructor ParamAttribute.Create(const AParamName: string);
begin
  inherited Create;
  FParamName := AParamName;
end;

initialization

TCommand.RegisterCommand('help', THelpCommand, True);
TCommand.RegisterCommand('list', TListCommand);
TCommand.RegisterCommand('listproducts', TListProductsCommand);
TCommand.RegisterCommand('init', TInitCommand);
TCommand.RegisterCommand('install', TInstallCommand);
TCommand.RegisterCommand('uninstall', TUninstallCommand);

end.
