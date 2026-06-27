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
unit Blocks.CLI.App;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.TypInfo,
  System.Rtti,
  System.StrUtils,
  System.Generics.Collections,
  Winapi.Windows,
  Winapi.ShellAPI,
  Blocks.Service.Product,
  Blocks.GitHub,
  Blocks.CLI.Command;

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
    procedure CheckLatestRelease;
  end;

  THelpCommand = class(TBaseCommand)
  private
    [Param]
    FCommandName: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  /// <summary>
  ///   Runs when blocks is invoked with no command (and as the fallback for an
  ///   unrecognised one). Shows the banner plus a short status: the configured
  ///   Delphi version and registry key when the current directory is a
  ///   workspace, otherwise a hint to run init or help.
  /// </summary>
  TDefaultCommand = class(TBaseCommand)
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

  TProductCommand = class(TBaseCommand)
  private
    [Param('all')]
    FAll: Boolean;
    [Param('detail')]
    FDetail: Boolean;
    [Param]
    FProductArgs: TArray<string>;
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
    [Param('source', 'sources')]
    FSource: string;
    [Param('platforms', 'platform')]
    FPlatforms: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TInstallCommand = class(TBaseCommand)
  private
    [Param('overwrite')]
    FOverwrite: Boolean;
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

  TBuildCommand = class(TBaseCommand)
  private
    [Param('silent')]
    FSilent: Boolean;
    [Param]
    FPackageName: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TUninstallCommand = class(TBaseCommand)
  private
    [Param('force')]
    FForce: Boolean;
    [Param]
    FPackageName: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TSearchCommand = class(TBaseCommand)
  private
    [Param]
    FPattern: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TConfigCommand = class(TBaseCommand)
  private
    [Param('add')]
    FAdd: Boolean;
    [Param('delete')]
    FDelete: Boolean;
    [Param('system')]
    FSystem: Boolean;
    [Param]
    FConfigs: TArray<string>;
    procedure WriteField(const ALabel, AValue: string);
    procedure WriteSectionTitle(const ATitle: string);
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
    [Param('silent')]
    FSilent: Boolean;
    function SelectSetup(AAssets: TGitHubReleaseAssets): string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  TUpdateCommand = class(TBaseCommand)
  private
    [Param('silent')]
    FSilent: Boolean;
    [Param]
    FPackageName: string;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

  /// <summary>
  ///   Opens the Delphi IDE (bds.exe) bound to the current workspace. Outside a
  ///   workspace the target must be given via <c>product=&lt;version&gt;</c>
  ///   (optionally <c>product=&lt;version&gt;:&lt;regkey&gt;</c>). IDE preferences
  ///   (architecture, personality, HighDPI) come from the workspace config and can be
  ///   overridden for this launch only via <c>key=value</c> arguments.
  /// </summary>
  TRunCommand = class(TBaseCommand)
  private
    [Param]
    FArgs: TArray<string>;
  public
    procedure Execute; override;
    procedure ShowHelp; override;
  end;

implementation

uses
  Blocks.Core,
  Blocks.Console,
  Blocks.Model.Config,
  Blocks.Model.Database,
  Blocks.Model.Manifest,
  Blocks.Model.SysConfig,
  Blocks.Service.Workspace,
  Blocks.JSON,
  Blocks.Http;

const
  OptionLength = 26;
  // Maximum width (in columns) of a package description before it is wrapped
  // onto multiple lines in the search results.
  DescriptionWidth = 80;

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
  WriteOption('install <package>', 'Install a package by id (vendor.name) or name.');
  WriteOption('build <package>', 'Recompile an already-installed package without downloading it.');
  WriteOption('update <package>', 'Update an installed package and recompile its dependents.');
  WriteOption('uninstall <package>', 'Remove a package from the workspace and database.');
  WriteOption('run', 'Open the Delphi IDE bound to the current workspace.');
  WriteOption('init', 'Initialise the workspace and download the package repository.');
  WriteOption('list', 'List packages installed in the current workspace.');
  WriteOption('product [name...]', 'Show Delphi installations. Pass names to filter and get details.');
  WriteOption('search [pattern]', 'Search the repository index by id, name, description or keywords.');
  WriteOption('config', 'Read or write workspace or system configuration values.');
  WriteOption('view <id[@version]>', 'Show details of a package from the repository.');
  WriteOption('version', 'Print the version of the blocks executable.');
  WriteOption('upgrade', 'Check for a newer release and download the setup if available.');
  WriteOption('help [command]', 'Show this message, or detailed help for a specific command.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' init /product delphi13');
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package');
  TConsole.WriteLine('  ' + AppExeName + ' install package /silent');
  TConsole.WriteLine('  ' + AppExeName + ' uninstall owner.package');
  TConsole.WriteLine('  ' + AppExeName + ' search json');
  TConsole.WriteLine('  ' + AppExeName + ' list');
  TConsole.WriteLine('  ' + AppExeName + ' help install');
  TConsole.WriteLine;
end;

{ TDefaultCommand }

procedure TDefaultCommand.Execute;
begin
  inherited;
  ShowBanner('', '');

  if TWorkspace.Exists then
  begin
    var LProduct := TWorkspace.Config.Product;
    var LRegistryKey := TWorkspace.Config.RegistryKey;
    if LRegistryKey = '' then
      LRegistryKey := 'BDS';

    TConsole.WriteLine('  Workspace  ▸  ' + TWorkspace.WorkDir, clWhite);
    TConsole.WriteLine(
        '  Delphi     ▸  '
            + if LProduct <> '' then LProduct
            else '(not configured)',
        clWhite
    );
    TConsole.WriteLine('  Registry   ▸  ' + LRegistryKey, clWhite);
    TConsole.WriteLine;
    TConsole.WriteLine('Run "' + AppExeName + ' help" to see the available commands.', clGray);
    TConsole.WriteLine;
  end
  else
  begin
    TConsole.WriteLine('  The current directory is not a Blocks workspace.', clYellow);
    TConsole.WriteLine;
    TConsole.WriteLine('Run "' + AppExeName + ' init" to create one here, or', clGray);
    TConsole.WriteLine('run "' + AppExeName + ' help" to see all the available commands.', clGray);
    TConsole.WriteLine;
  end;
end;

procedure TDefaultCommand.ShowHelp;
begin
  Execute;
end;

{ TListCommand }

procedure TListCommand.Execute;
begin
  inherited;
  var LProductName := TWorkspace.Config.Product;
  if LProductName = '' then
    raise Exception.Create('No Delphi version configured. Run "blocks init -product <version>" first.');
  ListBlocks(TProduct.Find(LProductName, TWorkspace.Config.RegistryKey));
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

{ TProductCommand }

procedure TProductCommand.Execute;

  procedure ShowDetail(AProduct: TProduct);
  begin
    TConsole.WriteLine('  ' + AProduct.VersionName, clCyan);
    TConsole.WriteLine(Format('    %-22s %s', ['Display Name:', AProduct.DisplayName]));
    TConsole.WriteLine(Format('    %-22s %s', ['BDS Version:', AProduct.BdsVersion]));
    TConsole.WriteLine(Format('    %-22s %s', ['Root Dir:', AProduct.RootDir]));
    TConsole.WriteLine(Format('    %-22s %s', ['Registry Key:', AProduct.RegistryKey]));
    TConsole.WriteLine(
        Format(
            '    %-22s %s',
            [
                'Running:',
                if AProduct.IsRunning then 'Yes'
                else 'No'
            ]
        )
    );
    for var LPlatform in AProduct.Platforms.Values do
    begin
      if not LPlatform.Active then
        Continue;
      TConsole.WriteLine('    [' + LPlatform.Name + ']', clDkCyan);
      TConsole.WriteLine(Format('      %-22s %s', ['Search Path:', LPlatform.SearchPath]));
      TConsole.WriteLine(Format('      %-22s %s', ['HPP Output Dir:', LPlatform.HPPOutputDirectory]));
      TConsole.WriteLine(Format('      %-22s %s', ['Package DCP Output:', LPlatform.PackageDCPOutput]));
      TConsole.WriteLine(Format('      %-22s %s', ['Package DPL Output:', LPlatform.PackageDPLOutput]));
      TConsole.WriteLine(Format('      %-22s %s', ['Package Search Path:', LPlatform.PackageSearchPath]));
    end;
    TConsole.WriteLine;
  end;

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

  // Filter by product names provided as positional arguments
  if Length(FProductArgs) > 0 then
  begin
    TConsole.WriteLine;
    TConsole.WriteLine('Delphi versions:', clWhite);
    TConsole.WriteLine;
    for var LArg in FProductArgs do
    begin
      var LParts := LArg.Split([':'], 2);
      var LVersionName := LParts[0];
      var LRegistryKey :=
          if Length(LParts) > 1 then LParts[1]
          else 'BDS';
      ShowDetail(TProduct.Find(LVersionName, LRegistryKey));
    end;
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
  if FDetail then
  begin
    for var P in TProduct.Products do
      ShowDetail(P);
  end
  else
  begin
    for var P in TProduct.Products do
      TConsole.WriteLine(Format('  %-20s %-15s %s', [P.VersionName, P.RegistryKey, P.DisplayName]));
    TConsole.WriteLine;
  end;
end;

procedure TProductCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Shows Delphi/RAD Studio installations detected in the Windows registry.');
  TConsole.WriteLine('Use the version name shown here as the /product argument for other commands.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' product [name[:regkey]...] [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/all', 'Show all supported Delphi versions instead of installed ones.');
  WriteOption('/detail', 'Show all properties for each installed product.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' product');
  TConsole.WriteLine('  ' + AppExeName + ' product /all');
  TConsole.WriteLine('  ' + AppExeName + ' product /detail');
  TConsole.WriteLine('  ' + AppExeName + ' product delphi12');
  TConsole.WriteLine('  ' + AppExeName + ' product delphi12:blocks');
  TConsole.WriteLine('  ' + AppExeName + ' product delphi12 delphi13');
  TConsole.WriteLine;
end;

{ TInitCommand }

procedure TInitCommand.Execute;
begin
  inherited;
  ShowBanner('', '');
  if TWorkspace.Exists then
  begin
    TWorkspace.UpdateRepositoryCache(GetCurrentDir);
  end
  else
  begin
    TConsole.WriteLine('Initialising workspace: ' + GetCurrentDir, clWhite);
    TConsole.WriteLine;
    TWorkspace.Initialize(GetCurrentDir, FProduct, FRegistryKey, FSource, FPlatforms);
    TConsole.WriteLine('Workspace initialised.', clGreen);
    TConsole.WriteLine;
  end;
  // Once a day, check GitHub for a newer blocks release and suggest "upgrade".
  if TSystemConfig.AutoUpdate and TWorkspace.Database.IsReleaseCheckStale(1) then
    CheckLatestRelease;
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
  WriteOption('', 'Run "' + AppExeName + ' product" to see valid values.');
  WriteOption('/registrykey <key>', 'Registry profile key (default: BDS).');
  WriteOption('', 'Use this when Delphi is started with -r <key>.');
  WriteOption('/source <url>', 'Package source(s) to use instead of the default.');
  WriteOption('/sources <url>', 'Alias of /source. Separate multiple sources with commas.');
  WriteOption('/platforms <list>', 'Comma-separated platforms to target (e.g. Win32,Win64).');
  WriteOption('', 'If omitted, you will be prompted to choose; selecting none');
  WriteOption('', 'targets all platforms supported by the Delphi version.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' init');
  TConsole.WriteLine('  ' + AppExeName + ' init /source https://github.com/owner/repo');
  TConsole.WriteLine('  ' + AppExeName + ' init /sources https://github.com/a/r1,https://github.com/b/r2');
  TConsole.WriteLine('  ' + AppExeName + ' init /product delphi13 /platforms Win32,Win64');
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
  var LOptions: TWorkspaceOptions := [];
  if FOverwrite then
    Include(LOptions, woOverwrite);
  if FSilent then
    Include(LOptions, woSilent);
  if FForce then
    Include(LOptions, woForce);
  TWorkspace.Install(LPackageName, LVersionConstraint, LOptions);
end;

procedure TInstallCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Downloads, compiles and registers a Delphi package into the active');
  TConsole.WriteLine('Delphi installation. The package can be specified by id (vendor.name)');
  TConsole.WriteLine('or by name; ambiguous names prompt for selection.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' install <package> [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Arguments:', clWhite);
  WriteOption('<package>', 'Package id (vendor.name) or package name.');
  WriteOption('', 'Append @<constraint> to specify a version constraint (e.g. owner.pkg@1.2.0,');
  WriteOption('', 'owner.pkg@^1.2.0, owner.pkg@>=1.0.0).');
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/overwrite', 'Overwrite the project directory if it already exists.');
  WriteOption('/silent', 'Skip non-critical interactive prompts (use defaults).');
  WriteOption('/force', 'Skip dependencies that conflict with the requested constraint');
  WriteOption('', 'instead of raising an error, using the already-installed version.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package');
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package@1.2.0');
  TConsole.WriteLine('  ' + AppExeName + ' install owner.package@^1.2.0 /force');
  TConsole.WriteLine('  ' + AppExeName + ' install package /silent');
  TConsole.WriteLine;
end;

{ TBuildCommand }

procedure TBuildCommand.Execute;
begin
  inherited;
  CheckWorkspace;
  ShowBanner('', '');
  // Recompiles an already-installed package without downloading it again.
  var LOptions: TWorkspaceOptions := [woBuildOnly];
  if FSilent then
    Include(LOptions, woSilent);
  TWorkspace.Install(FPackageName, '', LOptions);
end;

procedure TBuildCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Recompiles and re-registers a package that is already installed,');
  TConsole.WriteLine('reusing the sources already present in the workspace (no download).');
  TConsole.WriteLine('The package must have been installed first with "blocks install".');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' build <package> [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Arguments:', clWhite);
  WriteOption('<package>', 'Package id (vendor.name) or package name.');
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/silent', 'Skip non-critical interactive prompts (use defaults).');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' build owner.package');
  TConsole.WriteLine('  ' + AppExeName + ' build package /silent');
  TConsole.WriteLine;
end;

{ TUpdateCommand }

procedure TUpdateCommand.Execute;
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
  if LPackageName = '' then
    raise Exception.Create('Usage: ' + AppExeName + ' update <package>[@version]');
  ShowBanner('', '');
  var LOptions: TWorkspaceOptions := [];
  if FSilent then
    Include(LOptions, woSilent);
  TWorkspace.Update(LPackageName, LVersionConstraint, LOptions);
end;

procedure TUpdateCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Updates an already-installed package to a newer version and recompiles');
  TConsole.WriteLine('the packages that depend on it (directly or transitively). With no version,');
  TConsole.WriteLine('proposes the highest release within the installed major version; append');
  TConsole.WriteLine('@<version> to pick a specific one (a downgrade is allowed too).');
  TConsole.WriteLine;
  TConsole.WriteLine('Before updating, two compatibility checks run: the new version''s');
  TConsole.WriteLine('dependencies against what is installed, and the installed dependents');
  TConsole.WriteLine('against the new version. On problems the update is refused, leaving the');
  TConsole.WriteLine('workspace untouched: uninstall or update the conflicting packages first.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' update <package> [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Arguments:', clWhite);
  WriteOption('<package>', 'Package id (vendor.name) or package name.');
  WriteOption('', 'Append @<version> to target a specific version (e.g. owner.pkg@2.0.0).');
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/silent', 'Skip the version prompt, taking the proposed version.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' update owner.package');
  TConsole.WriteLine('  ' + AppExeName + ' update owner.package@2.0.0');
  TConsole.WriteLine;
end;

{ TRunCommand }

procedure TRunCommand.Execute;
begin
  inherited;

  var LInWorkspace := TWorkspace.Exists;

  // Outside a workspace use a fresh, in-memory config (never Loaded/Saved, so no
  // .blocks directory is created); inside one use the workspace config. CLI
  // key=value arguments override the config for this launch only and are never saved.
  var LOwnConfig: TConfig := nil;
  var LConfig: TConfig;
  if LInWorkspace then
    LConfig := TWorkspace.Config
  else
  begin
    LOwnConfig := TConfig.Create(TWorkspace.WorkDir);
    LConfig := LOwnConfig;
  end;
  try
    for var LArg in FArgs do
    begin
      var LKey: string;
      var LValue: string;
      var LEqualPos := Pos('=', LArg);
      if LEqualPos < 1 then
      begin
        // A bare token (no '=') is the product spec: <version> or <version>:<regkey>.
        LKey := 'product';
        LValue := LArg;
      end
      else
      begin
        LKey := Copy(LArg, 1, LEqualPos - 1);
        LValue := Copy(LArg, LEqualPos + 1, Length(LArg));
      end;

      if SameText(LKey, 'product') then
      begin
        // product=<version> or product=<version>:<regkey>
        var LColonPos := Pos(':', LValue);
        if LColonPos > 0 then
        begin
          LConfig.Product := Copy(LValue, 1, LColonPos - 1);
          LConfig.RegistryKey := Copy(LValue, LColonPos + 1, Length(LValue));
        end
        else
          LConfig.Product := LValue;
      end
      else if SameText(LKey, 'idearchitecture') or SameText(LKey, 'idepersonality') or SameText(LKey, 'idehighdpi') then
        LConfig.SetValue(LKey, LValue)
      else
        raise Exception
            .CreateFmt('Unknown argument "%s" (use product, idearchitecture, idepersonality or idehighdpi).', [LKey]);
    end;

    var LProduct: TProduct;
    var LRegistryKey: string;

    if LConfig.Product = '' then
    begin
      // No Delphi specified (none configured in the workspace and none on the command
      // line): let the user pick from the installed versions interactively, like "init".
      LProduct := TProduct.Choose;
      LRegistryKey := LProduct.RegistryKey;
    end
    else
    begin
      LRegistryKey := LConfig.RegistryKey;
      if LRegistryKey = '' then
        LRegistryKey := 'BDS';

      var LProfileExists: Boolean;
      LProduct := TProduct.FindForLaunch(LConfig.Product, LRegistryKey, LProfileExists);
      if not LProfileExists then
        TConsole.WriteWarning(
            Format('Registry profile "%s" does not exist yet; Delphi will create it on launch.', [LRegistryKey])
        );
    end;

    var LPreferWin64 := LConfig.IdeArchitecture = TIdeArchitecture.Win64;
    var LIsWin64: Boolean;
    var LExe := LProduct.IdeExecutable(LPreferWin64, LIsWin64);
    if LPreferWin64 and not LIsWin64 then
      TConsole.WriteWarning('No 64-bit IDE (App64) found for this profile; launching the 32-bit IDE.');

    var LParams := '';
    if not SameText(LRegistryKey, 'BDS') then
      LParams := LParams + ' -r ' + LRegistryKey;
    if LConfig.IdePersonality <> TIdePersonality.default then
      LParams := LParams + ' -p ' + IdePersonalityToStr(LConfig.IdePersonality);
    if LConfig.IdeHighDpi <> TIdeHighDpi.default then
      LParams := LParams + ' -highdpi:' + IdeHighDpiToStr(LConfig.IdeHighDpi);
    LParams := LParams.Trim;

    var LLabel := LProduct.DisplayName;
    if not SameText(LRegistryKey, 'BDS') then
      LLabel := LLabel + ' (' + LRegistryKey + ')';

    TConsole.WriteLine;
    TConsole.WriteLine('Launching ' + LLabel + '...', clCyan);
    TConsole.WriteLine('  ' + LExe + ' ' + LParams, clDkGray);
    TConsole.WriteLine;

    var LResult := ShellExecute(0, 'open', PChar(LExe), PChar(LParams), PChar(TWorkspace.WorkDir), SW_SHOWNORMAL);
    if LResult <= 32 then
      raise Exception.CreateFmt('Failed to launch the IDE (ShellExecute error %d): %s', [Integer(LResult), LExe]);
  finally
    LOwnConfig.Free;
  end;
end;

procedure TRunCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Opens the Delphi IDE bound to the current workspace, reading the executable');
  TConsole.WriteLine('path from the registry profile configured for the workspace.');
  TConsole.WriteLine;
  TConsole.WriteLine('When no Delphi is configured (outside a workspace) and none is given on the');
  TConsole.WriteLine('command line, you are prompted to choose from the installed versions, like');
  TConsole.WriteLine('"init". A registry profile that does not exist yet is created by Delphi on');
  TConsole.WriteLine('first launch.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' run [<version>[:<regkey>] | key=value ...]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Arguments (override the workspace config for this launch only):', clWhite);
  WriteOption('<version>[:<regkey>]', 'Target Delphi as a bare token, e.g. delphi13 or delphi13:myprofile.');
  WriteOption('', 'Shorthand for product=<version>. If omitted, you are prompted.');
  WriteOption('product=<version>', 'Same as the bare form (use product=<version>:<regkey> for a profile).');
  WriteOption('idearchitecture=<v>', 'Which IDE to launch: default, Win32 or Win64. Win64 uses the');
  WriteOption('', '64-bit IDE (App64) when available, else falls back to 32-bit.');
  WriteOption('idepersonality=<v>', 'IDE personality (bds.exe -p): default, Delphi or CBuilder.');
  WriteOption('idehighdpi=<v>', 'HighDPI override (bds.exe -highdpi:): default, unaware,');
  WriteOption('', 'systemaware, permonitor, permonitorv2 or unawaregdiscaling.');
  TConsole.WriteLine;
  TConsole.WriteLine('The same keys can be persisted with "' + AppExeName + ' config".', clGray);
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' run');
  TConsole.WriteLine('  ' + AppExeName + ' run idearchitecture=Win64');
  TConsole.WriteLine('  ' + AppExeName + ' run idehighdpi=permonitorv2 idepersonality=Delphi');
  TConsole.WriteLine('  ' + AppExeName + ' run delphi13');
  TConsole.WriteLine('  ' + AppExeName + ' run delphi13:myprofile');
  TConsole.WriteLine('  ' + AppExeName + ' run delphi13 idehighdpi=permonitorv2');
  TConsole.WriteLine;
end;

{ TUninstallCommand }

procedure TUninstallCommand.Execute;
begin
  inherited;
  CheckWorkspace;
  ShowBanner('', '');
  var LOptions: TWorkspaceOptions := [];
  if FForce then
    Include(LOptions, woForce);
  TWorkspace.Uninstall(FPackageName, LOptions);
end;

procedure TUninstallCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Removes a previously installed package: deletes its project directory');
  TConsole.WriteLine('and the corresponding entry from the local database.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' uninstall <package> [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Arguments:', clWhite);
  WriteOption('<package>', 'Package id (vendor.name) or package name.');
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/force', 'Remove without asking, even if other installed packages');
  WriteOption('', 'still depend on this one.');
  TConsole.WriteLine;
  TConsole.WriteLine('Example:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' uninstall owner.package');
  TConsole.WriteLine('  ' + AppExeName + ' uninstall owner.package /force');
  TConsole.WriteLine;
end;

{ TSearchCommand }

/// <summary>Splits <c>AText</c> into lines no longer than <c>AWidth</c>
/// columns, breaking on word boundaries.</summary>
function WrapText(const AText: string; AWidth: Integer): TArray<string>;
begin
  Result := [];
  var LLine := '';
  for var LWord in AText.Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    if LLine = '' then
      LLine := LWord
    else if Length(LLine) + 1 + Length(LWord) <= AWidth then
      LLine := LLine + ' ' + LWord
    else
    begin
      Result := Result + [LLine];
      LLine := LWord;
    end;
  end;
  if LLine <> '' then
    Result := Result + [LLine];
end;

procedure TSearchCommand.Execute;
begin
  inherited;
  CheckWorkspace;

  // Every id contains a dot
  if FPattern = '' then
    FPattern := '.';

  var LIndex := TRepositoryIndex.Create;
  try
    LIndex.Load;
    var LMatches := LIndex.Search(FPattern);

    TConsole.WriteLine;
    if Length(LMatches) = 0 then
    begin
      TConsole.WriteLine(Format('No packages match "%s".', [FPattern]), clYellow);
      TConsole.WriteLine;
      Exit;
    end;

    if FPattern = '' then
      TConsole.WriteLine(Format('Packages in repository (%d):', [Length(LMatches)]), clWhite)
    else
      TConsole.WriteLine(Format('Packages matching "%s" (%d):', [FPattern, Length(LMatches)]), clWhite);
    TConsole.WriteLine;

    for var LEntry in LMatches do
    begin
      TConsole.Write(Format('  %-40s ', [LEntry.Id]), clCyan);
      TConsole.WriteLine(LEntry.Name, clWhite);
      if LEntry.Description <> '' then
        for var LLine in WrapText(LEntry.Description, DescriptionWidth) do
          TConsole.WriteLine('    ' + LLine, clGray);
      TConsole.WriteLine;
    end;
  finally
    LIndex.Free;
  end;
end;

procedure TSearchCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Searches the local repository index by id, name, description and keywords.');
  TConsole.WriteLine('The match is case insensitive and looks for any substring.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' search [pattern]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Arguments:', clWhite);
  WriteOption('[pattern]', 'Substring to look for; omit to list all packages.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' search json');
  TConsole.WriteLine('  ' + AppExeName + ' search');
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
    TWorkspace.Initialize(TWorkspace.WorkDir, '', '');
    TConsole.WriteLine;
  end;

  // Refresh the repository list when it has not been updated for more than a day.
  if TWorkspace.Database.IsRepositoryStale(1) then
  begin
    TConsole.WriteLine;
    TConsole.WriteLine('Repository list is more than a day old, updating...', clCyan);
    TWorkspace.UpdateRepositoryCache(TWorkspace.WorkDir);
    TConsole.WriteLine;
  end;

  // Once a day, check GitHub for a newer blocks release and suggest "upgrade".
  if TSystemConfig.AutoUpdate and TWorkspace.Database.IsReleaseCheckStale(1) then
    CheckLatestRelease;
end;

procedure TBaseCommand.CheckLatestRelease;
begin
  try
    try
      var LReleases := TGitHub.GetGitHubReleases('delphi-blocks', 'blocks');
      try
        if LReleases.Count > 0 then
        begin
          var LLatest := TSemVer.Parse(ExtractVersionNumber(LReleases[0].Name));
          var LCurrent := TAppVersion.GetCurrentVersion;
          if LLatest.CompareTo(LCurrent) > 0 then
          begin
            TConsole.WriteLine;
            TConsole.WriteWarning(
                Format('A new version of blocks is available: %s (current: %s)', [LLatest.ToString, LCurrent.ToString])
            );
            TConsole.WriteLine('Run "' + AppExeName + ' upgrade" to update.', clYellow);
            TConsole.WriteLine;
          end;
        end;
      finally
        LReleases.Free;
      end;
    finally
      // Always record the attempt so the check is throttled to once a day even
      // when offline; this keeps every command fast.
      TWorkspace.Database.TouchReleaseCheck;
    end;
  except
    // A GitHub/network failure must never break the user's command — ignore it.
  end;
end;

// -- Banner, app name and description -----------------------------------------
procedure TBaseCommand.ShowBanner(const AppName, Description: string);
begin
  TConsole.WriteLine;
  TConsole.WriteLine(
      ' ██████╗ ██╗      ██████╗  ██████╗██╗  ██╗███████╗',
      clCyan
  );
  TConsole.WriteLine(
      ' ██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝██╔════╝',
      clCyan
  );
  TConsole.WriteLine(
      ' ██████╔╝██║     ██║   ██║██║     █████╔╝ ███████╗',
      clCyan
  );
  TConsole.WriteLine(
      ' ██╔══██╗██║     ██║   ██║██║     ██╔═██╗ ╚════██║',
      clCyan
  );
  TConsole.WriteLine(
      ' ██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗███████║',
      clCyan
  );
  TConsole.WriteLine(
      ' ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝',
      clDkCyan
  );
  var LVersion := TAppVersion.GetCurrentVersion;
  TConsole.WriteLine('   ▸  Delphi Package Installer', clDkCyan);
  TConsole.WriteLine('   ▸  Version: ' + LVersion, clDkCyan);
  TConsole.WriteLine;

  if AppName <> '' then
  begin
    TConsole.WriteLine('  Package  ▸  ' + AppName, clWhite);
    if Description <> '' then
      TConsole.WriteLine('  About    ▸  ' + Description, clGray);
    TConsole.WriteLine;
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
  if FAdd and FDelete then
    raise Exception.Create('Options /add and /delete cannot be used together.');

  if Length(FConfigs) = 0 then
  begin
    if FSystem then
    begin
      WriteSectionTitle('System configuration');
      var LSystemConfig := TStringList.Create;
      try
        TSystemConfig.GetAll(LSystemConfig);
        for var LIndex := 0 to LSystemConfig.Count - 1 do
          WriteField(LSystemConfig.Names[LIndex], LSystemConfig.ValueFromIndex[LIndex]);
      finally
        LSystemConfig.Free;
      end;
      TConsole.WriteLine;
      Exit;
    end;

    WriteSectionTitle('Workspace configuration');
    WriteField('Product', TWorkspace.Config.Product);
    WriteField('RegistryKey', TWorkspace.Config.RegistryKey);
    WriteField('UpdateDcpSearchPath', TWorkspace.Config.GetValue('updatedcpsearchpath'));
    WriteField('ToolArchitecture', TWorkspace.Config.GetValue('toolarchitecture'));
    WriteField('IdeArchitecture', TWorkspace.Config.GetValue('idearchitecture'));
    WriteField('IdePersonality', TWorkspace.Config.GetValue('idepersonality'));
    WriteField('IdeHighDpi', TWorkspace.Config.GetValue('idehighdpi'));

    WriteSectionTitle('Sources');
    if TWorkspace.Config.Sources.Count = 0 then
      TConsole.WriteLine('    (none)', clDkGray)
    else
      for var LSource in TWorkspace.Config.Sources do
        TConsole.WriteLine('    ' + LSource);

    WriteSectionTitle('Platforms');
    if TWorkspace.Config.Platforms.Count = 0 then
      TConsole.WriteLine('    (all)', clDkGray)
    else
      for var LPlatform in TWorkspace.Config.Platforms do
        TConsole.WriteLine('    ' + LPlatform);
    TConsole.WriteLine;
    Exit;
  end;

  for var LConfig in FConfigs do
  begin
    var LEqualPos := Pos('=', LConfig);
    if LEqualPos < 1 then
    begin
      var LValue := '';
      if FSystem then
        LValue := TSystemConfig.GetValue(LConfig)
      else
        LValue := TWorkspace.Config.GetValue(LConfig);

      WriteField(LConfig, LValue);
    end
    else
    begin
      var LKey := Copy(LConfig, 1, LEqualPos - 1);
      var LValue := Copy(LConfig, LEqualPos + 1, Length(LConfig));

      if FSystem then
      begin
        if FAdd then
          TSystemConfig.Add(LKey, LValue)
        else if FDelete then
          TSystemConfig.Delete(LKey, LValue)
        else
          TSystemConfig.SetValue(LKey, LValue);
      end
      else if SameText(LKey, 'platforms') and not FDelete then
      begin
        // Validate platform names against the configured Delphi version and store
        // them in canonical casing. Removals (/delete) fall through to the generic
        // path so a platform that is no longer buildable can still be removed.
        var LProduct := TProduct.Find(TWorkspace.Config.Product, TWorkspace.Config.RegistryKey);
        var LNormalized := LProduct.NormalizePlatforms(LValue.Split([',']));
        if FAdd then
          for var LPlatform in LNormalized do
            TWorkspace.Config.Add(LKey, LPlatform)
        else
          TWorkspace.Config.SetValue(LKey, string.Join(',', LNormalized));
        TWorkspace.Config.Save;
      end
      else
      begin
        if FAdd then
          TWorkspace.Config.Add(LKey, LValue)
        else if FDelete then
          TWorkspace.Config.Delete(LKey, LValue)
        else
          TWorkspace.Config.SetValue(LKey, LValue);
        TWorkspace.Config.Save;
      end;
      TConsole.WriteLine('Config applied');
      if not FSystem and SameText(LKey, 'sources') then
        TConsole.WriteWarning('Run "' + AppExeName + ' init" to refresh the repository with the new sources.');
      if not FSystem and SameText(LKey, 'updatedcpsearchpath') then
        TConsole.WriteWarning('Run "' + AppExeName + ' init" to apply the search path change.');
    end;
  end;
end;

procedure TConfigCommand.ShowHelp;
begin
  TConsole.WriteLine;
  TConsole.WriteLine('Reads or writes workspace or system configuration values.');
  TConsole.WriteLine;
  TConsole.WriteLine('Usage: ' + AppExeName + ' config [/add | /delete] [/system] [<key>[=<value>] ...]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Arguments:', clWhite);
  WriteOption('<key>', 'Print the current value of the given key.');
  WriteOption('<key>=<value>', 'Set the key to the given value.');
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/add', 'Append the value instead of replacing it (for list keys).');
  WriteOption('/delete', 'Remove the value from a list key (for list keys).');
  WriteOption('/system', 'Read or write system-level config (Windows registry) instead of');
  WriteOption('', 'workspace config.');
  TConsole.WriteLine;
  TConsole.WriteLine('Workspace keys:', clWhite);
  WriteOption('sources', 'Comma-separated list of repository URLs used by "init".');
  WriteOption('', 'After changing this key, run "' + AppExeName + ' init" to refresh');
  WriteOption('', 'the local repository.');
  WriteOption('platforms', 'Comma-separated platforms this workspace targets (e.g. Win32,Win64).');
  WriteOption('', 'Empty means all platforms supported by the Delphi version.');
  WriteOption('', 'Supports /add and /delete for single platforms.');
  WriteOption('product', 'Target Delphi version name (e.g. delphi12, delphi13).');
  WriteOption('registrykey', 'Registry profile key for the target Delphi IDE (default: BDS).');
  WriteOption('updatedcpsearchpath', 'When true, "init" adds the blocks DCP output directory to the');
  WriteOption('', 'Delphi library Search Path (true/false, default: false).');
  WriteOption('', 'After changing this key, run "' + AppExeName + ' init" to apply.');
  WriteOption('toolarchitecture', 'Compiler tools architecture MSBuild uses (Delphi 13+):');
  WriteOption('', 'default (don''t pass the flag), x32 (32-bit tools) or');
  WriteOption('', 'x64 (64-bit tools, more memory). Default: default.');
  WriteOption('', 'Does not change the produced binary.');
  WriteOption('idearchitecture', 'IDE "run" launches: default, Win32 or Win64 (Delphi 13+).');
  WriteOption('', 'Win64 uses the 64-bit IDE when available. Default: default.');
  WriteOption('idepersonality', 'IDE personality "run" selects (bds.exe -p):');
  WriteOption('', 'default, Delphi or CBuilder. Default: default.');
  WriteOption('idehighdpi', 'HighDPI override "run" applies (bds.exe -highdpi:):');
  WriteOption('', 'default, unaware, systemaware, permonitor, permonitorv2');
  WriteOption('', 'or unawaregdiscaling. Default: default.');
  TConsole.WriteLine;
  TConsole.WriteLine('System keys:', clWhite);
  WriteOption('InstallPath', 'Specifies the directory containing the blocks.exe to launch');
  WriteOption('', 'when multiple installations are present. This key is only ');
  WriteOption('', 'available when Blocks was installed using the setup package');
  WriteOption('', 'and requires the launcher to function.');
  WriteOption('AutoUpdate', 'When true (the default), blocks checks GitHub once a day for');
  WriteOption('', 'a newer release and suggests "upgrade" (true/false).');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' config');
  TConsole.WriteLine('  ' + AppExeName + ' config sources');
  TConsole.WriteLine('  ' + AppExeName + ' config sources=https://github.com/owner/my-repo');
  TConsole.WriteLine('  ' + AppExeName + ' config /add sources=https://github.com/owner/other-repo');
  TConsole.WriteLine('  ' + AppExeName + ' config /delete sources=https://github.com/owner/other-repo');
  TConsole.WriteLine('  ' + AppExeName + ' config product');
  TConsole.WriteLine('  ' + AppExeName + ' config platforms=Win32,Win64');
  TConsole.WriteLine('  ' + AppExeName + ' config /add platforms=Win64');
  TConsole.WriteLine('  ' + AppExeName + ' config /delete platforms=Win64');
  TConsole.WriteLine('  ' + AppExeName + ' config registrykey=myprofile');
  TConsole.WriteLine('  ' + AppExeName + ' config updatedcpsearchpath=true');
  TConsole.WriteLine('  ' + AppExeName + ' config toolarchitecture=x64');
  TConsole.WriteLine('  ' + AppExeName + ' config idearchitecture=Win64');
  TConsole.WriteLine('  ' + AppExeName + ' config idehighdpi=permonitorv2');
  TConsole.WriteLine('  ' + AppExeName + ' config /system InstallPath');
  TConsole.WriteLine('  ' + AppExeName + ' config /system InstallPath=C:\Tools\Blocks');
  TConsole.WriteLine('  ' + AppExeName + ' config /system AutoUpdate');
  TConsole.WriteLine('  ' + AppExeName + ' config /system AutoUpdate=false');
  TConsole.WriteLine;
end;

procedure TConfigCommand.WriteField(const ALabel, AValue: string);
const
  LabelW = 20;
begin
  TConsole.Write('  ' + ALabel.PadRight(LabelW), clCyan);
  if AValue = '' then
    TConsole.WriteLine('▸  (not set)', clDkGray)
  else
    TConsole.WriteLine('▸  ' + AValue);
end;

procedure TConfigCommand.WriteSectionTitle(const ATitle: string);
begin
  TConsole.WriteLine;
  TConsole.WriteLine('  ' + ATitle, clWhite);
  TConsole.WriteLine('  ' + StringOfChar('─', 44), clDkGray);
  TConsole.WriteLine;
end;

{ TViewCommand }

procedure TViewCommand.Execute;
begin
  inherited;
  CheckWorkspace;
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
    1: LPackageName := LPackageNamePair[0];
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
    LField :=
        procedure(ALabel, AValue: string)
        begin
          if AValue = '' then
            Exit;
          TConsole.Write('  ' + ALabel.PadRight(LabelW), clCyan);
          TConsole.WriteLine('▸  ' + AValue);
        end;

    var LSection: TProc<string>;
    LSection :=
        procedure(ATitle: string)
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

    LField('Id', LManifest.Id);
    LField('Author', LManifest.Author);
    LField('License', LManifest.License);
    LField('Homepage', LManifest.Homepage);
    LField('Repository', LManifest.Repository.Url);

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
        TConsole.Write(LDep.Value.PadRight(15), clDkGray);

        var LDepInstalled := TWorkspace.Database.InstalledVersion(LDep.Key);
        if LDepInstalled = '' then
        begin
          TConsole.WriteLine;
          Continue;
        end;

        var LDepSemVer: TSemVer;
        var LCompatible := TSemVer.TryParse(LDepInstalled, LDepSemVer) and LDepSemVer.MatchesConstraint(LDep.Value);
        if LCompatible then
          TConsole.WriteLine('installed ' + LDepInstalled, clGreen)
        else
          TConsole.WriteLine('installed ' + LDepInstalled, clRed);
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

    // Install status (workspace-local)
    TConsole.WriteLine;
    var LInstalledVer := TWorkspace.Database.InstalledVersion(LManifest.Id);
    if LInstalledVer = '' then
      TConsole.WriteLine('  Not installed in this workspace', clDkGray)
    else if SameText(LInstalledVer, LManifest.Version) then
      TConsole.WriteLine('  Installed: ' + LInstalledVer, clGreen)
    else
      TConsole.WriteLine(Format('  Installed: %s (viewing %s)', [LInstalledVer, LManifest.Version]), clYellow);

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
  TConsole.WriteLine('Usage: ' + AppExeName + ' view <id[@version]> [options]', clWhite);
  TConsole.WriteLine;
  TConsole.WriteLine('Arguments:', clWhite);
  WriteOption('<id[@version]>', 'Package id; optional @version selects a specific version');
  WriteOption('', '(latest is used when omitted, e.g. owner.package or owner.package@1.2.0).');
  TConsole.WriteLine;
  TConsole.WriteLine('Options:', clWhite);
  WriteOption('/raw', 'Print the raw manifest JSON instead of the formatted summary.');
  WriteOption('/versions', 'List all available versions of the package.');
  TConsole.WriteLine;
  TConsole.WriteLine('Examples:', clWhite);
  TConsole.WriteLine('  ' + AppExeName + ' view owner.package');
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

    var LDestinationPath :=
        TPath.Combine(TPath.GetTempPath, '.blocks', THttpUtils.ExtractFileName(LBrowserDownloadUrl));
    TConsole.WriteLine('Downloading to: ' + LDestinationPath);
    ForceDirectories(ExtractFilePath(LDestinationPath));

    var LParams :=
        if FSilent then '/verysilent'
        else '/silent';
    THttpUtils.DownloadFile(LBrowserDownloadUrl, LDestinationPath);
    ShellExecute(0, 'open', PChar(LDestinationPath), PChar(LParams), '', SW_SHOWDEFAULT);

  finally
    LReleases.Free;
  end;

end;

function TUpgradeCommand.SelectSetup(AAssets: TGitHubReleaseAssets): string;
const
{$IFDEF WIN64}
  PlatformSetupName = 'setup-x64';
{$ELSE}
  PlatformSetupName = 'setup-x32';
{$ENDIF}
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

  // If there is more than one setup search for a specific platform
  var LBrowserDownloadUrlList: TArray<string> := [];
  for var LAsset in AAssets do
  begin
    if LAsset.BrowserDownloadUrl.Contains(PlatformSetupName, True) then
    begin
      LBrowserDownloadUrlList := LBrowserDownloadUrlList + [LAsset.BrowserDownloadUrl];
    end;
  end;

  // If there is only one setup, exit
  if Length(LBrowserDownloadUrlList) = 1 then
  begin
    Exit(LBrowserDownloadUrlList[0]);
  end;

  // Else ask the user
  LBrowserDownloadUrlList := [];
  for var LAsset in AAssets do
  begin
    if LAsset.BrowserDownloadUrl.Contains('setup', True) then
    begin
      LBrowserDownloadUrlList := LBrowserDownloadUrlList + [LAsset.BrowserDownloadUrl];
    end;
  end;
  if Length(LBrowserDownloadUrlList) <= 0 then
  begin
    TConsole.WriteError('Setup package not found in release assets');
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

  TCommand.RegisterCommand('help', THelpCommand);
  TCommand.RegisterCommand('list', TListCommand);
  TCommand.RegisterCommand('product', TProductCommand);
  TCommand.RegisterCommand('init', TInitCommand);
  TCommand.RegisterCommand('install', TInstallCommand);
  TCommand.RegisterCommand('build', TBuildCommand);
  TCommand.RegisterCommand('update', TUpdateCommand);
  TCommand.RegisterCommand('uninstall', TUninstallCommand);
  TCommand.RegisterCommand('run', TRunCommand);
  TCommand.RegisterCommand('search', TSearchCommand);
  TCommand.RegisterCommand('config', TConfigCommand);
  TCommand.RegisterCommand('view', TViewCommand);
  TCommand.RegisterCommand('version', TVersionCommand);
  TCommand.RegisterCommand('upgrade', TUpgradeCommand);
  TCommand.RegisterCommand('', TDefaultCommand, True);

end.
