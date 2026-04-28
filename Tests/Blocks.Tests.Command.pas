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
unit Blocks.Tests.Command;

interface


uses
  System.SysUtils,
  DUnitX.TestFramework,

  Blocks.CLI.Command;

type
  [TestFixture]
  TCommandTest = class(TObject)
  private
    function CreateCommand<T: TCommand>(const ACommandLine: string): T;
  public
    [Test]
    procedure TestSingleNamedParam;
    [Test]
    procedure TestBooleanFlagPresent;
    [Test]
    procedure TestBooleanFlagAbsent;
    [Test]
    procedure TestNamedStringParam;
    [Test]
    procedure TestMixedFlagsAndUnnamed;
    [Test]
    procedure TestArrayUnnamedParam;
    [Test]
    procedure TestUnknownFlagRaises;
    [Test]
    procedure TestNamedIntegerParam;
    [Test]
    procedure TestNamedDoubleParam;
    [Test]
    procedure TestNamedEnumParam;
    [Test]
    procedure TestNamedEnumParamCaseInsensitive;
    [Test]
    procedure TestInvalidEnumValueRaises;
  end;

  TStringParamReader = class(TInterfacedObject, IParamReader)
  private
    FParams: TArray<string>;
  public
    { IParamReader }
    function ParamCount: Integer;
    function ParamStr(I: Integer): string;

    constructor Create(const ACommandLine: string); overload;
    constructor Create(AParams: TArray<string>); overload;
  end;

  TSingleNamedParamsCommand = class(TCommand)
  public
    [Param]
    FParam: string;
  end;

  TBoolFlagCommand = class(TCommand)
  public
    [Param('verbose')]
    FVerbose: Boolean;
  end;

  TNamedStringCommand = class(TCommand)
  public
    [Param('product')]
    FProduct: string;
  end;

  TInstallLikeCommand = class(TCommand)
  public
    [Param('overwrite')]
    FOverwrite: Boolean;
    [Param('silent')]
    FSilent: Boolean;
    [Param]
    FPackageName: string;
  end;

  TArrayCommand = class(TCommand)
  public
    [Param]
    FItems: TArray<string>;
  end;

  TIntegerCommand = class(TCommand)
  public
    [Param('count')]
    FCount: Integer;
  end;

  TDoubleCommand = class(TCommand)
  public
    [Param('threshold')]
    FThreshold: Double;
  end;

{$SCOPEDENUMS ON}
  TLogLevel = (Debug, Info, Warning, Error);
{$SCOPEDENUMS OFF}

  TLogLevelCommand = class(TCommand)
  public
    [Param('level')]
    FLevel: TLogLevel;
  end;

implementation

{ TCommandTest }

function TCommandTest.CreateCommand<T>(const ACommandLine: string): T;
begin
  Result := T.NewInstance as T;
  try
    TCommand.InjectArgs(Result, TStringParamReader.Create(ACommandLine));
  except
    Result.Free;
    raise;
  end;
end;

procedure TCommandTest.TestSingleNamedParam;
begin
  var LCommand := CreateCommand<TSingleNamedParamsCommand>('Blocks command param1');
  try
    Assert.AreEqual('param1', LCommand.FParam);
  finally
    LCommand.Free;
  end;
end;

procedure TCommandTest.TestBooleanFlagPresent;
begin
  var LCommand := CreateCommand<TBoolFlagCommand>('Blocks command /verbose');
  try
    Assert.IsTrue(LCommand.FVerbose);
  finally
    LCommand.Free;
  end;
end;

procedure TCommandTest.TestBooleanFlagAbsent;
begin
  var LCommand := CreateCommand<TBoolFlagCommand>('Blocks command');
  try
    Assert.IsFalse(LCommand.FVerbose);
  finally
    LCommand.Free;
  end;
end;

procedure TCommandTest.TestNamedStringParam;
begin
  var LCommand := CreateCommand<TNamedStringCommand>('Blocks init /product delphi13');
  try
    Assert.AreEqual('delphi13', LCommand.FProduct);
  finally
    LCommand.Free;
  end;
end;

procedure TCommandTest.TestMixedFlagsAndUnnamed;
begin
  var LCommand := CreateCommand<TInstallLikeCommand>('Blocks install /overwrite owner.package /silent');
  try
    Assert.IsTrue(LCommand.FOverwrite);
    Assert.IsTrue(LCommand.FSilent);
    Assert.AreEqual('owner.package', LCommand.FPackageName);
  finally
    LCommand.Free;
  end;
end;

procedure TCommandTest.TestArrayUnnamedParam;
begin
  var LCommand := CreateCommand<TArrayCommand>('Blocks config sources=a product=b');
  try
    Assert.AreEqual<Integer>(2, Length(LCommand.FItems));
    Assert.AreEqual('sources=a', LCommand.FItems[0]);
    Assert.AreEqual('product=b', LCommand.FItems[1]);
  finally
    LCommand.Free;
  end;
end;

procedure TCommandTest.TestUnknownFlagRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      var LCommand := CreateCommand<TBoolFlagCommand>('Blocks command /unknown');
      LCommand.Free;
    end,
    Exception);
end;

procedure TCommandTest.TestNamedIntegerParam;
begin
  var LCommand := CreateCommand<TIntegerCommand>('Blocks command /count 42');
  try
    Assert.AreEqual<Integer>(42, LCommand.FCount);
  finally
    LCommand.Free;
  end;
end;

procedure TCommandTest.TestNamedDoubleParam;
begin
  var LCommand := CreateCommand<TDoubleCommand>('Blocks command /threshold 3.14');
  try
    Assert.AreEqual(Double(3.14), LCommand.FThreshold, Double(0.0001));
  finally
    LCommand.Free;
  end;
end;

procedure TCommandTest.TestNamedEnumParam;
begin
  var LCommand := CreateCommand<TLogLevelCommand>('Blocks command /level Info');
  try
    Assert.AreEqual<Integer>(Ord(TLogLevel.Info), Ord(LCommand.FLevel));
  finally
    LCommand.Free;
  end;
end;

procedure TCommandTest.TestNamedEnumParamCaseInsensitive;
begin
  var LCommand := CreateCommand<TLogLevelCommand>('Blocks command /level WARNING');
  try
    Assert.AreEqual<Integer>(Ord(TLogLevel.Warning), Ord(LCommand.FLevel));
  finally
    LCommand.Free;
  end;
end;

procedure TCommandTest.TestInvalidEnumValueRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      var LCommand := CreateCommand<TLogLevelCommand>('Blocks command /level Trace');
      LCommand.Free;
    end,
    Exception);
end;

{ TStringParamReader }

constructor TStringParamReader.Create(const ACommandLine: string);
begin
  inherited Create;
  FParams := ACommandLine.Split([' ']);
end;

constructor TStringParamReader.Create(AParams: TArray<string>);
begin
  inherited Create;
  FParams := AParams;
end;

function TStringParamReader.ParamCount: Integer;
begin
  Result := Length(FParams) - 1;
end;

function TStringParamReader.ParamStr(I: Integer): string;
begin
  Result := FParams[I];
end;

initialization
  TDUnitX.RegisterTestFixture(TCommandTest);

end.
