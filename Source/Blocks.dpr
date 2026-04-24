program Blocks;

{$APPTYPE CONSOLE}
{$R *.res}

{$R 'blocks_version.res' 'blocks_version.rc'}

uses
  Winapi.ActiveX,
  System.SysUtils,
  Blocks.CLI.App in 'Blocks.CLI.App.pas',
  Blocks.Console in 'Blocks.Console.pas',
  Blocks.Http in 'Blocks.Http.pas',
  Blocks.Model.Database in 'Blocks.Model.Database.pas',
  Blocks.Model.Manifest in 'Blocks.Model.Manifest.pas',
  Blocks.Service.Workspace in 'Blocks.Service.Workspace.pas',
  Blocks.Service.Product in 'Blocks.Service.Product.pas',
  Blocks.JSON in 'Blocks.JSON.pas',
  Blocks.CLI.Command in 'Blocks.CLI.Command.pas',
  Blocks.GitHub in 'Blocks.GitHub.pas',
  Blocks.Core in 'Blocks.Core.pas',
  Blocks.Model.Config in 'Blocks.Model.Config.pas',
  Blocks.Model.SysConfig in 'Blocks.Model.SysConfig.pas',
  Blocks.Model.Package in 'Blocks.Model.Package.pas';

begin
  {$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
  try
    CoInitialize(nil);
    try
      TApp.RunBlocks;
    finally
      CoUninitialize;
    end;
  except
    on E: Exception do
    begin
      TConsole.WriteLine;
      TConsole.WriteError('[ERROR] ' + E.Message);
      TConsole.WriteLine;
      ExitCode := 1;
    end;
  end;
end.
