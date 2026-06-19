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
unit Blocks.Tests.Config;

interface

uses
  System.SysUtils,
  System.IOUtils,
  DUnitX.TestFramework,
  Blocks.Model.Config;

type
  [TestFixture]
  TConfigPlatformsTest = class(TObject)
  private
    FWorkspaceDir: string;
    FConfig: TConfig;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestDefaultPlatformsIsEmpty;
    [Test]
    procedure TestEmptyPlatformsEnablesAll;
    [Test]
    procedure TestSetPlatformsRestrictsToList;
    [Test]
    procedure TestIsPlatformEnabledIsCaseInsensitive;
    [Test]
    procedure TestSetEmptyValueClearsPlatforms;
    [Test]
    procedure TestAddAndDeletePlatform;
    [Test]
    procedure TestGetPlatformsJoinsWithComma;
    [Test]
    procedure TestSaveLoadRoundTrip;

    [Test]
    procedure TestDefaultToolArchitectureIsDefault;
    [Test]
    procedure TestSetToolArchitecture;
    [Test]
    procedure TestInvalidToolArchitectureRaises;
    [Test]
    procedure TestToolArchitectureRoundTrip;
    [Test]
    procedure TestToolArchitectureDefaultRoundTrip;
  end;

implementation

procedure TConfigPlatformsTest.Setup;
begin
  FWorkspaceDir := TPath.Combine(TPath.GetTempPath, 'blocks-test-' + TGUID.NewGuid.ToString);
  FConfig := TConfig.Create(FWorkspaceDir);
end;

procedure TConfigPlatformsTest.TearDown;
begin
  FConfig.Free;
  if TDirectory.Exists(FWorkspaceDir) then
    TDirectory.Delete(FWorkspaceDir, True);
end;

procedure TConfigPlatformsTest.TestDefaultPlatformsIsEmpty;
begin
  Assert.AreEqual(0, FConfig.Platforms.Count);
end;

procedure TConfigPlatformsTest.TestEmptyPlatformsEnablesAll;
begin
  Assert.IsTrue(FConfig.IsPlatformEnabled('Win32'));
  Assert.IsTrue(FConfig.IsPlatformEnabled('Linux64'));
end;

procedure TConfigPlatformsTest.TestSetPlatformsRestrictsToList;
begin
  FConfig.SetValue('platforms', 'Win32,Win64');
  Assert.IsTrue(FConfig.IsPlatformEnabled('Win32'));
  Assert.IsTrue(FConfig.IsPlatformEnabled('Win64'));
  Assert.IsFalse(FConfig.IsPlatformEnabled('Linux64'));
end;

procedure TConfigPlatformsTest.TestIsPlatformEnabledIsCaseInsensitive;
begin
  FConfig.SetValue('platforms', 'Win32');
  Assert.IsTrue(FConfig.IsPlatformEnabled('win32'));
end;

procedure TConfigPlatformsTest.TestSetEmptyValueClearsPlatforms;
begin
  FConfig.SetValue('platforms', 'Win32');
  FConfig.SetValue('platforms', '');
  Assert.AreEqual(0, FConfig.Platforms.Count);
  // An empty list means "all platforms" again.
  Assert.IsTrue(FConfig.IsPlatformEnabled('Win64'));
end;

procedure TConfigPlatformsTest.TestAddAndDeletePlatform;
begin
  FConfig.Add('platforms', 'Win32');
  FConfig.Add('platforms', 'Win64');
  Assert.AreEqual(2, FConfig.Platforms.Count);

  FConfig.Delete('platforms', 'Win32');
  Assert.AreEqual(1, FConfig.Platforms.Count);
  Assert.IsFalse(FConfig.IsPlatformEnabled('Win32'));
  Assert.IsTrue(FConfig.IsPlatformEnabled('Win64'));
end;

procedure TConfigPlatformsTest.TestGetPlatformsJoinsWithComma;
begin
  FConfig.SetValue('platforms', 'Win32,Win64');
  Assert.AreEqual('Win32,Win64', FConfig.GetValue('platforms'));
end;

procedure TConfigPlatformsTest.TestSaveLoadRoundTrip;
begin
  FConfig.SetValue('platforms', 'Win32,Win64');
  FConfig.Save;

  var LLoaded := TConfig.Create(FWorkspaceDir);
  try
    LLoaded.Load;
    Assert.AreEqual('Win32,Win64', LLoaded.GetValue('platforms'));
    Assert.IsFalse(LLoaded.IsPlatformEnabled('Linux64'));
  finally
    LLoaded.Free;
  end;
end;

procedure TConfigPlatformsTest.TestDefaultToolArchitectureIsDefault;
begin
  Assert.AreEqual('default', FConfig.GetValue('toolarchitecture'));
  Assert.IsTrue(FConfig.ToolArchitecture = TToolArchitecture.default);
end;

procedure TConfigPlatformsTest.TestSetToolArchitecture;
begin
  FConfig.SetValue('toolarchitecture', 'x64');
  Assert.IsTrue(FConfig.ToolArchitecture = TToolArchitecture.x64);
  Assert.AreEqual('x64', FConfig.GetValue('toolarchitecture'));

  // Case-insensitive parsing.
  FConfig.SetValue('toolarchitecture', 'X32');
  Assert.AreEqual('x32', FConfig.GetValue('toolarchitecture'));

  FConfig.SetValue('toolarchitecture', 'DEFAULT');
  Assert.IsTrue(FConfig.ToolArchitecture = TToolArchitecture.default);
end;

procedure TConfigPlatformsTest.TestInvalidToolArchitectureRaises;
begin
  Assert.WillRaise(procedure begin FConfig.SetValue('toolarchitecture', 'x86'); end, Exception);
end;

procedure TConfigPlatformsTest.TestToolArchitectureRoundTrip;
begin
  FConfig.SetValue('toolarchitecture', 'x64');
  FConfig.Save;

  var LLoaded := TConfig.Create(FWorkspaceDir);
  try
    LLoaded.Load;
    Assert.AreEqual('x64', LLoaded.GetValue('toolarchitecture'));
    Assert.IsTrue(LLoaded.ToolArchitecture = TToolArchitecture.x64);
  finally
    LLoaded.Free;
  end;
end;

procedure TConfigPlatformsTest.TestToolArchitectureDefaultRoundTrip;
begin
  // The default value must survive a save/load cycle (serialized as "default").
  FConfig.SetValue('toolarchitecture', 'x64');
  FConfig.SetValue('toolarchitecture', 'default');
  FConfig.Save;

  var LLoaded := TConfig.Create(FWorkspaceDir);
  try
    LLoaded.Load;
    Assert.AreEqual('default', LLoaded.GetValue('toolarchitecture'));
    Assert.IsTrue(LLoaded.ToolArchitecture = TToolArchitecture.default);
  finally
    LLoaded.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TConfigPlatformsTest);

end.
