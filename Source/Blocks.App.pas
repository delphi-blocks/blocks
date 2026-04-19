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
  Winapi.ShellAPI,
  System.Win.Registry,

  Blocks.Product,
  Blocks.GitHub,
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
    procedure ListBlocks(AProduct: TProduct);
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TListProductsCommand = class(TBaseCommand)
  private
    [Param('all')]
    FAll: Boolean;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TInitCommand = class(TBaseCommand)
  private
    [Param('product')]
    FProduct: string;
    [Param('registrykey')]
    FRegistryKey: string;
    [Param('canonical')]
    FCanonical: Boolean;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TInstallCommand = class(TBaseCommand)
  private
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
    [Param('system')]
    FSystem: Boolean;
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

  TVersionCommand = class(TBaseCommand)
  private
    [Param('silent')]
    FSilent: Boolean;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TUpgradeCommand = class(TBaseCommand)
  private
    [Param('check')]
    FCheck: Boolean;
    [Param('force')]
    FForce: Boolean;
    function SelectSetup(AAssets: TGitHubReleaseAssets): string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TSystemConfig = class(TObject)
  public
    const InstallPath = 'Software\Blocks';
    class function Get(const AKey: string): string; static;
    class procedure &Set(const AKey, AValue: string); static;
    class procedure Add(const AKey, AValue: string); static;
  end;

implementation

uses
  Blocks.Consts,
  Blocks.Console,
  Blocks.Database,
  Blocks.Manifest,
  Blocks.Workspace,
  Blocks.JSON,
  Blocks.Http,
  Blocks.Types;

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
  WriteOption('config', 'Read or write workspace or system configuration values.');
  WriteOption('view <id@version>', 'Show details of a package from the repository.');
  WriteOption('version', 'Print the version of the blocks executable.');
  WriteOption('upgrade', 'Check for a newer release and download the setup if available.');
  WriteOption('help [command]', 'Show this message, or detailed help for a specific command.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' init /product delphi13');
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package');
  TConsole.WriteLine('  ' + AppExeName + ' install C:\path\to\manifest.json /overwrite');
  TConsole.WriteLine('  ' + AppExeName + ' install https://example.com/manifest.json /silent');
  TConsole.WriteLine('  ' + AppExeName + ' uninstall owner.package');
  TConsole.WriteLine('  ' + AppExeName + ' list');
  TConsole.WriteLine('  ' + AppExeName + ' help install');
  TConsole.WriteLine;
end;

{ TListCommand }

procedure TListCommand.Execute;
begin
  inherited;
  var LProductName := TWorkspace.Config.Product;
  if LProductName = '' then
    raise Exception.Create(
        'No Delphi version configured. Run "blocks init -product <version>" first.');
  ListBlocks(TProduct.FindByNameAndKey(LProductName, TWorkspace.Config.RegistryKey));
end;

procedure TListCommand.ListBlocks(AProduct: TProduct);
begin
  TConsole.WriteLine;
  var LLabel := AProduct.DisplayName;
  if AProduct.RegistryKey <> 'BDS' then
    LLabel := LLabel + ' (' + AProduct.RegistryKey + ')';
  TConsole.WriteLine('  ' + LLabel, clCyan);
  TConsole.WriteLine;

  var Entries := TWorkspace.Database.ListEntries;
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

procedure TListCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Lists all packages installed in the current workspace.');
  TConsole.WriteLine('The Delphi version is read from the workspace configuration (set during init).');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' list', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Example:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' list');
  TConsole.WriteLine;
end;

{ TListProductsCommand }

procedure TListProductsCommand.Execute;
begin
  inherited;
  if FAll then
  begin
    TConsole.WriteLine;
    TConsole.WriteLine('Supported Delphi versions:', clWhite);
    TConsole.WriteLine;
    for var VerName in VersionOrder do
    begin
      var DispName: string;
      if not VersionNames.TryGetValue(VerName, DispName) then
        DispName := VerName;
      TConsole.WriteLine(Format('  %-20s %s', [VerName, DispName]));
    end;
    TConsole.WriteLine;
    Exit;
  end;

  if TProduct.Products.Count = 0 then
  begin
    TConsole.WriteWarning('No Delphi versions found in the registry.');
    Exit;
  end;
  TConsole.WriteLine;
  TConsole.WriteLine('Installed Delphi versions:', clWhite);
  TConsole.WriteLine;
  for var P in TProduct.Products do
    TConsole.WriteLine(Format('  %-20s %-15s %s', [P.VersionName, P.RegistryKey, P.DisplayName]));
  TConsole.WriteLine;
end;

procedure TListProductsCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Lists all Delphi installations detected in the Windows registry.');
  TConsole.WriteLine('Use the version name shown here as the /product argument for other commands.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' listproducts [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/all', 'Show all supported Delphi versions instead of installed ones.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' listproducts');
  TConsole.WriteLine('  ' + AppExeName + ' listproducts /all');
  TConsole.WriteLine;
end;

{ TInitCommand }

procedure TInitCommand.Execute;
begin
  inherited;
  ShowBanner('', '');
  if TDirectory.Exists(TWorkspace.BlocksDir) then
  begin
    TConsole.Write('Workspace already initialised. Update package list? [Y/N] (default: Y): ');
    var Confirm := TConsole.ReadLine;
    if SameText(Trim(Confirm), 'N') then
      raise Exception.Create('Operation cancelled.');
    TWorkspace.Update(GetCurrentDir);
  end
  else
  begin
    TConsole.WriteLine('Initialising workspace: ' + GetCurrentDir, clWhite);
    TConsole.WriteLine;
    TWorkspace.Initialize(GetCurrentDir, FProduct, FRegistryKey, FCanonical);
    TConsole.WriteLine('Workspace initialised.', clGreen);
    TConsole.WriteLine;
  end;
end;

procedure TInitCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Creates the .blocks\ directory in the current folder, selects the target');
  TConsole.WriteLine('Delphi version, and downloads the remote package repository.');
  TConsole.WriteLine('Run this once per workspace before using install.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' init [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/product <version>', 'Target Delphi version (e.g. delphi12, delphi13).');
  WriteOption('', 'If omitted, you will be prompted to choose.');
  WriteOption('', 'Run "' + AppExeName + ' listproducts" to see valid values.');
  WriteOption('/registrykey <key>', 'Registry profile key (default: BDS).');
  WriteOption('', 'Use this when Delphi is started with -r <key>.');
  WriteOption('/canonical', 'Use canonical BPL output structure without prompting.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
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
  TWorkspace.Install(LPackageName, LVersionConstraint, FOverwrite, FBuildOnly, FSilent, FForce);
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
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package /silent');
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package /buildonly');
  TConsole.WriteLine;
end;

{ TUninstallCommand }

procedure TUninstallCommand.Execute;
begin
  inherited;
  CheckWorkspace;
  ShowBanner('', '');
  TestDelphiRunning;
  TWorkspace.Uninstall(FPackageName);
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
  TConsole.WriteLine('Example:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' uninstall owner.package');
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
      raise Exception.Create('Operation cancelled. Run "blocks Init" to initialise the workspace first.');
    TWorkspace.Initialize(TWorkspace.WorkDir, '', '', False);
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
      if P.IsRunning and (P.RegistryKey = 'BDS') then
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
    if FSystem then
    begin
      TConsole.WriteWarning('Not supported.');
      Exit;
    end;
    TConsole.WriteLine(TWorkspace.Config.ToJson);
    Exit;
  end;

  for var LConfig in FConfigs do
  begin
    var LEqualPos := Pos('=', LConfig);
    if LEqualPos < 1 then
    begin
      var LValue := '';
      if FSystem then
        LValue := TSystemConfig.Get(LConfig)
      else
        LValue := TWorkspace.Config.Get(LConfig);

      TConsole.WriteLine(Format('%s: %s', [LConfig, LValue]));
    end
    else
    begin
      var LKey := Copy(LConfig, 1, LEqualPos - 1);
      var LValue := Copy(LConfig, LEqualPos + 1, Length(LConfig));

      if FSystem then
      begin
        if FAdd then
          TSystemConfig.Add(LKey, LValue)
        else
          TSystemConfig.Set(LKey, LValue);
        TWorkspace.Config.Save;
      end
      else
      begin
        if FAdd then
          TWorkspace.Config.Add(LKey, LValue)
        else
          TWorkspace.Config.&Set(LKey, LValue);
        TWorkspace.Config.Save;
      end;
      TConsole.WriteLine('Config applied');
    end;
  end;
end;

procedure TConfigCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Reads or writes workspace or system configuration values.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' config [/add] [/system] [<key>[=<value>] ...]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Arguments:', clWhite);
  WriteOption('<key>', 'Print the current value of the given key.');
  WriteOption('<key>=<value>', 'Set the key to the given value.');
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/add', 'Append the value instead of replacing it (for list keys).');
  WriteOption('/system', 'Read or write system-level config (Windows registry) instead of');
  WriteOption('', 'workspace config.');
  TConsole.WriteLine;
  TConsole.WriteLine('Workspace keys:', clWhite);
  WriteOption('sources', 'Comma-separated list of repository URLs used by "init".');
  WriteOption('product', 'Target Delphi version name (e.g. delphi12, delphi13).');
  WriteOption('registrykey', 'Registry profile key for the target Delphi IDE (default: BDS).');
  TConsole.WriteLine;
  TConsole.WriteLine('System keys:', clWhite);
  WriteOption('InstallPath', 'Specifies the directory containing the blocks.exe to launch');
  WriteOption('', 'when multiple installations are present. This key is only ');
  WriteOption('', 'available when Blocks was installed using the setup package');
  WriteOption('', 'and requires the launcher to function.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' config');
  TConsole.WriteLine('  ' + AppExeName + ' config sources');
  TConsole.WriteLine('  ' + AppExeName + ' config sources=https://github.com/owner/my-repo');
  TConsole.WriteLine('  ' + AppExeName + ' config /add sources=https://github.com/owner/other-repo');
  TConsole.WriteLine('  ' + AppExeName + ' config product');
  TConsole.WriteLine('  ' + AppExeName + ' config registrykey=myprofile');
  TConsole.WriteLine('  ' + AppExeName + ' config /system InstallPath');
  TConsole.WriteLine('  ' + AppExeName + ' config /system InstallPath=C:\Tools\Blocks');
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
      LField('Keywords', string.Join(', ', LManifest.Keywords.ToStringArray));

    // Packages
    if LManifest.Packages.Count > 0 then
    begin
      LSection('Packages');
      for var LPkg in LManifest.Packages do
      begin
        TConsole.Write('    ' + LPkg.Name.PadRight(30), clWhite);
        TConsole.WriteLine(string.Join(', ', LPkg.&Type.ToStringArray), clDkGray);
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
          LField('      Source', string.Join(', ', LPlat.Value.SourcePath.ToStringArray));
        if LPlat.Value.ReleaseDCUPath.Count > 0 then
          LField('      Release DCUs', string.Join(', ', LPlat.Value.ReleaseDCUPath.ToStringArray));
        if LPlat.Value.DebugDCUPath.Count > 0 then
          LField('      Debug DCUs', string.Join(', ', LPlat.Value.DebugDCUPath.ToStringArray));
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

{ TVersionCommand }

procedure TVersionCommand.Execute;
begin
  inherited;
  var LVersion := TAppVersion.GetCurrentVersion;
  if FSilent then
    TConsole.WriteLine(LVersion)
  else
    TConsole.WriteLine(AppExeName + ' ' + LVersion, clWhite);
end;

procedure TVersionCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Prints the version number of the blocks executable.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' version', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/silent', 'Show only the version number.');
  TConsole.WriteLine;
  TConsole.WriteLine('Example:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' version');
  TConsole.WriteLine('  ' + AppExeName + ' version /silent');
  TConsole.WriteLine;
end;

{ TSystemConfig }

class procedure TSystemConfig.Add(const AKey, AValue: string);
begin
  raise Exception.CreateFmt('System config key "%s" does not support multiple values.', [AKey]);
end;

class function TSystemConfig.Get(const AKey: string): string;
begin
  if SameText(AKey, 'InstallPath') then
  begin
    var LReg := TRegistry.Create;
    try
      if not LReg.KeyExists(InstallPath) then
        raise Exception.Create('Blocks launcher not installed');
      LReg.OpenKey(InstallPath, False);
      Result := LReg.ReadString('InstallPath');
    finally
      LReg.Free;
    end;
  end
  else
    raise Exception.CreateFmt('System config "%s" not found', [AKey]);

end;

class procedure TSystemConfig.&Set(const AKey, AValue: string);
begin
  if SameText(AKey, 'InstallPath') then
  begin
    if not FileExists(TPath.Combine(AValue, 'blocks.exe')) then
      raise Exception.Create('Blocks not found in the specified path');
    var LReg := TRegistry.Create;
    try
      if not LReg.KeyExists(InstallPath) then
        raise Exception.Create('Blocks launcher not installed');
      LReg.OpenKey(InstallPath, False);
      LReg.WriteString('InstallPath', AValue);
    finally
      LReg.Free;
    end;
  end
  else
    raise Exception.CreateFmt('System config "%s" not found', [AKey]);
end;

{ TUpgradeCommand }

procedure TUpgradeCommand.Execute;
begin
  inherited;
  var LCurrentVersion := TAppVersion.GetCurrentVersion;
  ShowBanner('', '');

  TConsole.WriteLine('Checking for the latest release on GitHub...');
  var LReleases := TGitHub.GetGitHubReleases('delphi-blocks', 'blocks');
  try
    if LReleases.Count = 0 then
      raise Exception.Create('No releases found on GitHub');

    var LGitHubVersion := TSemVer.Parse(ExtractVersionNumber(LReleases[0].Name));

    TConsole.WriteLine;
    TConsole.WriteLine('Current version: ' + LCurrentVersion.ToString);
    TConsole.WriteLine('Latest version:  ' + LGitHubVersion.ToString);

    if LGitHubVersion.CompareTo(LCurrentVersion) <= 0 then
    begin
      TConsole.WriteLine('Your version is up to date', clGreen);
      if not FForce then
        Exit;
    end;

    if FCheck then
    begin
      Exit;
    end;

    TConsole.WriteLine;
    TConsole.Write('Do you want to upgrade? [Y/N] (default: Y): ');
    var Confirm := TConsole.ReadLine;
    if SameText(Trim(Confirm), 'N') then
      raise Exception.Create('Operation cancelled.');

    var LBrowserDownloadUrl := SelectSetup(LReleases[0].Assets);
    if LBrowserDownloadUrl = '' then
      Exit;

    var LDestinationPath := TPath.Combine(TPath.GetTempPath, '.blocks', THttpUtils.ExtractFileName(LBrowserDownloadUrl));
    TConsole.WriteLine('Downloading to: ' + LDestinationPath);
    ForceDirectories(ExtractFilePath(LDestinationPath));

    THttpUtils.DownloadFile(LBrowserDownloadUrl, LDestinationPath);
    ShellExecute(0, 'open', PChar(LDestinationPath), '', '', SW_SHOWDEFAULT);

  finally
    LReleases.Free;
  end;

end;

function TUpgradeCommand.SelectSetup(AAssets: TGitHubReleaseAssets): string;
begin
  // If there are no assets, exit
  if AAssets.Count <= 0 then
  begin
    TConsole.WriteError('Setup package not found in release assets');
    Exit('');
  end;

  // If there is only one setup, exit
  if AAssets.Count = 1 then
  begin
    Exit(AAssets[0].BrowserDownloadUrl);
  end;

  TConsole.WriteLine;

  // If there is more than one setup, ask the user
  var LBrowserDownloadUrlList: TArray<string> := [];
  for var LAsset in AAssets do
  begin
    if LAsset.BrowserDownloadUrl.Contains('setup', True) then
    begin
      LBrowserDownloadUrlList := LBrowserDownloadUrlList + [LAsset.BrowserDownloadUrl];
    end;
  end;

  if Length(LBrowserDownloadUrlList) = 0 then
  begin
    TConsole.WriteError('No setup package found in release assets');
    Exit('');
  end;

  var I := 0;
  TConsole.WriteLine('Available setups:', clGreen);
  for var LBrowserDownloadUrl in LBrowserDownloadUrlList do
  begin
    TConsole.WriteLine(Format('  [%d] %s', [I + 1, THttpUtils.ExtractFileName(LBrowserDownloadUrl)]));
    Inc(I);
  end;
  TConsole.WriteLine;

  TConsole.Write(Format('Select setup [1-%d] (ENTER for none): ', [Length(LBrowserDownloadUrlList)]));
  var InputStr := Trim(TConsole.ReadLine);
  if InputStr = '' then
    Exit;

  var Index: Integer;
  if TryStrToInt(InputStr, Index) and (Index >= 1) and (Index <= Length(LBrowserDownloadUrlList)) then
    Exit(LBrowserDownloadUrlList[Index - 1]);

end;

procedure TUpgradeCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Checks GitHub for a newer release of blocks and, if one is found,');
  TConsole.WriteLine('downloads and launches the setup package.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' upgrade [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/check', 'Only check whether a newer version is available; do not download.');
  WriteOption('/force', 'Download and install even if the current version is already up to date.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' upgrade');
  TConsole.WriteLine('  ' + AppExeName + ' upgrade /check');
  TConsole.WriteLine('  ' + AppExeName + ' upgrade /force');
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
TCommand.RegisterCommand('version', TVersionCommand);
TCommand.RegisterCommand('upgrade', TUpgradeCommand);

end.
