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
unit Blocks.Tests.Core;

interface

uses
  System.Classes,
  System.SysUtils,
  DUnitX.TestFramework,
  Blocks.Core;

type
  [TestFixture]
  TExpandVariablesTest = class(TObject)
  private
    FEnv: TStringList;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestExpandsPercentSyntax;
    [Test]
    procedure TestExpandsParenthesisSyntax;
    [Test]
    procedure TestExpandsBothSyntaxesInOnePass;
    [Test]
    procedure TestExpandsMultipleOccurrences;
    [Test]
    procedure TestLookupIsCaseInsensitive;
    [Test]
    procedure TestNoPlaceholderReturnsInputUnchanged;
    [Test]
    procedure TestEmptyStringReturnsEmpty;

    // Variables that are not present in the string list.
    [Test]
    procedure TestUnknownPercentVariableResolvesToEmpty;
    [Test]
    procedure TestUnknownParenthesisVariableResolvesToEmpty;
    [Test]
    procedure TestUnknownVariableOnlyClearsItsOwnPlaceholder;
    [Test]
    procedure TestVariableWithEmptyValueResolvesToEmpty;
  end;

  [TestFixture]
  TPlatformInListTest = class(TObject)
  public
    [Test]
    procedure TestEmptyListMeansAll;
    [Test]
    procedure TestMatchIsCaseInsensitive;
    [Test]
    procedure TestPlatformNotInListReturnsFalse;
  end;

implementation

procedure TExpandVariablesTest.Setup;
begin
  FEnv := TStringList.Create;
end;

procedure TExpandVariablesTest.TearDown;
begin
  FEnv.Free;
end;

procedure TExpandVariablesTest.TestExpandsPercentSyntax;
begin
  FEnv.Values['NAME'] := 'World';
  Assert.AreEqual('Hello World', ExpandVariables('Hello %NAME%', FEnv));
end;

procedure TExpandVariablesTest.TestExpandsParenthesisSyntax;
begin
  FEnv.Values['NAME'] := 'World';
  Assert.AreEqual('Hello World', ExpandVariables('Hello $(NAME)', FEnv));
end;

procedure TExpandVariablesTest.TestExpandsBothSyntaxesInOnePass;
begin
  FEnv.Values['Platform'] := 'Win32';
  FEnv.Values['Config'] := 'Release';
  Assert.AreEqual('Win32-Release', ExpandVariables('%Platform%-$(Config)', FEnv));
end;

procedure TExpandVariablesTest.TestExpandsMultipleOccurrences;
begin
  FEnv.Values['X'] := 'ab';
  Assert.AreEqual('ab/ab', ExpandVariables('%X%/$(X)', FEnv));
end;

procedure TExpandVariablesTest.TestLookupIsCaseInsensitive;
begin
  FEnv.Values['PACKAGE_VERSION'] := '290';
  // The placeholder uses a different case than the stored name.
  Assert.AreEqual('290', ExpandVariables('%package_version%', FEnv));
end;

procedure TExpandVariablesTest.TestNoPlaceholderReturnsInputUnchanged;
begin
  FEnv.Values['NAME'] := 'World';
  Assert.AreEqual('plain text', ExpandVariables('plain text', FEnv));
end;

procedure TExpandVariablesTest.TestEmptyStringReturnsEmpty;
begin
  Assert.AreEqual('', ExpandVariables('', FEnv));
end;

procedure TExpandVariablesTest.TestUnknownPercentVariableResolvesToEmpty;
begin
  // %MISSING% is not in the string list, so it expands to ''.
  Assert.AreEqual('before-after', ExpandVariables('before-%MISSING%after', FEnv));
end;

procedure TExpandVariablesTest.TestUnknownParenthesisVariableResolvesToEmpty;
begin
  Assert.AreEqual('before-after', ExpandVariables('before-$(MISSING)after', FEnv));
end;

procedure TExpandVariablesTest.TestUnknownVariableOnlyClearsItsOwnPlaceholder;
begin
  // A known variable next to an unknown one is still expanded.
  FEnv.Values['KNOWN'] := 'value';
  Assert.AreEqual('value-', ExpandVariables('%KNOWN%-%MISSING%', FEnv));
end;

procedure TExpandVariablesTest.TestVariableWithEmptyValueResolvesToEmpty;
begin
  // Assigning an empty value removes the name from a TStringList, so the
  // variable is effectively absent and resolves to ''.
  FEnv.Values['EMPTY'] := '';
  Assert.AreEqual('[]', ExpandVariables('[%EMPTY%]', FEnv));
end;

{ TPlatformInListTest }

procedure TPlatformInListTest.TestEmptyListMeansAll;
begin
  // An empty list is the "all platforms" sentinel, so anything matches.
  Assert.IsTrue(PlatformInList([], 'Win32'));
end;

procedure TPlatformInListTest.TestMatchIsCaseInsensitive;
begin
  Assert.IsTrue(PlatformInList(['Win32', 'Win64'], 'win64'));
end;

procedure TPlatformInListTest.TestPlatformNotInListReturnsFalse;
begin
  Assert.IsFalse(PlatformInList(['Win32'], 'Win64'));
end;

initialization
  TDUnitX.RegisterTestFixture(TExpandVariablesTest);
  TDUnitX.RegisterTestFixture(TPlatformInListTest);

end.
