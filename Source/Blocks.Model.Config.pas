unit Blocks.Model.Config;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  /// <summary>Compiler tools architecture MSBuild should use (Delphi 13+). Maps to the
  ///   <c>DCC_PreferredToolArchitecture</c> MSBuild property: <c>x32</c> uses the 32-bit
  ///   compiler tools, <c>x64</c> the 64-bit ones (which give the compiler more memory).
  ///   It only affects the tools, not the produced binary. <c>default</c> (the default)
  ///   leaves the choice to Delphi: the property is not passed to MSBuild at all.</summary>
  TToolArchitecture = (default, x32, x64);

  /// <summary>Which IDE binary <c>run</c> launches: <c>Win32</c> uses the 32-bit IDE
  ///   (registry value <c>App</c>, <c>...\bin\bds.exe</c>), <c>Win64</c> the 64-bit IDE
  ///   (registry value <c>App64</c>, <c>...\bin64\bds.exe</c>) when available. <c>default</c>
  ///   uses the 32-bit IDE.</summary>
  TIdeArchitecture = (default, Win32, Win64);

  /// <summary>IDE personality <c>run</c> selects via <c>bds.exe -p &lt;personality&gt;</c>.
  ///   <c>default</c> passes nothing (the IDE picks its own default).</summary>
  TIdePersonality = (default, Delphi, CBuilder);

  /// <summary>HighDPI awareness override <c>run</c> passes via <c>bds.exe -highdpi:&lt;value&gt;</c>.
  ///   <c>default</c> passes nothing (the IDE uses its configured setting).</summary>
  TIdeHighDpi = (default, unaware, systemaware, permonitor, permonitorv2, unawaregdiscaling);
  {$SCOPEDENUMS OFF}

  TConfig = class(TObject)
  private
    FSources: TStringList;
    FPlatforms: TStringList;
    FProduct: string;
    FRegistryKey: string;
    FWorkspaceDir: string;
    FUpdateDCPSearchPath: Boolean;
    FToolArchitecture: TToolArchitecture;
    FCBuilderOutput: string;
    FIdeArchitecture: TIdeArchitecture;
    FIdePersonality: TIdePersonality;
    FIdeHighDpi: TIdeHighDpi;
    function ConfigPath: string;
  public
    property Sources: TStringList read FSources;
    /// <summary>Platforms this workspace targets. An empty list means "all platforms
    ///   supported by the configured Delphi version" (see <c>IsPlatformEnabled</c>).</summary>
    property Platforms: TStringList read FPlatforms;

    property Product: string read FProduct write FProduct;
    property RegistryKey: string read FRegistryKey write FRegistryKey;
    /// <summary>When True, "init" registers the blocks DCP output directory on the
    ///   Delphi library Search Path (see <c>TProduct.CheckDCPPath</c>). Default False.</summary>
    property UpdateDCPSearchPath: Boolean read FUpdateDCPSearchPath write FUpdateDCPSearchPath;
    /// <summary>Tools architecture passed to MSBuild as
    ///   <c>/p:DCC_PreferredToolArchitecture=&lt;x32|x64&gt;</c> (Delphi 13+). When
    ///   <c>default</c> (the default) the property is not passed to MSBuild at all.</summary>
    property ToolArchitecture: TToolArchitecture read FToolArchitecture write FToolArchitecture;
    /// <summary>Value passed to MSBuild as <c>/p:DCC_CBuilderOutput=&lt;value&gt;</c> when
    ///   compiling packages (e.g. <c>All</c> to generate C++ output). Used verbatim;
    ///   an empty string (the default) means the property is not passed to MSBuild.</summary>
    property CBuilderOutput: string read FCBuilderOutput write FCBuilderOutput;
    /// <summary>IDE architecture <c>run</c> launches (Delphi 13+ ships a 64-bit IDE). When
    ///   <c>Win64</c> the <c>App64</c> binary is used if present, otherwise it falls back to
    ///   the 32-bit <c>App</c>. Default <c>default</c> (32-bit IDE).</summary>
    property IdeArchitecture: TIdeArchitecture read FIdeArchitecture write FIdeArchitecture;
    /// <summary>IDE personality <c>run</c> selects (<c>bds.exe -p</c>). Default <c>default</c>.</summary>
    property IdePersonality: TIdePersonality read FIdePersonality write FIdePersonality;
    /// <summary>HighDPI override <c>run</c> applies (<c>bds.exe -highdpi:</c>). Default <c>default</c>.</summary>
    property IdeHighDpi: TIdeHighDpi read FIdeHighDpi write FIdeHighDpi;

    /// <summary>Returns True when <paramref name="APlatform"/> is enabled for this
    ///   workspace, i.e. the <c>Platforms</c> list is empty (all) or contains it.</summary>
    function IsPlatformEnabled(const APlatform: string): Boolean;

    procedure Load;
    procedure Save;
    function ToJson: string;

    function GetValue(const AKey: string): string;
    procedure SetValue(const AKey, AValue: string);
    procedure Add(const AKey, AValue: string);
    procedure Delete(const AKey, AValue: string);

    constructor Create(const AWorkspaceDir: string);
    destructor Destroy; override;
  end;

/// <summary>Returns the MSBuild value (<c>x32</c>/<c>x64</c>) for an architecture.</summary>
function ToolArchitectureToStr(const AValue: TToolArchitecture): string;

/// <summary>Parses <c>x32</c>/<c>x64</c> (case-insensitive); raises on anything else.</summary>
function StrToToolArchitecture(const AValue: string): TToolArchitecture;

/// <summary>Returns the config string (<c>default</c>/<c>Win32</c>/<c>Win64</c>) for an IDE architecture.</summary>
function IdeArchitectureToStr(const AValue: TIdeArchitecture): string;

/// <summary>Parses <c>default</c>/<c>win32</c>/<c>win64</c> (case-insensitive); raises on anything else.</summary>
function StrToIdeArchitecture(const AValue: string): TIdeArchitecture;

/// <summary>Returns the config string (<c>default</c>/<c>Delphi</c>/<c>CBuilder</c>) for an IDE personality.</summary>
function IdePersonalityToStr(const AValue: TIdePersonality): string;

/// <summary>Parses <c>default</c>/<c>delphi</c>/<c>cbuilder</c> (case-insensitive); raises on anything else.</summary>
function StrToIdePersonality(const AValue: string): TIdePersonality;

/// <summary>Returns the config string for a HighDPI override (e.g. <c>permonitorv2</c>).</summary>
function IdeHighDpiToStr(const AValue: TIdeHighDpi): string;

/// <summary>Parses a HighDPI override name (case-insensitive); raises on anything else.</summary>
function StrToIdeHighDpi(const AValue: string): TIdeHighDpi;

implementation

uses
  Blocks.JSON,
  Blocks.Core;

const
  WorkspaceSchemaUrl = 'https://delphi-blocks.dev/schema/workspace.v1.json';
  DefaultBlocksRepositoryUrl = 'https://github.com/delphi-blocks/blocks-repository';

function ToolArchitectureToStr(const AValue: TToolArchitecture): string;
begin
  case AValue of
    TToolArchitecture.x32: Result := 'x32';
    TToolArchitecture.x64: Result := 'x64';
  else
    Result := 'default';
  end;
end;

function StrToToolArchitecture(const AValue: string): TToolArchitecture;
begin
  if SameText(AValue, 'default') then
    Result := TToolArchitecture.default
  else if SameText(AValue, 'x32') then
    Result := TToolArchitecture.x32
  else if SameText(AValue, 'x64') then
    Result := TToolArchitecture.x64
  else
    raise Exception.CreateFmt('Invalid value "%s" for "toolArchitecture" (use default, x32 or x64)', [AValue]);
end;

function IdeArchitectureToStr(const AValue: TIdeArchitecture): string;
begin
  case AValue of
    TIdeArchitecture.Win32: Result := 'Win32';
    TIdeArchitecture.Win64: Result := 'Win64';
  else
    Result := 'default';
  end;
end;

function StrToIdeArchitecture(const AValue: string): TIdeArchitecture;
begin
  if SameText(AValue, 'default') then
    Result := TIdeArchitecture.default
  else if SameText(AValue, 'Win32') then
    Result := TIdeArchitecture.Win32
  else if SameText(AValue, 'Win64') then
    Result := TIdeArchitecture.Win64
  else
    raise Exception.CreateFmt('Invalid value "%s" for "ideArchitecture" (use default, Win32 or Win64)', [AValue]);
end;

function IdePersonalityToStr(const AValue: TIdePersonality): string;
begin
  case AValue of
    TIdePersonality.Delphi: Result := 'Delphi';
    TIdePersonality.CBuilder: Result := 'CBuilder';
  else
    Result := 'default';
  end;
end;

function StrToIdePersonality(const AValue: string): TIdePersonality;
begin
  if SameText(AValue, 'default') then
    Result := TIdePersonality.default
  else if SameText(AValue, 'Delphi') then
    Result := TIdePersonality.Delphi
  else if SameText(AValue, 'CBuilder') then
    Result := TIdePersonality.CBuilder
  else
    raise Exception.CreateFmt('Invalid value "%s" for "idePersonality" (use default, Delphi or CBuilder)', [AValue]);
end;

function IdeHighDpiToStr(const AValue: TIdeHighDpi): string;
begin
  case AValue of
    TIdeHighDpi.unaware: Result := 'unaware';
    TIdeHighDpi.systemaware: Result := 'systemaware';
    TIdeHighDpi.permonitor: Result := 'permonitor';
    TIdeHighDpi.permonitorv2: Result := 'permonitorv2';
    TIdeHighDpi.unawaregdiscaling: Result := 'unawaregdiscaling';
  else
    Result := 'default';
  end;
end;

function StrToIdeHighDpi(const AValue: string): TIdeHighDpi;
begin
  if SameText(AValue, 'default') then
    Result := TIdeHighDpi.default
  else if SameText(AValue, 'unaware') then
    Result := TIdeHighDpi.unaware
  else if SameText(AValue, 'systemaware') then
    Result := TIdeHighDpi.systemaware
  else if SameText(AValue, 'permonitor') then
    Result := TIdeHighDpi.permonitor
  else if SameText(AValue, 'permonitorv2') then
    Result := TIdeHighDpi.permonitorv2
  else if SameText(AValue, 'unawaregdiscaling') then
    Result := TIdeHighDpi.unawaregdiscaling
  else
    raise Exception.CreateFmt(
        'Invalid value "%s" for "ideHighDpi" (use default, unaware, systemaware, permonitor, permonitorv2 or unawaregdiscaling)',
        [AValue]);
end;

{ TConfig }

procedure TConfig.SetValue(const AKey, AValue: string);
begin
  if SameText(AKey, 'sources') then
  begin
    var LSources := AValue.Split([',']);
    FSources.Clear;
    for var S in LSources do
      FSources.Add(S);
  end
  else if SameText(AKey, 'platforms') then
  begin
    FPlatforms.Clear;
    // An empty value clears the list, restoring the "all platforms" default.
    if AValue <> '' then
      for var LPlatform in AValue.Split([',']) do
        FPlatforms.Add(LPlatform);
  end
  else if SameText(AKey, 'product') then
    FProduct := AValue
  else if SameText(AKey, 'registrykey') then
    FRegistryKey := AValue
  else if SameText(AKey, 'updatedcpsearchpath') then
  begin
    if SameText(AValue, 'true') then
      FUpdateDCPSearchPath := True
    else if SameText(AValue, 'false') then
      FUpdateDCPSearchPath := False
    else
      raise Exception.CreateFmt('Invalid boolean value "%s" for "%s" (use true or false)', [AValue, AKey]);
  end
  else if SameText(AKey, 'toolarchitecture') then
    FToolArchitecture := StrToToolArchitecture(AValue)
  else if SameText(AKey, 'cbuilderoutput') then
    FCBuilderOutput := AValue
  else if SameText(AKey, 'idearchitecture') then
    FIdeArchitecture := StrToIdeArchitecture(AValue)
  else if SameText(AKey, 'idepersonality') then
    FIdePersonality := StrToIdePersonality(AValue)
  else if SameText(AKey, 'idehighdpi') then
    FIdeHighDpi := StrToIdeHighDpi(AValue)
  else
    raise Exception.CreateFmt('Config "%s" does not exists', [AKey]);
end;

procedure TConfig.Add(const AKey, AValue: string);
begin
  if SameText(AKey, 'sources') then
    FSources.Add(AValue)
  else if SameText(AKey, 'platforms') then
    FPlatforms.Add(AValue)
  else
    raise Exception.CreateFmt('Config "%s" does not exists or doesn''t support /ADD', [AKey]);
end;

procedure TConfig.Delete(const AKey, AValue: string);
begin
  if SameText(AKey, 'sources') then
  begin
    var LIndex := FSources.IndexOf(AValue);
    if LIndex < 0 then
      raise Exception.CreateFmt('Value "%s" not found in "%s"', [AValue, AKey]);
    FSources.Delete(LIndex);
  end
  else if SameText(AKey, 'platforms') then
  begin
    var LIndex := FPlatforms.IndexOf(AValue);
    if LIndex < 0 then
      raise Exception.CreateFmt('Value "%s" not found in "%s"', [AValue, AKey]);
    FPlatforms.Delete(LIndex);
  end
  else
    raise Exception.CreateFmt('Config "%s" does not exists or doesn''t support /DELETE', [AKey]);
end;

function TConfig.ConfigPath: string;
begin
  var LBlocksDir := TPath.Combine(FWorkspaceDir, '.blocks');
  ForceDirectories(LBlocksDir);
  Result := TPath.Combine(LBlocksDir, 'workspace.json');
end;

constructor TConfig.Create(const AWorkspaceDir: string);
begin
  inherited Create;
  FWorkspaceDir := AWorkspaceDir;
  FSources := TStringList.Create;
  FSources.Add(DefaultBlocksRepositoryUrl);
  FPlatforms := TStringList.Create;
  FRegistryKey := 'BDS';
  FUpdateDCPSearchPath := False;
  FToolArchitecture := TToolArchitecture.default;
  FCBuilderOutput := '';
  FIdeArchitecture := TIdeArchitecture.default;
  FIdePersonality := TIdePersonality.default;
  FIdeHighDpi := TIdeHighDpi.default;
end;

destructor TConfig.Destroy;
begin
  FSources.Free;
  FPlatforms.Free;
  inherited;
end;

function TConfig.IsPlatformEnabled(const APlatform: string): Boolean;
begin
  Result := PlatformInList(FPlatforms.ToStringArray, APlatform);
end;

function TConfig.GetValue(const AKey: string): string;
begin
  if SameText(AKey, 'sources') then
    Result := string.Join(',', FSources.ToStringArray)
  else if SameText(AKey, 'platforms') then
    Result := string.Join(',', FPlatforms.ToStringArray)
  else if SameText(AKey, 'product') then
    Result := FProduct
  else if SameText(AKey, 'registrykey') then
    Result := FRegistryKey
  else if SameText(AKey, 'updatedcpsearchpath') then
  begin
    if FUpdateDCPSearchPath then
      Result := 'true'
    else
      Result := 'false';
  end
  else if SameText(AKey, 'toolarchitecture') then
    Result := ToolArchitectureToStr(FToolArchitecture)
  else if SameText(AKey, 'cbuilderoutput') then
    Result := FCBuilderOutput
  else if SameText(AKey, 'idearchitecture') then
    Result := IdeArchitectureToStr(FIdeArchitecture)
  else if SameText(AKey, 'idepersonality') then
    Result := IdePersonalityToStr(FIdePersonality)
  else if SameText(AKey, 'idehighdpi') then
    Result := IdeHighDpiToStr(FIdeHighDpi)
  else
    raise Exception.CreateFmt('Config "%s" does not exists', [AKey]);
end;

procedure TConfig.Load;
begin
  if FileExists(ConfigPath) then
  begin
    var LJSON := TJSONObject.ParseJSONValue(TFile.ReadAllText(ConfigPath), False, True);
    try
      TJsonHelper.CheckSchema(LJSON, WorkspaceSchemaUrl);
      TJsonHelper.JSONToObject(Self, LJSON);
    finally
      LJSON.Free;
    end;
  end;
end;

procedure TConfig.Save;
begin
  var LJSON := TJsonHelper.ObjectToJSON(Self) as TJSONObject;
  try
    LJSON.AddPair('$schema', WorkspaceSchemaUrl);
    TFile.WriteAllText(ConfigPath, TJsonHelper.PrettyPrint(LJSON));
  finally
    LJSON.Free;
  end;
end;

function TConfig.ToJson: string;
begin
  var LJSON := TJsonHelper.ObjectToJSON(Self) as TJSONObject;
  try
    LJSON.AddPair('$schema', WorkspaceSchemaUrl);
    Result := TJsonHelper.PrettyPrint(LJSON.ToJSON);
  finally
    LJSON.Free;
  end;
end;

end.
