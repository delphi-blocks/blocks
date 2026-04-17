unit Blocks.Tests.JSON;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,

  Blocks.Types,
  Blocks.JSON;

type
  TMyTestObj = class(TObject)
  private
    FStrProp: string;
    FIntProp: Integer;
  public
    property StrProp: string read FStrProp write FStrProp;
    property IntProp: Integer read FIntProp write FIntProp;
  end;

  // ----- string list -----

  TTaggedObj = class(TObject)
  private
    FName: string;
    FTags: TJSONStringList;
  public
    constructor Create;
    destructor Destroy; override;

    property Name: string read FName write FName;
    [JsonList(System.TypeInfo(string))]
    property Tags: TJSONStringList read FTags;
  end;

  // ----- object list -----

  TItemObj = class(TObject)
  private
    FValue: string;
    FCount: Integer;
  public
    property Value: string read FValue write FValue;
    property Count: Integer read FCount write FCount;
  end;

  TItemList = class(TObjectList<TItemObj>)
  public
    constructor Create;
  end;

  TListObj = class(TObject)
  private
    FTitle: string;
    FItems: TItemList;
  public
    constructor Create;
    destructor Destroy; override;

    property Title: string read FTitle write FTitle;
    [JsonList(System.TypeInfo(TItemObj))]
    property Items: TItemList read FItems;
  end;

  // ----- string dictionary -----

  TStrDict = class(TDictionary<string, string>)
  end;

  TStrDictObj = class(TObject)
  private
    FName: string;
    FProps: TStrDict;
  public
    constructor Create;
    destructor Destroy; override;

    property Name: string read FName write FName;
    [JsonDictionary(System.TypeInfo(string))]
    property Props: TStrDict read FProps;
  end;

  // ----- object dictionary -----

  TItemDict = class(TObjectDictionary<string, TItemObj>)
  public
    constructor Create;
  end;

  TObjDictObj = class(TObject)
  private
    FName: string;
    FChildren: TItemDict;
  public
    constructor Create;
    destructor Destroy; override;

    property Name: string read FName write FName;
    [JsonDictionary(System.TypeInfo(TItemObj))]
    property Children: TItemDict read FChildren;
  end;

  [TestFixture]
  TJSONTest = class(TObject)
  private
    FMyTestObj: TMyTestObj;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestSerialization_BasicProperties;
    [Test]
    procedure TestDeserialization_BasicProperties;
    [Test]
    procedure TestSerialization_StringList;
    [Test]
    procedure TestDeserialization_StringList;
    [Test]
    procedure TestSerialization_ObjectList;
    [Test]
    procedure TestDeserialization_ObjectList;
    [Test]
    procedure TestSerialization_StringDictionary;
    [Test]
    procedure TestDeserialization_StringDictionary;
    [Test]
    procedure TestSerialization_ObjectDictionary;
    [Test]
    procedure TestDeserialization_ObjectDictionary;
  end;

const
  MyTestJSON =
    '''
    {
      "strProp": "TestValue",
      "intProp": 43
    }
    ''';

  TaggedObjJSON =
    '''
    {
      "name": "TestName",
      "tags": ["alpha", "beta", "gamma"]
    }
    ''';

  ListObjJSON =
    '''
    {
      "title": "MyList",
      "items": [
        { "value": "first", "count": 1 },
        { "value": "second", "count": 2 }
      ]
    }
    ''';

  StrDictObjJSON =
    '''
    {
      "name": "TestLabel",
      "props": {
        "key1": "value1",
        "key2": "value2"
      }
    }
    ''';

  ObjDictObjJSON =
    '''
    {
      "name": "DictLabel",
      "children": {
        "child1": { "value": "v1", "count": 10 },
        "child2": { "value": "v2", "count": 20 }
      }
    }
    ''';

implementation

uses
  System.JSON;

{ TTaggedObj }

constructor TTaggedObj.Create;
begin
  inherited Create;
  FTags := TJSONStringList.Create;
end;

destructor TTaggedObj.Destroy;
begin
  FTags.Free;
  inherited;
end;

{ TItemList }

constructor TItemList.Create;
begin
  inherited Create(True);
end;

{ TListObj }

constructor TListObj.Create;
begin
  inherited Create;
  FItems := TItemList.Create;
end;

destructor TListObj.Destroy;
begin
  FItems.Free;
  inherited;
end;

{ TStrDictObj }

constructor TStrDictObj.Create;
begin
  inherited Create;
  FProps := TStrDict.Create;
end;

destructor TStrDictObj.Destroy;
begin
  FProps.Free;
  inherited;
end;

{ TItemDict }

constructor TItemDict.Create;
begin
  inherited Create([doOwnsValues]);
end;

{ TObjDictObj }

constructor TObjDictObj.Create;
begin
  inherited Create;
  FChildren := TItemDict.Create;
end;

destructor TObjDictObj.Destroy;
begin
  FChildren.Free;
  inherited;
end;

{ TJSONTest }

procedure TJSONTest.Setup;
begin
  FMyTestObj := TMyTestObj.Create;
end;

procedure TJSONTest.TearDown;
begin
  FMyTestObj.Free;
end;

procedure TJSONTest.TestSerialization_BasicProperties;
begin
  FMyTestObj.StrProp := 'MyValue';
  FMyTestObj.IntProp := 42;
  var LJSON := TJsonHelper.ObjectToJSON(FMyTestObj);
  try
    Assert.AreEqual('MyValue', LJSON.GetValue<string>('strProp'), 'strProp');
    Assert.AreEqual(42, LJSON.GetValue<Integer>('intProp'), 'intProp');
  finally
    LJSON.Free;
  end;
end;

procedure TJSONTest.TestDeserialization_BasicProperties;
begin
  var LObj := TJsonHelper.JSONToObject<TMyTestObj>(MyTestJSON);
  try
    Assert.AreEqual('TestValue', LObj.StrProp, 'strProp');
    Assert.AreEqual(43, LObj.IntProp, 'intProp');
  finally
    LObj.Free;
  end;
end;

procedure TJSONTest.TestSerialization_StringList;
begin
  var LObj := TTaggedObj.Create;
  try
    LObj.Name := 'TestName';
    LObj.Tags.Add('alpha');
    LObj.Tags.Add('beta');
    LObj.Tags.Add('gamma');
    var LJSON := TJsonHelper.ObjectToJSON(LObj);
    try
      Assert.AreEqual('TestName', LJSON.GetValue<string>('name'), 'name');
      var LTags := LJSON.FindValue('tags') as TJSONArray;
      Assert.IsNotNull(LTags, 'tags array present');
      Assert.AreEqual(3, LTags.Count, 'tags count');
      Assert.AreEqual('alpha', LTags.Items[0].Value, 'tags[0]');
      Assert.AreEqual('beta', LTags.Items[1].Value, 'tags[1]');
      Assert.AreEqual('gamma', LTags.Items[2].Value, 'tags[2]');
    finally
      LJSON.Free;
    end;
  finally
    LObj.Free;
  end;
end;

procedure TJSONTest.TestDeserialization_StringList;
begin
  var LObj := TJsonHelper.JSONToObject<TTaggedObj>(TaggedObjJSON);
  try
    Assert.AreEqual('TestName', LObj.Name, 'name');
    Assert.AreEqual(3, LObj.Tags.Count, 'tags count');
    Assert.AreEqual('alpha', LObj.Tags[0], 'tags[0]');
    Assert.AreEqual('beta', LObj.Tags[1], 'tags[1]');
    Assert.AreEqual('gamma', LObj.Tags[2], 'tags[2]');
  finally
    LObj.Free;
  end;
end;

procedure TJSONTest.TestSerialization_ObjectList;
begin
  var LObj := TListObj.Create;
  try
    LObj.Title := 'MyList';
    var LItem1 := TItemObj.Create;
    LItem1.Value := 'first';
    LItem1.Count := 1;
    LObj.Items.Add(LItem1);
    var LItem2 := TItemObj.Create;
    LItem2.Value := 'second';
    LItem2.Count := 2;
    LObj.Items.Add(LItem2);
    var LJSON := TJsonHelper.ObjectToJSON(LObj);
    try
      Assert.AreEqual('MyList', LJSON.GetValue<string>('title'), 'title');
      var LItems := LJSON.FindValue('items') as TJSONArray;
      Assert.IsNotNull(LItems, 'items array present');
      Assert.AreEqual(2, LItems.Count, 'items count');
      Assert.AreEqual('first', LItems.Items[0].GetValue<string>('value'), 'items[0].value');
      Assert.AreEqual(1, LItems.Items[0].GetValue<Integer>('count'), 'items[0].count');
      Assert.AreEqual('second', LItems.Items[1].GetValue<string>('value'), 'items[1].value');
      Assert.AreEqual(2, LItems.Items[1].GetValue<Integer>('count'), 'items[1].count');
    finally
      LJSON.Free;
    end;
  finally
    LObj.Free;
  end;
end;

procedure TJSONTest.TestDeserialization_ObjectList;
begin
  var LObj := TJsonHelper.JSONToObject<TListObj>(ListObjJSON);
  try
    Assert.AreEqual('MyList', LObj.Title, 'title');
    Assert.AreEqual(2, LObj.Items.Count, 'items count');
    Assert.AreEqual('first', LObj.Items[0].Value, 'items[0].value');
    Assert.AreEqual(1, LObj.Items[0].Count, 'items[0].count');
    Assert.AreEqual('second', LObj.Items[1].Value, 'items[1].value');
    Assert.AreEqual(2, LObj.Items[1].Count, 'items[1].count');
  finally
    LObj.Free;
  end;
end;

procedure TJSONTest.TestSerialization_StringDictionary;
begin
  var LObj := TStrDictObj.Create;
  try
    LObj.Name := 'TestLabel';
    LObj.Props.Add('key1', 'value1');
    LObj.Props.Add('key2', 'value2');
    var LJSON := TJsonHelper.ObjectToJSON(LObj);
    try
      Assert.AreEqual('TestLabel', LJSON.GetValue<string>('name'), 'name');
      var LProps := LJSON.FindValue('props') as TJSONObject;
      Assert.IsNotNull(LProps, 'props object present');
      Assert.AreEqual('value1', LProps.GetValue<string>('key1'), 'props.key1');
      Assert.AreEqual('value2', LProps.GetValue<string>('key2'), 'props.key2');
    finally
      LJSON.Free;
    end;
  finally
    LObj.Free;
  end;
end;

procedure TJSONTest.TestDeserialization_StringDictionary;
begin
  var LObj := TJsonHelper.JSONToObject<TStrDictObj>(StrDictObjJSON);
  try
    Assert.AreEqual('TestLabel', LObj.Name, 'name');
    Assert.AreEqual(2, LObj.Props.Count, 'props count');
    Assert.AreEqual('value1', LObj.Props['key1'], 'props.key1');
    Assert.AreEqual('value2', LObj.Props['key2'], 'props.key2');
  finally
    LObj.Free;
  end;
end;

procedure TJSONTest.TestSerialization_ObjectDictionary;
begin
  var LObj := TObjDictObj.Create;
  try
    LObj.Name := 'DictLabel';
    var LChild1 := TItemObj.Create;
    LChild1.Value := 'v1';
    LChild1.Count := 10;
    LObj.Children.Add('child1', LChild1);
    var LChild2 := TItemObj.Create;
    LChild2.Value := 'v2';
    LChild2.Count := 20;
    LObj.Children.Add('child2', LChild2);
    var LJSON := TJsonHelper.ObjectToJSON(LObj);
    try
      Assert.AreEqual('DictLabel', LJSON.GetValue<string>('name'), 'name');
      var LChildren := LJSON.FindValue('children') as TJSONObject;
      Assert.IsNotNull(LChildren, 'children object present');
      Assert.AreEqual('v1', LChildren.FindValue('child1').GetValue<string>('value'), 'child1.value');
      Assert.AreEqual(10, LChildren.FindValue('child1').GetValue<Integer>('count'), 'child1.count');
      Assert.AreEqual('v2', LChildren.FindValue('child2').GetValue<string>('value'), 'child2.value');
      Assert.AreEqual(20, LChildren.FindValue('child2').GetValue<Integer>('count'), 'child2.count');
    finally
      LJSON.Free;
    end;
  finally
    LObj.Free;
  end;
end;

procedure TJSONTest.TestDeserialization_ObjectDictionary;
begin
  var LObj := TJsonHelper.JSONToObject<TObjDictObj>(ObjDictObjJSON);
  try
    Assert.AreEqual('DictLabel', LObj.Name, 'name');
    Assert.AreEqual(2, LObj.Children.Count, 'children count');
    Assert.AreEqual('v1', LObj.Children['child1'].Value, 'child1.value');
    Assert.AreEqual(10, LObj.Children['child1'].Count, 'child1.count');
    Assert.AreEqual('v2', LObj.Children['child2'].Value, 'child2.value');
    Assert.AreEqual(20, LObj.Children['child2'].Count, 'child2.count');
  finally
    LObj.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJSONTest);

end.
