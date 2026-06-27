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

    [Test]
    procedure TestDefaultIdeSettingsAreDefault;
    [Test]
    procedure TestSetIdeArchitecture;
    [Test]
    procedure TestSetIdePersonality;
    [Test]
    procedure TestSetIdeHighDpi;
    [Test]
    procedure TestInvalidIdeArchitectureRaises;
    [Test]
    procedure TestInvalidIdePersonalityRaises;
    [Test]
    procedure TestInvalidIdeHighDpiRaises;
    [Test]
    procedure TestIdeSettingsRoundTrip;
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

procedure TConfigPlatformsTest.TestDefaultIdeSettingsAreDefault;
begin
  Assert.AreEqual('default', FConfig.GetValue('idearchitecture'));
  Assert.AreEqual('default', FConfig.GetValue('idepersonality'));
  Assert.AreEqual('default', FConfig.GetValue('idehighdpi'));
  Assert.IsTrue(FConfig.IdeArchitecture = TIdeArchitecture.default);
  Assert.IsTrue(FConfig.IdePersonality = TIdePersonality.default);
  Assert.IsTrue(FConfig.IdeHighDpi = TIdeHighDpi.default);
end;

procedure TConfigPlatformsTest.TestSetIdeArchitecture;
begin
  FConfig.SetValue('idearchitecture', 'Win64');
  Assert.IsTrue(FConfig.IdeArchitecture = TIdeArchitecture.Win64);
  Assert.AreEqual('Win64', FConfig.GetValue('idearchitecture'));

  // Case-insensitive parsing.
  FConfig.SetValue('idearchitecture', 'win32');
  Assert.AreEqual('Win32', FConfig.GetValue('idearchitecture'));
end;

procedure TConfigPlatformsTest.TestSetIdePersonality;
begin
  FConfig.SetValue('idepersonality', 'Delphi');
  Assert.IsTrue(FConfig.IdePersonality = TIdePersonality.Delphi);
  Assert.AreEqual('Delphi', FConfig.GetValue('idepersonality'));

  FConfig.SetValue('idepersonality', 'cbuilder');
  Assert.AreEqual('CBuilder', FConfig.GetValue('idepersonality'));
end;

procedure TConfigPlatformsTest.TestSetIdeHighDpi;
begin
  FConfig.SetValue('idehighdpi', 'permonitorv2');
  Assert.IsTrue(FConfig.IdeHighDpi = TIdeHighDpi.permonitorv2);
  Assert.AreEqual('permonitorv2', FConfig.GetValue('idehighdpi'));

  FConfig.SetValue('idehighdpi', 'SYSTEMAWARE');
  Assert.AreEqual('systemaware', FConfig.GetValue('idehighdpi'));
end;

procedure TConfigPlatformsTest.TestInvalidIdeArchitectureRaises;
begin
  Assert.WillRaise(procedure begin FConfig.SetValue('idearchitecture', 'x64'); end, Exception);
end;

procedure TConfigPlatformsTest.TestInvalidIdePersonalityRaises;
begin
  Assert.WillRaise(procedure begin FConfig.SetValue('idepersonality', 'python'); end, Exception);
end;

procedure TConfigPlatformsTest.TestInvalidIdeHighDpiRaises;
begin
  Assert.WillRaise(procedure begin FConfig.SetValue('idehighdpi', 'retina'); end, Exception);
end;

procedure TConfigPlatformsTest.TestIdeSettingsRoundTrip;
begin
  FConfig.SetValue('idearchitecture', 'Win64');
  FConfig.SetValue('idepersonality', 'CBuilder');
  FConfig.SetValue('idehighdpi', 'permonitorv2');
  FConfig.Save;

  var LLoaded := TConfig.Create(FWorkspaceDir);
  try
    LLoaded.Load;
    Assert.AreEqual('Win64', LLoaded.GetValue('idearchitecture'));
    Assert.AreEqual('CBuilder', LLoaded.GetValue('idepersonality'));
    Assert.AreEqual('permonitorv2', LLoaded.GetValue('idehighdpi'));
    Assert.IsTrue(LLoaded.IdeArchitecture = TIdeArchitecture.Win64);
    Assert.IsTrue(LLoaded.IdePersonality = TIdePersonality.CBuilder);
    Assert.IsTrue(LLoaded.IdeHighDpi = TIdeHighDpi.permonitorv2);
  finally
    LLoaded.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TConfigPlatformsTest);

end.
