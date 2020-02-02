unit RTTIOP;

interface

uses Classes, Vcl.Forms, Vcl.Dialogs, Vcl.Controls, Vcl.StdCtrls, SysUtils,
  Windows, WideStrUtils, variants, rtti,
  System.TypInfo, WPDFunction, Generics.Collections, LoadPhp,
  hzend_types, TEventSet, System.RTLConsts;

var
  EDTRc: TRttiContext;
  PhpEvent: TEvent;

  ListObjSelf: TDictionary<PAnsiChar, NativeInt>;
  ListObjEventClass: TDictionary<NativeInt, Pzval>;

function FindControlVCL(obj: PAnsiChar): longint; cdecl;

function TestVariant(var ZResult: Pzval; ZOwner, ZOwnerSelf: Integer;
  AName: PAnsiChar; arr: Pzval): Integer; cdecl;
procedure TestSetRet(return_value: Pzval; Result: TValue; ClassName: String);
procedure GUIStringToComponent(execute_data: Pzend_execute_data;
  return_value: Pzval); cdecl;
procedure GUISaveComponentToTextFile(execute_data: Pzend_execute_data;
  return_value: Pzval); cdecl;
procedure GUIComponentToString(execute_data: Pzend_execute_data;
  return_value: Pzval); cdecl;
procedure GUILoadComponentFromTextFile(execute_data: Pzend_execute_data;
  return_value: Pzval); cdecl;

implementation

function StringToSet3(TypeInfo: PTypeInfo; const Value: string): Integer;
var
  P: PChar;
  EnumName: string;
  EnumValue: NativeInt;
  PEnumInfo: PPTypeInfo;

  // grab the next enum name
  function NextWord(var P: PChar): string;
  var
    i: Integer;
  begin
    i := 0;

    // scan til whitespace
    while not(P[i] in [',', ' ', #0, ']']) do
      Inc(i);

    SetString(Result, P, i);

    // skip whitespace
    while (P[i] in [',', ' ', ']']) do
      Inc(i);

    Inc(P, i);
  end;

begin
  Result := 0;
  if Value = '' then
    Exit;
  P := PChar(Value);

  // skip leading bracket and whitespace
  while (P^ in ['[', ' ']) do
    Inc(P);

  PEnumInfo := GetTypeData(TypeInfo)^.CompType;
  if PEnumInfo <> nil then
  begin
    EnumName := NextWord(P);
    while EnumName <> '' do
    begin
      if EnumName.Trim <> '' then
      begin
        EnumValue := GetEnumValue(PEnumInfo^, EnumName);
        if EnumValue < 0 then
          raise EPropertyConvertError.CreateResFmt(@SInvalidPropertyElement,
            [EnumName]);
        Include(TIntegerSet(Result), EnumValue);
      end;
      EnumName := NextWord(P);
    end;
  end
  else
  begin
    EnumName := NextWord(P);
    while EnumName.Trim <> '' do
    begin
      if EnumName <> '' then
      begin
        EnumValue := StrToIntDef(EnumName, -1);
        if EnumValue < 0 then
          raise EPropertyConvertError.CreateResFmt(@SInvalidPropertyElement,
            [EnumName]);
        Include(TIntegerSet(Result), EnumValue);
      end;
      EnumName := NextWord(P);
    end;
  end;
end;

function ParEx(idx: Integer; Instance: TRttiType; ap: Pointer; Value: Pzval;
  pP: byte = 0): TValue;
var
  Data: PByte;
  ResultType: Pointer;
  i: Integer;
  P: TRttiType;
  Src: Pointer;
  obj: TObject;
  cls: TClass;
begin

  if TObject(ap) is TRttiMethod then
  begin
    P := TRttiMethod(ap).ReturnType;
  end
  else if TObject(ap) is TRttiIndexedProperty then
  begin
    P := TRttiIndexedProperty(ap).PropertyType;
  end
  else if TObject(ap) is TRttiProperty then
  begin
    P := TRttiProperty(ap).PropertyType;
  end
  else if TObject(ap) is TRttiField then
  begin
    P := TRttiField(ap).FieldType;
  end
  else if TObject(ap) is TRttiParameter then
  begin
    P := TRttiParameter(ap).ParamType;
  end;

  if P = nil then
    Result := Pointer(ZvalGetInt(Value))
  else
  begin
    case P.TypeKind of
      tkChar:
        Result := ZvalGetStringA(Value)[1];
      tkClass:
        begin
          obj := TObject(ZvalGetInt(Value));
          if obj = nil then
            Result := obj
          else
          begin
            if obj.InheritsFrom(P.Handle.TypeData.ClassType) then
            begin
              Result := obj
            end
            else
            begin
              Result := nil;
              zend_error(E_USER_ERROR,
                '%S �� ���������� ������� %S ��� ��� �����������.',
                obj.ClassName, String(P.Handle.Name));
            end;
          end;
        end;
      tkClassRef:
        begin
          cls := TClass(ZvalGetInt(Value));
          if cls = nil then
            Result := cls
          else
          begin
            if cls.InheritsFrom(P.Handle.TypeData.ClassType) or
              cls.InheritsFrom(TComponent) then
            begin
              Result := cls
            end
            else
            begin
              Result := nil;
              zend_error(E_USER_ERROR,
                '%S �� ���������� ������� %S ��� ��� �����������.',
                cls.ClassName, String(P.Handle.Name));
            end;
          end;
        end;
      tkPointer:
        begin
          ResultType := nil;
          if (P.Name = 'PWideChar') or (P.Name = 'PChar') then
            ResultType := StringToOleStr(ZvalGetString(Value))
          else if (P.Name = 'PAnsiChar') or (P.Name = '_PAnsiChar') then
            ResultType := PAnsiChar(ZvalGetStringA(Value))
          else if P.Name = 'PAnsiString' then
            ResultType := PAnsiString(ZvalGetStringA(Value))
          else if P.Name = 'UnicodeString' then
            ResultType := StringToOleStr(StringToOleStr(ZvalGetString(Value)));

          if assigned(ResultType) then
            TValue.Make(@ResultType, P.Handle, Result)
          else
            Result := Pointer(ZvalGetInt(Value));
        end;
      tkInteger:
        Result := ZvalGetInt(Value);
      tkFloat:
        Result := ZvalGetDouble(Value);
      tkString:
        Result := TValue.From<ShortString>(ShortString(ZvalGetStringA(Value)));
      tkWChar:
        Result := ZvalGetString(Value)[1];
      tkLString:
        Result := ZvalGetStringA(Value);
      tkWString:
        Result := ZvalGetString(Value);
      tkInt64:
        Result := StrToInt64(ZvalGetStringA(Value));
      tkUString:
        Result := ZvalGetString(Value);
      tkEnumeration:
        begin
          Result := TValue.FromOrdinal(P.Handle,
            GetEnumValue(P.Handle, ZvalGetString(Value)));
        end;
      tkSet:
        begin
          i := StringToSet3(P.Handle, String(ZvalGetPChar(Value)));
          TValue.Make(@i, P.Handle, Result);
        end;
      tkUnknown:
        begin
          case Value^.u1.type_info of
            IS_LONG:
              Result := ZvalGetInt(Value);
            IS_DOUBLE:
              Result := ZvalGetDouble(Value);
            IS_BOOL:
              Result := ZvalGetBool(Value);
            IS_STRING:
              Result := ZvalGetStringA(Value);
          end;
        end
    else
      begin
        ShowMessage('Realize Type Kind ' +
          GetEnumName(System.TypeInfo(TTypeKind), Ord(P.TypeKind)) +
          '! (ParEx)');
        Result := nil;
      end;
    end;
  end;

end;

function Par(TMethod: TRttiMethod; Instance: TRttiType;
  T: TArray<TRttiParameter>; Args: Pzval): TArray<TValue>;
var
  P: TRttiParameter;
  i: Integer;
begin
  SetLength(Result, Length(T));

  if Args <> nil then
  begin
    if Length(T) = Args^.Value.arr.nNumOfElements then
    begin
      i := 0;
      for P in T do
      begin
        Result[i] := ParEx(i, Instance, P, zend_hash_index_findZval(Args, i));
        Inc(i);
      end;
    end;
  end;
end;

procedure CreateClassSelf(return_value: Pzval; ClassName: string;
  Self: NativeInt);
begin
  if ClassName = '-1' then
    ZvalVAL(return_value, Self)
  else
  begin
    ClassName := StringReplace(ClassName, '.', '\',
      [rfReplaceAll, rfIgnoreCase]);

    CreateCll(return_value, PAnsiChar(AnsiString('DClass\' + ClassName)), Self);
  end;
end;

procedure TestSetRet(return_value: Pzval; Result: TValue; ClassName: String);
var
  A: TClass;
  B: TObject;
  FGRG: PTypeInfo;
begin
  if Result.IsEmpty then
  begin
    ZvalVAL(return_value);
    Exit;
  end;
  case Result.Kind of
    tkPointer:
      ZvalVAL(return_value, Integer(Result.GetReferenceToRawData));
    tkClass:
      begin
        if (ClassName = '') and Result.IsObject then
        begin
          ClassName := Result.AsObject.QualifiedClassName;

        end;

        CreateClassSelf(return_value, ClassName, NativeInt(Result.AsObject));
      end;
    tkClassRef:
      begin
        if ClassName = '' then
          ClassName := Result.AsClass.QualifiedClassName;

        CreateClassSelf(return_value, ClassName, NativeInt(Result.AsClass));
      end;
    tkFloat:
      ZvalVAL(return_value, Result.AsExtended);
    tkInteger:
      ZvalVAL(return_value, Integer(Result.AsInteger));
    tkInt64:
      ZvalVAL(return_value, Integer(Result.AsInt64));
  else
    ZvalVAL(return_value, Result.ToString);
  end;
end;

function FindControlVCL(obj: PAnsiChar): longint; cdecl;
var
  ClassName: string;
  Self: NativeInt;
begin
  Self := 0;
  if not ListObjSelf.TryGetValue(obj, Self) then
  begin
    ClassName := StringReplace(obj, '\', '.', [rfReplaceAll, rfIgnoreCase]);

    if Copy(ClassName, 0, 1) = '.' then
      ClassName := Copy(ClassName, 2);

    if Copy(ClassName, 0, 7).ToLower = 'dclass.' then
      ClassName := Copy(ClassName, 8);

    Self := NativeInt(EDTRc.FindType(ClassName)); // EDTRc.FindType(ClassName)

    ListObjSelf.Add(obj, Self);
  end;
  Result := Self
end;

function TestVariant(var ZResult: Pzval; ZOwner, ZOwnerSelf: Integer;
  AName: PAnsiChar; arr: Pzval): Integer; cdecl;
var
  TRttiIT: TRttiType;
  Instance: TRttiType;
  TMethod: TRttiMethod;
  TPropertyIdx: TRttiIndexedProperty;
  TProperty: TRttiProperty;
  TField: TRttiField;
  TParameter: TRttiParameter;
  Args: TArray<TValue>;
  NumParams, Num, i: Integer;
  zv: Pzval;
  tmp, tmp2: Pzval;
  Kind: TTypeKind;
  TT: Pzval;
begin
  Result := 0;

  TRttiIT := TRttiType(ZOwner);

  if TRttiIT <> nil then
  begin
    Num := 0;

    if (arr <> nil) then
    begin
      if arr.u1.v._type = IS_ARRAY then
        Num := arr.Value.arr.nNumOfElements
      else
        Num := 1;
    end;

    TMethod := TRttiIT.GetMethod(AName);

    if (TMethod = nil) and (ZOwnerSelf <> -1) then
    begin
      Instance := TRttiType(ZOwnerSelf);

      if Instance <> nil then
      begin
        TPropertyIdx := EDTRc.GetType(Instance.ClassInfo)
          .GetIndexedProperty(AName);

        if TPropertyIdx <> nil then
        begin
          NumParams := Length(TPropertyIdx.ReadMethod.GetParameters);

          SetLength(Args, NumParams);
          i := 0;
          for TParameter in TPropertyIdx.ReadMethod.GetParameters do
          begin
            zv := zend_hash_index_findZval(arr, i);
            Args[i] := ParEx(i, Instance, TParameter, zv);
            Inc(i);
          end;

          if (NumParams = Num) and TPropertyIdx.IsReadable then
          begin
            TestSetRet(@ZResult, TPropertyIdx.GetValue(Instance, Args),
              TPropertyIdx.PropertyType.QualifiedName);
            Result := 1;
          end
          else if (NumParams = Num - 1) and TPropertyIdx.IsWritable then
          begin
            zv := zend_hash_index_findZval(arr, Num - 1);
            TPropertyIdx.SetValue(Instance, Args,
              ParEx(0, Instance, TPropertyIdx, zv));
            Result := 1;
          end;
        end
        else
        begin
          TProperty := EDTRc.GetType(Instance.ClassInfo).GetProperty(AName);

          if TProperty <> nil then
          begin

            if (TProperty.IsWritable and (arr <> nil)) then
            begin
              if TProperty.PropertyType.TypeKind = tkMethod then
              begin
                PhpEvent.Add(arr, TObject(Instance), TProperty.Name);
              end
              else
              BEGIN
                TProperty.SetValue(Instance,
                  ParEx(0, Instance, TProperty, arr));

              END;
              Result := 1;
            end
            else if TProperty.IsReadable then
            begin
              TestSetRet(@ZResult, TProperty.GetValue(Instance),
                TProperty.PropertyType.QualifiedName);
              Result := 1;
            end;
          end
          else
          begin
            TField := EDTRc.GetType(Instance.ClassInfo).GetField(AName);
            if TField <> nil then
            begin
              if (arr <> nil) then
                TField.SetValue(Instance, ParEx(0, Instance, TField, arr))
              else
                TestSetRet(@ZResult, TField.GetValue(Instance),
                  TField.FieldType.QualifiedName);
              Result := 1;
            end
          end;
        end
      end
    end
    else if (TMethod <> nil) then
    begin



      Args := Par(TMethod, TRttiIT, TMethod.GetParameters, arr);

      if TMethod.MethodKind in [mkConstructor, mkClassProcedure,
        mkClassFunction, mkClassConstructor, mkClassDestructor] then
        TestSetRet(@ZResult, TMethod.Invoke(TRttiIT.AsInstance.MetaclassType,
          Args), ZOwnerSelf.ToString)
      else if TRttiIT.AsInstance.MetaclassType.InheritsFrom(TApplication) then
        TestSetRet(@ZResult, TMethod.Invoke(Application, Args),
          ZOwnerSelf.ToString)
      else if (ZOwnerSelf <> 0) then
      begin
        Kind := EDTRc.GetType(TRttiType(ZOwnerSelf).ClassInfo).Handle.Kind;
        if Kind = tkClass then
          TestSetRet(@ZResult, TMethod.Invoke(TObject(ZOwnerSelf), Args), '')
        else if Kind = tkClassRef then
          TestSetRet(@ZResult, TMethod.Invoke(TClass(ZOwnerSelf), Args), '');
      end;

      Result := 1;
      NumParams := Length(TMethod.GetParameters);

      if NumParams <> 0 then
      begin
        for i := 0 to NumParams - 1 do
        begin
          if (pfVar in TMethod.GetParameters[i].Flags) or
            (pfOut in TMethod.GetParameters[i].Flags) then
          begin
            tmp := zend_hash_index_findZval(arr, i);

            if tmp.u1.v._type = IS_OBJECT then
            begin
              if isset_property(tmp, '__DClassSelf') = 1 then
              begin
                if (TObject(Args[i].GetReferenceToRawData) <> nil) then
                begin
                  new(tmp2);
                  TestSetRet(tmp2, Args[i], '-1');

                  update_property_zval(tmp, '__DClassSelf', tmp2);
                  Dispose(tmp2);
                end;
              end;
            end
            else
              TestSetRet(tmp, Args[i], '');
          end;
        end;
      end;

    end;

    if (Result = 0) and (Num = 2) then
    begin
      tmp := zend_hash_index_findZval(arr, 0);
      tmp2 := zend_hash_index_findZval(arr, 1);

      if (String(AName).ToLower = 'dguisize') then
      begin
        if ZvalGetInt(tmp) <> -1 then
          TestVariant(TT, ZOwner, ZOwnerSelf, 'Width', tmp);
        if ZvalGetInt(tmp2) <> -1 then
          TestVariant(TT, ZOwner, ZOwnerSelf, 'Height', tmp2);
        Result := 1;
      end
      else if ((String(AName).ToLower = 'dguimove') and (Num = 2)) then
      begin
        if ZvalGetInt(tmp) <> -1 then
          TestVariant(TT, ZOwner, ZOwnerSelf, 'Left', tmp);
        if ZvalGetInt(tmp2) <> -1 then
          TestVariant(TT, ZOwner, ZOwnerSelf, 'Top', tmp2);
        Result := 1;
      end;
    end;

  end;
end;

procedure DoBefore2(_Function: Pzval; o: TRttiProperty;
  const Args: TArray<TValue>);
var
  CountArg, i: Integer;
  P, p2: Pointer;
begin
  CountArg := Length(Args) - 1;

  P := ZvalEmalloc(CountArg + 1);

  for i := 0 to CountArg do
  begin
    asm
      mov eax, i
      shl eax, $04
      add eax, p
      mov p2, EAX
    end;

    TestSetRet(p2, Args[i], '');
  end;

  __call_function(_Function, P, CountArg + 1);
end;

procedure GUILoadComponentFromTextFile(execute_data: Pzend_execute_data;
  return_value: Pzval); cdecl;

var
  MemStream: TMemoryStream;
  FileStream: TFileStream;
  Instance, _File: Pzval;
begin
  if zend_parse_method_parameters(2, nil, 'zz', @Instance, @_File) = 0 then
  begin
    MemStream := TMemoryStream.Create;
    FileStream := TFileStream.Create(ZvalGetStringA(_File), fmOpenRead);
    try
      ObjectTextToBinary(FileStream, MemStream);
      MemStream.Position := 0;
      MemStream.ReadComponent(TComponent(ZvalGetInt(Instance)));
    finally
      MemStream.Free;
      FileStream.Free;
    end;
  end;
end;

procedure GUIStringToComponent(execute_data: Pzend_execute_data;
  return_value: Pzval); cdecl;

var
  StrStream: TStringStream;
  MemStream: TMemoryStream;
  Instance, _File: Pzval;
begin
  if zend_parse_method_parameters(2, nil, 'zz', @Instance, @_File) = 0 then
  begin
    StrStream := TStringStream.Create(ZvalGetStringA(_File));
    try
      MemStream := TMemoryStream.Create;
      try
        ObjectTextToBinary(StrStream, MemStream);
        MemStream.Position := 0;
        MemStream.ReadComponent(TComponent(ZvalGetInt(Instance)));
      finally
        MemStream.Free;
      end;
    finally
      StrStream.Free;
    end;
  end;
end;

procedure GUIComponentToString(execute_data: Pzend_execute_data;
  return_value: Pzval); cdecl;

var
  MemStream: TMemoryStream;
  StringStream: TStringStream;
  Instance: Pzval;
begin
  if zend_parse_method_parameters(1, nil, 'z', @Instance) = 0 then
  begin
    StringStream := TStringStream.Create(' ');
    MemStream := TMemoryStream.Create;
    try
      MemStream.WriteComponent(TComponent(ZvalGetInt(Instance)));
      MemStream.Position := 0;
      ObjectBinaryToText(MemStream, StringStream);
      StringStream.Position := 0;
      ZvalVAL(return_value, StringStream.DataString);
    finally
      MemStream.Free;
      StringStream.Free;
    end;
  end;
end;

procedure GUISaveComponentToTextFile(execute_data: Pzend_execute_data;
  return_value: Pzval); cdecl;

var
  MemStream: TMemoryStream;
  FileStream: TFileStream;
  Instance, _File: Pzval;
begin
  if zend_parse_method_parameters(2, nil, 'zz', @Instance, @_File) = 0 then
  begin

    FileStream := TFileStream.Create(ZvalGetStringA(_File),
      fmCreate or fmOpenWrite);
    try
      MemStream := TMemoryStream.Create;
      try
        MemStream.WriteComponent(TComponent(ZvalGetInt(Instance)));
        MemStream.Position := 0;
        ObjectBinaryToText(MemStream, FileStream);
      finally
        MemStream.Free;
      end;
    finally
      FileStream.Free;
    end;
  end;
end;

initialization

ListObjSelf := TDictionary<PAnsiChar, NativeInt>.Create;
ListObjEventClass := TDictionary<NativeInt, Pzval>.Create;
PhpEvent := TEvent.Create;
PhpEvent.OnBefore := DoBefore2;

end.
