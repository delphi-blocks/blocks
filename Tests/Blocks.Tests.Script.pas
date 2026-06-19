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
