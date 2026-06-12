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
  System.Generics.Collections,
  Blocks.Model.Manifest;

type
  EScriptError = class(Exception)
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
    function CompileProject(const AWorkspaceDir, AManifestName, AProjectFileName, AConfig, APlatform: string): string;
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
    /// <param name="AArgs">The script args, already <c>%VAR%</c>-expanded.</param>
    /// <param name="AEnvironmentVariables">The event variables (name=value pairs).</param>
    procedure Run(
        AHelper: IScriptHelper;
        AManifest: TManifest;
        AArgs, AEnvironmentVariables: TStrings
    ); virtual; abstract;
  end;

  // -----------------------------------------------------------------------
  // Built-in command: prints the (already expanded) args as one line.
  // -----------------------------------------------------------------------
  TEchoCommand = class(TScriptCommand)
  public
    procedure Run(AHelper: IScriptHelper; AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings); override;
  end;

  // -----------------------------------------------------------------------
  // Built-in command (install events): compiles the project named by its first
  // argument (resolved against %PROJECT_PATH% when relative), always in Release.
  // A "/p:plat1,plat2" option lists the platforms to build (every one whose
  // compiler is installed; default Win32). Requires a compiler, supplied through
  // IScriptHelper. The compile loop calls AfterPlatformCompiled after each
  // successful platform; subclasses override it to add post-build steps.
  // -----------------------------------------------------------------------
  TCompileCommand = class(TScriptCommand)
  protected
    /// <summary>Hook run after a platform is successfully compiled. Base: no-op.</summary>
    /// <param name="AProjectFile">Resolved full path of the compiled <c>.dproj</c>.</param>
    procedure AfterPlatformCompiled(
        AHelper: IScriptHelper;
        AManifest: TManifest;
        const AProjectFile, AWorkspaceDir, APlatform: string
    ); virtual;
  public
    procedure Run(AHelper: IScriptHelper; AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings); override;
  end;

  // -----------------------------------------------------------------------
  // Built-in command (install events): same arguments and build behaviour as
  // "compile", but each compiled platform's output is treated as an IDE expert
  // .dll and registered via IScriptHelper, so the IDE loads it on next start.
  // -----------------------------------------------------------------------
  TExpertCommand = class(TCompileCommand)
  protected
    procedure AfterPlatformCompiled(
        AHelper: IScriptHelper;
        AManifest: TManifest;
        const AProjectFile, AWorkspaceDir, APlatform: string
    ); override;
  end;

  // -----------------------------------------------------------------------
  // Built-in command (afterCompile): copies every .res and .dfm found under the
  // current platform's source paths into %DCU_PATH%, so the compiled DCUs sit next
  // to their resources. Bound to afterCompile, where %DCU_PATH% is defined.
  // -----------------------------------------------------------------------
  TCopyResCommand = class(TScriptCommand)
  public
    procedure Run(AHelper: IScriptHelper; AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings); override;
  end;

  // -----------------------------------------------------------------------
  // Runs manifest scripts by resolving each one to a registered TScriptCommand
  // -----------------------------------------------------------------------
  TScriptRunner = class
  private
    /// <summary>Expands <c>%VAR%</c> macros using <paramref name="AEnvironmentVariables"/>.
    ///   Unknown variables resolve to an empty string.</summary>
    class function ExpandVariables(const AValue: string; AEnvironmentVariables: TStrings): string; static;
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
    /// <summary>Runs a single manifest script: expands the <c>%VAR%</c> macros on
    ///   command and args, resolves the command by name and runs it.</summary>
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
        AHelper: IScriptHelper = nil
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
        AHelper: IScriptHelper = nil
    ); static;
  end;

implementation

uses
  System.IOUtils,
  System.RegularExpressions,
  Blocks.Core,
  Blocks.Console;

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

procedure TEchoCommand.Run(AHelper: IScriptHelper; AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings);
begin
  // The args are already %VAR%-expanded by TScriptRunner; join them into one message.
  TConsole.WriteLine(string.Join(' ', AArgs.ToStringArray));
end;

{ TCompileCommand }

procedure TCompileCommand.AfterPlatformCompiled(
    AHelper: IScriptHelper;
    AManifest: TManifest;
    const AProjectFile, AWorkspaceDir, APlatform: string
);
begin
  // Base command only compiles; nothing to do after a platform builds.
end;

procedure TCompileCommand.Run(AHelper: IScriptHelper; AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings);
begin
  if AArgs.Count < 1 then
    raise EScriptError.Create('compile: missing project file argument');
  if AHelper = nil then
    raise EScriptError.Create('compile: no compiler available for this event');

  var LProjectFile := AArgs[0];
  // The path is relative to the extracted project; %PROJECT_PATH% is exposed for
  // install events. Absolute paths are honoured as given.
  var LProjectPath := AEnvironmentVariables.Values['PROJECT_PATH'];
  if TPath.IsRelativePath(LProjectFile) and (LProjectPath <> '') then
    LProjectFile := TPath.Combine(LProjectPath, LProjectFile);

  if not TFile.Exists(LProjectFile) then
    raise EScriptError.CreateFmt('compile: project file not found: "%s"', [LProjectFile]);

  var LWorkspace := AEnvironmentVariables.Values['WORKSPACE_PATH'];

  // Platforms come from a "/p:plat1,plat2" option (e.g. "/p:win32,win64");
  // with none given, default to Win32 (the usual target for an IDE expert).
  var LPlatforms: TArray<string> := [];
  for var I := 1 to AArgs.Count - 1 do
    if AArgs[I].StartsWith('/p:', True) then
      for var LPlat in AArgs[I].Substring(3).Split([',']) do
        if LPlat.Trim <> '' then
          LPlatforms := LPlatforms + [LPlat.Trim];
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
    AHelper.CompileProject(LWorkspace, AManifest.Name, LProjectFile, LConfig, LPlatform);
    TConsole.WriteLine(' OK', clGreen);
    LCompiled := True;

    AfterPlatformCompiled(AHelper, AManifest, LProjectFile, LWorkspace, LPlatform);
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
    const AProjectFile, AWorkspaceDir, APlatform: string
);
begin
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
  AHelper.RegisterExpert(LExpertDll, TPath.GetFileName(LExpertDll), APlatform);
end;

{ TCopyResCommand }

procedure TCopyResCommand.Run(AHelper: IScriptHelper; AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings);
begin
  var LPlatform := AEnvironmentVariables.Values['PLATFORM'];
  var LProjectPath := AEnvironmentVariables.Values['PROJECT_PATH'];
  var LDcuPath := AEnvironmentVariables.Values['DCU_PATH'];

  if LDcuPath = '' then
    raise EScriptError.Create('copyres: %DCU_PATH% is not set');

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

class function TScriptRunner.ExpandVariables(const AValue: string; AEnvironmentVariables: TStrings): string;
begin
  Result :=
      RegExReplace(
          AValue,
          '%([^%]+)%',
          function(const AMatch: TMatch): string
          begin
            // Unknown variables resolve to '' — same convention as ExpandMacros.
            Result := AEnvironmentVariables.Values[AMatch.Groups[1].Value];
          end
      );
end;

class procedure TScriptRunner.Execute(
    AManifest: TManifest;
    AScript: TManifestScript;
    AEnvironmentVariables: TStrings;
    AHelper: IScriptHelper
);
begin
  var LCommandName := ExpandVariables(AScript.Command, AEnvironmentVariables);

  var LArgs := TStringList.Create;
  try
    for var LArg in AScript.Args do
      LArgs.Add(ExpandVariables(LArg, AEnvironmentVariables));

    // Reject commands that declare a set of events they support but exclude this one.
    TScriptCommand.ValidateEvent(LCommandName, AScript.Event);

    var LCommand := TScriptCommand.Create(LCommandName);
    try
      LCommand.Run(AHelper, AManifest, LArgs, AEnvironmentVariables);
    finally
      LCommand.Free;
    end;
  finally
    LArgs.Free;
  end;
end;

class procedure TScriptRunner.RunEvent(
    AManifest: TManifest;
    const AEvent: string;
    AEnvironmentVariables: TStrings;
    AHelper: IScriptHelper
);
begin
  for var LScript in AManifest.Scripts do
    if SameText(LScript.Event, AEvent) then
      Execute(AManifest, LScript, AEnvironmentVariables, AHelper);
end;

initialization
  TScriptCommand.RegisterCommand('echo', TEchoCommand);
  TScriptCommand.RegisterCommand('copyres', TCopyResCommand, [TScriptRunner.EventAfterCompile]);
  TScriptCommand
      .RegisterCommand('compile', TCompileCommand, [TScriptRunner.EventBeforeInstall, TScriptRunner.EventAfterInstall]);
  TScriptCommand
      .RegisterCommand('expert', TExpertCommand, [TScriptRunner.EventBeforeInstall, TScriptRunner.EventAfterInstall]);

end.
