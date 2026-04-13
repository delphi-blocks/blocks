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
unit Blocks.Command;

interface

uses
  System.Classes, System.SysUtils, System.Rtti, System.TypInfo, System.IOUtils,
  System.Generics.Collections;

type
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
    class function FindCommand(const ACommandName: string): TCommandClass;
    constructor InnerCreate;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>
    ///   Registers a command class under a given name in the global registry.
    ///   If ADefault is True, the class also becomes the fallback command when
    ///   no matching name is found.
    /// </summary>
    class procedure RegisterCommand(const AName: string; AClass: TCommandClass; ADefault: Boolean = False);
    /// <summary>
    ///   Looks up ACommandName in the registry and returns a new instance of
    ///   the matching command class. Falls back to the default command (if any)
    ///   when the name is not found; aborts if no default is registered.
    /// </summary>
    class function Create(const ACommandName: string): TCommand;
    /// <summary>
    ///   Parses the process command-line arguments (starting at index 2) and
    ///   injects their values into fields of ACommand that carry a
    ///   [Param] attribute. Syntax example:
    ///
    ///     blocks install /verbose /product package.name
    ///
    ///   Field mapping:
    ///     [Param('verbose')] FVerbose: Boolean;    // /verbose sets it to True
    ///     [Param('product')] FProduct: string;     // /product reads next arg
    ///     [Param]            FPackageName: string; // unnamed param (one only)
    /// </summary>
    class procedure InjectArgs(ACommand: TCommand);
  public
    /// <summary>
    ///   Executes the command. The base implementation calls InjectArgs to
    ///   populate fields before subclass logic runs.
    /// </summary>
    procedure Execute; virtual;
    /// <summary>
    ///   Displays usage information for the command.
    /// </summary>
    procedure ShowHelp; virtual;
  end;

implementation

uses
  Blocks.Console;

{ TCommand }

class constructor TCommand.Create;
begin
  FRegistry := TDictionary<string, TCommandClass>.Create;
  FContext := TRttiContext.Create;
end;

class function TCommand.Create(const ACommandName: string): TCommand;
begin
  var LCommandClass: TCommandClass;
  if ACommandName = '' then
  begin
    LCommandClass := FDefaultCommand;
  end
  else
  begin
    LCommandClass := FindCommand(ACommandName);
    if not Assigned(LCommandClass) then
    begin
      TConsole.WriteError(Format('Command "%s" not found', [ACommandName]));
      LCommandClass := FDefaultCommand;
    end;
  end;

  if not Assigned(LCommandClass) then
    Abort;

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

class function TCommand.FindCommand(const ACommandName: string): TCommandClass;
begin
  Result := nil;

  for var LPair in FRegistry do
  begin
    if SameText(LPair.Key, ACommandName) then
    begin
      Exit(LPair.Value);
    end;
  end;
  Exit;
end;

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
    else if LField.DataType.TypeKind = tkDynArray then
    begin
      if not LUnnamedParam then
        raise Exception.Create('Array type supported only for unnamed paramers');
      var LArray := LField.GetValue(ACommand).AsType<TArray<string>>;
      LArray := LArray + [ParamStr(I)];
      LField.SetValue(ACommand, TValue.From(LArray));
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

procedure TCommand.ShowHelp;
begin

end;

{ ParamAttribute }

constructor ParamAttribute.Create(const AParamName: string);
begin
  inherited Create;
  FParamName := AParamName;
end;

end.
