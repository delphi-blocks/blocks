program Launcher;

{$APPTYPE CONSOLE}
{$R 'blocks_version.res' 'blocks_version.rc'}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Win.Registry;

function GetInstallPath: string;
var
  Reg: TRegistry;
begin
  Result := '';
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('Software\Blocks') then
    begin
      if Reg.ValueExists('InstallPath') then
        Result := Reg.ReadString('InstallPath');
    end;
  finally
    Reg.Free;
  end;
end;

function GetCommandLineArgs: string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to ParamCount do
  begin
    if I > 1 then
      Result := Result + ' ';
    Result := Result + '"' + ParamStr(I) + '"';
  end;
end;

var
  InstallPath: string;
  ExePath: string;
  CmdLine: string;
  SI: TStartupInfo;
  PI: TProcessInformation;
  ProcExitCode: DWORD;
begin
  InstallPath := GetInstallPath;

  if InstallPath = '' then
  begin
    Writeln('Blocks is not installed correctly.');
    ExitCode := 1;
    Exit;
  end;

  ExePath := IncludeTrailingPathDelimiter(InstallPath) + 'Blocks.exe';

  if not FileExists(ExePath) then
  begin
    Writeln('Executable not found: ' + ExePath);
    ExitCode := 1;
    Exit;
  end;

  CmdLine := '"' + ExePath + '"';
  if GetCommandLineArgs <> '' then
    CmdLine := CmdLine + ' ' + GetCommandLineArgs;

  ZeroMemory(@SI, SizeOf(SI));
  SI.cb := SizeOf(SI);

  if not CreateProcess(nil, PChar(CmdLine), nil, nil, True, 0, nil, nil, SI, PI) then
  begin
    Writeln('Failed to launch: ' + ExePath);
    ExitCode := 1;
    Exit;
  end;

  WaitForSingleObject(PI.hProcess, INFINITE);
  GetExitCodeProcess(PI.hProcess, ProcExitCode);
  CloseHandle(PI.hProcess);
  CloseHandle(PI.hThread);
  ExitCode := ProcExitCode;
end.
