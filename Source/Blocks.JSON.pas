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
  EJSONSerializerError = class(Exception)
  end;

  EJSONDeserializerError = class(Exception)
  end;

  JsonNameAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    property Name: string read FName;
    constructor Create(const AName: string);
  end;

  JsonDictionaryAttribute = class(TCustomAttribute)
  private
    FTypeInfo: PTypeInfo;
  public
    property TypeInfo: PTypeInfo read FTypeInfo;
    constructor Create(ATypeInfo: PTypeInfo);
  end;

  JsonListAttribute = class(TCustomAttribute)
  private
    FTypeInfo: PTypeInfo;
  public
    property TypeInfo: PTypeInfo read FTypeInfo;
    constructor Create(ATypeInfo: PTypeInfo);
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

    class function ObjectToJSONString(AObject: TObject): string; overload;
    class function ObjectToJSON(AObject: TObject): TJSONValue; overload;
    class function PrettyPrint(AJSON: TJSONValue): string; overload; static;
    class function PrettyPrint(const AJSONString: string): string; overload; static;

    /// <summary>Raises an exception if the JSON contains a "$schema" field that
    /// does not match <c>AExpectedSchema</c>. A missing field is silently ignored.</summary>
    class procedure CheckSchema(AJSON: TJSONValue; const AExpectedSchema: string); static;
  end;

  TJsonSerializer = class
  private
    function WriteList(AObject: TObject; ADataType: PTypeInfo): TJSONArray;
    function WriteDictionary(AObject: TObject; ADataType: PTypeInfo): TJSONObject;
    function WriteDataMembers(AObject: TObject): TJSONObject;
    function WriteStringListMembers(AObject: TStrings): TJSONArray;
  public
    function ObjectToJSON(AObject: TObject): TJSONValue;
  end;


  TJsonDeserializer = class
  private
    procedure ReadDataMembers(AObject: TObject; AType: TRttiType; AJSON: TJSONValue);
    procedure ReadDictionary(AObject: TObject; ADataType: PTypeInfo; AJSON: TJSONValue);
    procedure ReadList(AObject: TObject; ADataType: PTypeInfo; AJSON: TJSONValue);
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
    class function CreateInstanceValue(AType: TRttiType): TValue; static;
    class function CreateInstance(AType: TRttiType): TObject; static;
    class property Context: TRttiContext read FContext;
  end;

  TCaseAlgorithm = class
  public
    class function PascalToCamel(const AString: string): string; static;
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

procedure TJsonDeserializer.JSONToObject(AObject: TObject;
  AType: TRttiType; AJSON: TJSONValue);
begin
  ReadDataMembers(AObject, AType, AJSON);
end;

procedure TJsonDeserializer.ReadDataMembers(AObject: TObject; AType: TRttiType;
  AJSON: TJSONValue);
begin
  if not (AJSON is TJSONObject) then Exit;

  for var LProp in AType.GetProperties do
  begin
    var LValue: TValue;
    var LPropName := GetJSONFieldName(LProp);
    case LProp.PropertyType.TypeKind of
      tkInt64:       LValue := AJSON.GetValue<Int64>(LPropName, 0);
      tkInteger:     LValue := AJSON.GetValue<Integer>(LPropName, 0);
      tkFloat:       LValue := AJSON.GetValue<Double>(LPropName, 0);
      tkLString:     LValue := AJSON.GetValue<string>(LPropName, '');
      tkWString:     LValue := AJSON.GetValue<string>(LPropName, '');
      tkUString:     LValue := AJSON.GetValue<string>(LPropName, '');
      tkString:      LValue := AJSON.GetValue<string>(LPropName, '');
      tkEnumeration: LValue := AJSON.GetValue<Boolean>(LPropName, False);

      tkClass:
      begin
        var LPropInstance := LProp.GetValue(AObject).AsObject;
        if LProp.HasAttribute(JsonDictionaryAttribute) then
        begin
          var LAttr := LProp.GetAttribute<JsonDictionaryAttribute>;
          ReadDictionary(LPropInstance, LAttr.TypeInfo, AJSON.FindValue(LPropName));
        end
        else if LProp.HasAttribute(JsonListAttribute) then
        begin
          var LAttr := LProp.GetAttribute<JsonListAttribute>;
          ReadList(LPropInstance, LAttr.TypeInfo, AJSON.FindValue(LPropName));
        end
        else if LPropInstance is TStrings then
        begin
          var LJSON := AJSON.FindValue(LPropName);
          if Assigned(LJSON) then
          begin
            if LJSON is not TJSONArray then
              raise EJSONDeserializerError.Create('TJSONArray expected');
            ReadStringList(TStrings(LPropInstance), TJSONArray(LJSON));
          end;
        end
        else
          ReadDataMembers(LPropInstance, LProp.DataType, AJSON.FindValue(LPropName));
      end;
      else
        raise EJSONDeserializerError.CreateFmt('ReadDataMembers: type "%s" unknown', [TRttiEnumerationType.GetName(LProp.PropertyType.TypeKind)]);
    end;
    if not LValue.IsEmpty then
      LProp.SetValue(AObject, LValue);
  end;
end;

procedure TJsonDeserializer.ReadDictionary(AObject: TObject; ADataType: PTypeInfo; AJSON: TJSONValue);
begin
  if not (AJSON is TJSONObject) then
    Exit;

  var DictType := TRttiHelper.Context.GetType(AObject.ClassType);
  var AddMethod := DictType.GetMethod('Add');
  if AddMethod = nil then
    Exit;

  // Get RttiType of the value (T) from PTypeInfo
  var ValueRttiType := TRttiHelper.Context.GetType(ADataType);

  for var Pair in (AJSON as TJSONObject) do
  begin
    // Key is always string
    var Key := TValue.From<string>(Pair.JsonString.Value);
    // Declare Value
    var Value: TValue;

    // Build the value
    case ADataType^.Kind of
      tkClass:
      begin
        var ValueObj := TRttiHelper.CreateInstance(ValueRttiType);
        ReadDataMembers(ValueObj, ValueRttiType, Pair.JsonValue);
        Value := TValue.From<TObject>(ValueObj);
      end;

      tkInteger: Value := TValue.From<Integer>(StrToInt(Pair.JsonValue.Value));
      tkUString: Value := TValue.From<string>(Pair.JsonValue.Value);
      tkLString: Value := TValue.From<string>(Pair.JsonValue.Value);
      tkWString: Value := TValue.From<string>(Pair.JsonValue.Value);
      tkString: Value := TValue.From<string>(Pair.JsonValue.Value);
      tkFloat: Value := TValue.From<Double>(StrToFloat(Pair.JsonValue.Value));
      else
        raise EJSONDeserializerError.CreateFmt('ReadDictionary: type "%s" unknown', [TRttiEnumerationType.GetName(ADataType^.Kind)]);
    end;

    // Invoke Add(key, value) via RTTI
    AddMethod.Invoke(AObject, [Key, Value]);
  end;
end;

procedure TJsonDeserializer.ReadList(AObject: TObject; ADataType: PTypeInfo;
  AJSON: TJSONValue);
begin
  if not (AJSON is TJSONArray) then
    Exit;

  var ListType := TRttiHelper.Context.GetType(AObject.ClassType);
  var AddMethod := ListType.GetMethod('Add');
  if AddMethod = nil then
    Exit;

  var LMethodClear := ListType.GetMethod('Clear');
  if not Assigned(LMethodClear) or (LMethodClear.MethodKind <> mkProcedure) then
    Exit;

  // Get RttiType of the value (T) from PTypeInfo
  var ValueRttiType := TRttiHelper.Context.GetType(ADataType);

  LMethodClear.Invoke(AObject, []);

  for var JsonItem in (AJSON as TJSONArray) do
  begin
    var Value: TValue;

    // Build the value
    case ADataType^.Kind of
      tkClass:
      begin
        var ValueObj := TRttiHelper.CreateInstance(ValueRttiType);
        ReadDataMembers(ValueObj, ValueRttiType, JsonItem);
        Value := TValue.From<TObject>(ValueObj);
      end;

      tkInteger: Value := TValue.From<Integer>(StrToInt(JsonItem.Value));
      tkInt64: Value := TValue.From<Integer>(StrToInt64(JsonItem.Value));
      tkUString: Value := TValue.From<string>(JsonItem.Value);
      tkLString: Value := TValue.From<string>(JsonItem.Value);
      tkWString: Value := TValue.From<string>(JsonItem.Value);
      tkString: Value := TValue.From<string>(JsonItem.Value);
      tkFloat: Value := TValue.From<Double>(StrToFloat(JsonItem.Value));
      else
        raise EJSONDeserializerError.CreateFmt('ReadList: type "%s" unknown', [TRttiEnumerationType.GetName(ADataType^.Kind)]);
    end;

    // Invoke Add(key, value) via RTTI
    AddMethod.Invoke(AObject, [Value]);
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

{ JsonDictionaryAttribute }

constructor JsonDictionaryAttribute.Create(ATypeInfo: PTypeInfo);
begin
  inherited Create;
  FTypeInfo := ATypeInfo;
end;

{ JsonListAttribute }

constructor JsonListAttribute.Create(ATypeInfo: PTypeInfo);
begin
  inherited Create;
  FTypeInfo := ATypeInfo;
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

class destructor TRttiHelper.Destroy;
begin
  FContext.Free;
end;

{ TJsonSerializer }

function TJsonSerializer.ObjectToJSON(AObject: TObject): TJSONValue;
begin
  Result := WriteDataMembers(AObject);
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
      var LValue: TJSONValue;
      var LPropName := GetJSONFieldName(LProp);
      case LProp.PropertyType.TypeKind of
        tkInt64:       LValue := TJSONNumber.Create(LProp.GetValue(AObject).AsInteger);
        tkInteger:     LValue := TJSONNumber.Create(LProp.GetValue(AObject).AsInt64);
        tkFloat:       LValue := TJSONNumber.Create(LProp.GetValue(AObject).AsExtended);
        tkLString:     LValue := TJSONString.Create(LProp.GetValue(AObject).AsString);
        tkWString:     LValue := TJSONString.Create(LProp.GetValue(AObject).AsString);
        tkUString:     LValue := TJSONString.Create(LProp.GetValue(AObject).AsString);
        tkString:      LValue := TJSONString.Create(LProp.GetValue(AObject).AsString);
        tkEnumeration:
        begin
          if not LProp.GetValue(AObject).IsType<Boolean> then
            raise EJSONSerializerError.Create('Only boolean enum supported');

          LValue := TJSONBool.Create(LProp.GetValue(AObject).AsBoolean);
        end;
        tkClass:
        begin
          var LPropInstance := LProp.GetValue(AObject).AsObject;
          if LProp.HasAttribute(JsonDictionaryAttribute) then
          begin
            var LAttr := LProp.GetAttribute<JsonDictionaryAttribute>;
            LValue := WriteDictionary(LPropInstance, LAttr.TypeInfo);
          end
          else if LProp.HasAttribute(JsonListAttribute) then
          begin
            var LAttr := LProp.GetAttribute<JsonListAttribute>;
            LValue := WriteList(LPropInstance, LAttr.TypeInfo);
          end
          else if LPropInstance is TStrings then
          begin
            LValue := WriteStringListMembers(TStrings(LPropInstance));
          end
          else
          begin
            LValue := WriteDataMembers(LPropInstance);
          end;
        end;
        else
          raise EJSONSerializerError.CreateFmt('WriteDataMembers: type "%s" unknown', [TRttiEnumerationType.GetName(LProp.PropertyType.TypeKind)]);
      end;
      if Assigned(LValue) then
        Result.AddPair(LPropName, LValue);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TJsonSerializer.WriteDictionary(AObject: TObject; ADataType: PTypeInfo): TJSONObject;
begin
  if not Assigned(AObject) then
    Exit(nil);

  Result := TJSONObject.Create;
  try

    if not Assigned(AObject) then
      Exit(nil);

    var LListType := TRttiHelper.Context.GetType(AObject.ClassType);
    var LMethodGetEnumerator := LListType.GetMethod('GetEnumerator');
    if not Assigned(LMethodGetEnumerator) or
       (LMethodGetEnumerator.MethodKind <> mkFunction) or
       (LMethodGetEnumerator.ReturnType.Handle.Kind <> tkClass)
    then
      Exit;

    // Get the enumerator instance
    var LEnumInstance := LMethodGetEnumerator.Invoke(AObject, []).AsObject;
    if not Assigned(LEnumInstance) then
      Exit;

    var LEnumType := TRttiHelper.Context.GetType(LEnumInstance.ClassType);

    var LCurrentProp := LEnumType.GetProperty('Current');
    if not Assigned(LCurrentProp) then
      Exit;

    var LPairKeyField := TRttiInstanceType(LCurrentProp.PropertyType).GetField('Key');
    if not Assigned(LPairKeyField) then
      Exit;

    var LPairValueField := TRttiInstanceType(LCurrentProp.PropertyType).GetField('Value');
    if not Assigned(LPairValueField) then
      Exit;

    var LMethodMoveNext := LEnumType.GetMethod('MoveNext');
    if not Assigned(LMethodMoveNext) or
       (Length(LMethodMoveNext.GetParameters) <> 0) or
       (LMethodMoveNext.MethodKind <> mkFunction) or
       (LMethodMoveNext.ReturnType.Handle <> TypeInfo(Boolean))
    then
      Exit;

    while LMethodMoveNext.Invoke(LEnumInstance, []).AsBoolean do
    begin
      var LValue: TJSONValue;
      var LCurrent := LCurrentProp.GetValue(LEnumInstance).GetReferenceToRawData;
      var LPairKey :=  LPairKeyField.GetValue(LCurrent).AsString;
      var LPairValue := LPairValueField.GetValue(LCurrent);
      case LPairValue.Kind of
        tkClass: LValue := WriteDataMembers(LPairValue.AsObject);

        tkInteger: LValue := TJSONNumber.Create(LPairValue.AsInteger);
        tkInt64: LValue := TJSONNumber.Create(LPairValue.AsInt64);
        tkUString: LValue := TJSONString.Create(LPairValue.AsString);
        tkLString: LValue := TJSONString.Create(LPairValue.AsString);
        tkWString: LValue := TJSONString.Create(LPairValue.AsString);
        tkString: LValue := TJSONString.Create(LPairValue.AsString);
        tkFloat: LValue := TJSONNumber.Create(LPairValue.AsExtended);
        else
          raise EJSONSerializerError.CreateFmt('WriteDictionary: type "%s" unknown', [TRttiEnumerationType.GetName(LPairValue.Kind)]);
      end;
      if Assigned(LValue) then
        Result.AddPair(LPairKey, LValue)
    end;

    if Assigned(LEnumInstance) then
      LEnumInstance.Free;

  except
    Result.Free;
    raise;
  end;
end;

function TJsonSerializer.WriteList(AObject: TObject; ADataType: PTypeInfo): TJSONArray;
begin
  if not Assigned(AObject) then
    Exit(nil);

  Result := TJSONArray.Create;
  try

    if not Assigned(AObject) then
      Exit(nil);

    var LListType := TRttiHelper.Context.GetType(AObject.ClassType);

    var LMethodGetEnumerator := LListType.GetMethod('GetEnumerator');
    if not Assigned(LMethodGetEnumerator) or
       (LMethodGetEnumerator.MethodKind <> mkFunction) or
       (LMethodGetEnumerator.ReturnType.Handle.Kind <> tkClass)
    then
      Exit;

    // Get the enumerator instance
    var LEnumInstance := LMethodGetEnumerator.Invoke(AObject, []).AsObject;
    if not Assigned(LEnumInstance) then
      Exit;

    var LEnumType := TRttiHelper.Context.GetType(LEnumInstance.ClassType);

    var LCurrentProp := LEnumType.GetProperty('Current');
    if not Assigned(LCurrentProp) then
      Exit;

    var LMethodMoveNext := LEnumType.GetMethod('MoveNext');
    if not Assigned(LMethodMoveNext) or
       (Length(LMethodMoveNext.GetParameters) <> 0) or
       (LMethodMoveNext.MethodKind <> mkFunction) or
       (LMethodMoveNext.ReturnType.Handle <> TypeInfo(Boolean))
    then
      Exit;

    while LMethodMoveNext.Invoke(LEnumInstance, []).AsBoolean do
    begin
      var LValue: TJSONValue;
      var LCurrent := LCurrentProp.GetValue(LEnumInstance);
      case LCurrent.Kind of
        tkClass:
        begin
          LValue := WriteDataMembers(LCurrent.AsObject);
        end;

        tkInteger: LValue := TJSONNumber.Create(LCurrent.AsInteger);
        tkInt64: LValue := TJSONNumber.Create(LCurrent.AsInt64);
        tkUString: LValue := TJSONString.Create(LCurrent.AsString);
        tkWString: LValue := TJSONString.Create(LCurrent.AsString);
        tkLString: LValue := TJSONString.Create(LCurrent.AsString);
        tkString: LValue := TJSONString.Create(LCurrent.AsString);
        tkFloat: LValue := TJSONNumber.Create(LCurrent.AsExtended);
        else
          raise EJSONSerializerError.CreateFmt('WriteList: type "%s" unknown', [TRttiEnumerationType.GetName(LCurrent.Kind)]);
      end;
      if Assigned(LValue) then
        Result.AddElement(LValue);
    end;

    if Assigned(LEnumInstance) then
      LEnumInstance.Free;
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

end.
