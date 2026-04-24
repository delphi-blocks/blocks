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
unit Blocks.Tests.Package;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  DUnitX.TestFramework,

  Blocks.Model.Package;

type
  [TestFixture]
  TPackageProjectTest = class(TObject)
  public

    [Test]
    procedure TestPropertyGroups_Count;
    [Test]
    procedure TestPropertyGroups_FirstHasNoCondition;
    [Test]
    procedure TestPropertyGroups_ConditionPreservedVerbatim;
    [Test]
    procedure TestPropertyGroups_UnconditionalKeysRead;
    [Test]
    procedure TestPropertyGroups_ConditionalKeysRead;
    [Test]
    procedure TestPropertyGroups_KeyCount;
    [Test]
    procedure TestPropertyGroups_CaseInsensitiveLookup;
    [Test]
    procedure TestPropertyGroups_MissingKeyReturnsFalse;

    [Test]
    procedure TestReferences_Count;
    [Test]
    procedure TestReferences_PlainInclude;
    [Test]
    procedure TestReferences_WithForm;
    [Test]
    procedure TestReferences_HasFormFlag;

    [Test]
    procedure TestLoadFromFile_RaisesWhenMissing;
    [Test]
    procedure TestLoadFromString_RaisesWhenRootInvalid;

    [Test]
    procedure TestEvaluator_GetMainSource;
    [Test]
    procedure TestEvaluator_GetDescription;

    [Test]
    procedure TestEvaluator_GetExeOutput_Win32Release;
    [Test]
    procedure TestEvaluator_GetExeOutput_Win32Test;
    [Test]
    procedure TestEvaluator_GetExeOutput_Win64Debug;
    [Test]
    procedure TestEvaluator_GetExeOutput_Win64Release;
    [Test]
    procedure TestEvaluator_GetExeOutput_Win64Test;
    [Test]
    procedure TestEvaluator_GetExeOutput_Win32Debug;
  end;

const
  SamplePackageXml =
    '''
    <?xml version="1.0" encoding="utf-8"?>
    <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
        <PropertyGroup>
            <ProjectGuid>{B7363784-25C2-456C-BE44-D3E58F77E983}</ProjectGuid>
            <MainSource>WiRLDesign.dpk</MainSource>
            <ProjectVersion>20.1</ProjectVersion>
            <FrameworkType>VCL</FrameworkType>
            <AppType>Package</AppType>
            <Base>True</Base>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Base)'!=''">
            <DesignOnlyPackage>true</DesignOnlyPackage>
            <SanitizedProjectName>WiRLDesign</SanitizedProjectName>
            <DCC_Description>WiRL REST components</DCC_Description>
            <DllSuffix>280</DllSuffix>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Cfg_1_Win32)'!=''">
            <DllSuffix>$(Auto)</DllSuffix>
        </PropertyGroup>
        <ItemGroup>
            <DCCReference Include="rtl.dcp"/>
            <DCCReference Include="WiRL.dcp"/>
            <DCCReference Include="..\..\Source\Core\WiRL.Core.Application.Editor.pas">
                <Form>WiRLAppEditor</Form>
                <FormType>dfm</FormType>
            </DCCReference>
            <DCCReference Include="..\..\Source\Client\WiRL.Client.Register.pas"/>
        </ItemGroup>
    </Project>
    ''';

  InvalidRootXml =
    '''
    <?xml version="1.0" encoding="utf-8"?>
    <NotAProject>
        <Foo>bar</Foo>
    </NotAProject>
    ''';

  ComplexPackageXML =
    '''
    <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
        <PropertyGroup>
            <ProjectGuid>{F1EB13B0-2B15-45B5-8303-7E464C23A839}</ProjectGuid>
            <ProjectVersion>20.3</ProjectVersion>
            <FrameworkType>VCL</FrameworkType>
            <Base>True</Base>
            <Config Condition="'$(Config)'==''">Debug</Config>
            <Platform Condition="'$(Platform)'==''">Win32</Platform>
            <ProjectName Condition="'$(ProjectName)'==''">TestPrj</ProjectName>
            <TargetedPlatforms>3</TargetedPlatforms>
            <AppType>Application</AppType>
            <MainSource>TestPrj.dpr</MainSource>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Config)'=='Base' or '$(Base)'!=''">
            <Base>true</Base>
        </PropertyGroup>
        <PropertyGroup Condition="('$(Platform)'=='Win32' and '$(Base)'=='true') or '$(Base_Win32)'!=''">
            <Base_Win32>true</Base_Win32>
            <CfgParent>Base</CfgParent>
            <Base>true</Base>
        </PropertyGroup>
        <PropertyGroup Condition="('$(Platform)'=='Win64' and '$(Base)'=='true') or '$(Base_Win64)'!=''">
            <Base_Win64>true</Base_Win64>
            <CfgParent>Base</CfgParent>
            <Base>true</Base>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Config)'=='Debug' or '$(Cfg_1)'!=''">
            <Cfg_1>true</Cfg_1>
            <CfgParent>Base</CfgParent>
            <Base>true</Base>
        </PropertyGroup>
        <PropertyGroup Condition="('$(Platform)'=='Win32' and '$(Cfg_1)'=='true') or '$(Cfg_1_Win32)'!=''">
            <Cfg_1_Win32>true</Cfg_1_Win32>
            <CfgParent>Cfg_1</CfgParent>
            <Cfg_1>true</Cfg_1>
            <Base>true</Base>
        </PropertyGroup>
        <PropertyGroup Condition="('$(Platform)'=='Win64' and '$(Cfg_1)'=='true') or '$(Cfg_1_Win64)'!=''">
            <Cfg_1_Win64>true</Cfg_1_Win64>
            <CfgParent>Cfg_1</CfgParent>
            <Cfg_1>true</Cfg_1>
            <Base>true</Base>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Config)'=='Release' or '$(Cfg_2)'!=''">
            <Cfg_2>true</Cfg_2>
            <CfgParent>Base</CfgParent>
            <Base>true</Base>
        </PropertyGroup>
        <PropertyGroup Condition="('$(Platform)'=='Win32' and '$(Cfg_2)'=='true') or '$(Cfg_2_Win32)'!=''">
            <Cfg_2_Win32>true</Cfg_2_Win32>
            <CfgParent>Cfg_2</CfgParent>
            <Cfg_2>true</Cfg_2>
            <Base>true</Base>
        </PropertyGroup>
        <PropertyGroup Condition="('$(Platform)'=='Win64' and '$(Cfg_2)'=='true') or '$(Cfg_2_Win64)'!=''">
            <Cfg_2_Win64>true</Cfg_2_Win64>
            <CfgParent>Cfg_2</CfgParent>
            <Cfg_2>true</Cfg_2>
            <Base>true</Base>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Config)'=='TestDefault' or '$(Cfg_3)'!=''">
            <Cfg_3>true</Cfg_3>
            <CfgParent>Base</CfgParent>
            <Base>true</Base>
        </PropertyGroup>
        <PropertyGroup Condition="('$(Platform)'=='Win32' and '$(Cfg_3)'=='true') or '$(Cfg_3_Win32)'!=''">
            <Cfg_3_Win32>true</Cfg_3_Win32>
            <CfgParent>Cfg_3</CfgParent>
            <Cfg_3>true</Cfg_3>
            <Base>true</Base>
        </PropertyGroup>
        <PropertyGroup Condition="('$(Platform)'=='Win64' and '$(Cfg_3)'=='true') or '$(Cfg_3_Win64)'!=''">
            <Cfg_3_Win64>true</Cfg_3_Win64>
            <CfgParent>Cfg_3</CfgParent>
            <Cfg_3>true</Cfg_3>
            <Base>true</Base>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Base)'!=''">
            <DCC_DcuOutput>.\$(Platform)\$(Config)</DCC_DcuOutput>
            <DCC_ExeOutput>BASE</DCC_ExeOutput>
            <DCC_E>false</DCC_E>
            <DCC_N>false</DCC_N>
            <DCC_S>false</DCC_S>
            <DCC_F>false</DCC_F>
            <DCC_K>false</DCC_K>
            <DCC_Namespace>System;Xml;Data;Datasnap;Web;Soap;Vcl;Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell;$(DCC_Namespace)</DCC_Namespace>
            <Icon_MainIcon>$(BDS)\bin\delphi_PROJECTICON.ico</Icon_MainIcon>
            <UWP_DelphiLogo44>$(BDS)\bin\Artwork\Windows\UWP\delphi_UwpDefault_44.png</UWP_DelphiLogo44>
            <UWP_DelphiLogo150>$(BDS)\bin\Artwork\Windows\UWP\delphi_UwpDefault_150.png</UWP_DelphiLogo150>
            <SanitizedProjectName>TestPrj</SanitizedProjectName>
            <VerInfo_Locale>1040</VerInfo_Locale>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Base_Win32)'!=''">
            <DCC_Namespace>Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win;Bde;$(DCC_Namespace)</DCC_Namespace>
            <BT_BuildType>Debug</BT_BuildType>
            <VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>
            <VerInfo_Locale>1033</VerInfo_Locale>
            <AppDPIAwarenessMode>none</AppDPIAwarenessMode>
            <Manifest_File>$(BDS)\bin\default_app.manifest</Manifest_File>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Base_Win64)'!=''">
            <DCC_Namespace>Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win;$(DCC_Namespace)</DCC_Namespace>
            <BT_BuildType>Debug</BT_BuildType>
            <VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>
            <VerInfo_Locale>1033</VerInfo_Locale>
            <AppDPIAwarenessMode>none</AppDPIAwarenessMode>
            <Manifest_File>$(BDS)\bin\default_app.manifest</Manifest_File>
            <DCC_ExeOutput>WIN64</DCC_ExeOutput>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Cfg_1)'!=''">
            <DCC_Define>DEBUG;$(DCC_Define)</DCC_Define>
            <DCC_DebugDCUs>true</DCC_DebugDCUs>
            <DCC_Optimize>false</DCC_Optimize>
            <DCC_GenerateStackFrames>true</DCC_GenerateStackFrames>
            <DCC_DebugInfoInExe>true</DCC_DebugInfoInExe>
            <DCC_RemoteDebug>true</DCC_RemoteDebug>
            <DCC_IntegerOverflowCheck>true</DCC_IntegerOverflowCheck>
            <DCC_RangeChecking>true</DCC_RangeChecking>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Cfg_1_Win32)'!=''">
            <DCC_RemoteDebug>false</DCC_RemoteDebug>
            <AppDPIAwarenessMode>PerMonitorV2</AppDPIAwarenessMode>
            <VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>
            <VerInfo_Locale>1033</VerInfo_Locale>
            <DCC_ExeOutput>WIN32/DEBUG</DCC_ExeOutput>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Cfg_1_Win64)'!=''">
            <AppDPIAwarenessMode>PerMonitorV2</AppDPIAwarenessMode>
            <VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>
            <VerInfo_Locale>1033</VerInfo_Locale>
            <DCC_ExeOutput>WIN64</DCC_ExeOutput>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Cfg_2)'!=''">
            <DCC_LocalDebugSymbols>false</DCC_LocalDebugSymbols>
            <DCC_Define>RELEASE;$(DCC_Define)</DCC_Define>
            <DCC_SymbolReferenceInfo>0</DCC_SymbolReferenceInfo>
            <DCC_DebugInformation>0</DCC_DebugInformation>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Cfg_2_Win32)'!=''">
            <AppDPIAwarenessMode>PerMonitorV2</AppDPIAwarenessMode>
            <VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>
            <VerInfo_Locale>1033</VerInfo_Locale>
            <DCC_ExeOutput>WIN32/RELEASE</DCC_ExeOutput>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Cfg_2_Win64)'!=''">
            <AppDPIAwarenessMode>PerMonitorV2</AppDPIAwarenessMode>
            <VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>
            <VerInfo_Locale>1033</VerInfo_Locale>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Cfg_3_Win32)'!=''">
            <VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>
            <VerInfo_Locale>1033</VerInfo_Locale>
        </PropertyGroup>
        <PropertyGroup Condition="'$(Cfg_3_Win64)'!=''">
            <VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>
            <VerInfo_Locale>1033</VerInfo_Locale>
        </PropertyGroup>
        <ItemGroup>
            <DelphiCompile Include="$(MainSource)">
                <MainSource>MainSource</MainSource>
            </DelphiCompile>
            <DCCReference Include="TestUnit.pas">
                <Form>Form3</Form>
                <FormType>dfm</FormType>
            </DCCReference>
            <BuildConfiguration Include="Base">
                <Key>Base</Key>
            </BuildConfiguration>
            <BuildConfiguration Include="Debug">
                <Key>Cfg_1</Key>
                <CfgParent>Base</CfgParent>
            </BuildConfiguration>
            <BuildConfiguration Include="Release">
                <Key>Cfg_2</Key>
                <CfgParent>Base</CfgParent>
            </BuildConfiguration>
            <BuildConfiguration Include="TestDefault">
                <Key>Cfg_3</Key>
                <CfgParent>Base</CfgParent>
            </BuildConfiguration>
        </ItemGroup>
        <Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" Condition="Exists('$(BDS)\Bin\CodeGear.Delphi.Targets')"/>
        <Import Project="$(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(PRODUCTVERSION)\UserTools.proj" Condition="Exists('$(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(PRODUCTVERSION)\UserTools.proj')"/>
        <Import Project="$(MSBuildProjectName).deployproj" Condition="Exists('$(MSBuildProjectName).deployproj')"/>
    </Project>
    ''';

implementation

{ TPackageProjectTest }

procedure TPackageProjectTest.TestEvaluator_GetDescription;
begin
  var LProject := TPackageProject.LoadFromString(SamplePackageXml);
  try
    Assert.AreEqual('WiRL REST components', LProject.GetProperty(TPackageProject.DCCDescription, 'Debug', 'Win32'));
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestEvaluator_GetExeOutput_Win32Debug;
begin
  var LProject := TPackageProject.LoadFromString(ComplexPackageXML);
  try
    Assert.AreEqual('WIN32/DEBUG', LProject.GetProperty(TPackageProject.DCCExeOutput, 'Debug', 'Win32'));
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestEvaluator_GetExeOutput_Win64Debug;
begin
  var LProject := TPackageProject.LoadFromString(ComplexPackageXML);
  try
    Assert.AreEqual('WIN64', LProject.GetProperty(TPackageProject.DCCExeOutput, 'Debug', 'Win64'));
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestEvaluator_GetExeOutput_Win32Release;
begin
  var LProject := TPackageProject.LoadFromString(ComplexPackageXML);
  try
    Assert.AreEqual('WIN32/RELEASE', LProject.GetProperty(TPackageProject.DCCExeOutput, 'Release', 'Win32'));
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestEvaluator_GetExeOutput_Win64Release;
begin
  var LProject := TPackageProject.LoadFromString(ComplexPackageXML);
  try
    Assert.AreEqual('WIN64', LProject.GetProperty(TPackageProject.DCCExeOutput, 'Release', 'Win64'));
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestEvaluator_GetExeOutput_Win32Test;
begin
  var LProject := TPackageProject.LoadFromString(ComplexPackageXML);
  try
    Assert.AreEqual('BASE', LProject.GetProperty(TPackageProject.DCCExeOutput, 'TestDefault', 'Win32'));
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestEvaluator_GetExeOutput_Win64Test;
begin
  var LProject := TPackageProject.LoadFromString(ComplexPackageXML);
  try
    Assert.AreEqual('WIN64', LProject.GetProperty(TPackageProject.DCCExeOutput, 'TestDefault', 'Win64'));
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestEvaluator_GetMainSource;
begin
  var LProject := TPackageProject.LoadFromString(ComplexPackageXML);
  try
    Assert.AreEqual('TestPrj.dpr', LProject.GetProperty(TPackageProject.MainSource, 'Debug', 'Win32'));
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestPropertyGroups_Count;
begin
  var LProject := TPackageProject.LoadFromString(SamplePackageXml);
  try
    Assert.AreEqual(3, LProject.PropertyGroups.Count, 'PropertyGroups count');
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestPropertyGroups_FirstHasNoCondition;
begin
  var LProject := TPackageProject.LoadFromString(SamplePackageXml);
  try
    Assert.AreEqual('', LProject.PropertyGroups[0].Condition, 'First group has no Condition');
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestPropertyGroups_ConditionPreservedVerbatim;
begin
  var LProject := TPackageProject.LoadFromString(SamplePackageXml);
  try
    Assert.AreEqual('''$(Base)''!=''''',       LProject.PropertyGroups[1].Condition, 'Base group');
    Assert.AreEqual('''$(Cfg_1_Win32)''!=''''', LProject.PropertyGroups[2].Condition, 'Cfg_1_Win32 group');
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestPropertyGroups_UnconditionalKeysRead;
begin
  var LProject := TPackageProject.LoadFromString(SamplePackageXml);
  try
    var LGroup := LProject.PropertyGroups[0];
    Assert.AreEqual('{B7363784-25C2-456C-BE44-D3E58F77E983}', LGroup['ProjectGuid']);
    Assert.AreEqual('WiRLDesign.dpk', LGroup['MainSource']);
    Assert.AreEqual('20.1',           LGroup['ProjectVersion']);
    Assert.AreEqual('VCL',            LGroup['FrameworkType']);
    Assert.AreEqual('Package',        LGroup['AppType']);
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestPropertyGroups_ConditionalKeysRead;
begin
  var LProject := TPackageProject.LoadFromString(SamplePackageXml);
  try
    var LBase := LProject.PropertyGroups[1];
    Assert.AreEqual('true',                  LBase['DesignOnlyPackage']);
    Assert.AreEqual('WiRLDesign',            LBase['SanitizedProjectName']);
    Assert.AreEqual('WiRL REST components',  LBase['DCC_Description']);
    Assert.AreEqual('280',                   LBase['DllSuffix']);

    var LWin32 := LProject.PropertyGroups[2];
    Assert.AreEqual('$(Auto)', LWin32['DllSuffix']);
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestPropertyGroups_KeyCount;
begin
  var LProject := TPackageProject.LoadFromString(SamplePackageXml);
  try
    Assert.AreEqual(6, LProject.PropertyGroups[0].Count, 'group #0 has 6 keys');
    Assert.AreEqual(4, LProject.PropertyGroups[1].Count, 'group #1 has 4 keys');
    Assert.AreEqual(1, LProject.PropertyGroups[2].Count, 'group #2 has 1 key');
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestPropertyGroups_CaseInsensitiveLookup;
begin
  var LProject := TPackageProject.LoadFromString(SamplePackageXml);
  try
    var LGroup := LProject.PropertyGroups[0];
    Assert.AreEqual('WiRLDesign.dpk', LGroup['mainsource'], 'lowercase lookup');
    Assert.AreEqual('WiRLDesign.dpk', LGroup['MAINSOURCE'], 'uppercase lookup');
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestPropertyGroups_MissingKeyReturnsFalse;
begin
  var LProject := TPackageProject.LoadFromString(SamplePackageXml);
  try
    var LValue: string;
    Assert.IsFalse(LProject.PropertyGroups[0].TryGetValue('NotThere', LValue),
      'TryGetValue returns False for missing key');
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestReferences_Count;
begin
  var LProject := TPackageProject.LoadFromString(SamplePackageXml);
  try
    Assert.AreEqual(4, LProject.References.Count);
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestReferences_PlainInclude;
begin
  var LProject := TPackageProject.LoadFromString(SamplePackageXml);
  try
    Assert.AreEqual('rtl.dcp',  LProject.References[0].Include);
    Assert.AreEqual('WiRL.dcp', LProject.References[1].Include);
    Assert.AreEqual('..\..\Source\Client\WiRL.Client.Register.pas',
      LProject.References[3].Include);
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestReferences_WithForm;
begin
  var LProject := TPackageProject.LoadFromString(SamplePackageXml);
  try
    var LRef := LProject.References[2];
    Assert.AreEqual('..\..\Source\Core\WiRL.Core.Application.Editor.pas', LRef.Include);
    Assert.AreEqual('WiRLAppEditor', LRef.FormName);
    Assert.AreEqual('dfm',           LRef.FormType);
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestReferences_HasFormFlag;
begin
  var LProject := TPackageProject.LoadFromString(SamplePackageXml);
  try
    Assert.IsFalse(LProject.References[0].HasForm, 'rtl.dcp has no form');
    Assert.IsTrue(LProject.References[2].HasForm,  'editor reference has form');
  finally
    LProject.Free;
  end;
end;

procedure TPackageProjectTest.TestLoadFromFile_RaisesWhenMissing;
begin
  var LMissing := TPath.Combine(TPath.GetTempPath, 'BlocksTests.DoesNotExist.dproj');
  if TFile.Exists(LMissing) then
    TFile.Delete(LMissing);

  Assert.WillRaise(
    procedure
    begin
      TPackageProject.LoadFromFile(LMissing).Free;
    end,
    Exception);
end;

procedure TPackageProjectTest.TestLoadFromString_RaisesWhenRootInvalid;
begin
  Assert.WillRaise(
    procedure
    begin
      TPackageProject.LoadFromString(InvalidRootXml).Free;
    end,
    Exception);
end;

initialization
  TDUnitX.RegisterTestFixture(TPackageProjectTest);

end.
