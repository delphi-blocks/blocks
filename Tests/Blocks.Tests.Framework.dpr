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
program Blocks.Tests.Framework;

{$IFNDEF DEBUG}
{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$ENDIF}
{$STRONGLINKTYPES ON}
uses
  System.SysUtils,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ENDIF }
  {$IFDEF DEBUG}
  DUnitX.Loggers.GUI.VCL,
  {$ENDIF }
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  {$IFDEF RELEASE}
  Winapi.ActiveX,
  {$ENDIF }
  Blocks.Tests.SemVer in 'Blocks.Tests.SemVer.pas',
  Blocks.Console in '..\Source\Blocks.Console.pas',
  Blocks.Http in '..\Source\Blocks.Http.pas',
  Blocks.JSON in '..\Source\Blocks.JSON.pas',
  Blocks.Tests.JSON in 'Blocks.Tests.JSON.pas',
  Blocks.Core in '..\Source\Blocks.Core.pas',
  Blocks.Model.Package in '..\Source\Blocks.Model.Package.pas',
  Blocks.Tests.Package in 'Blocks.Tests.Package.pas';

var
  runner : ITestRunner;
  results : IRunResults;
  logger : ITestLogger;
  nunitLogger : ITestLogger;
begin
  ReportMemoryLeaksOnShutdown := True;
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
  Exit;
{$ENDIF}
{$IFDEF DEBUG}
  DUnitX.Loggers.GUI.VCL.Run;
  Exit;
{$ENDIF}
{$IFDEF RELEASE}
  CoInitialize(nil);
{$ENDIF }

  try
    //Check command line options, will exit if invalid
    TDUnitX.CheckCommandLine;
    //Create the test runner
    runner := TDUnitX.CreateRunner;
    //Tell the runner to use RTTI to find Fixtures
    runner.UseRTTI := True;
    //tell the runner how we will log things
    //Log to the console window
    logger := TDUnitXConsoleLogger.Create(true);
    runner.AddLogger(logger);
    //Generate an NUnit compatible XML File
    nunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    runner.AddLogger(nunitLogger);
    runner.FailsOnNoAsserts := False; //When true, Assertions must be made during tests;

    //Run tests
    results := runner.Execute;
    if not results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    {$IFNDEF CI}
    //We don't want this happening when running under CI.
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
    {$ENDIF}
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
{$IFDEF RELEASE}
  CoUninitialize;
{$ENDIF }
end.
