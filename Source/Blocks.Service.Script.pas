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
    /// <param name="AManifest">The owning manifest, for commands that inspect it.</param>
    /// <param name="AArgs">The script args, already <c>%VAR%</c>-expanded.</param>
    /// <param name="AEnvironmentVariables">The event variables (name=value pairs).</param>
    procedure Run(AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings); virtual; abstract;
  end;

  // -----------------------------------------------------------------------
  // Built-in command: prints the (already expanded) args as one line.
  // -----------------------------------------------------------------------
  TEchoCommand = class(TScriptCommand)
  public
    procedure Run(AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings); override;
  end;

  // -----------------------------------------------------------------------
  // Built-in command (afterCompile): copies every .res and .dfm found under the
  // current platform's source paths into %DCU_PATH%, so the compiled DCUs sit next
  // to their resources. Bound to afterCompile, where %DCU_PATH% is defined.
  // -----------------------------------------------------------------------
  TCopyResCommand = class(TScriptCommand)
  public
    procedure Run(AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings); override;
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
    /// <exception cref="EScriptError">Raised when the command name is unknown, or when the
    ///   command is bound to a set of events that does not include the script's event.</exception>
    class procedure Execute(AManifest: TManifest; AScript: TManifestScript; AEnvironmentVariables: TStrings); static;

    /// <summary>Runs, in declaration order, every manifest script registered for
    ///   <paramref name="AEvent"/>.</summary>
    /// <param name="AManifest">Manifest whose <c>Scripts</c> are scanned.</param>
    /// <param name="AEvent">Event name to match (see the <c>Event*</c> constants).</param>
    /// <param name="AEnvironmentVariables">Variables meaningful for this event; the
    ///   caller builds the set appropriate to the event.</param>
    class procedure RunEvent(AManifest: TManifest; const AEvent: string; AEnvironmentVariables: TStrings); static;
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

procedure TEchoCommand.Run(AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings);
begin
  // The args are already %VAR%-expanded by TScriptRunner; join them into one message.
  TConsole.WriteLine(string.Join(' ', AArgs.ToStringArray));
end;

{ TCopyResCommand }

procedure TCopyResCommand.Run(AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings);
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

class procedure TScriptRunner.Execute(AManifest: TManifest; AScript: TManifestScript; AEnvironmentVariables: TStrings);
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
      LCommand.Run(AManifest, LArgs, AEnvironmentVariables);
    finally
      LCommand.Free;
    end;
  finally
    LArgs.Free;
  end;
end;

class procedure TScriptRunner.RunEvent(AManifest: TManifest; const AEvent: string; AEnvironmentVariables: TStrings);
begin
  for var LScript in AManifest.Scripts do
    if SameText(LScript.Event, AEvent) then
      Execute(AManifest, LScript, AEnvironmentVariables);
end;

initialization
  TScriptCommand.RegisterCommand('echo', TEchoCommand);
  TScriptCommand.RegisterCommand('copyres', TCopyResCommand, [TScriptRunner.EventAfterCompile]);

end.
