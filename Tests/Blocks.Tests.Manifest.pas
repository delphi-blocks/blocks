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
unit Blocks.Tests.Manifest;

interface

uses
  System.Classes,
  System.SysUtils,
  System.JSON,
  DUnitX.TestFramework,
  Blocks.Core,
  Blocks.JSON,
  Blocks.Model.Manifest,
  Blocks.Service.Script;

type
  [TestFixture]
  TManifestDeserializationTest = class(TObject)
  public
    [Test]
    procedure TestBasicFields;
    [Test]
    procedure TestRepository;
    [Test]
    procedure TestRepository_MetaPackageWithoutRepositoryNode;
    [Test]
    procedure TestKeywords;
    [Test]
    procedure TestPlatforms;
    [Test]
    procedure TestPackages;
    [Test]
    procedure TestPackageOptions;
    [Test]
    procedure TestDependencies;
    [Test]
    procedure TestScripts;
  end;

  [TestFixture]
  TManifestSerializationTest = class(TObject)
  public
    [Test]
    procedure TestRoundTrip_BasicFields;
    [Test]
    procedure TestRoundTrip_Platforms;
    [Test]
    procedure TestRoundTrip_Packages;
    [Test]
    procedure TestRoundTrip_Dependencies;
    [Test]
    procedure TestRoundTrip_Scripts;
  end;

  [TestFixture]
  TManifestProductSupportTest = class(TObject)
  public
    [Test]
    procedure TestPackage_NoProductsSupportsAny;
    [Test]
    procedure TestPackage_ExactMatch;
    [Test]
    procedure TestPackage_ExactMatchCaseInsensitive;
    [Test]
    procedure TestPackage_ExactMatchDoesNotMatchHigherVersion;
    [Test]
    procedure TestPackage_PlusSuffixSupportsAtOrAboveVersion;
    [Test]
    procedure TestPackage_PlusSuffixExcludesBelowVersion;
    [Test]
    procedure TestPackage_UnknownProductMatchesOnlyExactEntry;

    [Test]
    procedure TestManifest_EmptyFoldersSupportsAnyProduct;
    [Test]
    procedure TestManifest_FolderKeySupportsAtOrAboveVersion;
    [Test]
    procedure TestManifest_FolderKeyExcludesBelowVersion;
    [Test]
    procedure TestManifest_FolderKeyWithoutPlusBehavesSameAsWithPlus;
    [Test]
    procedure TestManifest_MultipleFolderKeysPicksLowestApplicable;
    [Test]
    procedure TestManifest_UnknownProductNameIsNeverSupported;
  end;

  // Tests focused on TManifestScript and TSupportedPlatforms, the manifest model
  // classes that implement the explicit ToJSON/FromJSON pair (the IDynamicObject
  // duck-type the JSON framework looks for). Other manifest classes are
  // (de)serialized through the generic RTTI-based reader/writer, covered above.
  [TestFixture]
  TManifestScriptJSONTest = class(TObject)
  public
    [Test]
    procedure TestFromJSON_NilIsNoOp;
    [Test]
    procedure TestToJSON_OmitsEmptyDescriptionAndMissingArgs;
    [Test]
    procedure TestFromJSONString_EchoArgsParsed;
    [Test]
    procedure TestFromJSONString_CompileArgsMissingPlatformsRaises;
    [Test]
    procedure TestFromJSONString_UnregisteredCommandFallsBackToNoArguments;
  end;

  // TSupportedPlatforms.FromJSON expands a comma-separated key ("Win64,Linux64")
  // into one dictionary entry per platform name. ToJSON does not (yet) do the
  // reverse compaction — see the TODO on TSupportedPlatforms.ToJSON — so the
  // round trip is deliberately asymmetric; the tests below document that.
  [TestFixture]
  TSupportedPlatformsJSONTest = class(TObject)
  public
    [Test]
    procedure TestFromJSON_NilIsNoOp;
    [Test]
    procedure TestFromJSON_NonObjectIsNoOp;
    [Test]
    procedure TestFromJSON_SingleKeyCreatesOnePlatform;
    [Test]
    procedure TestFromJSON_CommaSeparatedKeySplitsIntoMultiplePlatforms;
    [Test]
    procedure TestToJSON_WritesOneKeyPerPlatform;
    [Test]
    procedure TestToJSON_DoesNotCompactIdenticalPlatforms;
  end;

const
  FullManifestJSON =
      '''
      {
        "$schema": "https://delphi-blocks.dev/schema/package.v1.json",
        "id": "acme.widgets",
        "name": "Widgets",
        "version": "1.2.3",
        "description": "A widget library",
        "license": "MIT",
        "homepage": "https://example.com/widgets",
        "author": "Jane Doe",
        "keywords": ["ui", "widgets"],
        "repository": { "type": "github", "url": "https://github.com/acme/widgets/tree/v1.2.3" },
        "platforms": {
          "Win32": {
            "sourcePath": ["Source\\Core"],
            "releaseDCUPath": ["lib\\release"],
            "debugDCUPath": ["lib\\debug"],
            "runtimeOnly": true
          },
          "Win64,Linux64": {
            "sourcePath": ["Source\\Core"]
          }
        },
        "packages": [
          { "name": "Widgets", "type": ["runtime"], "products": ["delphi11+"] },
          { "name": "WidgetsDesign", "type": ["designtime"] }
        ],
        "packageOptions": {
          "rootFolder": "pkgs",
          "folders": { "delphi12+": "12.0Athens" }
        },
        "dependencies": { "acme.core": "^2.0.0" },
        "scripts": [
          {
            "command": "echo",
            "event": "afterInstall",
            "args": "Installed $(NAME)"
          },
          {
            "command": "compile",
            "description": "Build helper",
            "event": "afterInstall",
            "args": { "projectFile": "Helper.dproj", "platforms": ["Win32"] }
          }
        ]
      }
      ''';

implementation

{ TManifestDeserializationTest }

procedure TManifestDeserializationTest.TestBasicFields;
begin
  var LManifest := TJsonHelper.JSONToObject<TManifest>(FullManifestJSON);
  try
    Assert.AreEqual('acme.widgets', LManifest.Id, 'id');
    Assert.AreEqual('Widgets', LManifest.Name, 'name');
    Assert.AreEqual('1.2.3', LManifest.Version, 'version');
    Assert.AreEqual('A widget library', LManifest.Description, 'description');
    Assert.AreEqual('MIT', LManifest.License, 'license');
    Assert.AreEqual('https://example.com/widgets', LManifest.Homepage, 'homepage');
    Assert.AreEqual('Jane Doe', LManifest.Author, 'author');
  finally
    LManifest.Free;
  end;
end;

procedure TManifestDeserializationTest.TestRepository;
begin
  var LManifest := TJsonHelper.JSONToObject<TManifest>(FullManifestJSON);
  try
    Assert.AreEqual('github', LManifest.Repository.RepoType, 'repository.type');
    Assert.AreEqual(
        'https://github.com/acme/widgets/tree/v1.2.3',
        LManifest.Repository.Config<TGitHubConfig>.Url,
        'repository.url'
    );
  finally
    LManifest.Free;
  end;
end;

procedure TManifestDeserializationTest.TestRepository_MetaPackageWithoutRepositoryNode;
begin
  // A meta-package has no "repository" node: FromJSON is invoked with a nil JSON
  // value and must not crash, leaving a "none" repository.
  const MetaPackageJSON =
      '''
      {
        "id": "acme.meta",
        "name": "Meta",
        "version": "1.0.0"
      }
      ''';
  var LManifest := TJsonHelper.JSONToObject<TManifest>(MetaPackageJSON);
  try
    Assert.AreEqual('none', LManifest.Repository.RepoType, 'repository.type');
    Assert.AreEqual('', LManifest.Repository.ToString, 'repository.ToString');
    Assert.IsTrue(LManifest.IsMeta, 'IsMeta');
  finally
    LManifest.Free;
  end;
end;

procedure TManifestDeserializationTest.TestKeywords;
begin
  var LManifest := TJsonHelper.JSONToObject<TManifest>(FullManifestJSON);
  try
    Assert.AreEqual(2, LManifest.Keywords.Count, 'keywords count');
    Assert.AreEqual('ui', LManifest.Keywords[0], 'keywords[0]');
    Assert.AreEqual('widgets', LManifest.Keywords[1], 'keywords[1]');
  finally
    LManifest.Free;
  end;
end;

procedure TManifestDeserializationTest.TestPlatforms;
begin
  var LManifest := TJsonHelper.JSONToObject<TManifest>(FullManifestJSON);
  try
    Assert.AreEqual(3, LManifest.Platforms.Count, 'platforms count');

    var LWin32: TManifestPlatform;
    Assert.IsTrue(LManifest.Platforms.TryGetValue('Win32', LWin32), 'Win32 platform present');
    Assert.AreEqual(1, LWin32.SourcePath.Count, 'Win32 sourcePath count');
    Assert.AreEqual('Source\Core', LWin32.SourcePath[0], 'Win32 sourcePath[0]');
    Assert.AreEqual('lib\release', LWin32.ReleaseDCUPath[0], 'Win32 releaseDCUPath[0]');
    Assert.AreEqual('lib\debug', LWin32.DebugDCUPath[0], 'Win32 debugDCUPath[0]');
    Assert.IsTrue(LWin32.RuntimeOnly, 'Win32 runtimeOnly');

    var LWin64: TManifestPlatform;
    Assert.IsTrue(LManifest.Platforms.TryGetValue('Win64', LWin64), 'Win64 platform present');
    Assert.AreEqual('Source\Core', LWin64.SourcePath[0], 'Win64 sourcePath[0]');
    Assert.IsFalse(LWin64.RuntimeOnly, 'Win64 runtimeOnly defaults to False');
    var LLinux64: TManifestPlatform;
    Assert.IsTrue(LManifest.Platforms.TryGetValue('Linux64', LLinux64), 'Linux64 platform present');
    Assert.AreEqual('Source\Core', LLinux64.SourcePath[0], 'Linux64 sourcePath[0]');
    Assert.IsFalse(LLinux64.RuntimeOnly, 'Linux64 runtimeOnly defaults to False');
  finally
    LManifest.Free;
  end;
end;

procedure TManifestDeserializationTest.TestPackages;
begin
  var LManifest := TJsonHelper.JSONToObject<TManifest>(FullManifestJSON);
  try
    Assert.AreEqual(2, LManifest.Packages.Count, 'packages count');

    var LRuntime := LManifest.Packages[0];
    Assert.AreEqual('Widgets', LRuntime.Name, 'packages[0].name');
    Assert.IsTrue(LRuntime.IsRuntime, 'packages[0] is runtime');
    Assert.IsFalse(LRuntime.IsDesignTime, 'packages[0] is not designtime');
    Assert.AreEqual(1, LRuntime.Products.Count, 'packages[0].products count');
    Assert.AreEqual('delphi11+', LRuntime.Products[0], 'packages[0].products[0]');

    var LDesign := LManifest.Packages[1];
    Assert.AreEqual('WidgetsDesign', LDesign.Name, 'packages[1].name');
    Assert.IsTrue(LDesign.IsDesignTime, 'packages[1] is designtime');
    Assert.IsFalse(LDesign.IsRuntime, 'packages[1] is not runtime');
    Assert.AreEqual(0, LDesign.Products.Count, 'packages[1].products is empty (no constraint)');
  finally
    LManifest.Free;
  end;
end;

procedure TManifestDeserializationTest.TestPackageOptions;
begin
  var LManifest := TJsonHelper.JSONToObject<TManifest>(FullManifestJSON);
  try
    Assert.AreEqual('pkgs', LManifest.PackageOptions.RootFolder, 'rootFolder');
    Assert.AreEqual(1, LManifest.PackageOptions.Folders.Count, 'folders count');

    var LFound := False;
    for var LFolder in LManifest.PackageOptions.Folders do
    begin
      Assert.AreEqual('delphi12+', LFolder.Key, 'folder key');
      Assert.AreEqual('12.0Athens', LFolder.Value, 'folder value');
      LFound := True;
    end;
    Assert.IsTrue(LFound, 'folders enumerated');
  finally
    LManifest.Free;
  end;
end;

procedure TManifestDeserializationTest.TestDependencies;
begin
  var LManifest := TJsonHelper.JSONToObject<TManifest>(FullManifestJSON);
  try
    Assert.AreEqual(1, LManifest.Dependencies.Count, 'dependencies count');

    var LFound := False;
    for var LDep in LManifest.Dependencies do
    begin
      Assert.AreEqual('acme.core', LDep.Key, 'dependency key');
      Assert.AreEqual('^2.0.0', LDep.Value, 'dependency value');
      LFound := True;
    end;
    Assert.IsTrue(LFound, 'dependencies enumerated');
  finally
    LManifest.Free;
  end;
end;

procedure TManifestDeserializationTest.TestScripts;
begin
  var LManifest := TJsonHelper.JSONToObject<TManifest>(FullManifestJSON);
  try
    Assert.AreEqual(2, LManifest.Scripts.Count, 'scripts count');

    var LEcho := LManifest.Scripts[0];
    Assert.AreEqual('echo', LEcho.Command, 'scripts[0].command');
    Assert.AreEqual('afterInstall', LEcho.Event, 'scripts[0].event');
    Assert.IsTrue(LEcho.Args is TManifestEchoArguments, 'scripts[0].args type');
    Assert.AreEqual('Installed $(NAME)', LEcho.Args.GetAs<TManifestEchoArguments>.Message, 'scripts[0].args.message');

    var LCompile := LManifest.Scripts[1];
    Assert.AreEqual('compile', LCompile.Command, 'scripts[1].command');
    Assert.AreEqual('Build helper', LCompile.Description, 'scripts[1].description');
    Assert.IsTrue(LCompile.Args is TManifestCompileArguments, 'scripts[1].args type');
    Assert.AreEqual(
        'Helper.dproj',
        LCompile.Args.GetAs<TManifestCompileArguments>.ProjectFile,
        'scripts[1].args.projectFile'
    );
    Assert.AreEqual(1, Length(LCompile.Args.GetAs<TManifestCompileArguments>.Platforms), 'scripts[1].args.platforms');
    Assert
        .AreEqual('Win32', LCompile.Args.GetAs<TManifestCompileArguments>.Platforms[0], 'scripts[1].args.platforms[0]');
  finally
    LManifest.Free;
  end;
end;

{ TManifestSerializationTest }

procedure TManifestSerializationTest.TestRoundTrip_BasicFields;
begin
  var LSrc := TJsonHelper.JSONToObject<TManifest>(FullManifestJSON);
  try
    var LText := TJsonHelper.ObjectToJSONString(LSrc);
    var LDst := TJsonHelper.JSONToObject<TManifest>(LText);
    try
      Assert.AreEqual(LSrc.Id, LDst.Id, 'id');
      Assert.AreEqual(LSrc.Name, LDst.Name, 'name');
      Assert.AreEqual(LSrc.Version, LDst.Version, 'version');
      Assert.AreEqual(LSrc.Description, LDst.Description, 'description');
      Assert.AreEqual(LSrc.License, LDst.License, 'license');
      Assert.AreEqual(LSrc.Homepage, LDst.Homepage, 'homepage');
      Assert.AreEqual(LSrc.Author, LDst.Author, 'author');
      Assert.AreEqual(LSrc.Repository.RepoType, LDst.Repository.RepoType, 'repository.type');
      Assert.AreEqual(
          LSrc.Repository.Config<TGitHubConfig>.Url,
          LDst.Repository.Config<TGitHubConfig>.Url,
          'repository.url'
      );
    finally
      LDst.Free;
    end;
  finally
    LSrc.Free;
  end;
end;

procedure TManifestSerializationTest.TestRoundTrip_Platforms;
begin
  var LSrc := TJsonHelper.JSONToObject<TManifest>(FullManifestJSON);
  try
    var LText := TJsonHelper.ObjectToJSONString(LSrc);
    var LDst := TJsonHelper.JSONToObject<TManifest>(LText);
    try
      Assert.AreEqual(LSrc.Platforms.Count, LDst.Platforms.Count, 'platforms count');

      var LWin32: TManifestPlatform;
      Assert.IsTrue(LDst.Platforms.TryGetValue('Win32', LWin32), 'Win32 present after round trip');
      Assert.AreEqual('Source\Core', LWin32.SourcePath[0], 'Win32 sourcePath[0]');
      Assert.IsTrue(LWin32.RuntimeOnly, 'Win32 runtimeOnly survives round trip');
    finally
      LDst.Free;
    end;
  finally
    LSrc.Free;
  end;
end;

procedure TManifestSerializationTest.TestRoundTrip_Packages;
begin
  var LSrc := TJsonHelper.JSONToObject<TManifest>(FullManifestJSON);
  try
    var LText := TJsonHelper.ObjectToJSONString(LSrc);
    var LDst := TJsonHelper.JSONToObject<TManifest>(LText);
    try
      Assert.AreEqual(LSrc.Packages.Count, LDst.Packages.Count, 'packages count');
      Assert.AreEqual('Widgets', LDst.Packages[0].Name, 'packages[0].name');
      Assert.AreEqual('delphi11+', LDst.Packages[0].Products[0], 'packages[0].products[0]');
      Assert.AreEqual('WidgetsDesign', LDst.Packages[1].Name, 'packages[1].name');
      Assert.IsTrue(LDst.Packages[1].IsDesignTime, 'packages[1] is designtime');
    finally
      LDst.Free;
    end;
  finally
    LSrc.Free;
  end;
end;

procedure TManifestSerializationTest.TestRoundTrip_Dependencies;
begin
  var LSrc := TJsonHelper.JSONToObject<TManifest>(FullManifestJSON);
  try
    var LText := TJsonHelper.ObjectToJSONString(LSrc);
    var LDst := TJsonHelper.JSONToObject<TManifest>(LText);
    try
      Assert.AreEqual(LSrc.Dependencies.Count, LDst.Dependencies.Count, 'dependencies count');

      var LFound := False;
      for var LDep in LDst.Dependencies do
      begin
        Assert.AreEqual('acme.core', LDep.Key, 'dependency key');
        Assert.AreEqual('^2.0.0', LDep.Value, 'dependency value');
        LFound := True;
      end;
      Assert.IsTrue(LFound, 'dependencies enumerated after round trip');
    finally
      LDst.Free;
    end;
  finally
    LSrc.Free;
  end;
end;

procedure TManifestSerializationTest.TestRoundTrip_Scripts;
begin
  // Exercises the *real* serialization path for the script list: TJsonSerializer
  // detects TManifestScript's ToJSON/FromJSON pair (IDynamicObject) rather than
  // walking its declared properties directly.
  var LSrc := TJsonHelper.JSONToObject<TManifest>(FullManifestJSON);
  try
    var LText := TJsonHelper.ObjectToJSONString(LSrc);
    var LDst := TJsonHelper.JSONToObject<TManifest>(LText);
    try
      Assert.AreEqual(LSrc.Scripts.Count, LDst.Scripts.Count, 'scripts count');

      Assert.AreEqual('echo', LDst.Scripts[0].Command, 'scripts[0].command');
      Assert.IsTrue(LDst.Scripts[0].Args is TManifestEchoArguments, 'scripts[0].args type after round trip');
      Assert.AreEqual(
          'Installed $(NAME)',
          LDst.Scripts[0].Args.GetAs<TManifestEchoArguments>.Message,
          'scripts[0].args.message'
      );

      Assert.AreEqual('compile', LDst.Scripts[1].Command, 'scripts[1].command');
      Assert.AreEqual('Build helper', LDst.Scripts[1].Description, 'scripts[1].description');
      Assert.IsTrue(LDst.Scripts[1].Args is TManifestCompileArguments, 'scripts[1].args type after round trip');
      Assert.AreEqual(
          'Helper.dproj',
          LDst.Scripts[1].Args.GetAs<TManifestCompileArguments>.ProjectFile,
          'scripts[1].args.projectFile'
      );
    finally
      LDst.Free;
    end;
  finally
    LSrc.Free;
  end;
end;

{ TManifestProductSupportTest }

procedure TManifestProductSupportTest.TestPackage_NoProductsSupportsAny;
begin
  var LPackage := TManifestPackage.Create;
  try
    Assert.IsTrue(LPackage.SupportsProduct('delphi13'), 'no constraint supports any product');
    Assert.IsTrue(LPackage.SupportsProduct('madeup'), 'no constraint supports even unknown product names');
  finally
    LPackage.Free;
  end;
end;

procedure TManifestProductSupportTest.TestPackage_ExactMatch;
begin
  var LPackage := TManifestPackage.Create;
  try
    LPackage.Products.Add('delphi12');
    Assert.IsTrue(LPackage.SupportsProduct('delphi12'), 'exact match supported');
  finally
    LPackage.Free;
  end;
end;

procedure TManifestProductSupportTest.TestPackage_ExactMatchCaseInsensitive;
begin
  var LPackage := TManifestPackage.Create;
  try
    LPackage.Products.Add('Delphi12');
    Assert.IsTrue(LPackage.SupportsProduct('delphi12'), 'exact match is case insensitive');
  finally
    LPackage.Free;
  end;
end;

procedure TManifestProductSupportTest.TestPackage_ExactMatchDoesNotMatchHigherVersion;
begin
  var LPackage := TManifestPackage.Create;
  try
    LPackage.Products.Add('delphi12');
    Assert.IsFalse(LPackage.SupportsProduct('delphi13'), 'exact entry without "+" does not extend forward');
  finally
    LPackage.Free;
  end;
end;

procedure TManifestProductSupportTest.TestPackage_PlusSuffixSupportsAtOrAboveVersion;
begin
  var LPackage := TManifestPackage.Create;
  try
    LPackage.Products.Add('delphi11+');
    Assert.IsTrue(LPackage.SupportsProduct('delphi11'), 'the base version itself is supported');
    Assert.IsTrue(LPackage.SupportsProduct('delphi13'), 'a later version is supported');
  finally
    LPackage.Free;
  end;
end;

procedure TManifestProductSupportTest.TestPackage_PlusSuffixExcludesBelowVersion;
begin
  var LPackage := TManifestPackage.Create;
  try
    LPackage.Products.Add('delphi11+');
    Assert.IsFalse(LPackage.SupportsProduct('delphi104'), 'an earlier version is not supported');
  finally
    LPackage.Free;
  end;
end;

procedure TManifestProductSupportTest.TestPackage_UnknownProductMatchesOnlyExactEntry;
begin
  var LPackage := TManifestPackage.Create;
  try
    LPackage.Products.Add('delphi11+');
    Assert.IsFalse(LPackage.SupportsProduct('customproduct'), 'unknown product fails the "+" rank comparison');

    LPackage.Products.Clear;
    LPackage.Products.Add('customproduct');
    Assert.IsTrue(LPackage.SupportsProduct('customproduct'), 'unknown product still matches an exact entry');
  finally
    LPackage.Free;
  end;
end;

procedure TManifestProductSupportTest.TestManifest_EmptyFoldersSupportsAnyProduct;
begin
  var LManifest := TManifest.Create;
  try
    Assert.IsTrue(LManifest.IsProductSupported('delphi13'), 'no folders supports any product');
    Assert.IsTrue(LManifest.IsProductSupported('madeup'), 'no folders supports even unknown product names');
  finally
    LManifest.Free;
  end;
end;

procedure TManifestProductSupportTest.TestManifest_FolderKeySupportsAtOrAboveVersion;
begin
  var LManifest := TManifest.Create;
  try
    LManifest.PackageOptions.Folders.Add('delphi12+', '12.0Athens');
    Assert.IsTrue(LManifest.IsProductSupported('delphi12'), 'the floor version is supported');
    Assert.IsTrue(LManifest.IsProductSupported('delphi13'), 'a later version is supported');
  finally
    LManifest.Free;
  end;
end;

procedure TManifestProductSupportTest.TestManifest_FolderKeyExcludesBelowVersion;
begin
  var LManifest := TManifest.Create;
  try
    LManifest.PackageOptions.Folders.Add('delphi12+', '12.0Athens');
    Assert.IsFalse(LManifest.IsProductSupported('delphi11'), 'an earlier version is not supported');
  finally
    LManifest.Free;
  end;
end;

procedure TManifestProductSupportTest.TestManifest_FolderKeyWithoutPlusBehavesSameAsWithPlus;
begin
  // IsProductSupported always treats a folder key as a floor (greatest-lower-bound
  // resolution), regardless of a trailing "+" — unlike TManifestPackage.SupportsProduct.
  var LManifest := TManifest.Create;
  try
    LManifest.PackageOptions.Folders.Add('delphi12', '12.0Athens');
    Assert.IsTrue(LManifest.IsProductSupported('delphi13'), 'a later version is supported without "+"');
    Assert.IsFalse(LManifest.IsProductSupported('delphi11'), 'an earlier version is still excluded');
  finally
    LManifest.Free;
  end;
end;

procedure TManifestProductSupportTest.TestManifest_MultipleFolderKeysPicksLowestApplicable;
begin
  var LManifest := TManifest.Create;
  try
    LManifest.PackageOptions.Folders.Add('delphi10+', 'old');
    LManifest.PackageOptions.Folders.Add('delphi12+', 'new');
    Assert.IsTrue(LManifest.IsProductSupported('delphi101'), 'covered by the lower "delphi10+" floor');
    Assert.IsFalse(LManifest.IsProductSupported('delphixe8'), 'below every floor');
  finally
    LManifest.Free;
  end;
end;

procedure TManifestProductSupportTest.TestManifest_UnknownProductNameIsNeverSupported;
begin
  var LManifest := TManifest.Create;
  try
    LManifest.PackageOptions.Folders.Add('delphi12+', '12.0Athens');
    Assert.IsFalse(LManifest.IsProductSupported('madeup'), 'unknown product rank never satisfies a floor');
  finally
    LManifest.Free;
  end;
end;

{ TManifestScriptJSONTest }

procedure TManifestScriptJSONTest.TestFromJSON_NilIsNoOp;
begin
  var LScript := TManifestScript.Create;
  try
    LScript.FromJSON(nil);
    Assert.AreEqual('', LScript.Command, 'command stays unset');
    Assert.AreEqual('', LScript.Event, 'event stays unset');
    Assert.IsNull(LScript.Args, 'args stays nil');
  finally
    LScript.Free;
  end;
end;

procedure TManifestScriptJSONTest.TestToJSON_OmitsEmptyDescriptionAndMissingArgs;
begin
  var LScript := TManifestScript.Create;
  try
    LScript.Command := 'echo';
    LScript.Event := 'afterInstall';

    var LJSON := LScript.ToJSON as TJSONObject;
    try
      Assert.AreEqual('echo', LJSON.GetValue<string>('command'), 'command');
      Assert.AreEqual('afterInstall', LJSON.GetValue<string>('event'), 'event');
      Assert.IsNull(LJSON.FindValue('description'), 'empty description is omitted');
      Assert.IsNull(LJSON.FindValue('args'), 'missing args is omitted');
    finally
      LJSON.Free;
    end;
  finally
    LScript.Free;
  end;
end;

procedure TManifestScriptJSONTest.TestFromJSONString_EchoArgsParsed;
begin
  var LScript := TManifestScript.Create;
  try
    LScript.FromJSONString(
        '''
        {
          "command": "echo",
          "event": "afterInstall",
          "args": "Hello $(NAME)"
        }
        '''
    );

    Assert.IsTrue(LScript.Args is TManifestEchoArguments, 'args decode to TManifestEchoArguments');
    Assert.AreEqual('Hello $(NAME)', LScript.Args.GetAs<TManifestEchoArguments>.Message, 'args.message');
  finally
    LScript.Free;
  end;
end;

procedure TManifestScriptJSONTest.TestFromJSONString_CompileArgsMissingPlatformsRaises;
begin
  var LScript := TManifestScript.Create;
  try
    Assert.WillRaise(
        procedure
        begin
          LScript.FromJSONString(
              '''
              {
                "command": "compile",
                "event": "afterInstall",
                "args": { "projectFile": "Helper.dproj" }
              }
              '''
          );
        end,
        Exception,
        '"platforms" is mandatory for "compile" args'
    );
  finally
    LScript.Free;
  end;
end;

procedure TManifestScriptJSONTest.TestFromJSONString_UnregisteredCommandFallsBackToNoArguments;
begin
  var LScript := TManifestScript.Create;
  try
    LScript.FromJSONString(
        '''
        {
          "command": "totallyunknowncommand",
          "event": "afterInstall"
        }
        '''
    );
    Assert.IsTrue(LScript.Args is TManifestNoArguments, 'unregistered command falls back to TManifestNoArguments');
  finally
    LScript.Free;
  end;
end;

{ TSupportedPlatformsJSONTest }

procedure TSupportedPlatformsJSONTest.TestFromJSON_NilIsNoOp;
begin
  var LPlatforms := TSupportedPlatforms.Create;
  try
    LPlatforms.FromJSON(nil);
    Assert.AreEqual(0, LPlatforms.Count, 'nil JSON adds nothing');
  finally
    LPlatforms.Free;
  end;
end;

procedure TSupportedPlatformsJSONTest.TestFromJSON_NonObjectIsNoOp;
begin
  var LPlatforms := TSupportedPlatforms.Create;
  try
    var LJSON := TJSONArray.Create;
    try
      LPlatforms.FromJSON(LJSON);
      Assert.AreEqual(0, LPlatforms.Count, 'a non-object JSON value adds nothing');
    finally
      LJSON.Free;
    end;
  finally
    LPlatforms.Free;
  end;
end;

procedure TSupportedPlatformsJSONTest.TestFromJSON_SingleKeyCreatesOnePlatform;
begin
  var LPlatforms := TSupportedPlatforms.Create;
  try
    var LJSON := TJSONObject.ParseJSONValue('{"Win32": {"sourcePath": ["Source\\Core"]}}');
    try
      LPlatforms.FromJSON(LJSON);

      Assert.AreEqual(1, LPlatforms.Count, 'one platform created');
      var LWin32: TManifestPlatform;
      Assert.IsTrue(LPlatforms.TryGetValue('Win32', LWin32), 'Win32 present');
      Assert.AreEqual('Source\Core', LWin32.SourcePath[0], 'sourcePath[0]');
    finally
      LJSON.Free;
    end;
  finally
    LPlatforms.Free;
  end;
end;

procedure TSupportedPlatformsJSONTest.TestFromJSON_CommaSeparatedKeySplitsIntoMultiplePlatforms;
begin
  var LPlatforms := TSupportedPlatforms.Create;
  try
    var LJSON := TJSONObject.ParseJSONValue('{"Win64,Linux64": {"sourcePath": ["Source\\Core"]}}');
    try
      LPlatforms.FromJSON(LJSON);

      Assert.AreEqual(2, LPlatforms.Count, 'comma-separated key expands into two entries');

      var LWin64, LLinux64: TManifestPlatform;
      Assert.IsTrue(LPlatforms.TryGetValue('Win64', LWin64), 'Win64 present');
      Assert.IsTrue(LPlatforms.TryGetValue('Linux64', LLinux64), 'Linux64 present');
      Assert.AreEqual('Source\Core', LWin64.SourcePath[0], 'Win64 sourcePath[0]');
      Assert.AreEqual('Source\Core', LLinux64.SourcePath[0], 'Linux64 sourcePath[0]');
      // Each split platform is decoded from its own clone of the JSON value, so
      // the two entries are equal but independent instances (not aliases).
      Assert.IsTrue(LWin64 <> LLinux64, 'Win64 and Linux64 are independent instances');
    finally
      LJSON.Free;
    end;
  finally
    LPlatforms.Free;
  end;
end;

procedure TSupportedPlatformsJSONTest.TestToJSON_WritesOneKeyPerPlatform;
begin
  var LPlatforms := TSupportedPlatforms.Create;
  try
    var LWin32 := TManifestPlatform.Create;
    LWin32.SourcePath.Add('Source\Core');
    LPlatforms.Add('Win32', LWin32);

    var LWin64 := TManifestPlatform.Create;
    LWin64.SourcePath.Add('Source\Core');
    LPlatforms.Add('Win64', LWin64);

    var LJSON := LPlatforms.ToJSON as TJSONObject;
    try
      Assert.AreEqual(2, LJSON.Count, 'one JSON key per platform entry');
      Assert.IsNotNull(LJSON.FindValue('Win32'), 'Win32 key present');
      Assert.IsNotNull(LJSON.FindValue('Win64'), 'Win64 key present');
    finally
      LJSON.Free;
    end;
  finally
    LPlatforms.Free;
  end;
end;

procedure TSupportedPlatformsJSONTest.TestToJSON_DoesNotCompactIdenticalPlatforms;
begin
  // Known limitation (see the TODO on TSupportedPlatforms.ToJSON): identical
  // platform entries should ideally be compacted back into a single
  // comma-separated key, mirroring what FromJSON expands. That compaction isn't
  // implemented yet -- Blocks never writes manifests today -- so the round trip
  // is asymmetric on purpose. This test documents the current behavior so it
  // fails loudly (and gets updated) once compaction is implemented.
  var LPlatforms := TSupportedPlatforms.Create;
  try
    var LJSON := TJSONObject.ParseJSONValue('{"Win64,Linux64": {"sourcePath": ["Source\\Core"]}}');
    try
      LPlatforms.FromJSON(LJSON);
    finally
      LJSON.Free;
    end;

    var LOutput := LPlatforms.ToJSON as TJSONObject;
    try
      Assert.AreEqual(2, LOutput.Count, 'identical platforms are written as separate keys, not compacted');
      Assert.IsNotNull(LOutput.FindValue('Win64'), 'Win64 key present');
      Assert.IsNotNull(LOutput.FindValue('Linux64'), 'Linux64 key present');
      Assert.IsNull(LOutput.FindValue('Win64,Linux64'), 'compacted comma key is not produced (not yet implemented)');
    finally
      LOutput.Free;
    end;
  finally
    LPlatforms.Free;
  end;
end;

initialization
  // Built-in commands ("echo", "compile", ...) register their [ScriptManifest(...)]
  // args class as a side effect; needed so TManifestScript.FromJSON can resolve them.
  // Safe to call again even if another test unit already did.
  RegisterScripts;

  TDUnitX.RegisterTestFixture(TManifestDeserializationTest);
  TDUnitX.RegisterTestFixture(TManifestSerializationTest);
  TDUnitX.RegisterTestFixture(TManifestProductSupportTest);
  TDUnitX.RegisterTestFixture(TManifestScriptJSONTest);
  TDUnitX.RegisterTestFixture(TSupportedPlatformsJSONTest);

end.
