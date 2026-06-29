unit Blocks.Model.SysConfig;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.Win.Registry;

type
  TSystemConfig = class(TObject)
  private
    class function GetAutoUpdate: Boolean; static;
    class function GetInstallPath: string; static;
    class function GetGitPath: string; static;
  public
    const
      DefaultRegistryKey = 'Software\Blocks';
      InstallPathKey = 'InstallPath';
      AutoUpdateKey = 'AutoUpdate';
      GitPathKey = 'GitPath';
    class function GetValue(const AKey: string): string; static;
    class procedure SetValue(const AKey, AValue: string); static;
    class procedure Add(const AKey, AValue: string); static;
    class procedure Delete(const AKey, AValue: string); static;
    class procedure GetAll(AConfigs: TStrings); static;

    /// <summary>Full path to <c>git.exe</c> when configured, otherwise <c>git</c>
    ///   (resolved through the PATH).</summary>
    class function GitExecutable: string; static;

    class property AutoUpdate: Boolean read GetAutoUpdate;
    class property InstallPath: string read GetInstallPath;
    /// <summary>Configured path to <c>git.exe</c>, or an empty string when unset.</summary>
    class property GitPath: string read GetGitPath;
  end;

implementation

{ TSystemConfig }

class procedure TSystemConfig.Add(const AKey, AValue: string);
begin
  raise Exception.CreateFmt('System config key "%s" does not support multiple values.', [AKey]);
end;

class procedure TSystemConfig.Delete(const AKey, AValue: string);
begin
  raise Exception.CreateFmt('System config key "%s" does not support multiple values.', [AKey]);
end;

class function TSystemConfig.GetValue(const AKey: string): string;
begin
  if SameText(AKey, InstallPathKey) then
  begin
    var LReg := TRegistry.Create;
    try
      if not LReg.KeyExists(DefaultRegistryKey) then
        raise Exception.Create('Blocks launcher not installed');
      LReg.OpenKey(DefaultRegistryKey, False);
      Result := LReg.ReadString(InstallPathKey);
    finally
      LReg.Free;
    end;
  end
  else if SameText(AKey, AutoUpdateKey) then
  begin
    // Absent value means "enabled": the check is on by default.
    var LResult := True;
    var LReg := TRegistry.Create;
    try
      if LReg.OpenKeyReadOnly(DefaultRegistryKey) and LReg.ValueExists(AutoUpdateKey) then
        try
          LResult := LReg.ReadBool(AutoUpdateKey);
        except
          // A malformed/legacy value must not break every command: fall back to enabled.
          LResult := True;
        end;
    finally
      LReg.Free;
    end;

    Result := BoolToStr(LResult, True);
  end
  else if SameText(AKey, GitPathKey) then
  begin
    // Absent value means "use git from PATH": return an empty string, do not raise.
    Result := '';
    var LReg := TRegistry.Create;
    try
      if LReg.OpenKeyReadOnly(DefaultRegistryKey) and LReg.ValueExists(GitPathKey) then
        Result := LReg.ReadString(GitPathKey);
    finally
      LReg.Free;
    end;
  end
  else
    raise Exception.CreateFmt('System config "%s" not found', [AKey]);
end;

class procedure TSystemConfig.GetAll(AConfigs: TStrings);
begin
  // InstallPath only exists when the launcher is installed; skip it otherwise so
  // the always-available keys are still listed.
  try
    AConfigs.Values[InstallPathKey] := GetValue(InstallPathKey);
  except
  end;
  AConfigs.Values[AutoUpdateKey] := GetValue(AutoUpdateKey);
  // Use Add (not Values[]) so the key still appears when unset: assigning an empty
  // value through Values[] would delete the entry.
  AConfigs.Add(GitPathKey + '=' + GetValue(GitPathKey));
end;

class function TSystemConfig.GetAutoUpdate: Boolean;
begin
  Result := StrToBool(GetValue(AutoUpdateKey));
end;

class function TSystemConfig.GetInstallPath: string;
begin
  Result := GetValue(InstallPathKey);
end;

class function TSystemConfig.GetGitPath: string;
begin
  Result := GetValue(GitPathKey);
end;

class function TSystemConfig.GitExecutable: string;
begin
  Result := GetGitPath;
  if Result = '' then
    Result := 'git';
end;

class procedure TSystemConfig.SetValue(const AKey, AValue: string);
begin
  if SameText(AKey, InstallPathKey) then
  begin
    if not FileExists(TPath.Combine(AValue, 'blocks.exe')) then
      raise Exception.Create('Blocks not found in the specified path');
    var LReg := TRegistry.Create;
    try
      if not LReg.KeyExists(DefaultRegistryKey) then
        raise Exception.Create('Blocks launcher not installed');
      LReg.OpenKey(DefaultRegistryKey, False);
      LReg.WriteString(InstallPathKey, AValue);
    finally
      LReg.Free;
    end;
  end
  else if SameText(AKey, AutoUpdateKey) then
  begin
    if not (SameText(AValue, 'true') or SameText(AValue, 'false')) then
      raise Exception.CreateFmt('Invalid boolean value "%s" for "%s" (use true or false)', [AValue, AKey]);
    var LReg := TRegistry.Create;
    try
      if not LReg.OpenKey(DefaultRegistryKey, True) then
        raise Exception.Create('Unable to open the Blocks registry key');
      LReg.WriteBool(AutoUpdateKey, StrToBool(AValue));
    finally
      LReg.Free;
    end;
  end
  else if SameText(AKey, GitPathKey) then
  begin
    if not FileExists(AValue) then
      raise Exception.CreateFmt('git executable not found: %s', [AValue]);
    var LReg := TRegistry.Create;
    try
      if not LReg.OpenKey(DefaultRegistryKey, True) then
        raise Exception.Create('Unable to open the Blocks registry key');
      LReg.WriteString(GitPathKey, AValue);
    finally
      LReg.Free;
    end;
  end
  else
    raise Exception.CreateFmt('System config "%s" not found', [AKey]);
end;

end.
