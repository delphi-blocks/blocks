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
unit Blocks.JSON;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Rtti, System.TypInfo,
  System.Generics.Collections;

type
  EJSONBlockError = class(Exception)
  end;

  EJSONSerializerError = class(EJSONBlockError)
  end;

  EJSONDeserializerError = class(EJSONBlockError)
  end;

  JsonNameAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    property Name: string read FName;
    constructor Create(const AName: string);
  end;

  TJsonHelper = class
  private
    class procedure PrettyPrint(const AJSONString: string; AWriter: TTextWriter); overload; static;
  public
    class function JSONToObject<T: class, constructor>(AJson: TJSONValue):T; overload; static;
    class function JSONToObject<T: class, constructor>(const AJsonString: string):T; overload; static;
    class function JSONToObject(AType: TRttiType; AJSON: TJSONValue): TObject; overload;
    class procedure JSONToObject(AObject: TObject; AType: TRttiType; AJSON: TJSONValue); overload;
    class procedure JSONToObject(AObject: TObject; AJSON: TJSONValue); overload;
    class procedure JSONToObject(AObject: TObject; const AJSONString: string); overload;
    class function ValueAs<T>(AJSONValue: TJSONValue; ADefault: T): T; static;

    class function ObjectToJSONString(AObject: TObject): string; overload;
    class function ObjectToJSON(AObject: TObject): TJSONValue; overload;
    class function PrettyPrint(AJSON: TJSONValue): string; overload; static;
    class function PrettyPrint(const AJSONString: string): string; overload; static;

    /// <summary>Raises an exception if the JSON contains a "$schema" field that
    /// does not match <c>AExpectedSchema</c>. A missing field is silently ignored.</summary>
    class procedure CheckSchema(AJSON: TJSONValue; const AExpectedSchema: string); static;
  end;

  IDynamicType = interface
  ['{DD163E75-134C-4035-809C-D9E1EEEC4225}']
  end;

  IDynamicList = interface(IDynamicType)
  ['{9F4A2D72-078B-4EA2-B86E-068206AD0F16}']
    function NewItem: TValue;
    function GetItemType: TRttiType;
    procedure Add(AItem: TValue);
    procedure Clear;
    function Count: Integer;
    // Enumerator functions
    function Current: TValue;
    function MoveNext: Boolean;
  end;

  IDynamicMap = interface(IDynamicType)
  ['{89E60A06-C1A9-4D70-83B8-85D9B29510DB}']
    function NewKey: TValue;
    function NewValue: TValue;
    function GetKeyType: TRttiType;
    function GetValueType: TRttiType;
    procedure Add(const AKey, AValue: TValue);
    procedure Clear;
    function Count: Integer;
    // Enumerator functions
    function CurrentKey: TValue;
    function CurrentValue: TValue;
    function MoveNext: Boolean;
    // Key-related functions
    function KeyIsString: Boolean;
    function KeyToString(const AKey: TValue): string;
    procedure KeyFromString(const AKey: TValue; const AStringVal: string);
  end;

  TJsonSerializer = class
  private
    function IsEnumerableMap(AObject: TObject; out AMap: IDynamicMap): Boolean;
    function IsEnumerableList(AObject: TObject; out AList: IDynamicList): Boolean;
    function WriteList(AObject: TObject; AList: IDynamicList): TJSONArray;
    function WriteDictionary(AObject: TObject; AMap: IDynamicMap): TJSONObject;
    function WriteDataMembers(AObject: TObject): TJSONObject;
    function WriteStringListMembers(AObject: TStrings): TJSONArray;
    function WriteDataMember(AType: TRttiType; AValue: TValue): TJSONValue;
  public
    function ObjectToJSON(AObject: TObject): TJSONValue;
  end;

  TJsonDeserializer = class
  private
    function IsEnumerableMap(AObject: TObject; out AMap: IDynamicMap): Boolean;
    function IsEnumerableList(AObject: TObject; out AList: IDynamicList): Boolean;
    procedure ReadDataMember(AType: TRttiType; var AValue: TValue; AJSON: TJSONValue);
    procedure ReadDataMembers(AObject: TObject; AType: TRttiType; AJSON: TJSONValue);
    procedure ReadDictionary(ADynamicMap: IDynamicMap; AJSONObject: TJSONObject);
    procedure ReadList(ADynamicList: IDynamicList; AJSONArray: TJSONArray);
    procedure ReadStringList(AObject: TStrings; AJSON: TJSONArray);
  public
    procedure JSONToObject(AObject: TObject; AType: TRttiType; AJSON: TJSONValue);
  end;

  TRttiHelper = class
  private
    class var FContext: TRttiContext;
  public
    class constructor Create;
    class destructor Destroy;
    class property Context: TRttiContext read FContext;

    class function GetType(AValue: TValue): TRttiType; overload; static;

    class function CreateInstance(AType: TRttiType): TObject; overload; static;
    class function CreateNewValue(AType: TRttiType): TValue; overload; static;
    class function CreateInstance(AClass: TClass): TObject; overload; static;
    class function CreateInstance(const ATypeName: string): TObject; overload; static;
    class function CreateInstance(AClass: TClass; const AValue: string): TObject; overload; static;
    class function CreateInstance(AType: TRttiType; const AValue: string): TObject; overload; static;
    class function CreateInstanceValue(AType: TRttiType): TValue; overload; static;
  end;

  TCaseAlgorithm = class
  public
    class function CamelToPascal(const AString: string): string; static;
    class function PascalToCamel(const AString: string): string; static;
  end;

  TDynamicList = class(TInterfacedObject, IDynamicList)
  private
    FInstance: TObject;
    FEnumInstance: TObject;
    FItemType: TRttiType;
    FAddMethod: TRttiMethod;
    FClearMethod: TRttiMethod;
    FMoveNextMethod: TRttiMethod;
    FCurrentProperty: TRttiProperty;
    FCountProperty: TRttiProperty;
    constructor Create(AInstance, AEnumInstance: TObject; AItemType: TRttiType;
      AAddMethod, AClearMethod, AMoveNextMethod: TRttiMethod;
      ACurrentProperty, ACountProperty: TRttiProperty);
  public
    destructor Destroy; override;
    class function GuessType(AInstance: TObject): IDynamicList;
  public
    function NewItem: TValue;
    function GetItemType: TRttiType;
    procedure Add(AItem: TValue);
    procedure Clear;
    function Count: Integer;
    // Enumerator functions
    function Current: TValue;
    function MoveNext: Boolean;
  end;

  TDynamicMap = class(TInterfacedObject, IDynamicMap)
  public type
    TEnumerator = class
    private
      const CURRENT_PROP = 'Current';
      const MOVENEXT_METH = 'MoveNext';
    private
      FInstance: TObject;
      FMoveNextMethod: TRttiMethod;
      FCurrentProperty: TRttiProperty;
    public
      constructor Create(AMethod: TRttiMethod; AInstance: TObject);
      destructor Destroy; override;
    public
      function Current: TValue;
      function MoveNext: Boolean;
    end;
  private
    FInstance: TObject;
    FKeyType: TRttiType;
    FValueType: TRttiType;
    FAddMethod: TRttiMethod;
    FClearMethod: TRttiMethod;
    FKeyEnum: TDynamicMap.TEnumerator;
    FValueEnum: TDynamicMap.TEnumerator;
    FCountProp: TRttiProperty;
    FToStringMethod: TRttiMethod;
    FFromStringMethod: TRttiMethod;

    constructor Create(AInstance: TObject; AKeyType, AValueType: TRttiType;
      AAddMethod, AClearMethod: TRttiMethod; ACountProp: TRttiProperty;
      AKeyEnum, AValueEnum: TDynamicMap.TEnumerator; AToStringMethod, AFromStringMethod: TRttiMethod);
  public
    class function GuessType(AInstance: TObject): IDynamicMap;
    destructor Destroy; override;
  public
    function NewKey: TValue;
    function NewValue: TValue;
    function GetKeyType: TRttiType;
    function GetValueType: TRttiType;
    procedure Add(const AKey, AValue: TValue);
    procedure Clear;
    function Count: Integer;
    // Enumerator functions
    function CurrentKey: TValue;
    function CurrentValue: TValue;
    function MoveNext: Boolean;
    // Key-related functions
    function KeyIsString: Boolean;
    function KeyToString(const AKey: TValue): string;
    procedure KeyFromString(const AKey: TValue; const AStringVal: string);
  end;

implementation

function GetJSONFieldName(AProp: TRttiNamedObject): string;
begin
  if AProp.HasAttribute(JsonNameAttribute) then
    Result := AProp.GetAttribute<JsonNameAttribute>.Name
  else
    Result := TCaseAlgorithm.PascalToCamel(AProp.Name);
end;

class function TCaseAlgorithm.PascalToCamel(const AString: string): string;
var
  LOld, LNew: Char;
begin
  Result := AString;
  if Result.IsEmpty then
    Exit;

  LOld := Result.Chars[0];
  LNew := LowerCase(LOld).Chars[0];

  Result := Result.Replace(LOld, LNew, []);
end;

class function TCaseAlgorithm.CamelToPascal(const AString: string): string;
var
  LOld, LNew: Char;
begin
  Result := AString;
  if Result.IsEmpty then
    Exit;

  LOld := Result.Chars[0];
  LNew := UpperCase(LOld).Chars[0];

  Result := Result.Replace(LOld, LNew, []);
end;

{ TJsonHelper }

class function TJsonHelper.JSONToObject(AType: TRttiType;
  AJSON: TJSONValue): TObject;
begin
  Result := TRttiHelper.CreateInstance(AType);
  try
    JSONToObject(Result, AType, AJSON);
  except
    Result.Free;
    raise;
  end;
end;

class procedure TJsonHelper.JSONToObject(AObject: TObject; AType: TRttiType;
  AJSON: TJSONValue);
begin
  var LDeserializer := TJsonDeserializer.Create;
  try
    LDeserializer.JSONToObject(AObject, AType, AJSON);
  finally
    LDeserializer.Free;
  end;
end;

class procedure TJsonHelper.JSONToObject(AObject: TObject; AJSON: TJSONValue);
begin
  JSONToObject(AObject, TRttiHelper.Context.GetType(AObject.ClassType) , AJSON);
end;

class procedure TJsonHelper.JSONToObject(AObject: TObject;
  const AJSONString: string);
begin
  var LJson := TJSONObject.ParseJSONValue(AJsonString, False, True);
  try
    JSONToObject(AObject, LJson);
  finally
    LJson.Free;
  end;
end;

class function TJsonHelper.JSONToObject<T>(const AJsonString: string): T;
begin
  var LJson := TJSONObject.ParseJSONValue(AJsonString, False, True);
  try
    Result := JSONToObject<T>(LJson);
  finally
    LJson.Free;
  end;
end;

class function TJsonHelper.ObjectToJSON(AObject: TObject): TJSONValue;
var
  LWriter: TJsonSerializer;
begin
  LWriter := TJsonSerializer.Create();
  try
    Result := LWriter.ObjectToJSON(AObject);
  finally
    LWriter.Free;
  end;
end;

class function TJsonHelper.ObjectToJSONString(AObject: TObject): string;
begin
  var LJSON := ObjectToJSON(AObject);
  try
    Result := LJSON.ToJSON;
  finally
    LJSON.Free;
  end;
end;

class procedure TJsonHelper.PrettyPrint(const AJSONString: string; AWriter: TTextWriter);

  function Spaces(AOffset: Integer): string; inline;
  begin
    Result := StringOfChar(#32, AOffset * 2);
  end;

begin
  var LOffset := 0;
  var LOutsideString := True;

  var LPrev := #0;
  for var LIndex := 0 to Length(AJSONString) - 1 do
  begin
    var LChar := AJSONString.Chars[LIndex];

    if (LChar = '"') and not (LPrev = '\') then
      LOutsideString := not LOutsideString;

    if LOutsideString and (LChar = '{') then
    begin
      Inc(LOffset);
      AWriter.Write(LChar);
      AWriter.Write(sLineBreak);
      AWriter.Write(Spaces(LOffset));
    end
    else if LOutsideString and (LChar = '}') then
    begin
      Dec(LOffset);
      AWriter.Write(sLineBreak);
      AWriter.Write(Spaces(LOffset));
      AWriter.Write(LChar);
    end
    else if LOutsideString and (LChar = ',') then
    begin
      AWriter.Write(LChar);
      AWriter.Write(sLineBreak);
      AWriter.Write(Spaces(LOffset));
    end
    else if LOutsideString and (LChar = '[') then
    begin
      Inc(LOffset);
      AWriter.Write(LChar);
      AWriter.Write(sLineBreak);
      AWriter.Write(Spaces(LOffset));
    end
    else if LOutsideString and (LChar = ']') then
    begin
      Dec(LOffset);
      AWriter.Write(sLineBreak);
      AWriter.Write(Spaces(LOffset));
      AWriter.Write(LChar);
    end
    else if LOutsideString and (LChar = ':') then
    begin
      AWriter.Write(LChar);
      AWriter.Write(' ');
    end
    else
      AWriter.Write(LChar);

    LPrev := LChar;
  end;
end;

class function TJsonHelper.PrettyPrint(const AJSONString: string): string;
begin
  var LWriter := TStringWriter.Create();
  try
    PrettyPrint(AJSONString, LWriter);
    Result := LWriter.ToString;
  finally
    LWriter.Free;
  end;
end;

class function TJsonHelper.ValueAs<T>(AJSONValue: TJSONValue; ADefault: T): T;
begin
  if not Assigned(AJSONValue) then
    Exit(ADefault);
  if not AJSONValue.TryGetValue<T>(Result) then
    Result := ADefault;
end;

class function TJsonHelper.PrettyPrint(AJSON: TJSONValue): string;
begin
  Result := TJsonHelper.PrettyPrint(AJSON.ToJSON);
end;

class function TJsonHelper.JSONToObject<T>(AJson: TJSONValue): T;
begin
  Result := JSONToObject(TRttiHelper.Context.GetType(TClass(T)), AJSON) as T;
end;

class procedure TJsonHelper.CheckSchema(AJSON: TJSONValue; const AExpectedSchema: string);
var
  LSchemaValue: TJSONValue;
begin
  if not (AJSON is TJSONObject) then
    raise Exception.CreateFmt('Unsupported schema: expected "%s"', [AExpectedSchema]);
  LSchemaValue := TJSONObject(AJSON).GetValue('$schema');
  if not Assigned(LSchemaValue) then
    raise Exception.CreateFmt('Unsupported schema: expected "%s"', [AExpectedSchema]);
  if LSchemaValue.Value <> AExpectedSchema then
    raise Exception.CreateFmt('Unsupported schema: "%s"', [LSchemaValue.Value]);
end;

{ TJsonDeserializer }

function TJsonDeserializer.IsEnumerableList(AObject: TObject;
  out AList: IDynamicList): Boolean;
begin
  AList := TDynamicList.GuessType(AObject);
  Result := Assigned(AList);
end;

function TJsonDeserializer.IsEnumerableMap(AObject: TObject;
  out AMap: IDynamicMap): Boolean;
begin
  AMap := TDynamicMap.GuessType(AObject);
  Result := Assigned(AMap);
end;

procedure TJsonDeserializer.JSONToObject(AObject: TObject;
  AType: TRttiType; AJSON: TJSONValue);
begin
  ReadDataMembers(AObject, AType, AJSON);
end;

procedure TJsonDeserializer.ReadDataMember(AType: TRttiType; var AValue: TValue; AJSON: TJSONValue);
var
  LDynamicType: IDynamicType;

  LDynamicMap: IDynamicMap absolute LDynamicType;
  LDynamicList: IDynamicList absolute LDynamicType;
begin
  case AType.TypeKind of
    tkInt64:       AValue := TJSONHelper.ValueAs<Int64>(AJSON, 0);
    tkInteger:     AValue := TJSONHelper.ValueAs<Integer>(AJSON, 0);
    tkFloat:       AValue := TJSONHelper.ValueAs<Double>(AJSON, 0);
    tkLString:     AValue := TJSONHelper.ValueAs<string>(AJSON, '');
    tkWString:     AValue := TJSONHelper.ValueAs<string>(AJSON, '');
    tkUString:     AValue := TJSONHelper.ValueAs<string>(AJSON, '');
    tkString:      AValue := TJSONHelper.ValueAs<string>(AJSON, '');
    tkEnumeration: AValue := TJSONHelper.ValueAs<Boolean>(AJSON, False);
    tkClass:
    begin
      var LPropInstance := AValue.AsObject;
      if LPropInstance is TStrings then
      begin
        if Assigned(AJSON) then
        begin
          if AJSON is not TJSONArray then
            raise EJSONDeserializerError.Create('TJSONArray expected');
          ReadStringList(TStrings(LPropInstance), TJSONArray(AJSON));
        end
      end
      else if IsEnumerableMap(LPropInstance, LDynamicMap) then
      begin
        ReadDictionary(LDynamicMap, AJSON as TJSONObject)
      end
      else if IsEnumerableList(LPropInstance, LDynamicList) then
      begin
        ReadList(LDynamicList, AJSON as TJSONArray)
      end
      else
      begin
        ReadDataMembers(AValue.AsObject, AType, AJSON);
      end;
    end;
  end;
end;

procedure TJsonDeserializer.ReadDataMembers(AObject: TObject; AType: TRttiType;
  AJSON: TJSONValue);
begin
  if not (AJSON is TJSONObject) then Exit;

  for var LProp in AType.GetProperties do
  begin
    var LValue := LProp.GetValue(AObject);
    var LPropName := GetJSONFieldName(LProp);
    var LJSONValue := AJSON.FindValue(LPropName);
    ReadDataMember(LProp.PropertyType, LValue, LJSONValue);
    if not LValue.IsEmpty and LProp.IsWritable then
      LProp.SetValue(AObject, LValue);
  end;
end;

procedure TJsonDeserializer.ReadDictionary(ADynamicMap: IDynamicMap; AJSONObject: TJSONObject);
begin
  if not Assigned(ADynamicMap) then
    Exit;

  if not Assigned(AJSONObject) then
    Exit;

  for var LPair in AJSONObject do
  begin
    var LKey := LPair.JsonString.Value;
    var LValue := ADynamicMap.NewValue;
    var LValueType := TRttiHelper.GetType(LValue);
    ReadDataMember(LValueType, LValue, LPair.JsonValue);
    ADynamicMap.Add(LKey, LValue);
  end;
end;

procedure TJsonDeserializer.ReadList(ADynamicList: IDynamicList; AJSONArray: TJSONArray);
begin
  if not Assigned(ADynamicList) then
    Exit;

  if not Assigned(AJSONArray) then
    Exit;

  for var LItem in AJSONArray do
  begin
    var LValue := ADynamicList.NewItem;
    var LValueType := TRttiHelper.GetType(LValue);
    ReadDataMember(LValueType, LValue, LItem);
    ADynamicList.Add(LValue);
  end;
end;

procedure TJsonDeserializer.ReadStringList(AObject: TStrings;
  AJSON: TJSONArray);
begin
  AObject.Clear;
  for var LJSONItem in AJSON do
  begin
    if LJSONItem is not TJSONString then
      raise EJSONDeserializerError.Create('String expected');
    AObject.Add(LJSONItem.Value);
  end;
end;

{ JsonNameAttribute }

constructor JsonNameAttribute.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

{ TRttiHelper }

class constructor TRttiHelper.Create;
begin
  FContext := TRttiContext.Create;
end;

class function TRttiHelper.CreateInstance(AType: TRttiType): TObject;
begin
  Result := CreateInstanceValue(AType).AsObject;
end;

class function TRttiHelper.CreateInstanceValue(AType: TRttiType): TValue;
begin
  Result := nil;
  if Assigned(AType) then
    for var LMethod in AType.GetMethods do
    begin
      if LMethod.HasExtendedInfo and LMethod.IsConstructor then
      begin
        if Length(LMethod.GetParameters) = 0 then
        begin
          var LMetaClass := AType.AsInstance.MetaclassType;
          Exit(LMethod.Invoke(LMetaClass, []));
        end;
      end;
    end;
end;

class function TRttiHelper.CreateNewValue(AType: TRttiType): TValue;
var
  LAllocatedMem: Pointer;
begin
  case AType.TypeKind of
    tkEnumeration: Result := TValue.From<Byte>(0);
    tkInteger:     Result := TValue.From<Integer>(0);
    tkInt64:       Result := TValue.From<Int64>(0);
    tkChar:        Result := TValue.From<UTF8Char>(#0);
    tkWChar:       Result := TValue.From<Char>(#0);
    tkFloat:       Result := TValue.From<Double>(0);
    tkString:      Result := TValue.From<UTF8String>('');
    tkWString:     Result := TValue.From<string>('');
    tkLString:     Result := TValue.From<UTF8String>('');
    tkUString:     Result := TValue.From<string>('');
    //tkVariant:     Result := TValue.From<Variant>(Null);

    tkClass:       Result := CreateInstance(AType);

    tkRecord, tkDynArray:
    begin
      LAllocatedMem := AllocMem(AType.TypeSize);
      try
        TValue.Make(LAllocatedMem, AType.Handle, Result);
      finally
        FreeMem(LAllocatedMem);
      end;
    end;
  else
    raise Exception.CreateFmt('Error creating type [%s]', [AType.Name]);
  end;
end;

class function TRttiHelper.CreateInstance(AClass: TClass): TObject;
var
  LType: TRttiType;
begin
  LType := FContext.GetType(AClass);
  Result := CreateInstanceValue(LType).AsObject;
end;

class function TRttiHelper.CreateInstance(const ATypeName: string): TObject;
var
  LType: TRttiType;
begin
  LType := Context.FindType(ATypeName);
  Result := CreateInstanceValue(LType).AsObject;
end;

class function TRttiHelper.CreateInstance(AClass: TClass; const AValue: string): TObject;
var
  LType: TRttiType;
begin
  LType := FContext.GetType(AClass);
  Result := CreateInstance(LType, AValue);
end;

class function TRttiHelper.CreateInstance(AType: TRttiType; const AValue: string): TObject;
var
  LMethod: TRttiMethod;
  LMetaClass: TClass;
begin
  Result := nil;
  if Assigned(AType) then
  begin
    for LMethod in AType.GetMethods do
    begin
      if LMethod.HasExtendedInfo and LMethod.IsConstructor then
      begin
        if Length(LMethod.GetParameters) = 1 then
        begin
          if LMethod.GetParameters[0].ParamType.TypeKind in [tkLString, tkUString, tkWString, tkString] then
          begin
            LMetaClass := AType.AsInstance.MetaclassType;
            Exit(LMethod.Invoke(LMetaClass, [AValue]).AsObject);
          end;
        end;
      end;
    end;
  end;
end;

class destructor TRttiHelper.Destroy;
begin
  FContext.Free;
end;

class function TRttiHelper.GetType(AValue: TValue): TRttiType;
begin
  Result := FContext.GetType(AValue.TypeInfo);
end;

{ TJsonSerializer }

function TJsonSerializer.IsEnumerableList(AObject: TObject; out AList: IDynamicList): Boolean;
begin
  AList := TDynamicList.GuessType(AObject);
  Result := Assigned(AList);
end;

function TJsonSerializer.IsEnumerableMap(AObject: TObject; out AMap: IDynamicMap): Boolean;
begin
  AMap := TDynamicMap.GuessType(AObject);
  Result := Assigned(AMap);
end;

function TJsonSerializer.ObjectToJSON(AObject: TObject): TJSONValue;
begin
  Result := WriteDataMembers(AObject);
end;

function TJsonSerializer.WriteDataMember(AType: TRttiType; AValue: TValue): TJSONValue;
var
  LDynamicType: IDynamicType;

  LDynamicMap: IDynamicMap absolute LDynamicType;
  LDynamicList: IDynamicList absolute LDynamicType;
begin
  case AType.TypeKind of
    tkInt64:        Result := TJSONNumber.Create(AValue.AsInt64);
    tkInteger:      Result := TJSONNumber.Create(AValue.AsInteger);
    tkFloat:        Result := TJSONNumber.Create(AValue.AsExtended);
    tkLString:      Result := TJSONString.Create(AValue.AsString);
    tkWString:      Result := TJSONString.Create(AValue.AsString);
    tkUString:      Result := TJSONString.Create(AValue.AsString);
    tkString:       Result := TJSONString.Create(AValue.AsString);
    tkEnumeration:
    begin
      if not AValue.IsType<Boolean> then
        raise EJSONSerializerError.Create('Only boolean enum supported');

      Result := TJSONBool.Create(AValue.AsBoolean);
    end;
    tkClass:
    begin
      var LPropInstance := AValue.AsObject;
      if LPropInstance is TStrings then
      begin
        Result := WriteStringListMembers(TStrings(LPropInstance));
      end
      else if IsEnumerableMap(LPropInstance, LDynamicMap) then
      begin
        Result := WriteDictionary(LPropInstance, LDynamicMap);
      end
      else if IsEnumerableList(LPropInstance, LDynamicList) then
      begin
        Result := WriteList(LPropInstance, LDynamicList);
      end
      else
      begin
        Result := WriteDataMembers(LPropInstance);
      end;
    end;

    else
      raise EJSONSerializerError.CreateFmt('WriteDataMembers: type "%s" unknown', [TRttiEnumerationType.GetName(AType.TypeKind)]);
  end;
end;

function TJsonSerializer.WriteDataMembers(AObject: TObject): TJSONObject;
begin
  if not Assigned(AObject) then
    Exit(nil);

  Result := TJSONObject.Create;
  try
    var LType := TRttiHelper.Context.GetType(AObject.ClassType) as TRttiInstanceType;

    for var LProp in LType.GetProperties do
    begin
      var LPropName := GetJSONFieldName(LProp);
      var LValue := WriteDataMember(LProp.PropertyType, LProp.GetValue(AObject));
      if Assigned(LValue) then
        Result.AddPair(LPropName, LValue);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TJsonSerializer.WriteDictionary(AObject: TObject; AMap: IDynamicMap): TJSONObject;
begin
  if not Assigned(AMap) then
    Exit(nil);

  Result := TJSONObject.Create;
  try
    while AMap.MoveNext do
    begin
      var LKeyValue := AMap.CurrentKey;
      var LValValue := AMap.CurrentValue;

      var LJSONName := WriteDataMember(AMap.GetKeyType, LKeyValue);
      try
        var LJSONValue := WriteDataMember(AMap.GetValueType, LValValue);

        var LName: string;
        if LJSONName is TJSONString then
          LName := (LJSONName as TJSONString).Value
        else if AMap.KeyIsString then
          LName := AMap.KeyToString(LKeyValue);

        (Result as TJSONObject).AddPair(LName, LJSONValue);

        if LName.IsEmpty then
          raise EJSONBLockError.Create('Invalid map type');
      finally
        LJSONName.Free;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TJsonSerializer.WriteList(AObject: TObject; AList: IDynamicList): TJSONArray;
var
  LJSONValue: TJSONValue;
begin
  // Not an enumerable object
  if not Assigned(AList) then
    Exit(nil);

  Result := TJSONArray.Create;
  try
    while AList.MoveNext do
    begin
      LJSONValue := WriteDataMember(AList.GetItemType, AList.Current);
      (Result as TJSONArray).AddElement(LJSONValue);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TJsonSerializer.WriteStringListMembers(AObject: TStrings): TJSONArray;
begin
  Result := TJSONArray.Create;
  try
    for var LStr in AObject do
    begin
      Result.Add(LStr);
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ TDynamicList }

procedure TDynamicList.Add(AItem: TValue);
begin
  FAddMethod.Invoke(FInstance, [AItem]);
end;

procedure TDynamicList.Clear;
begin
  FClearMethod.Invoke(FInstance, []);
end;

function TDynamicList.Count: Integer;
begin
  Result := FCountProperty.GetValue(FInstance).AsInteger;
end;

constructor TDynamicList.Create(AInstance, AEnumInstance: TObject; AItemType: TRttiType;
  AAddMethod, AClearMethod, AMoveNextMethod: TRttiMethod;
  ACurrentProperty, ACountProperty: TRttiProperty);
begin
  FInstance := AInstance;
  FEnumInstance := AEnumInstance;
  FItemType := AItemType;
  FAddMethod := AAddMethod;
  FClearMethod := AClearMethod;
  FMoveNextMethod := AMoveNextMethod;
  FCurrentProperty := ACurrentProperty;
  FCountProperty := ACountProperty;
end;

function TDynamicList.Current: TValue;
begin
  Result := FCurrentProperty.GetValue(FEnumInstance);
end;

destructor TDynamicList.Destroy;
begin
  FEnumInstance.Free;
  inherited;
end;

function TDynamicList.GetItemType: TRttiType;
begin
  Result := FItemType;
end;

class function TDynamicList.GuessType(AInstance: TObject): IDynamicList;
var
  LMethodGetEnumerator, LMethodAdd: TRttiMethod;
  LMethodClear, LMethodMoveNext: TRttiMethod;
  LEnumInstance: TObject;
  LListType, LItemType, LEnumType: TRttiType;
  LCountProp, LCurrentProp: TRttiProperty;
begin
  Result := nil;

  if not Assigned(AInstance) then
    Exit;

  LListType := TRttiHelper.Context.GetType(AInstance.ClassType);

  LMethodGetEnumerator := LListType.GetMethod('GetEnumerator');
  if not Assigned(LMethodGetEnumerator) or
     (LMethodGetEnumerator.MethodKind <> mkFunction) or
     (LMethodGetEnumerator.ReturnType.Handle.Kind <> tkClass)
  then
    Exit;

  LMethodClear := LListType.GetMethod('Clear');
  if not Assigned(LMethodClear) then
    Exit;

  LMethodAdd := LListType.GetMethod('Add');
  if not Assigned(LMethodAdd) or (Length(LMethodAdd.GetParameters) <> 1) then
    Exit;

  LItemType := LMethodAdd.GetParameters[0].ParamType;

  LCountProp := LListType.GetProperty('Count');
  if not Assigned(LCountProp) then
    Exit;

  LEnumInstance := LMethodGetEnumerator.Invoke(AInstance, []).AsObject;
  try
    if not Assigned(LEnumInstance) then
      Exit;

    LEnumType := TRttiHelper.Context.GetType(LEnumInstance.ClassType);

    LCurrentProp := LEnumType.GetProperty('Current');
    if not Assigned(LCurrentProp) then
      Exit;

    LMethodMoveNext := LEnumType.GetMethod('MoveNext');
    if not Assigned(LMethodMoveNext) or
       (Length(LMethodMoveNext.GetParameters) <> 0) or
       (LMethodMoveNext.MethodKind <> mkFunction) or
       (LMethodMoveNext.ReturnType.Handle <> TypeInfo(Boolean))
    then
      Exit;

    Result := TDynamicList.Create(
      AInstance,
      LEnumInstance,
      LItemType,
      LMethodAdd,
      LMethodClear,
      LMethodMoveNext,
      LCurrentProp,
      LCountProp
    );
    LEnumInstance := nil;
  finally
    LEnumInstance.Free;
  end;
end;

function TDynamicList.MoveNext: Boolean;
begin
  Result := FMoveNextMethod.Invoke(FEnumInstance, []).AsBoolean;
end;

function TDynamicList.NewItem: TValue;
begin
  Result := TRttiHelper.CreateNewValue(FItemType);
end;

{ TDynamicMap }

procedure TDynamicMap.Add(const AKey, AValue: TValue);
begin
  FAddMethod.Invoke(FInstance, [AKey, AValue]);
end;

procedure TDynamicMap.Clear;
begin
  FClearMethod.Invoke(FInstance, []);
end;

function TDynamicMap.Count: Integer;
begin
  Result := FCountProp.GetValue(FInstance).AsInteger;
end;

constructor TDynamicMap.Create(AInstance: TObject; AKeyType, AValueType: TRttiType;
  AAddMethod, AClearMethod: TRttiMethod; ACountProp: TRttiProperty;
  AKeyEnum, AValueEnum: TDynamicMap.TEnumerator; AToStringMethod, AFromStringMethod: TRttiMethod);
begin
  FInstance := AInstance;
  FKeyType := AKeyType;
  FValueType := AValueType;
  FAddMethod := AAddMethod;
  FClearMethod := AClearMethod;
  FKeyEnum := AKeyEnum;
  FValueEnum := AValueEnum;
  FCountProp := ACountProp;
  FToStringMethod := AToStringMethod;
  FFromStringMethod := AFromStringMethod;
end;

function TDynamicMap.CurrentKey: TValue;
begin
  Result := FKeyEnum.Current;
end;

function TDynamicMap.CurrentValue: TValue;
begin
  Result := FValueEnum.Current;
end;

destructor TDynamicMap.Destroy;
begin
  FKeyEnum.Free;
  FValueEnum.Free;
  inherited;
end;

procedure TDynamicMap.KeyFromString(const AKey: TValue; const AStringVal: string);
begin
  if Assigned(FFromStringMethod) then
    FFromStringMethod.Invoke(AKey.AsObject, [AStringVal]);
end;

function TDynamicMap.GetKeyType: TRttiType;
begin
  Result := FKeyType;
end;

function TDynamicMap.GetValueType: TRttiType;
begin
  Result := FValueType;
end;

class function TDynamicMap.GuessType(AInstance: TObject): IDynamicMap;
var
  LMapType: TRttiType;
  LKeyType, LValType: TRttiType;
  LKeyProp, LValProp: TRttiProperty;
  LCountProp: TRttiProperty;
  LAddMethod, LClearMethod: TRttiMethod;
  LToStringMethod, LFromStringMethod: TRttiMethod;

  LKeyEnumMethod, LValEnumMethod: TRttiMethod;
  LKeyEnumObject, LValEnumObject: TObject;
  LKeyEnum, LValEnum: TDynamicMap.TEnumerator;
begin
  Result := nil;

  if not Assigned(AInstance) then
    Exit;

  LMapType := TRttiHelper.Context.GetType(AInstance.ClassType);

  // Keys & Values Enumerator
  LKeyProp := LMapType.GetProperty('Keys');
  if not Assigned(LKeyProp) then
    Exit;

  LValProp := LMapType.GetProperty('Values');
  if not Assigned(LValProp) then
    Exit;

  LKeyEnumObject := LKeyProp.GetValue(AInstance).AsObject;
  LValEnumObject := LValProp.GetValue(AInstance).AsObject;

  LKeyEnumMethod := TRttiHelper.Context.GetType(LKeyEnumObject.ClassInfo).GetMethod('GetEnumerator');
  LValEnumMethod := TRttiHelper.Context.GetType(LValEnumObject.ClassInfo).GetMethod('GetEnumerator');

  LKeyEnum := TDynamicMap.TEnumerator.Create(LKeyEnumMethod, LKeyEnumObject);
  LValEnum := TDynamicMap.TEnumerator.Create(LValEnumMethod, LValEnumObject);
  // End Keys & Values Enumerator

  try
    LClearMethod := LMapType.GetMethod('Clear');
    if not Assigned(LClearMethod) then
      Exit;

    LAddMethod := LMapType.GetMethod('Add');
    if not Assigned(LAddMethod) or (Length(LAddMethod.GetParameters) <> 2) then
      Exit;

    LKeyType := LAddMethod.GetParameters[0].ParamType;
    LValType := LAddMethod.GetParameters[1].ParamType;

    LCountProp := LMapType.GetProperty('Count');
    if not Assigned(LCountProp) then
      Exit;

    LToStringMethod := nil;
    LFromStringMethod := nil;

    // Optional methods (on Key object)
    case LKeyType.TypeKind of
      tkClass{, tkRecord, tkInterface}:
      begin
        LToStringMethod := LKeyType.GetMethod('ToString');
        LFromStringMethod := LKeyType.GetMethod('FromString');
      end;
    end;

    Result := TDynamicMap.Create(
      AInstance,
      LKeyType,
      LValType,
      LAddMethod,
      LClearMethod,
      LCountProp,
      LKeyEnum,
      LValEnum,
      LToStringMethod,
      LFromStringMethod
    );
    LKeyEnum := nil;
    LValEnum := nil;
  finally
    LKeyEnum.Free;
    LValEnum.Free;
  end;
end;

function TDynamicMap.MoveNext: Boolean;
begin
  Result := (FKeyEnum.MoveNext and FValueEnum.MoveNext);
end;

function TDynamicMap.NewKey: TValue;
begin
  Result := TRttiHelper.CreateNewValue(FKeyType);
end;

function TDynamicMap.NewValue: TValue;
begin
  Result := TRttiHelper.CreateNewValue(FValueType);
end;

function TDynamicMap.KeyIsString: Boolean;
begin
  Result := Assigned(FToStringMethod) and Assigned(FFromStringMethod);
end;

function TDynamicMap.KeyToString(const AKey: TValue): string;
begin
  if Assigned(FToStringMethod) then
    Result := FToStringMethod.Invoke(AKey.AsObject, []).AsString
  else
    Result := '';
end;

{ TDynamicMap.TEnumerator }

constructor TDynamicMap.TEnumerator.Create(AMethod: TRttiMethod; AInstance: TObject);
begin
  // Memory creation, must destroy the object
  FInstance := AMethod.Invoke(AInstance, []).AsObject;

  FCurrentProperty := TRttiHelper.Context.GetType(FInstance.ClassInfo).GetProperty(CURRENT_PROP);
  if not Assigned(FCurrentProperty) then
    raise EJSONBlockError.CreateFmt('Property [%s] not found', [CURRENT_PROP]);

  FMoveNextMethod := TRttiHelper.Context.GetType(FInstance.ClassInfo).GetMethod(MOVENEXT_METH);
  if not Assigned(FMoveNextMethod) then
    raise EJSONBlockError.CreateFmt('Method [%s] not found', [MOVENEXT_METH]);
end;

function TDynamicMap.TEnumerator.Current: TValue;
begin
  Result := FCurrentProperty.GetValue(FInstance);
end;

destructor TDynamicMap.TEnumerator.Destroy;
begin
  FInstance.Free;
  inherited;
end;

function TDynamicMap.TEnumerator.MoveNext: Boolean;
begin
  Result := FMoveNextMethod.Invoke(FInstance, []).AsBoolean;
end;

end.
