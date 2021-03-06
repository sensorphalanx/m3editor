unit ustructures;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, XMLRead, XMLWrite, DOM;

type
  Pm3ref = ^m3ref;
  m3ref = packed record
    refCount: UInt32;
    refIndex: UInt32;
    refFlags: UInt32;
  end;

  Pm3ref_small = ^m3ref_small;
  m3ref_small = packed record
    refCount: UInt32;
    refIndex: UInt32;
  end;

  Pm3Header = ^m3Header;
  m3Header = packed record
    tag: UInt32;
    tagListOffset: UInt32;
    tagListCount: UInt32;
    ref_MODL: m3ref;
  end;

  m3VEC2 = packed record
    x: single;
    y: single;
  end;

  m3VEC3 = packed record
    x: single;
    y: single;
    z: single;
  end;

  m3VEC4 = packed record // same as QUAT
    x: single;
    y: single;
    z: single;
    w: single;
  end;

  m3Matrix44 = packed record
    x: m3VEC4;
    y: m3VEC4;
    z: m3VEC4;
    w: m3VEC4;
  end;

  m3Normal4b = packed record
    x: Byte;
    y: Byte;
    z: Byte;
    sign: Byte;
    // formula (((i / 255.0) * 2) - 1) to get the actual float value [-1; 1]
  end;

  m3UV = packed record
    x: Int16;
    y: Int16;
    // formula (i / 2048.0) to get the actual float value
  end;

  m3Color = packed record
    blue: Byte;
    green: Byte;
    red: Byte;
    alpha: Byte;
  end;

  TM3VerticleFull = record
    position: m3VEC3;
    boneWeight0: UInt8;
    boneWeight1: UInt8;
    boneWeight2: UInt8;
    boneWeight3: UInt8;
    boneLookupIndex0: UInt8;
    boneLookupIndex1: UInt8;
    boneLookupIndex2: UInt8;
    boneLookupIndex3: UInt8;
    normal: m3Normal4b;
    // variable size part
    color: m3Color;
    uv0: m3UV;
    uv1: m3UV;
    uv2: m3UV;
    uv3: m3UV;
    tangent: m3Normal4b;
  end;

  { TM3Structures }

  TM3TagInfo = record
    Name: string;
    Tag: UInt32;
    Ver: UInt32;
    Size: integer;
  end;

  TM3FieldTypes = (
    ftBinary,
    ftUInt8, ftUInt16, ftUInt32,
    ftInt8, ftInt16, ftInt32,
    ftFloat,
    ftSubStruct
  );

  TM3FieldInfo = record
    fiName: string;
    fiGroupName: string;
    fiSubLevel: Integer;
    fiType: TM3FieldTypes;
    fiTypeName: string;
    fiTypeInfo: string;
    fiTypeFlag: Boolean;
    fiTypeFlagBits: array [0..31] of string;
    fiSize: Integer;
    fiVerMin: integer;
    fiVerMax: integer;
    fiDefault: string;
    fiExpected: string;
  end;

  TM3StructInfo = record
    iStructName: string;
    iDescription: string;
    iFields: array of TM3FieldInfo;
  end;

  TM3Field = record
    fName: string;
    fGroupName: string;
    fSubLevel: Integer;
    fType: TM3FieldTypes;
    fTypeName: string;
    fTypeInfo: string;
    fTypeFlag: Boolean;
    fTypeFlagBits: array [0..31] of string;
    fSize: Integer;
    fOffset: Integer;
    fData: Pointer;
    fDefault: string;
    fExpected: string;
  end;

  PM3Structure = ^TM3Structure;
  TM3Structure = record
    Tag: UInt32;
    Index: Integer;
    StructName: string;
    Description: string;
    Ver: UInt32;
    Data: Pointer;
    DataSize: Integer;
    ItemSize: UInt32;
    ItemCount: UInt32;
    ItemFields: array of TM3Field;
  end;

  TM3Structures = class
  private
    FXML: TXMLDocument;

    FTagInfos: array of TM3TagInfo;
    FStructInfos: array of TM3StructInfo;

    procedure ParseFieldInfo(const Node: TDOMElement; var Field: TM3FieldInfo;
      const DefMinVer: Integer = 0; const DefMaxVer: Integer = MaxInt);
    procedure ParseSubStructInfo(var m3Tag: TM3StructInfo; SubName, GroupName: string;
      const SubLevel, SubVerMin, SubVerMax: Integer; var Desc: string);
    procedure LoadTagInfos;
    procedure LoadStructInfos;

    procedure checkVersionInfo(version: TDOMElement; const TagName: string);
  public
    destructor Destroy; override;

    procedure LoadStructures(const aFileName: string);
    procedure SaveStructures(const aFileName: string);
    function StructuresLoaded: boolean;

    function GetStructureInfo(var m3Tag: TM3Structure): boolean;
    procedure GetTagSize(var m3Tag: TM3Structure);
  end;

var
  Structures: TM3Structures;

procedure ResizeStructure(var Struct: TM3Structure; NewCount: UInt32);

function M3FloatToStr(const F: Single): string;

implementation

uses
  umain;

procedure ResizeStructure(var Struct: TM3Structure; NewCount: UInt32);
var
  newSize, fillSize: Integer;
begin
  if NewCount = Struct.ItemCount then Exit;
  if NewCount <= 0 then
  begin
    Freemem(Struct.Data, Struct.DataSize);
    Struct.DataSize := 0;
    Struct.ItemCount := 0;
    Exit;
  end;
  newSize := 16;
  while newSize < (NewCount * Struct.ItemSize) do inc(newSize,16);
  ReAllocMem(Struct.Data, newSize);
  Struct.DataSize := newSize;

  newSize := NewCount * Struct.ItemSize;
  fillSize := Struct.DataSize - newSize;
  FillChar((Struct.Data + newSize)^,fillSize,$AA);
end;

function M3FloatToStr(const F: Single): string;
var
  i: integer;
begin
  Result := FloatToStrF(F,ffFixed,0,100);
  i := length(Result);
  while (i > 3) and (Result[i] = '0') do
    dec(i);
  Result := copy(Result,1,i);
end;

function GetChildDOMElement(const el: TDOMElement): TDOMElement;
var
  n: TDOMNode;
begin
  n := el.FirstChild;
  while (n <> nil) and not (n is TDOMElement) do
    n := n.NextSibling;
  if n = nil then
    Result := nil
  else
    Result := n as TDOMElement;
end;

procedure NextDOMElement(var el: TDOMElement);
var
  n: TDOMNode;
begin
  n := el.NextSibling;
  while (n <> nil) and not (n is TDOMElement) do
    n := n.NextSibling;
  if n = nil then
    el := nil
  else
    el := n as TDOMElement;
end;

function FieldTypeFromStr(const S: string): TM3FieldTypes;
begin
  //S := LowerCase(S);
  if S = '' then Result := ftBinary // when type attribute is not present
  else if S = 'uint8' then Result := ftUInt8
  else if S = 'fixed8' then Result := ftUInt8
  else if S = 'uint16' then Result := ftUInt16
  else if S = 'uint32' then Result := ftUInt32
  else if S = 'tag' then Result := ftUInt32
  else if S = 'int8' then Result := ftInt8
  else if S = 'int16' then Result := ftInt16
  else if S = 'int32' then Result := ftInt32
  else if S = 'float' then Result := ftFloat
  else Result := ftSubStruct;
end;

function FieldSizeFromType(const fType: TM3FieldTypes): integer;
begin
  case fType of
    ftUInt8:  Result := 1;
    ftUInt16: Result := 2;
    ftUInt32: Result := 4;
    ftInt8:   Result := 1;
    ftInt16:  Result := 2;
    ftInt32:  Result := 4;
    ftFloat:  Result := 4;
  else Result := 0;
  end;
end;

function GetFlagBitIndex(const Bit: string): integer;
var
  i: integer;
  n: UInt32;
begin
  n := StrToIntDef(bit,0);
  if n = 0 then Exit(-1);
  i := 0;
  while (n and 1) = 0 do
  begin
    n := n shr 1;
    inc(i);
  end;
  if n = 1 then
    Result := i
  else
    Result := -1;
end;

function GetStructByName(domRoot: TDOMElement; const Name: string): TDOMElement;
var
  el: TDOMElement;
begin
  el := domRoot.FirstChild as TDOMElement;
  while Assigned(el) do
  begin
    if (el.TagName = 'structure') and (el['name']=Name) then
    begin
      Result := el;
      Exit;
    end;
    NextDOMElement(el);
  end;
  Result := nil;
end;

{ TM3Structures }

procedure TM3Structures.ParseFieldInfo(const Node: TDOMElement;
  var Field: TM3FieldInfo; const DefMinVer: Integer; const DefMaxVer: Integer);
var
  bit: TDOMElement;
  i: integer;
begin
  Field.fiName := Node['name'];
  Field.fiTypeName := Node['type'];
  Field.fiType := FieldTypeFromStr(Field.fiTypeName);
  Field.fiSize := StrToIntDef(Node['size'],FieldSizeFromType(Field.fiType));
  Field.fiVerMin := StrToIntDef(Node['since-version'],DefMinVer);
  Field.fiVerMax := StrToIntDef(Node['till-version'],DefMaxVer);
  Field.fiDefault := Node['default-value'];
  Field.fiExpected := Node['expected-value'];
  bit := Node.FindNode('bits') as TDOMElement;
  if Assigned(bit) then
  begin
    Field.fiTypeFlag := true;
    for i := 0 to 31 do
      Field.fiTypeFlagBits[i]:='';
    bit := GetChildDOMElement(bit);
    while Assigned(bit) do
    begin
      i := GetFlagBitIndex(bit['mask']);
      if i <> -1 then
        Field.fiTypeFlagBits[i]:=bit['name'];
      NextDOMElement(bit);
    end;
  end
  else
    Field.fiTypeFlag := false;
end;

procedure TM3Structures.ParseSubStructInfo(var m3Tag: TM3StructInfo; SubName,
  GroupName: string; const SubLevel, SubVerMin, SubVerMax: Integer; var Desc: string);
var
  struct, el: TDOMElement;
  i, subVer: Integer;
begin
  struct := GetStructByName(FXML.DocumentElement,SubName);
  if struct = nil then
  begin
    // check if subStruct version is a part of SubName
    i := length(SubName);
    while (i > 0) and (SubName[i] <> 'V') do
      dec(i);
    if i = 0 then
      subVer := 0
    else
    begin
      subVer := StrToIntDef(copy(SubName,i+1,MaxInt),-1);
      if subVer <> -1 then
        SubName := Copy(SubName,1,i-1)
      else
        subVer := 0;
    end;
    struct := GetStructByName(FXML.DocumentElement,SubName);
  end
  else
    subVer := 0;
  if struct = nil then
  begin
    FMain.Log('Error: can''t find "%s" structure info',[SubName]);
    Exit;
  end;
  el := struct.FindNode('description') as TDOMElement;
  if el <> nil then
    Desc := el.TextContent;

  el := struct.FindNode('fields') as TDOMElement;
  if el = nil then
  begin
    FMain.Log('Error: can''t find fields in "%s" structure info',[SubName]);
    Exit;
  end;

  i := length(m3Tag.iFields);
  el := GetChildDOMElement(el);
  while Assigned(el) do
  begin
    SetLength(m3Tag.iFields,i+1);
    ParseFieldInfo(el,m3Tag.iFields[i],SubVerMin,SubVerMax);
    m3Tag.iFields[i].fiGroupName := GroupName;
    m3Tag.iFields[i].fiSubLevel := SubLevel;
    if (m3Tag.iFields[i].fiType = ftSubStruct) and (m3Tag.iFields[i].fiSize = 0) then
    begin
      ParseSubStructInfo(
        m3Tag,
        m3Tag.iFields[i].fiTypeName,
        GroupName + m3Tag.iFields[i].fiName + '.',
        SubLevel + 1,
        m3Tag.iFields[i].fiVerMin,
        m3Tag.iFields[i].fiVerMax,
        m3Tag.iFields[i].fiTypeInfo
      );
      i := length(m3Tag.iFields)-1;
    end;
    inc(i);
    NextDOMElement(el);
  end;
end;

procedure TM3Structures.LoadTagInfos;
var
  el: TDOMElement;
  i, v, t, n: integer;
begin
  SetLength(FTagInfos,0);
  if FXML = nil then Exit;
  el := FXML.DocumentElement.FindNode('m3tags') as TDOMElement;
  if el = nil then Exit;
  el := GetChildDOMElement(el);
  i := 0;
  while Assigned(el) do
  begin
    v := StrToIntDef(el['ver'],0);
    n := StrToIntDef(el['size'],0);
    t := StrToIntDef(el['value'],0);
    if (n > 0) and (t <> 0) then
    begin
      SetLength(FTagInfos,i+1);
      FTagInfos[i].Name := el['name'];
      FTagInfos[i].Tag := t;
      FTagInfos[i].Ver := v;
      FTagInfos[i].Size := n;
      inc(i);
    end;
    NextDOMElement(el);
  end;
end;

procedure TM3Structures.LoadStructInfos;
var
  struct, sub, field: TDOMElement;
  i, j: integer;
begin
  for i := 0 to length(FStructInfos)-1 do
    SetLength(FStructInfos[i].iFields,0);
  SetLength(FStructInfos,0);
  i:=0;
  struct := GetChildDOMElement(FXML.DocumentElement);
  while Assigned(struct) do
  begin
    if (struct.TagName = 'structure') then
    begin
      SetLength(FStructInfos,i+1);
      FStructInfos[i].iStructName := struct['name'];
      sub := struct.FindNode('description') as TDOMElement;
      if sub <> nil then
        FStructInfos[i].iDescription := sub.TextContent
      else
        FStructInfos[i].iDescription := '';

      sub := struct.FindNode('versions') as TDOMElement;
      if sub <> nil then
      begin
        field := GetChildDOMElement(sub);
        if field = nil then
          FMain.Log('Note: structure "%s" don''t have version info.',[FStructInfos[i].iStructName])
        else
          checkVersionInfo(field,FStructInfos[i].iStructName);
      end
      else
      begin
        FMain.Log('Note: structure "%s" don''t have version info.',[FStructInfos[i].iStructName]);
      end;

      sub := struct.FindNode('fields') as TDOMElement;
      if sub <> nil then
      with FStructInfos[i] do
      begin
        SetLength(iFields,0);
        j := 0;
        field := GetChildDOMElement(sub);
        while Assigned(field) do
        begin
          SetLength(iFields,j+1);
          ParseFieldInfo(field,iFields[j]);
          iFields[j].fiGroupName := '';
          iFields[j].fiSubLevel := 0;
          if (iFields[j].fiType = ftSubStruct) and (iFields[j].fiSize = 0) then
          begin
            ParseSubStructInfo(
              FStructInfos[i],
              iFields[j].fiTypeName,
              iFields[j].fiName + '.', 1,
              iFields[j].fiVerMin,
              iFields[j].fiVerMax,
              iFields[j].fiTypeInfo);
            j := length(iFields)-1;
          end;

          inc(j);
          NextDOMElement(field);
        end;
      end;
      inc(i);
    end;
    NextDOMElement(struct);
  end;
end;

procedure TM3Structures.checkVersionInfo(version: TDOMElement;
  const TagName: string);
var
  i, v, s: integer;

begin
  while Assigned(version) do
  begin
    if (version.TagName = 'version') then
    begin
      v := StrToIntDef(version['number'],-1);
      s := StrToIntDef(version['size'],0);
      if v <> -1 then
      begin
        for i := 0 to length(FTagInfos)-1 do
          with FTagInfos[i] do
          if
            (Name = TagName) and
            (Ver = v) and
            (Size <> s)
          then FMain.Log(
            'Warning: Structure "%s" V%d size (%d) is different than tag "%s" V%d (%.8x) size (%d)',
            [TagName,v,s, Name,Ver,Tag,Size]
          );
      end;
      Break;
    end;
    NextDOMElement(version);
  end;
end;

destructor TM3Structures.Destroy;
begin
  if FXML <> nil then
    FXML.Free;
  SetLength(FTagInfos,0);
  inherited Destroy;
end;

procedure TM3Structures.LoadStructures(const aFileName: string);
begin
  if FXML <> nil then
    FXML.Free;
  ReadXMLFile(FXML,aFileName);
  LoadTagInfos;
  LoadStructInfos;
end;

procedure TM3Structures.SaveStructures(const aFileName: string);
begin
  if FXML <> nil then
    WriteXMLFile(FXML,aFileName);
end;

function TM3Structures.StructuresLoaded: boolean;
begin
  Result := FXML <> nil;
end;

function TM3Structures.GetStructureInfo(var m3Tag: TM3Structure): boolean;
var
  i, j, k, idx, off: integer;
begin
  idx := -1;
  for i := 0 to length(FStructInfos)-1 do
    if FStructInfos[i].iStructName = m3Tag.StructName then
    begin
      idx := i;
      Break;
    end;
  Result := idx <> -1;
  if not Result then
  begin
    FMain.Log('Warning: Tag structure info not found: "%s"',[m3Tag.StructName]);
    SetLength(m3Tag.ItemFields,1);
    with m3Tag.ItemFields[0] do
    begin
      fName := 'Unknown (auto)';
      fGroupName := '';
      fSubLevel := 0;
      fType := ftBinary;
      fTypeName := 'Binary Data';
      fTypeInfo := '';
      fTypeFlag := False;
      for k := 0 to 31 do
        fTypeFlagBits[k] := '';
      if m3Tag.ItemSize <> 0 then
        fSize := m3Tag.ItemSize
      else
        fSize := m3Tag.DataSize;
      fOffset := 0;
      fDefault := '';
      fExpected := '';
    end;
    Exit;
  end;

  with FStructInfos[idx] do
  begin
    m3Tag.Description := iDescription;
    SetLength(m3Tag.ItemFields,0);
    j := 0;
    off := 0;
    for i := 0 to length(iFields)-1 do
      if (
         (m3Tag.Ver >= iFields[i].fiVerMin) and (m3Tag.Ver <= iFields[i].fiVerMax)
      ) then
      begin
        SetLength(m3Tag.ItemFields,j+1);
        with m3Tag.ItemFields[j], iFields[i] do
        begin
          fName := fiName;
          fGroupName := fiGroupName;
          fSubLevel := fiSubLevel;
          fType := fiType;
          fTypeName := fiTypeName;
          fTypeInfo := fiTypeInfo;
          fTypeFlag := fiTypeFlag;
          for k := 0 to 31 do
            fTypeFlagBits[k] := fiTypeFlagBits[k];
          fSize := fiSize;
          fOffset := off;
          inc(off, fSize);
          fDefault := fiDefault;
          fExpected := fiExpected;
        end;
        inc(j);
      end;
  end;

end;

procedure TM3Structures.GetTagSize(var m3Tag: TM3Structure);
var
  i: integer;
  b: PByte;
begin
  for i := 0 to length(FTagInfos)-1 do
    if (FTagInfos[i].Tag = m3Tag.Tag) and (FTagInfos[i].Ver = m3Tag.Ver) then
    begin
      m3Tag.ItemSize := FTagInfos[i].Size;
      Exit;
    end;
  // structure not found, guessing size
  FMain.Log('Warning: Tag size info not found: "%s" V%d (%.8x)',[m3Tag.StructName,m3Tag.Ver,m3Tag.Tag]);
  with m3Tag do
  if ItemCount <> 0 then
  begin
    ItemSize := DataSize;
    b := (Data + DataSize - 1);
    while (ItemSize > 0) and (b^ = $AA) do // magic number here, $AA is used to fill empties in m3 files by default
    begin
      dec(ItemSize);
      dec(b);
    end;
    while ((ItemSize mod ItemCount) <> 0) and (ItemSize < DataSize) do // in case $AA was actually a part of value
      inc(ItemSize);
    ItemSize := ItemSize div ItemCount;
    FMain.Log('Note: Guessed tag item size = %d',[ItemSize]);
  end
  else
    ItemSize := DataSize;
end;

end.

