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
unit Blocks.Service.Script;

interface

uses
  System.Classes,
  System.SysUtils,
  System.Rtti,
  System.Generics.Collections,
  Blocks.Model.Manifest,
  Blocks.Model.Config;

type
  EScriptError = class(Exception)
  end;

  // -----------------------------------------------------------------------
  // Options for a single project compilation. Built with a fluent API:
  //   TCompilerOptions.New.SetPlatform('Win32').SetConfig('Release')...
  // Interface-based (TInterfacedObject) so callers don't manage its lifetime;
  // a temporary created inline lives for the duration of the call it is passed to.
  // -----------------------------------------------------------------------
  ICompilerOptions = interface
    ['{6E2B1F0A-9C4D-4E1B-8A77-2C3F5B9D1E64}']
    function GetPlatform: string;
    function GetConfig: string;
    function GetToolArchitecture: TToolArchitecture;

    function SetPlatform(const AValue: string): ICompilerOptions;
    function SetConfig(const AValue: string): ICompilerOptions;
    function SetToolArchitecture(const AValue: TToolArchitecture): ICompilerOptions;

    property Platform: string read GetPlatform;
    property Config: string read GetConfig;
    /// <summary>Compiler tools architecture; <c>default</c> means "do not pass
    ///   <c>/p:DCC_PreferredToolArchitecture</c> to MSBuild".</summary>
    property ToolArchitecture: TToolArchitecture read GetToolArchitecture;
  end;

  TCompilerOptions = class(TInterfacedObject, ICompilerOptions)
  private
    FPlatform: string;
    FConfig: string;
    FToolArchitecture: TToolArchitecture;
    function GetPlatform: string;
    function GetConfig: string;
    function GetToolArchitecture: TToolArchitecture;
  public
    /// <summary>Creates an empty options object (ToolArchitecture = default).</summary>
    class function New: ICompilerOptions; static;
    function SetPlatform(const AValue: string): ICompilerOptions;
    function SetConfig(const AValue: string): ICompilerOptions;
    function SetToolArchitecture(const AValue: TToolArchitecture): ICompilerOptions;
  end;

  ScriptManifestAttribute = class(TCustomAttribute)
  private
    FManifestArgumentsClass: TManifestScriptArgumentsClass;
  public
    property ManifestArgumentsClass: TManifestScriptArgumentsClass
        read FManifestArgumentsClass write FManifestArgumentsClass;
    constructor Create(AManifestArgumentsClass: TManifestScriptArgumentsClass);
  end;

  // -----------------------------------------------------------------------
  // Services a script command may need from the host but that this unit must
  // not depend on directly (e.g. compiling a project lives in
  // Blocks.Service.Product, which already uses this unit). The host passes a
  // concrete implementation down to the runner; for now it only exposes the
  // ability to compile a single project.
  // -----------------------------------------------------------------------
  IScriptHelper = interface
    ['{B6A1F3C2-4D2E-4F8A-9C3B-7E1D2A5F8C40}']
    function CompileProject(
        const AWorkspaceDir, AManifestName, AProjectFileName: string;
        const AOptions: ICompilerOptions
    ): string;
    function HasCompiler(const APlatform: string): Boolean;
    /// <summary>Registers an IDE expert (a compiled <c>.dll</c>) so the IDE loads it on start.</summary>
    /// <param name="AExpertPath">Full path to the expert <c>.dll</c>.</param>
    /// <param name="AName">Registry value name to register the expert under.</param>
    /// <param name="APlatform">IDE platform the expert targets (<c>Win32</c> or <c>Win64</c>).</param>
    procedure RegisterExpert(const AExpertPath, AName, APlatform: string);
  end;

  TScriptCommand = class;
  TScriptCommandClass = class of TScriptCommand;

  // -----------------------------------------------------------------------
  // Base class for a built-in script command (echo, copy, copyres, ...).
  // Derive from this, override Run, and register the subclass with
  // RegisterCommand so a manifest script can invoke it by name. A command may
  // optionally be bound to a set of events; when bound, using it under any other
  // event raises EScriptError.
  // -----------------------------------------------------------------------
  TScriptCommand = class
  strict private
    type
      TRegistration = record
        CommandClass: TScriptCommandClass;
        // Events the command may run for; empty means it is valid for any event.
        Events: TArray<string>;
      end;
    class var
      FRegistry: TDictionary<string, TRegistration>;
    class function FindRegistration(const AName: string; out ARegistration: TRegistration): Boolean;
    constructor InnerCreate;
  public
    class constructor Create;
    class destructor Destroy;

    /// <summary>Registers a command class under <paramref name="AName"/> (case-insensitive),
    ///   valid for any event.</summary>
    class procedure RegisterCommand(const AName: string; AClass: TScriptCommandClass); overload;
    /// <summary>Registers a command class bound to a set of events.</summary>
    /// <param name="AEvents">Events the command may run for; pass <c>[]</c> for any event.</param>
    class procedure RegisterCommand(
        const AName: string;
        AClass: TScriptCommandClass;
        const AEvents: array of string
    ); overload;
    /// <summary>Returns a new instance of the command registered under <paramref name="AName"/>.</summary>
    /// <exception cref="EScriptError">Raised when no command matches the name.</exception>
    class function Create(const AName: string): TScriptCommand;
    /// <summary>Raises <c>EScriptError</c> when <paramref name="AName"/> is registered but not
    ///   allowed for <paramref name="AEvent"/>. Unknown commands and commands bound to no event
    ///   pass through (an unknown name is reported by <see cref="Create"/>).</summary>
    class procedure ValidateEvent(const AName, AEvent: string);

    /// <summary>Runs the command.</summary>
    /// <param name="AHelper">Host services (e.g. compilation); may be <c>nil</c> when
    ///   the firing event provides none. Commands that need it must guard.</param>
    /// <param name="AManifest">The owning manifest, for commands that inspect it.</param>
    /// <param name="AArgs">Typed script args (the right subclass for this command).
    ///   Not pre-expanded: each command expands the <c>$(VAR)</c> macros in the fields
    ///   it actually uses against <paramref name="AEnvironmentVariables"/>.</param>
    /// <param name="AEnvironmentVariables">The event variables (name=value pairs).</param>
    /// <param name="AConfig">Workspace configuration; may be <c>nil</c>. Commands that build
    ///   a project read the tool architecture from it. Commands that need it must guard.</param>
    procedure Run(
        AHelper: IScriptHelper;
        AManifest: TManifest;
        AArgs: TManifestScriptArguments;
        AEnvironmentVariables: TStrings;
        AConfig: TConfig
    ); virtual; abstract;
  end;

  // -----------------------------------------------------------------------
  // Built-in command: prints its message arg (after $(VAR) expansion) to the
  // console. Valid for any event.
  // -----------------------------------------------------------------------
  [ScriptManifest(TManifestEchoArguments)]
  TEchoCommand = class(TScriptCommand)
  public
    procedure Run(
        AHelper: IScriptHelper;
        AManifest: TManifest;
        AArgs: TManifestScriptArguments;
        AEnvironmentVariables: TStrings;
        AConfig: TConfig
    ); override;
  end;

  // -----------------------------------------------------------------------
  // Built-in command (install events): compiles the project given by
  // args.projectFile (resolved against $(PROJECT_PATH) when relative), always in
  // Release. args.platforms lists the platforms to build (only those whose
  // compiler is installed; default Win32). Requires a compiler, supplied through
  // IScriptHelper. The compile loop calls AfterPlatformCompiled after each
  // successful platform; subclasses override it to add post-build steps.
  // -----------------------------------------------------------------------
  [ScriptManifest(TManifestCompileArguments)]
  TCompileCommand = class(TScriptCommand)
  protected
    /// <summary>Hook run after a platform is successfully compiled. Base: no-op.</summary>
    /// <param name="AProjectFile">Resolved full path of the compiled <c>.dproj</c>.</param>
    procedure AfterPlatformCompiled(
        AHelper: IScriptHelper;
        AManifest: TManifest;
        AArgs: TManifestScriptArguments;
        const AProjectFile, AWorkspaceDir, APlatform: string
    ); virtual;
  public
    procedure Run(
        AHelper: IScriptHelper;
        AManifest: TManifest;
        AArgs: TManifestScriptArguments;
        AEnvironmentVariables: TStrings;
        AConfig: TConfig
    ); override;
  end;

  // -----------------------------------------------------------------------
  // Built-in command (install events): same arguments and build behaviour as
  // "compile", but each compiled platform's output is treated as an IDE expert
  // .dll and registered via IScriptHelper, so the IDE loads it on next start.
  // -----------------------------------------------------------------------
  [ScriptManifest(TManifestExpertArguments)]
  TExpertCommand = class(TCompileCommand)
  protected
    procedure AfterPlatformCompiled(
        AHelper: IScriptHelper;
        AManifest: TManifest;
        AArgs: TManifestScriptArguments;
        const AProjectFile, AWorkspaceDir, APlatform: string
    ); override;
  end;

  // -----------------------------------------------------------------------
  // Built-in command (afterCompile): copies every .res and .dfm found under the
  // current platform's source paths into $(DCU_PATH), so the compiled DCUs sit next
  // to their resources. Bound to afterCompile, where $(DCU_PATH) is defined.
  // -----------------------------------------------------------------------
  [ScriptManifest(TManifestNoArguments)]
  TCopyResCommand = class(TScriptCommand)
  public
    procedure Run(
        AHelper: IScriptHelper;
        AManifest: TManifest;
        AArgs: TManifestScriptArguments;
        AEnvironmentVariables: TStrings;
        AConfig: TConfig
    ); override;
  end;

  // -----------------------------------------------------------------------
  // Runs manifest scripts by resolving each one to a registered TScriptCommand
  // -----------------------------------------------------------------------
  TScriptRunner = class
  public
    const
      // Lifecycle events a manifest script can hook into. Compile events fire once
      // per package (per platform/config); install/uninstall events fire once per
      // manifest.
      EventBeforeCompile = 'beforeCompile';
      EventAfterCompile = 'afterCompile';
      EventBeforeInstall = 'beforeInstall';
      EventAfterInstall = 'afterInstall';
      EventBeforeUninstall = 'beforeUninstall';
      EventAfterUninstall = 'afterUninstall';
  public
    /// <summary>Runs a single manifest script: expands the <c>$(VAR)</c> macros on the
    ///   command name, resolves the command by name and runs it. The command expands
    ///   the macros in its own typed args.</summary>
    /// <param name="AManifest">The owning manifest, made available to the command
    ///   (e.g. to inspect packages or platforms).</param>
    /// <param name="AScript">The script configuration to execute.</param>
    /// <param name="AEnvironmentVariables">name=value pairs holding the variables
    ///   that are meaningful for the current event.</param>
    /// <param name="AHelper">Host services forwarded to the command (may be <c>nil</c>).</param>
    /// <exception cref="EScriptError">Raised when the command name is unknown, or when the
    ///   command is bound to a set of events that does not include the script's event.</exception>
    class procedure Execute(
        AManifest: TManifest;
        AScript: TManifestScript;
        AEnvironmentVariables: TStrings;
        AHelper: IScriptHelper = nil;
        AConfig: TConfig = nil
    ); static;

    /// <summary>Runs, in declaration order, every manifest script registered for
    ///   <paramref name="AEvent"/>.</summary>
    /// <param name="AManifest">Manifest whose <c>Scripts</c> are scanned.</param>
    /// <param name="AEvent">Event name to match (see the <c>Event*</c> constants).</param>
    /// <param name="AEnvironmentVariables">Variables meaningful for this event; the
    ///   caller builds the set appropriate to the event.</param>
    /// <param name="AHelper">Host services forwarded to each command (may be <c>nil</c>).</param>
    class procedure RunEvent(
        AManifest: TManifest;
        const AEvent: string;
        AEnvironmentVariables: TStrings;
        AHelper: IScriptHelper = nil;
        AConfig: TConfig = nil
    ); static;
  end;

procedure RegisterScripts;

implementation

uses
  System.IOUtils,
  Blocks.Core,
  Blocks.Console;

{ TCompilerOptions }

class function TCompilerOptions.New: ICompilerOptions;
begin
  Result := TCompilerOptions.Create;
end;

function TCompilerOptions.GetPlatform: string;
begin
  Result := FPlatform;
end;

function TCompilerOptions.GetConfig: string;
begin
  Result := FConfig;
end;

function TCompilerOptions.GetToolArchitecture: TToolArchitecture;
begin
  Result := FToolArchitecture;
end;

function TCompilerOptions.SetPlatform(const AValue: string): ICompilerOptions;
begin
  FPlatform := AValue;
  Result := Self;
end;

function TCompilerOptions.SetConfig(const AValue: string): ICompilerOptions;
begin
  FConfig := AValue;
  Result := Self;
end;

function TCompilerOptions.SetToolArchitecture(const AValue: TToolArchitecture): ICompilerOptions;
begin
  FToolArchitecture := AValue;
  Result := Self;
end;

{ TScriptCommand }

class constructor TScriptCommand.Create;
begin
  FRegistry := TDictionary<string, TRegistration>.Create;
end;

class destructor TScriptCommand.Destroy;
begin
  FRegistry.Free;
end;

constructor TScriptCommand.InnerCreate;
begin
  inherited Create;
end;

class procedure TScriptCommand.RegisterCommand(const AName: string; AClass: TScriptCommandClass);
begin
  RegisterCommand(AName, AClass, []);
end;

class procedure TScriptCommand.RegisterCommand(
    const AName: string;
    AClass: TScriptCommandClass;
    const AEvents: array of string
);
begin
  var LRegistration: TRegistration;
  LRegistration.CommandClass := AClass;
  SetLength(LRegistration.Events, Length(AEvents));
  for var I := 0 to High(AEvents) do
    LRegistration.Events[I] := AEvents[I];
  FRegistry.AddOrSetValue(AName, LRegistration);

  // Keep the model-side args registry in sync from this same call (both
  // overloads funnel here): the [ScriptManifest(...)] attribute pairs the
  // command with the class that decodes its "args".
  var LRttiContext := TRttiContext.Create;
  try
    var LRttiType := LRttiContext.GetType(AClass);
    if LRttiType.HasAttribute(ScriptManifestAttribute) then
      TManifest.RegisterScriptManifest(AName, LRttiType.GetAttribute<ScriptManifestAttribute>.ManifestArgumentsClass);
  finally
    LRttiContext.Free;
  end;
end;

class function TScriptCommand.FindRegistration(const AName: string; out ARegistration: TRegistration): Boolean;
begin
  for var LPair in FRegistry do
    if SameText(LPair.Key, AName) then
    begin
      ARegistration := LPair.Value;
      Exit(True);
    end;
  Result := False;
end;

class function TScriptCommand.Create(const AName: string): TScriptCommand;
begin
  var LRegistration: TRegistration;
  if not FindRegistration(AName, LRegistration) then
    raise EScriptError.CreateFmt('Unknown script command: "%s"', [AName]);
  Result := LRegistration.CommandClass.InnerCreate;
end;

class procedure TScriptCommand.ValidateEvent(const AName, AEvent: string);
begin
  var LRegistration: TRegistration;
  if not FindRegistration(AName, LRegistration) then
    Exit; // Unknown command: Create reports it.
  if Length(LRegistration.Events) = 0 then
    Exit; // Not bound to any event: valid everywhere.

  for var LEvent in LRegistration.Events do
    if SameText(LEvent, AEvent) then
      Exit;

  raise EScriptError.CreateFmt(
      'Command "%s" is not allowed for event "%s" (allowed: %s)',
      [AName, AEvent, string.Join(', ', LRegistration.Events)]);
end;

{ TEchoCommand }

procedure TEchoCommand.Run(
    AHelper: IScriptHelper;
    AManifest: TManifest;
    AArgs: TManifestScriptArguments;
    AEnvironmentVariables: TStrings;
    AConfig: TConfig
);
begin
  var LMessagePattern := AArgs.GetAs<TManifestEchoArguments>().Message;
  var LMessage := ExpandVariables(LMessagePattern, AEnvironmentVariables);
  TConsole.WriteLine(LMessage);
end;

{ TCompileCommand }

procedure TCompileCommand.AfterPlatformCompiled(
    AHelper: IScriptHelper;
    AManifest: TManifest;
    AArgs: TManifestScriptArguments;
    const AProjectFile, AWorkspaceDir, APlatform: string
);
begin
  // Base command only compiles; nothing to do after a platform builds.
end;

procedure TCompileCommand.Run(
    AHelper: IScriptHelper;
    AManifest: TManifest;
    AArgs: TManifestScriptArguments;
    AEnvironmentVariables: TStrings;
    AConfig: TConfig
);
begin
  var LCompileArgs := AArgs.GetAs<TManifestCompileArguments>;

  var LProjectFile := ExpandVariables(LCompileArgs.ProjectFile, AEnvironmentVariables);
  if LProjectFile = '' then
    raise EScriptError.Create('compile: missing project file argument');
  if AHelper = nil then
    raise EScriptError.Create('compile: no compiler available for this event');

  // The path is relative to the extracted project; $(PROJECT_PATH) is exposed for
  // install events. Absolute paths are honoured as given.
  var LProjectPath := AEnvironmentVariables.Values['PROJECT_PATH'];
  if TPath.IsRelativePath(LProjectFile) and (LProjectPath <> '') then
    LProjectFile := TPath.Combine(LProjectPath, LProjectFile);

  if not TFile.Exists(LProjectFile) then
    raise EScriptError.CreateFmt('compile: project file not found: "%s"', [LProjectFile]);

  var LWorkspace := AEnvironmentVariables.Values['WORKSPACE_PATH'];

  var LPlatforms := LCompileArgs.Platforms;
  if Length(LPlatforms) = 0 then
    LPlatforms := ['Win32'];

  // Experts target the design-time IDE: a Release build is what gets registered.
  var LConfig := 'Release';

  // Build every requested platform whose compiler is actually installed; skip
  // the rest so a manifest listing more platforms than the IDE has stays usable.
  var LCompiled := False;
  for var LPlatform in LPlatforms do
  begin
    if not AHelper.HasCompiler(LPlatform) then
    begin
      TConsole.WriteWarning(Format('  compile: skipping %s (compiler not installed)', [LPlatform]));
      Continue;
    end;

    TConsole.Write(Format('  Compiling %s [%s/%s]...', [TPath.GetFileName(LProjectFile), LConfig, LPlatform]));
    var LToolArch := TToolArchitecture.default;
    if AConfig <> nil then
      LToolArch := AConfig.ToolArchitecture;

    AHelper.CompileProject(
        LWorkspace,
        AManifest.Name,
        LProjectFile,
        TCompilerOptions.New
          .SetConfig(LConfig)
          .SetPlatform(LPlatform)
          .SetToolArchitecture(LToolArch)
    );
    TConsole.WriteLine(' OK', clGreen);
    LCompiled := True;

    AfterPlatformCompiled(AHelper, AManifest, AArgs, LProjectFile, LWorkspace, LPlatform);
  end;

  if not LCompiled then
    raise EScriptError.CreateFmt(
        'compile: none of the requested platforms (%s) has a compiler installed',
        [string.Join(', ', LPlatforms)]);
end;

{ TExpertCommand }

procedure TExpertCommand.AfterPlatformCompiled(
    AHelper: IScriptHelper;
    AManifest: TManifest;
    AArgs: TManifestScriptArguments;
    const AProjectFile, AWorkspaceDir, APlatform: string
);
begin
  var LDescription := AArgs.GetAs<TManifestExpertArguments>.Description;

  // The expert .dll lands in the DCU output dir (DCC_ExeOutput mirrors it):
  // <workspace>\.blocks\lib\<manifest name>\<platform>, named after the .dproj.
  var LExpertDll :=
      TPath.Combine(
          [
              AWorkspaceDir,
              '.blocks',
              'lib',
              AManifest.Name,
              APlatform,
              TPath.GetFileNameWithoutExtension(AProjectFile) + '.dll'
          ]
      );
  TConsole.Write(Format('  Registering expert %s [%s]...', [TPath.GetFileName(LExpertDll), APlatform]));
  if LDescription = '' then
    LDescription := TPath.GetFileName(LExpertDll);

  AHelper.RegisterExpert(LExpertDll, LDescription, APlatform);
end;

{ TCopyResCommand }

procedure TCopyResCommand.Run(
    AHelper: IScriptHelper;
    AManifest: TManifest;
    AArgs: TManifestScriptArguments;
    AEnvironmentVariables: TStrings;
    AConfig: TConfig
);
begin
  var LPlatform := AEnvironmentVariables.Values['PLATFORM'];
  var LProjectPath := AEnvironmentVariables.Values['PROJECT_PATH'];
  var LDcuPath := AEnvironmentVariables.Values['DCU_PATH'];

  if LDcuPath = '' then
    raise EScriptError.Create('copyres: $(DCU_PATH) is not set');

  // Source paths are declared per platform; nothing to do if this platform is absent.
  var LPlatformManifest: TManifestPlatform;
  if not AManifest.Platforms.TryGetValue(LPlatform, LPlatformManifest) then
    Exit;

  if not TDirectory.Exists(LDcuPath) then
    TDirectory.CreateDirectory(LDcuPath);

  var LPatterns := ['*.res', '*.dfm', '*.fmx'];

  for var LSource in LPlatformManifest.SourcePath do
  begin
    var LSourceDir := LSource;
    if TPath.IsRelativePath(LSourceDir) then
      LSourceDir := TPath.Combine(LProjectPath, LSourceDir);

    if not TDirectory.Exists(LSourceDir) then
      Continue;

    for var LPattern in LPatterns do
      for var LFile in TDirectory.GetFiles(LSourceDir, LPattern, TSearchOption.soAllDirectories) do
        TFile.Copy(LFile, TPath.Combine(LDcuPath, TPath.GetFileName(LFile)), True);
  end;
end;

{ TScriptRunner }

class procedure TScriptRunner.Execute(
    AManifest: TManifest;
    AScript: TManifestScript;
    AEnvironmentVariables: TStrings;
    AHelper: IScriptHelper;
    AConfig: TConfig
);
begin
  var LCommandName := ExpandVariables(AScript.Command, AEnvironmentVariables);

  // Reject commands that declare a set of events they support but exclude this one.
  TScriptCommand.ValidateEvent(LCommandName, AScript.Event);

  var LCommand := TScriptCommand.Create(LCommandName);
  try
    LCommand.Run(AHelper, AManifest, AScript.Args, AEnvironmentVariables, AConfig);
  finally
    LCommand.Free;
  end;
end;

class procedure TScriptRunner.RunEvent(
    AManifest: TManifest;
    const AEvent: string;
    AEnvironmentVariables: TStrings;
    AHelper: IScriptHelper;
    AConfig: TConfig
);
begin
  for var LScript in AManifest.Scripts do
    if SameText(LScript.Event, AEvent) then
      Execute(AManifest, LScript, AEnvironmentVariables, AHelper, AConfig);
end;

procedure RegisterScripts;
begin
  TScriptCommand.RegisterCommand('echo', TEchoCommand);
  TScriptCommand.RegisterCommand('copyres', TCopyResCommand, [TScriptRunner.EventAfterCompile]);
  TScriptCommand
      .RegisterCommand('compile', TCompileCommand, [TScriptRunner.EventBeforeInstall, TScriptRunner.EventAfterInstall]);
  TScriptCommand
      .RegisterCommand('expert', TExpertCommand, [TScriptRunner.EventBeforeInstall, TScriptRunner.EventAfterInstall]);
end;

{ ScriptManifestAttribute }

constructor ScriptManifestAttribute.Create(AManifestArgumentsClass: TManifestScriptArgumentsClass);
begin
  inherited Create;
  FManifestArgumentsClass := AManifestArgumentsClass;
end;

end.
