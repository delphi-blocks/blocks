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
unit Blocks.CLI.Command;

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

  IParamReader = interface
    ['{B00B4F44-FA9E-4F7D-AA20-B9F3AC8F6EE9}']
    function ParamCount: Integer;
    function ParamStr(I: Integer): string;
  end;

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
    class procedure InjectArgs(ACommand: TCommand); overload;
    class procedure InjectArgs(ACommand: TCommand; AParams: IParamReader); overload;
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

  TCommandLineParamReader = class(TInterfacedObject, IParamReader)
  public
    { IParamReader }
    function ParamCount: Integer;
    function ParamStr(I: Integer): string;
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
begin
  TCommand.InjectArgs(ACommand, TCommandLineParamReader.Create);
end;

class procedure TCommand.InjectArgs(ACommand: TCommand; AParams: IParamReader);

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
  while I <= AParams.ParamCount do
  begin
    var LField := FindClassFieldByParamName(AParams.ParamStr(I), LUnnamedParam);
    if LField.DataType.TypeKind = tkEnumeration then
    begin
      if LField.FieldType.Handle = TypeInfo(Boolean) then
        LField.SetValue(ACommand, True)
      else
      begin
        if not LUnnamedParam then
          Inc(I);
        var LEnumName := AParams.ParamStr(I);
        var LEnumOrd := GetEnumValue(LField.FieldType.Handle, LEnumName);
        if LEnumOrd < 0 then
          raise Exception.CreateFmt('Invalid value "%s" for param', [LEnumName]);
        LField.SetValue(ACommand, TValue.FromOrdinal(LField.FieldType.Handle, LEnumOrd));
      end;
    end
    else if LField.DataType.TypeKind = tkUString then
    begin
      if not LUnnamedParam then
        Inc(I);
      LField.SetValue(ACommand, AParams.ParamStr(I));
    end
    else if LField.DataType.TypeKind = tkInteger then
    begin
      if not LUnnamedParam then
        Inc(I);
      LField.SetValue(ACommand, StrToInt(AParams.ParamStr(I)));
    end
    else if LField.DataType.TypeKind = tkFloat then
    begin
      if not LUnnamedParam then
        Inc(I);
      LField.SetValue(ACommand, StrToFloat(AParams.ParamStr(I), TFormatSettings.Invariant));
    end
    else if LField.DataType.TypeKind = tkDynArray then
    begin
      if not LUnnamedParam then
        raise Exception.Create('Array type supported only for unnamed paramers');
      if (LField.FieldType as TRttiDynamicArrayType).ElementType.TypeKind not in [tkUString, tkString, tkWString] then
        raise Exception.Create('Array type should be of type string');

      var LArray := LField.GetValue(ACommand).AsType<TArray<string>>;
      LArray := LArray + [AParams.ParamStr(I)];
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

{ TCommandLineParamReader }

function TCommandLineParamReader.ParamCount: Integer;
begin
  Result := System.ParamCount;
end;

function TCommandLineParamReader.ParamStr(I: Integer): string;
begin
  Result := System.ParamStr(I);
end;

end.
