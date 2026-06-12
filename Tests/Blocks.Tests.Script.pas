unit Blocks.Tests.Script;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  DUnitX.TestFramework,
  Blocks.Model.Manifest,
  Blocks.Service.Script;

type
  // A throwaway command used to verify the registry: it records what it received.
  TFakeCommand = class(TScriptCommand)
  public
    class var
      LastArgs: string;
    class var
      LastManifest: TManifest;
    procedure Run(AHelper: IScriptHelper; AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings); override;
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
    procedure TestEchoIsRecognized;
    [Test]
    procedure TestCustomCommandIsRegisteredAndRun;
    [Test]
    procedure TestEventBoundCommandRejectsOtherEvents;
    [Test]
    procedure TestCopyResCopiesResAndDfm;
  end;

implementation

{ TFakeCommand }

procedure TFakeCommand.Run(AHelper: IScriptHelper; AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings);
begin
  LastManifest := AManifest;
  LastArgs := string.Join(' ', AArgs.ToStringArray);
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

procedure TScriptRunnerTest.TestEchoIsRecognized;
begin
  var LScript := TManifestScript.Create;
  var LEnv := TStringList.Create;
  try
    LScript.Command := 'echo';
    LScript.Args.Add('Hello %NAME%');
    LEnv.Values['NAME'] := 'World';

    // "echo" is a recognised command: it must not raise (it prints "Hello World").
    Assert.WillNotRaise(procedure begin TScriptRunner.Execute(FManifest, LScript, LEnv); end);
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
    LScript.Command := 'fake';
    LScript.Args.Add('a %V%');
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
  // Bind the command to afterCompile only.
  TScriptCommand.RegisterCommand('boundfake', TFakeCommand, [TScriptRunner.EventAfterCompile]);

  var LScript := TManifestScript.Create;
  var LEnv := TStringList.Create;
  try
    LScript.Command := 'boundfake';

    // A different event is rejected.
    LScript.Event := TScriptRunner.EventBeforeInstall;
    Assert.WillRaise(procedure begin TScriptRunner.Execute(FManifest, LScript, LEnv); end, EScriptError);

    // The bound event runs fine.
    LScript.Event := TScriptRunner.EventAfterCompile;
    Assert.WillNotRaise(procedure begin TScriptRunner.Execute(FManifest, LScript, LEnv); end);
  finally
    LEnv.Free;
    LScript.Free;
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

initialization
  TDUnitX.RegisterTestFixture(TScriptRunnerTest);

end.
