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
unit Blocks.Tests.ManifestValidator;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  DUnitX.TestFramework,
  Blocks.Model.ManifestValidator;

type
  [TestFixture]
  TManifestValidatorTest = class(TObject)
  private
    FValidator: TManifestValidator;
    FManifest: TJSONObject;
    procedure Run;
    function HasError(const APath: string): Boolean;
    function HasWarning(const APath: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestValidManifest;
    [Test]
    procedure TestNotAnObject;
    [Test]
    [TestCase('schema', '$schema')]
    [TestCase('id', 'id')]
    [TestCase('name', 'name')]
    [TestCase('version', 'version')]
    [TestCase('platforms', 'platforms')]
    [TestCase('packages', 'packages')]
    procedure TestMissingRequiredField(const AField: string);
    [Test]
    procedure TestUnsupportedSchema;
    [Test]
    [TestCase('NoDot', 'vendorname')]
    [TestCase('TwoDots', 'vendor.name.x')]
    [TestCase('EmptyVendor', '.name')]
    [TestCase('EmptyName', 'vendor.')]
    [TestCase('Backslash', 'ven\dor.name')]
    [TestCase('Slash', 'vendor.na/me')]
    [TestCase('Reserved', 'con.name')]
    procedure TestInvalidId(const AId: string);
    [Test]
    [TestCase('Dot', 'My.Lib')]
    [TestCase('Colon', 'My:Lib')]
    [TestCase('Asterisk', 'My*Lib')]
    [TestCase('TrailingSpace', 'MyLib ')]
    procedure TestInvalidName(const AName: string);
    [Test]
    [TestCase('TwoParts', '1.2')]
    [TestCase('Text', 'abc')]
    procedure TestInvalidVersion(const AVersion: string);
    [Test]
    procedure TestFourPartVersionIsValid;
    [Test]
    procedure TestUnsupportedRepositoryType;
    [Test]
    [TestCase('NoScheme', 'github.com/owner/repo')]
    [TestCase('NoHost', 'https://')]
    [TestCase('Spaces', 'https://github.com/owner/my repo')]
    [TestCase('FtpScheme', 'ftp://github.com/owner/repo')]
    procedure TestInvalidGitHubUrl(const AUrl: string);
    [Test]
    procedure TestGitScpLikeUrlIsValid;
    [Test]
    procedure TestGitMultipleRefs;
    [Test]
    procedure TestSvnFileUrlIsValid;
    [Test]
    procedure TestMetaPackageNeedsNoPlatformsOrPackages;
    [Test]
    procedure TestMissingRepositoryIsMetaPackage;
    [Test]
    procedure TestMetaPackageWithoutDependenciesWarns;
    [Test]
    procedure TestUnknownPackageTypeWarns;
    [Test]
    procedure TestPackageTypeWithoutRuntimeOrDesignTime;
    [Test]
    procedure TestInvalidFolderKey;
    [Test]
    procedure TestFolderKeyWithPlusIsValid;
    [Test]
    procedure TestInvalidProduct;
    [Test]
    procedure TestInvalidDependencyId;
    [Test]
    procedure TestFileNameMismatchWarns;
    [Test]
    procedure TestValidateFileInvalidJson;
    [Test]
    procedure TestValidateFileMissing;
  end;

implementation

const
  ValidManifest =
      '{'
          + '"$schema": "https://delphi-blocks.dev/schema/package.v1.json",'
          + '"id": "owner.mylib",'
          + '"name": "MyLib",'
          + '"version": "1.2.3",'
          + '"homepage": "https://example.com",'
          + '"keywords": ["json"],'
          + '"repository": { "type": "github", "url": "https://github.com/owner/mylib/tree/v1.2.3" },'
          + '"platforms": { "Win32,Win64": { "sourcePath": ["Source"] } },'
          + '"packages": ['
          + '  { "name": "MyLib", "type": ["runtime"] },'
          + '  { "name": "dclMyLib", "type": ["designtime"], "products": ["delphi103+"] }'
          + '],'
          + '"packageOptions": { "folders": { "delphi11": "11", "delphi12+": "12" } },'
          + '"dependencies": { "other.lib": "^1.0.0" }'
          + '}';

procedure TManifestValidatorTest.Setup;
begin
  FValidator := TManifestValidator.Create;
  FManifest := TJSONObject.ParseJSONValue(ValidManifest) as TJSONObject;
end;

procedure TManifestValidatorTest.TearDown;
begin
  FManifest.Free;
  FValidator.Free;
end;

procedure TManifestValidatorTest.Run;
begin
  FValidator.Clear;
  FValidator.Validate(FManifest);
end;

function TManifestValidatorTest.HasError(const APath: string): Boolean;
begin
  for var LMessage in FValidator.Messages do
    if (LMessage.Severity = vsError) and (LMessage.Path = APath) then
      Exit(True);
  Result := False;
end;

function TManifestValidatorTest.HasWarning(const APath: string): Boolean;
begin
  for var LMessage in FValidator.Messages do
    if (LMessage.Severity = vsWarning) and (LMessage.Path = APath) then
      Exit(True);
  Result := False;
end;

procedure TManifestValidatorTest.TestValidManifest;
begin
  Run;
  Assert.AreEqual(0, FValidator.Messages.Count);
end;

procedure TManifestValidatorTest.TestNotAnObject;
begin
  var LArray := TJSONArray.Create;
  try
    FValidator.Validate(LArray);
  finally
    LArray.Free;
  end;
  Assert.AreEqual(1, FValidator.ErrorCount);
end;

procedure TManifestValidatorTest.TestMissingRequiredField(const AField: string);
begin
  FManifest.RemovePair(AField).Free;
  Run;
  Assert.IsTrue(HasError(AField));
end;

procedure TManifestValidatorTest.TestUnsupportedSchema;
begin
  FManifest.RemovePair('$schema').Free;
  FManifest.AddPair('$schema', 'https://delphi-blocks.dev/schema/package.v2.json');
  Run;
  Assert.IsTrue(HasError('$schema'));
end;

procedure TManifestValidatorTest.TestInvalidId(const AId: string);
begin
  FManifest.RemovePair('id').Free;
  FManifest.AddPair('id', AId);
  Run;
  Assert.IsTrue(HasError('id'));
end;

procedure TManifestValidatorTest.TestInvalidName(const AName: string);
begin
  FManifest.RemovePair('name').Free;
  FManifest.AddPair('name', AName);
  Run;
  Assert.IsTrue(HasError('name'));
end;

procedure TManifestValidatorTest.TestInvalidVersion(const AVersion: string);
begin
  FManifest.RemovePair('version').Free;
  FManifest.AddPair('version', AVersion);
  Run;
  Assert.IsTrue(HasError('version'));
end;

procedure TManifestValidatorTest.TestFourPartVersionIsValid;
begin
  FManifest.RemovePair('version').Free;
  FManifest.AddPair('version', '1.0.10.52');
  Run;
  Assert.AreEqual(0, FValidator.ErrorCount);
end;

procedure TManifestValidatorTest.TestUnsupportedRepositoryType;
begin
  FManifest.RemovePair('repository').Free;
  FManifest.AddPair('repository', TJSONObject.ParseJSONValue('{ "type": "mercurial", "url": "https://x.org/r" }'));
  Run;
  Assert.IsTrue(HasError('repository.type'));
end;

procedure TManifestValidatorTest.TestInvalidGitHubUrl(const AUrl: string);
begin
  FManifest.RemovePair('repository').Free;
  FManifest.AddPair('repository', TJSONObject.Create.AddPair('type', 'github').AddPair('url', AUrl));
  Run;
  Assert.IsTrue(HasError('repository.url'));
end;

procedure TManifestValidatorTest.TestGitScpLikeUrlIsValid;
begin
  FManifest.RemovePair('repository').Free;
  FManifest.AddPair(
      'repository',
      TJSONObject.Create.AddPair('type', 'git').AddPair('url', 'git@bitbucket.org:owner/repo.git')
  );
  Run;
  Assert.AreEqual(0, FValidator.ErrorCount);
end;

procedure TManifestValidatorTest.TestGitMultipleRefs;
begin
  FManifest.RemovePair('repository').Free;
  FManifest.AddPair(
      'repository',
      TJSONObject
          .ParseJSONValue('{ "type": "git", "url": "https://example.com/repo.git", "tag": "v1", "branch": "main" }')
  );
  Run;
  Assert.IsTrue(HasError('repository'));
end;

procedure TManifestValidatorTest.TestSvnFileUrlIsValid;
begin
  FManifest.RemovePair('repository').Free;
  FManifest.AddPair('repository', TJSONObject.Create.AddPair('type', 'svn').AddPair('url', 'file:///C:/svn/repo'));
  Run;
  Assert.AreEqual(0, FValidator.ErrorCount);
end;

procedure TManifestValidatorTest.TestMetaPackageNeedsNoPlatformsOrPackages;
begin
  FManifest.RemovePair('repository').Free;
  FManifest.RemovePair('platforms').Free;
  FManifest.RemovePair('packages').Free;
  FManifest.RemovePair('packageOptions').Free;
  FManifest.AddPair('repository', TJSONObject.Create.AddPair('type', 'none'));
  Run;
  Assert.AreEqual(0, FValidator.Messages.Count);
end;

procedure TManifestValidatorTest.TestMissingRepositoryIsMetaPackage;
begin
  FManifest.RemovePair('repository').Free;
  FManifest.RemovePair('platforms').Free;
  FManifest.RemovePair('packages').Free;
  Run;
  Assert.AreEqual(0, FValidator.ErrorCount);
  Assert.IsTrue(HasWarning('repository'));
end;

procedure TManifestValidatorTest.TestMetaPackageWithoutDependenciesWarns;
begin
  FManifest.RemovePair('repository').Free;
  FManifest.RemovePair('dependencies').Free;
  FManifest.AddPair('repository', TJSONObject.Create.AddPair('type', 'none'));
  Run;
  Assert.AreEqual(0, FValidator.ErrorCount);
  Assert.IsTrue(HasWarning('dependencies'));
end;

procedure TManifestValidatorTest.TestUnknownPackageTypeWarns;
begin
  FManifest.RemovePair('packages').Free;
  FManifest.AddPair('packages', TJSONObject.ParseJSONValue('[{ "name": "MyLib", "type": ["runtime", "FMX"] }]'));
  Run;
  Assert.AreEqual(0, FValidator.ErrorCount);
  Assert.IsTrue(HasWarning('packages[0].type[1]'));
end;

procedure TManifestValidatorTest.TestPackageTypeWithoutRuntimeOrDesignTime;
begin
  FManifest.RemovePair('packages').Free;
  FManifest.AddPair('packages', TJSONObject.ParseJSONValue('[{ "name": "MyLib", "type": ["library"] }]'));
  Run;
  Assert.IsTrue(HasError('packages[0].type'));
end;

procedure TManifestValidatorTest.TestInvalidFolderKey;
begin
  FManifest.RemovePair('packageOptions').Free;
  FManifest.AddPair('packageOptions', TJSONObject.ParseJSONValue('{ "folders": { "delphi99": "99" } }'));
  Run;
  Assert.IsTrue(HasError('packageOptions.folders.delphi99'));
end;

procedure TManifestValidatorTest.TestFolderKeyWithPlusIsValid;
begin
  Assert.IsTrue(TManifestValidator.IsValidProductKey('delphixe6+'));
  Assert.IsTrue(TManifestValidator.IsValidProductKey('delphi13'));
  Assert.IsFalse(TManifestValidator.IsValidProductKey('delphi13++'));
  Assert.IsFalse(TManifestValidator.IsValidProductKey('+'));
end;

procedure TManifestValidatorTest.TestInvalidProduct;
begin
  FManifest.RemovePair('packages').Free;
  FManifest.AddPair(
      'packages',
      TJSONObject.ParseJSONValue('[{ "name": "MyLib", "type": ["runtime"], "products": ["delphi7"] }]')
  );
  Run;
  Assert.IsTrue(HasError('packages[0].products[0]'));
end;

procedure TManifestValidatorTest.TestInvalidDependencyId;
begin
  FManifest.RemovePair('dependencies').Free;
  FManifest.AddPair('dependencies', TJSONObject.Create.AddPair('nodot', '^1.0.0'));
  Run;
  Assert.IsTrue(HasError('dependencies.nodot'));
end;

procedure TManifestValidatorTest.TestFileNameMismatchWarns;
begin
  FValidator.Validate(FManifest, 'C:\temp\other.name.manifest.json');
  Assert.AreEqual(0, FValidator.ErrorCount);
  Assert.AreEqual(1, FValidator.WarningCount);

  FValidator.Clear;
  FValidator.Validate(FManifest, 'C:\temp\owner.mylib.manifest.json');
  Assert.AreEqual(0, FValidator.Messages.Count);
end;

procedure TManifestValidatorTest.TestValidateFileInvalidJson;
begin
  var LFileName := TPath.Combine(TPath.GetTempPath, 'blocks-test-' + TGUID.NewGuid.ToString + '.json');
  TFile.WriteAllText(LFileName, '{ "id": ');
  try
    FValidator.ValidateFile(LFileName);
  finally
    TFile.Delete(LFileName);
  end;
  Assert.AreEqual(1, FValidator.ErrorCount);
end;

procedure TManifestValidatorTest.TestValidateFileMissing;
begin
  FValidator.ValidateFile(TPath.Combine(TPath.GetTempPath, 'blocks-missing-' + TGUID.NewGuid.ToString + '.json'));
  Assert.AreEqual(1, FValidator.ErrorCount);
end;

initialization
  TDUnitX.RegisterTestFixture(TManifestValidatorTest);

end.
