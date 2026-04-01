program Blocks;

{$APPTYPE CONSOLE}
{$R *.res}

{$R 'blocks_version.res' 'blocks_version.rc'}

uses
  System.SysUtils,
  Blocks.App in 'Blocks.App.pas',
  Blocks.Consts in 'Blocks.Consts.pas',
  Blocks.Console in 'Blocks.Console.pas',
  Blocks.Http in 'Blocks.Http.pas',
  Blocks.Database in 'Blocks.Database.pas',
  Blocks.Manifest in 'Blocks.Manifest.pas',
  Blocks.Workspace in 'Blocks.Workspace.pas',
  Blocks.Product in 'Blocks.Product.pas';

begin
  try
    TApp.RunBlocks;
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
