unit Blocks.Model.SysConfig;

interface

uses
  System.Classes, System.SysUtils, System.IOUtils,
  System.Win.Registry;

type
  TSystemConfig = class(TObject)
  public
    const InstallPath = 'Software\Blocks';
    class function Get(const AKey: string): string; static;
    class procedure &Set(const AKey, AValue: string); static;
    class procedure Add(const AKey, AValue: string); static;
    class procedure GetAll(AConfigs: TStrings); static;
  end;

implementation

{ TSystemConfig }

class procedure TSystemConfig.Add(const AKey, AValue: string);
begin
  raise Exception.CreateFmt('System config key "%s" does not support multiple values.', [AKey]);
end;

class function TSystemConfig.Get(const AKey: string): string;
begin
  if SameText(AKey, 'InstallPath') then
  begin
    var LReg := TRegistry.Create;
    try
      if not LReg.KeyExists(InstallPath) then
        raise Exception.Create('Blocks launcher not installed');
      LReg.OpenKey(InstallPath, False);
      Result := LReg.ReadString('InstallPath');
    finally
      LReg.Free;
    end;
  end
  else
    raise Exception.CreateFmt('System config "%s" not found', [AKey]);

end;

class procedure TSystemConfig.GetAll(AConfigs: TStrings);
begin
  AConfigs.Values['InstallPath'] := Get('InstallPath');
end;

class procedure TSystemConfig.&Set(const AKey, AValue: string);
begin
  if SameText(AKey, 'InstallPath') then
  begin
    if not FileExists(TPath.Combine(AValue, 'blocks.exe')) then
      raise Exception.Create('Blocks not found in the specified path');
    var LReg := TRegistry.Create;
    try
      if not LReg.KeyExists(InstallPath) then
        raise Exception.Create('Blocks launcher not installed');
      LReg.OpenKey(InstallPath, False);
      LReg.WriteString('InstallPath', AValue);
    finally
      LReg.Free;
    end;
  end
  else
    raise Exception.CreateFmt('System config "%s" not found', [AKey]);
end;

end.
