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
unit Blocks.App;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.TypInfo,
  System.Rtti, System.StrUtils,
  System.Generics.Collections,

  Winapi.Windows,

  Blocks.Product,
  Blocks.Command;

type
  TApp = class
  public
    class procedure RunBlocks; static;
  end;

  TBaseCommand = class(TCommand)
  protected
    procedure ShowBanner(const AppName, Description: string);
    procedure WriteOption(const AOption, AText: string); overload;
    procedure WriteOption(const AText: string); overload;
    procedure CheckWorkspace;
    procedure TestDelphiRunning;
  end;

  THelpCommand = class(TBaseCommand)
  private
    [Param]
    FCommandName: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TListCommand = class(TBaseCommand)
  private
    [Param('product')]
    FProduct: string;
    procedure ListBlocks(AProduct: TProduct); overload;
    procedure ListBlocks(const AProductName: string); overload;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TListProductsCommand = class(TBaseCommand)
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TInitCommand = class(TBaseCommand)
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TInstallCommand = class(TBaseCommand)
  private
    [Param('product')]
    FProduct: string;
    [Param('overwrite')]
    FOverwrite: Boolean;
    [Param('buildonly')]
    FBuildOnly: Boolean;
    [Param('silent')]
    FSilent: Boolean;
    [Param('force')]
    FForce: Boolean;
    [Param]
    FPackageName: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TUninstallCommand = class(TBaseCommand)
  private
    [Param('product')]
    FProduct: string;
    [Param]
    FPackageName: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TConfigCommand = class(TBaseCommand)
  private
    [Param('add')]
    FAdd: Boolean;
    [Param]
    FConfigs: TArray<string>;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TViewCommand = class(TBaseCommand)
  private
    [Param('raw')]
    FRaw: Boolean;
    [Param('versions')]
    FVersions: Boolean;
    [Param]
    FPackage: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

implementation

uses
  Blocks.Consts,
  Blocks.Console,
  Blocks.Database,
  Blocks.Manifest,
  Blocks.Workspace,
  Blocks.JSON;

const
  OptionLength = 26;

function CtrlHandler(CtrlType: DWORD): BOOL; stdcall;
begin
  TConsole.ResetColor;
  TConsole.WriteLine;
  TConsole.WriteLine('Interrupted.', clYellow);
  TConsole.WriteLine;
  Result := False; // pass to the default handler, which terminates the process
end;

class procedure TApp.RunBlocks;
begin
  SetConsoleCtrlHandler(@CtrlHandler, True);
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
  WriteOption('config', 'Read or write workspace configuration values.');
  WriteOption('view <id@version>', 'Show details of a package from the repository.');
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

{ TListCommand }

procedure TListCommand.Execute;
begin
  inherited;
  var LProducts := if FProduct <> '' then FProduct.Split([',']) else TProduct.ProductNames;
  for var LProduct in LProducts do
    ListBlocks(LProduct);
end;

procedure TListCommand.ListBlocks(AProduct: TProduct);
begin
  TConsole.WriteLine;
  TConsole.WriteLine('  ' + AProduct.DisplayName, clCyan);
  TConsole.WriteLine;

  var Entries := TWorkspace.Database.ListEntries(AProduct.VersionName);
  if Length(Entries) = 0 then
  begin
    TConsole.WriteLine('    No packages installed.');
    TConsole.WriteLine;
    Exit;
  end;

  for var Entry in Entries do
  begin
    var Parts := Entry.Split(['@'], 2);
    if Length(Parts) = 2 then
      TConsole.WriteLine(Format('    %-35s %s', [Parts[0], Parts[1]]))
    else
      TConsole.WriteLine('    ' + Entry);
  end;

  TConsole.WriteLine;
end;

procedure TListCommand.ListBlocks(const AProductName: string);
begin
  var LProduct := TProduct.Find(AProductName);
  ListBlocks(LProduct);
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
var
  LPackageName: string;
  LVersionConstraint: string;
begin
  inherited;
  CheckWorkspace;
  LPackageName := FPackageName;
  LVersionConstraint := '';
  if ContainsStr(FPackageName, '@') then
  begin
    var LParts := FPackageName.Split(['@'], 2);
    LPackageName := Trim(LParts[0]);
    LVersionConstraint := Trim(LParts[1]);
  end;
  ShowBanner('', '');
  TestDelphiRunning;
  TWorkspace.Install(LPackageName, LVersionConstraint, FProduct, FOverwrite, FBuildOnly, FSilent, FForce);
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
  WriteOption('', 'Append @<constraint> to specify a version constraint (e.g. owner.pkg@1.2.0,');
  WriteOption('', 'owner.pkg@^1.2.0, owner.pkg@>=1.0.0).');
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/product <version>', 'Target Delphi version (e.g. delphi12, delphi13).');
  WriteOption('', 'If omitted you will be prompted to choose.');
  WriteOption('/overwrite', 'Overwrite the project directory if it already exists.');
  WriteOption('/buildonly', 'Skip download; compile the already-extracted project.');
  WriteOption('/silent', 'Skip non-critical interactive prompts (use defaults).');
  WriteOption('/force', 'Skip dependencies that conflict with the requested constraint');
  WriteOption('', 'instead of raising an error, using the already-installed version.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package');
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package@1.2.0');
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package@^1.2.0 /force');
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
  ShowBanner('', '');
  TestDelphiRunning;
  TWorkspace.Uninstall(FPackageName, FProduct);
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
  WriteOption('<id>', 'Package identifier (e.g. owner.package).');
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

{ TBaseCommand }

procedure TBaseCommand.CheckWorkspace;
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

// -- Banner, app name and description -----------------------------------------
procedure TBaseCommand.ShowBanner(const AppName, Description: string);
begin
  TConsole.WriteLine;
  TConsole.WriteLine(' ██████╗ ██╗      ██████╗  ██████╗██╗  ██╗███████╗', clCyan);
  TConsole.WriteLine(' ██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝██╔════╝', clCyan);
  TConsole.WriteLine(' ██████╔╝██║     ██║   ██║██║     █████╔╝ ███████╗', clCyan);
  TConsole.WriteLine(' ██╔══██╗██║     ██║   ██║██║     ██╔═██╗ ╚════██║', clCyan);
  TConsole.WriteLine(' ██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗███████║', clCyan);
  TConsole.WriteLine(' ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝', clDkCyan);
  TConsole.WriteLine('   ▸  Delphi Package Installer', clDkCyan);
  TConsole.WriteLine;

  if AppName <> '' then
  begin
    TConsole.WriteLine('  Package  ▸  ' + AppName, clWhite);
    if Description <> '' then
      TConsole.WriteLine('  About    ▸  ' + Description, clGray);
    TConsole.WriteLine;
  end;
end;

// -- Delphi running check ------------------------------------------------------

procedure TBaseCommand.TestDelphiRunning;
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

procedure TBaseCommand.WriteOption(const AText: string);
begin
  TConsole.WriteLine(AText);
end;

procedure TBaseCommand.WriteOption(const AOption, AText: string);
begin
  TConsole.Write('  ' + AOption + StringOfChar(' ', OptionLength - Length(AOption) - 3), clCyan);
  TConsole.WriteLine(AText, clGray);
end;

{ TConfigCommand }

procedure TConfigCommand.Execute;
begin
  inherited;
  if Length(FConfigs) = 0 then
  begin
    ShowHelp;
    Exit;
  end;

  for var LConfig in FConfigs do
  begin
    var LEqualPos := Pos('=', LConfig);
    if LEqualPos < 1 then
    begin
      var LValue := TWorkspace.Config.Get(LConfig);
      TConsole.WriteLine(Format('%s: %s', [LConfig, LValue]));
    end
    else
    begin
      var LKey := Copy(LConfig, 1, LEqualPos - 1);
      var LValue := Copy(LConfig, LEqualPos + 1, Length(LConfig));
      if FAdd then
        TWorkspace.Config.Add(LKey, LValue)
      else
        TWorkspace.Config.&Set(LKey, LValue);
      TWorkspace.Config.Save;
      TConsole.WriteLine('Config applyed');
    end;
  end;
end;

procedure TConfigCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Reads or writes workspace configuration values.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' config [/add] [<key>[=<value>] ...]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Arguments:', clWhite);
  WriteOption('<key>', 'Print the current value of the given key.');
  WriteOption('<key>=<value>', 'Set the key to the given value.');
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/add', 'Append the value instead of replacing it (for list keys).');
  TConsole.WriteLine;
  TConsole.WriteLine('Keys:', clWhite);
  WriteOption('sources', 'Comma-separated list of repository URLs used by "init".');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' config sources');
  TConsole.WriteLine('  ' + AppExeName + ' config sources=https://github.com/owner/my-repo');
  TConsole.WriteLine('  ' + AppExeName + ' config /add sources=https://github.com/owner/other-repo');
  TConsole.WriteLine;
end;

{ TViewCommand }

procedure TViewCommand.Execute;
begin
  inherited;
  if FPackage = '' then
    raise Exception.Create('Package name needed');

  if FVersions then
  begin
    var LVersions := TManifest.GetVersions(FPackage);
    if Length(LVersions) = 0 then
    begin
      TConsole.WriteWarning('No versions found for: ' + FPackage);
      Exit;
    end;
    TConsole.WriteLine;
    TConsole.WriteLine('Available versions of ' + FPackage + ':', clWhite);
    TConsole.WriteLine;
    for var LVer in LVersions do
      TConsole.WriteLine('  ' + LVer.ToString);
    TConsole.WriteLine;
    Exit;
  end;

  var LPackageName := '';
  var LPackageVersion := '';
  var LPackageNamePair := FPackage.Split(['@']);
  case Length(LPackageNamePair) of
    1:
      LPackageName := LPackageNamePair[0];
    2:
    begin
      LPackageName := LPackageNamePair[0];
      LPackageVersion := LPackageNamePair[1];
    end;
    else
      raise Exception.Create('Package id should be in the form vendor.name@version');
  end;

  var LManifest := TManifest.GetManifest(LPackageName, LPackageVersion);
  try
    if FRaw then
    begin
      TConsole.WriteLine(TJsonHelper.PrettyPrint(TJsonHelper.ObjectToJSONString(LManifest)));
      Exit;
    end;

    const LabelW = 13;
    var LField: TProc<string, string>;
    LField := procedure(ALabel, AValue: string)
      begin
        if AValue = '' then
          Exit;
        TConsole.Write('  ' + ALabel.PadRight(LabelW), clCyan);
        TConsole.WriteLine('▸  ' + AValue);
      end;

    var LSection: TProc<string>;
    LSection := procedure(ATitle: string)
      begin
        TConsole.WriteLine;
        TConsole.Write('  ', clDkGray);
        TConsole.WriteLine(ATitle, clWhite);
        TConsole.WriteLine('  ' + StringOfChar('─', 44), clDkGray);
      end;

    TConsole.WriteLine;
    TConsole.WriteLine('  ' + LManifest.Name + '  ' + LManifest.Version, clWhite);
    TConsole.WriteLine('  ' + StringOfChar('─', 44), clDkGray);
    TConsole.WriteLine;

    LField('Id',          LManifest.Id);
    LField('Author',      LManifest.Author);
    LField('License',     LManifest.License);
    LField('Homepage',    LManifest.Homepage);
    LField('Repository',  LManifest.Repository.Url);

    if LManifest.Description <> '' then
    begin
      TConsole.WriteLine;
      TConsole.WriteLine('  ' + LManifest.Description, clGray);
    end;

    if LManifest.Keywords.Count > 0 then
      LField('Keywords', string.Join(', ', LManifest.Keywords.ToArray));

    // Packages
    if LManifest.Packages.Count > 0 then
    begin
      LSection('Packages');
      for var LPkg in LManifest.Packages do
      begin
        TConsole.Write('    ' + LPkg.Name.PadRight(30), clWhite);
        TConsole.WriteLine(string.Join(', ', LPkg.&Type.ToArray), clDkGray);
      end;
    end;

    // Platforms
    if LManifest.Platforms.Count > 0 then
    begin
      LSection('Platforms');
      for var LPlat in LManifest.Platforms do
      begin
        TConsole.WriteLine('    ' + LPlat.Key, clCyan);
        if LPlat.Value.SourcePath.Count > 0 then
          LField('      Source',   string.Join(', ', LPlat.Value.SourcePath.ToArray));
        if LPlat.Value.BrowsingPath.Count > 0 then
          LField('      Browsing', string.Join(', ', LPlat.Value.BrowsingPath.ToArray));
        if LPlat.Value.DebugDCUPath.Count > 0 then
          LField('      Debug',    string.Join(', ', LPlat.Value.DebugDCUPath.ToArray));
      end;
    end;

    // Dependencies
    if LManifest.Dependencies.Count > 0 then
    begin
      LSection('Dependencies');
      for var LDep in LManifest.Dependencies do
      begin
        TConsole.Write('    ' + LDep.Key.PadRight(30), clWhite);
        TConsole.WriteLine(LDep.Value, clDkGray);
      end;
    end;

    // Package folders
    if LManifest.PackageOptions.Folders.Count > 0 then
    begin
      LSection('Package folders');
      for var LFolder in LManifest.PackageOptions.Folders do
      begin
        TConsole.Write('    ' + LFolder.Key.PadRight(16), clCyan);
        TConsole.WriteLine('→  ' + LFolder.Value);
      end;
    end;

    TConsole.WriteLine;
  finally
    LManifest.Free;
  end;
end;

procedure TViewCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Shows details of a package from the local repository.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' view <id@version> [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Arguments:', clWhite);
  WriteOption('<id@version>', 'Package identifier and version (e.g. owner.package@1.2.0).');
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/raw', 'Print the raw manifest JSON instead of the formatted summary.');
  WriteOption('/versions', 'List all available versions of the package (no @version needed).');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' view owner.package@1.2.0');
  TConsole.WriteLine('  ' + AppExeName + ' view owner.package@1.2.0 /raw');
  TConsole.WriteLine('  ' + AppExeName + ' view owner.package /versions');
  TConsole.WriteLine;
end;

initialization

TCommand.RegisterCommand('help', THelpCommand, True);
TCommand.RegisterCommand('list', TListCommand);
TCommand.RegisterCommand('listproducts', TListProductsCommand);
TCommand.RegisterCommand('init', TInitCommand);
TCommand.RegisterCommand('install', TInstallCommand);
TCommand.RegisterCommand('uninstall', TUninstallCommand);
TCommand.RegisterCommand('config', TConfigCommand);
TCommand.RegisterCommand('view', TViewCommand);

end.
