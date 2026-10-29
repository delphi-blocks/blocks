unit Blocks.Tests.Script;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  DUnitX.TestFramework,
  Blocks.Core,
  Blocks.JSON,
  Blocks.Model.Manifest,
  Blocks.Model.Config,
  Blocks.Service.Script;

type
  // A throwaway command used to verify the registry: it records what it received.
  TFakeCommand = class(TScriptCommand)
  public
    class var
      LastArgs: string;
    class var
      LastManifest: TManifest;
    procedure Run(
        AHelper: IScriptHelper;
        AManifest: TManifest;
        AArgs: TManifestScriptArguments;
        AEnvironmentVariables: TStrings;
        AConfig: TConfig
    ); override;
  end;

  TManifestFakeArguments = class(TManifestScriptArguments)
  private
    FValue: string;
  public
    property Value: string read FValue;
    constructor Create(AValue: TJSONValue); override;
  end;

  [TestFixture]
  TScriptRunnerTest = class(TObject)
  private
    FManifest: TManifest;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestExpandsCommandBeforeDispatch;
    [Test]
    procedure TestUnknownCommandRaises;
    [Test]
    procedure TestCustomCommandIsRegisteredAndRun;
    [Test]
    procedure TestEventBoundCommandRejectsOtherEvents;
    [Test]
    procedure TestCopyResCopiesResAndDfm;
    [Test]
    procedure TestToJSONRoundTripsArgs;
    [Test]
    procedure TestManifestSerializationThroughFramework;
    [Test]
    procedure TestEventBoundCommandRegistersItsArgumentsClass;
    [Test]
    procedure TestFetchDecodesArgs;
    [Test]
    procedure TestFetchMissingUrlRaises;
    [Test]
    procedure TestFetchMissingOutputFileRaises;
    [Test]
    procedure TestCopyCopiesFile;
    [Test]
    procedure TestCopyMissingInputFileRaises;
    [Test]
    procedure TestCopyMissingOutputFileRaises;
    [Test]
    procedure TestCopyCopiesFileWithSourceAndTarget;
    [Test]
    procedure TestCopyDirectoryNonRecursive;
    [Test]
    procedure TestCopyDirectoryRecursive;
    [Test]
    procedure TestFilterTrueRunsTheScript;
    [Test]
    procedure TestFilterFalseSkipsTheScript;
    [Test]
    procedure TestFilterComparisonIsCaseSensitive;
    [Test]
    procedure TestFilterCombinesOperators;
    [Test]
    procedure TestFilterUnknownVariableIsEmptyString;
    [Test]
    procedure TestMissingFilterRunsTheScript;
    [Test]
    procedure TestFilterFalseSkipsUnknownCommand;
    [Test]
    procedure TestInvalidFilterRaises;
  end;

implementation

{ TFakeCommand }

procedure TFakeCommand.Run(
    AHelper: IScriptHelper;
    AManifest: TManifest;
    AArgs: TManifestScriptArguments;
    AEnvironmentVariables: TStrings;
    AConfig: TConfig
);
begin
  LastManifest := AManifest;
  LastArgs := ExpandVariables(AArgs.GetAs<TManifestFakeArguments>.Value, AEnvironmentVariables);
end;

procedure TScriptRunnerTest.Setup;
begin
  FManifest := TManifest.Create;
end;

procedure TScriptRunnerTest.TearDown;
begin
  FManifest.Free;
end;

procedure TScriptRunnerTest.TestExpandsCommandBeforeDispatch;
begin
  var LScript := TManifestScript.Create;
  var LEnv := TStringList.Create;
  try
    LScript.Command := '%CMD%';
    LEnv.Values['CMD'] := 'foo';

    var LRaised := False;
    try
      TScriptRunner.Execute(FManifest, LScript, LEnv);
    except
      on E: EScriptError do
      begin
        LRaised := True;
        Assert.Contains(E.Message, 'foo', 'command should be expanded before dispatch');
      end;
    end;
    Assert.IsTrue(LRaised, 'EScriptError expected');
  finally
    LEnv.Free;
    LScript.Free;
  end;
end;

procedure TScriptRunnerTest.TestUnknownCommandRaises;
begin
  var LScript := TManifestScript.Create;
  var LEnv := TStringList.Create;
  try
    LScript.Command := 'doesnotexist';
    Assert.WillRaise(procedure begin TScriptRunner.Execute(FManifest, LScript, LEnv); end, EScriptError);
  finally
    LEnv.Free;
    LScript.Free;
  end;
end;

procedure TScriptRunnerTest.TestCustomCommandIsRegisteredAndRun;
begin
  TScriptCommand.RegisterCommand('fake', TFakeCommand);
  TFakeCommand.LastArgs := '';
  TFakeCommand.LastManifest := nil;

  var LScript := TManifestScript.Create;
  var LEnv := TStringList.Create;
  try
    LScript.FromJSONString(
        '''
        {
          "command": "fake",
          "args": "a %V%",
          "event": "beforeCompile"
        }
        '''
    );
    LEnv.Values['V'] := 'b';

    TScriptRunner.Execute(FManifest, LScript, LEnv);

    Assert.AreEqual('a b', TFakeCommand.LastArgs, 'args should be expanded and forwarded');
    Assert.IsTrue(TFakeCommand.LastManifest = FManifest, 'manifest should be forwarded to the command');
  finally
    LEnv.Free;
    LScript.Free;
  end;
end;

procedure TScriptRunnerTest.TestEventBoundCommandRejectsOtherEvents;
begin
  // 'boundfake' is bound to afterCompile only (see initialization).
  var LEnv := TStringList.Create;
  var LRejected := TManifestScript.Create;
  var LAllowed := TManifestScript.Create;
  try
    // A different event is rejected.
    LRejected.FromJSONString(
        '''
        {
          "command": "boundfake",
          "args": "anything",
          "event": "beforeInstall"
        }
        '''
    );
    Assert.WillRaise(procedure begin TScriptRunner.Execute(FManifest, LRejected, LEnv); end, EScriptError);

    // The bound event runs fine.
    LAllowed.FromJSONString(
        '''
        {
          "command": "boundfake",
          "args": "anything",
          "event": "afterCompile"
        }
        '''
    );
    Assert.WillNotRaise(procedure begin TScriptRunner.Execute(FManifest, LAllowed, LEnv); end);
  finally
    LEnv.Free;
    LRejected.Free;
    LAllowed.Free;
  end;
end;

procedure TScriptRunnerTest.TestCopyResCopiesResAndDfm;
begin
  var LRoot := TPath.Combine(TPath.GetTempPath, 'blocks_copyres_' + TGUID.NewGuid.ToString);
  var LSourceDir := TPath.Combine(LRoot, 'Source');
  var LDcuDir := TPath.Combine(LRoot, 'dcu');
  TDirectory.CreateDirectory(LSourceDir);
  TDirectory.CreateDirectory(LDcuDir);
  try
    TFile.WriteAllText(TPath.Combine(LSourceDir, 'unit1.dfm'), 'dfm');
    TFile.WriteAllText(TPath.Combine(LSourceDir, 'unit1.res'), 'res');
    TFile.WriteAllText(TPath.Combine(LSourceDir, 'unit1.pas'), 'pas');

    // Declare the platform's source path in the manifest.
    var LPlat := TManifestPlatform.Create;
    LPlat.SourcePath.Add('Source');
    FManifest.Platforms.Add('Win32', LPlat);

    var LScript := TManifestScript.Create;
    var LEnv := TStringList.Create;
    try
      LScript.Command := 'copyres';
      LScript.Event := TScriptRunner.EventAfterCompile;
      LEnv.Values['PLATFORM'] := 'Win32';
      LEnv.Values['PROJECT_PATH'] := LRoot;
      LEnv.Values['DCU_PATH'] := LDcuDir;

      TScriptRunner.Execute(FManifest, LScript, LEnv);

      Assert.IsTrue(TFile.Exists(TPath.Combine(LDcuDir, 'unit1.dfm')), '.dfm should be copied');
      Assert.IsTrue(TFile.Exists(TPath.Combine(LDcuDir, 'unit1.res')), '.res should be copied');
      Assert.IsFalse(TFile.Exists(TPath.Combine(LDcuDir, 'unit1.pas')), '.pas should not be copied');
    finally
      LEnv.Free;
      LScript.Free;
    end;
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TScriptRunnerTest.TestToJSONRoundTripsArgs;
begin
  var LScript := TManifestScript.Create;
  try
    LScript.FromJSONString(
        '''
        {
          "command": "compile",
          "description": "Build the helper",
          "event": "afterInstall",
          "args": { "projectFile": "Helper.dproj", "platforms": ["Win32", "Win64"] }
        }
        '''
    );

    var LJSON := LScript.ToJSON as TJSONObject;
    try
      Assert.AreEqual('compile', LJSON.GetValue<string>('command'));
      Assert.AreEqual('Build the helper', LJSON.GetValue<string>('description'));
      Assert.AreEqual('afterInstall', LJSON.GetValue<string>('event'));
      // The args are preserved verbatim, including the nested object.
      Assert.AreEqual('Helper.dproj', LJSON.GetValue<string>('args.projectFile'));
      Assert.AreEqual('Win64', LJSON.GetValue<string>('args.platforms[1]'));
    finally
      LJSON.Free;
    end;
  finally
    LScript.Free;
  end;
end;

procedure TScriptRunnerTest.TestManifestSerializationThroughFramework;
begin
  // Exercise the *real* serialization path: a script inside the manifest goes
  // through TJsonSerializer, which detects the FromJSON/ToJSON pair and calls
  // TManifestScript.ToJSON. Verifies no AV / leak and that args survive.
  var LScript := TManifestScript.Create;
  LScript.FromJSONString(
      '''
      {
        "command": "compile",
        "event": "afterInstall",
        "args": { "projectFile": "Helper.dproj", "platforms": ["Win32"] }
      }
      '''
  );
  FManifest.Scripts.Add(LScript);

  var LText := TJsonHelper.ObjectToJSONString(FManifest);

  Assert.Contains(LText, '"command":"compile"');
  Assert.Contains(LText, '"projectFile":"Helper.dproj"');
end;

procedure TScriptRunnerTest.TestEventBoundCommandRegistersItsArgumentsClass;
begin
  // Registering through the events overload (as copyres/compile/expert do) must
  // still wire up the [ScriptManifest(...)] args class, not just the command.
  TScriptCommand.RegisterCommand('compiletest', TCompileCommand, [TScriptRunner.EventAfterInstall]);

  var LScript := TManifestScript.Create;
  try
    LScript.FromJSONString(
        '''
        {
          "command": "compiletest",
          "event": "afterInstall",
          "args": { "projectFile": "x.dproj", "platforms": ["Win32"] }
        }
        '''
    );
    Assert.IsTrue(
        LScript.Args is TManifestCompileArguments,
        'args should decode to TManifestCompileArguments, got ' + LScript.Args.ClassName
    );
  finally
    LScript.Free;
  end;
end;

procedure TScriptRunnerTest.TestFetchDecodesArgs;
begin
  var LScript := TManifestScript.Create;
  var LEnv := TStringList.Create;
  try
    LScript.FromJSONString(
        '''
        {
          "command": "fetch",
          "event": "afterCompile",
          "args": { "url": "https://example.com/data.bin", "outputFile": "$(DCU_PATH)\\data.bin" }
        }
        '''
    );
    LEnv.Values['DCU_PATH'] := 'C:\out';

    var LArgs := LScript.Args.GetAs<TManifestFetchArguments>;
    Assert.AreEqual('https://example.com/data.bin', LArgs.Url, 'url should decode');
    // The output file is variable-expanded by the command using the same helper.
    Assert.AreEqual('C:\out\data.bin', ExpandVariables(LArgs.OutputFile, LEnv), 'outputFile should expand');
  finally
    LEnv.Free;
    LScript.Free;
  end;
end;

procedure TScriptRunnerTest.TestFetchMissingUrlRaises;
begin
  var LScript := TManifestScript.Create;
  var LEnv := TStringList.Create;
  try
    LScript.FromJSONString(
        '''
        {
          "command": "fetch",
          "event": "afterCompile",
          "args": { "outputFile": "C:\\out\\data.bin" }
        }
        '''
    );
    Assert.WillRaise(procedure begin TScriptRunner.Execute(FManifest, LScript, LEnv); end, EScriptError);
  finally
    LEnv.Free;
    LScript.Free;
  end;
end;

procedure TScriptRunnerTest.TestFetchMissingOutputFileRaises;
begin
  var LScript := TManifestScript.Create;
  var LEnv := TStringList.Create;
  try
    LScript.FromJSONString(
        '''
        {
          "command": "fetch",
          "event": "afterCompile",
          "args": { "url": "https://example.com/data.bin" }
        }
        '''
    );
    Assert.WillRaise(procedure begin TScriptRunner.Execute(FManifest, LScript, LEnv); end, EScriptError);
  finally
    LEnv.Free;
    LScript.Free;
  end;
end;

procedure TScriptRunnerTest.TestCopyCopiesFile;
begin
  var LRoot := TPath.Combine(TPath.GetTempPath, 'blocks_copy_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LRoot);
  try
    TFile.WriteAllText(TPath.Combine(LRoot, 'in.txt'), 'hello');

    var LScript := TManifestScript.Create;
    var LEnv := TStringList.Create;
    try
      // Relative paths are resolved against $(PROJECT_PATH); the output subdir
      // does not exist yet, so the command must create it.
      LScript.FromJSONString(
          '''
          {
            "command": "copy",
            "event": "afterCompile",
            "args": { "inputFile": "in.txt", "outputFile": "sub\\out.txt" }
          }
          '''
      );
      LEnv.Values['PROJECT_PATH'] := LRoot;

      TScriptRunner.Execute(FManifest, LScript, LEnv);

      var LOut := TPath.Combine(LRoot, TPath.Combine('sub', 'out.txt'));
      Assert.IsTrue(TFile.Exists(LOut), 'output file should be created (with missing dir)');
      Assert.AreEqual('hello', TFile.ReadAllText(LOut), 'content should match the source');
    finally
      LEnv.Free;
      LScript.Free;
    end;
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TScriptRunnerTest.TestCopyMissingInputFileRaises;
begin
  var LScript := TManifestScript.Create;
  var LEnv := TStringList.Create;
  try
    LScript.FromJSONString(
        '''
        {
          "command": "copy",
          "event": "afterCompile",
          "args": { "outputFile": "C:\\out\\data.bin" }
        }
        '''
    );
    Assert.WillRaise(procedure begin TScriptRunner.Execute(FManifest, LScript, LEnv); end, EScriptError);
  finally
    LEnv.Free;
    LScript.Free;
  end;
end;

procedure TScriptRunnerTest.TestCopyMissingOutputFileRaises;
begin
  var LScript := TManifestScript.Create;
  var LEnv := TStringList.Create;
  try
    LScript.FromJSONString(
        '''
        {
          "command": "copy",
          "event": "afterCompile",
          "args": { "inputFile": "C:\\in\\data.bin" }
        }
        '''
    );
    Assert.WillRaise(procedure begin TScriptRunner.Execute(FManifest, LScript, LEnv); end, EScriptError);
  finally
    LEnv.Free;
    LScript.Free;
  end;
end;

procedure TScriptRunnerTest.TestCopyCopiesFileWithSourceAndTarget;
begin
  var LRoot := TPath.Combine(TPath.GetTempPath, 'blocks_copy_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LRoot);
  try
    TFile.WriteAllText(TPath.Combine(LRoot, 'in.txt'), 'hello');

    var LScript := TManifestScript.Create;
    var LEnv := TStringList.Create;
    try
      LScript.FromJSONString(
          '''
          {
            "command": "copy",
            "event": "afterCompile",
            "args": { "source": "in.txt", "target": "sub\\out.txt" }
          }
          '''
      );
      LEnv.Values['PROJECT_PATH'] := LRoot;

      TScriptRunner.Execute(FManifest, LScript, LEnv);

      var LOut := TPath.Combine(LRoot, TPath.Combine('sub', 'out.txt'));
      Assert.IsTrue(TFile.Exists(LOut), 'output file should be created (with missing dir)');
      Assert.AreEqual('hello', TFile.ReadAllText(LOut), 'content should match the source');
    finally
      LEnv.Free;
      LScript.Free;
    end;
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TScriptRunnerTest.TestCopyDirectoryNonRecursive;
begin
  var LRoot := TPath.Combine(TPath.GetTempPath, 'blocks_copy_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(TPath.Combine(LRoot, TPath.Combine('src', 'nested')));
  try
    TFile.WriteAllText(TPath.Combine(LRoot, TPath.Combine('src', 'a.inc')), 'a');
    TFile.WriteAllText(TPath.Combine(LRoot, TPath.Combine('src', TPath.Combine('nested', 'b.inc'))), 'b');

    var LScript := TManifestScript.Create;
    var LEnv := TStringList.Create;
    try
      LScript.FromJSONString(
          '''
          {
            "command": "copy",
            "event": "afterCompile",
            "args": { "source": "src", "target": "dst" }
          }
          '''
      );
      LEnv.Values['PROJECT_PATH'] := LRoot;

      TScriptRunner.Execute(FManifest, LScript, LEnv);

      var LDst := TPath.Combine(LRoot, 'dst');
      Assert.IsTrue(TFile.Exists(TPath.Combine(LDst, 'a.inc')), 'top-level file should be copied');
      Assert.AreEqual('a', TFile.ReadAllText(TPath.Combine(LDst, 'a.inc')), 'content should match the source');
      Assert.IsFalse(
          TDirectory.Exists(TPath.Combine(LDst, 'nested')),
          'sub-directories should be skipped without "recursive"'
      );
    finally
      LEnv.Free;
      LScript.Free;
    end;
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TScriptRunnerTest.TestCopyDirectoryRecursive;
begin
  var LRoot := TPath.Combine(TPath.GetTempPath, 'blocks_copy_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(TPath.Combine(LRoot, TPath.Combine('src', 'nested')));
  try
    TFile.WriteAllText(TPath.Combine(LRoot, TPath.Combine('src', 'a.inc')), 'a');
    TFile.WriteAllText(TPath.Combine(LRoot, TPath.Combine('src', TPath.Combine('nested', 'b.inc'))), 'b');

    var LScript := TManifestScript.Create;
    var LEnv := TStringList.Create;
    try
      LScript.FromJSONString(
          '''
          {
            "command": "copy",
            "event": "afterCompile",
            "args": { "source": "src", "target": "dst", "recursive": true }
          }
          '''
      );
      LEnv.Values['PROJECT_PATH'] := LRoot;

      TScriptRunner.Execute(FManifest, LScript, LEnv);

      var LDst := TPath.Combine(LRoot, 'dst');
      Assert.IsTrue(TFile.Exists(TPath.Combine(LDst, 'a.inc')), 'top-level file should be copied');
      var LNested := TPath.Combine(LDst, TPath.Combine('nested', 'b.inc'));
      Assert.IsTrue(TFile.Exists(LNested), 'nested file should be copied with "recursive"');
      Assert.AreEqual('b', TFile.ReadAllText(LNested), 'nested content should match the source');
    finally
      LEnv.Free;
      LScript.Free;
    end;
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

// Runs the 'fake' command with AFilter and the Win32/Release compile variables,
// returning what the command recorded ('' when the filter skipped the script).
function RunFiltered(AManifest: TManifest; const AFilter: string): string;
begin
  TScriptCommand.RegisterCommand('fake', TFakeCommand);
  TFakeCommand.LastArgs := '';

  var LScript := TManifestScript.Create;
  var LEnv := TStringList.Create;
  try
    LScript.FromJSONString(
        '''
        {
          "command": "fake",
          "args": "ran",
          "event": "afterCompile"
        }
        '''
    );
    LScript.Filter := AFilter;

    LEnv.Values['PLATFORM'] := 'Win32';
    LEnv.Values['CONFIG'] := 'Release';
    LEnv.Values['PACKAGE'] := 'JclVcl';

    TScriptRunner.Execute(AManifest, LScript, LEnv);
    Result := TFakeCommand.LastArgs;
  finally
    LEnv.Free;
    LScript.Free;
  end;
end;

procedure TScriptRunnerTest.TestFilterTrueRunsTheScript;
begin
  Assert.AreEqual('ran', RunFiltered(FManifest, '$(PLATFORM) = ''Win32'''), 'matching filter should run the script');
end;

procedure TScriptRunnerTest.TestFilterFalseSkipsTheScript;
begin
  Assert.AreEqual('', RunFiltered(FManifest, '$(PLATFORM) = ''Win64'''), 'non-matching filter should skip the script');
end;

procedure TScriptRunnerTest.TestFilterComparisonIsCaseSensitive;
begin
  // String comparisons are delegated to the bindings evaluator; docs/script.md
  // promises they are case-sensitive.
  Assert.AreEqual('ran', RunFiltered(FManifest, '$(PLATFORM) = ''Win32'''), 'exact casing should match');
  Assert.AreEqual('', RunFiltered(FManifest, '$(PLATFORM) = ''win32'''), 'lower-case literal should not match');
  Assert.AreEqual('', RunFiltered(FManifest, '$(PLATFORM) = ''WIN32'''), 'upper-case literal should not match');
  Assert.AreEqual('ran', RunFiltered(FManifest, '$(PLATFORM) <> ''win32'''), 'different casing should compare unequal');
end;

procedure TScriptRunnerTest.TestFilterCombinesOperators;
begin
  Assert.AreEqual(
      'ran',
      RunFiltered(FManifest, '$(PLATFORM) = ''Win64'' or $(PACKAGE) = ''JclVcl'''),
      '"or" should run the script when the second operand holds'
  );
  Assert.AreEqual(
      'ran',
      RunFiltered(FManifest, '($(PLATFORM) = ''Win32'') and ($(CONFIG) <> ''Debug'')'),
      '"and"/"<>"/parentheses should be supported'
  );
  Assert.AreEqual(
      '',
      RunFiltered(FManifest, '$(PLATFORM) = ''Win32'' and $(CONFIG) = ''Debug'''),
      '"and" should skip the script when one operand fails'
  );
end;

procedure TScriptRunnerTest.TestFilterUnknownVariableIsEmptyString;
begin
  // A variable not defined for the event binds to '', as ExpandVariables does.
  Assert.AreEqual('ran', RunFiltered(FManifest, '$(NOPE) = '''''), 'unknown variables should compare equal to ""');
  Assert.AreEqual('', RunFiltered(FManifest, '$(NOPE) <> '''''), 'unknown variables should not compare unequal to ""');
end;

procedure TScriptRunnerTest.TestMissingFilterRunsTheScript;
begin
  Assert.AreEqual('ran', RunFiltered(FManifest, ''), 'an empty filter means "always run"');
  Assert.AreEqual('ran', RunFiltered(FManifest, '   '), 'a blank filter means "always run"');
end;

procedure TScriptRunnerTest.TestFilterFalseSkipsUnknownCommand;
begin
  // The filter is evaluated before the command is resolved, so a script excluded
  // by it never reports the unknown command.
  var LScript := TManifestScript.Create;
  var LEnv := TStringList.Create;
  try
    LScript.Command := 'doesnotexist';
    LScript.Filter := '$(PLATFORM) = ''Win64''';
    LEnv.Values['PLATFORM'] := 'Win32';

    Assert.WillNotRaise(procedure begin TScriptRunner.Execute(FManifest, LScript, LEnv); end);
  finally
    LEnv.Free;
    LScript.Free;
  end;
end;

procedure TScriptRunnerTest.TestInvalidFilterRaises;
begin
  var LScript := TManifestScript.Create;
  var LEnv := TStringList.Create;
  try
    LScript.Command := 'echo';
    LScript.Filter := '$(PLATFORM) = ';
    LEnv.Values['PLATFORM'] := 'Win32';

    Assert.WillRaise(procedure begin TScriptRunner.Execute(FManifest, LScript, LEnv); end, EScriptError);
  finally
    LEnv.Free;
    LScript.Free;
  end;
end;

{ TManifestFakeArguments }

constructor TManifestFakeArguments.Create(AValue: TJSONValue);
begin
  inherited;
  FValue := '';
  if AValue is TJSONString then
  begin
    FValue := AValue.Value;
    Exit;
  end;
end;

initialization
  // The app registers the built-in commands from Blocks.dpr; the test exe must
  // do the same so tests can use 'copyres', 'compile', etc.
  RegisterScripts;

  TScriptCommand.RegisterCommand('fake', TFakeCommand, [TScriptRunner.EventAfterCompile]);
  TManifest.RegisterScriptManifest('fake', TManifestFakeArguments);

  // A dedicated command kept bound to afterCompile; 'fake' is re-registered
  // unbound by TestCustomCommandIsRegisteredAndRun, so it can't test binding.
  TScriptCommand.RegisterCommand('boundfake', TFakeCommand, [TScriptRunner.EventAfterCompile]);
  TManifest.RegisterScriptManifest('boundfake', TManifestFakeArguments);

  TDUnitX.RegisterTestFixture(TScriptRunnerTest);

end.
