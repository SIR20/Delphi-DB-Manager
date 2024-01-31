unit DBClassUnit;

interface

uses
  System.Classes, Win.ADODB, DB, System.Rtti, System.Generics.Collections,
  System.SysUtils;

type
  TFType = TFieldType;
  TDBConnection = TADOConnection;

  TPropAtrributes = class(TCustomAttribute)
  private
    FName: string;
    FType: TFType;

  public
    constructor Create(ft: TFType = ftUnknown; name: string = '');
    property Name: string read FName write FName;
    property FieldType: TFType read FType write FType;
  end;

  TDBContext = class
  private
    FConnection: TDBConnection;

  public
    constructor Create(Connection: TDBConnection);
  end;

  TDBSet<T> = class

  private
    FConnection: TADOConnection;
    FName: string;

  public
    constructor Create(cconnection: TDBConnection; cname: string);
    function Insert(item: T; props: TArray<string>;
      isReverse: boolean = false): boolean;
    function Select(props: TArray<string>; sqlString: string = ';'): TList<T>;
    // function Delete(): boolean;
    // function Update(): boolean;

    property name: string read FName write FName;
  end;

implementation

{ TDBContext }

constructor TDBContext.Create(Connection: TDBConnection);
var
  pName: string;
  RttiContext: TRttiContext;
  ClassType, dbSetProp, dbSetType: TRttiType;
  instanceType: TRttiInstanceType;
  dbSetObject: TValue;
begin
  FConnection := Connection;

  RttiContext := TRttiContext.Create;
  try
    ClassType := RttiContext.GetType(self.ClassInfo);
    for var Prop in ClassType.GetProperties do
    begin
      pName := Prop.name;
      dbSetProp := Prop.PropertyType;
      dbSetType := RttiContext.FindType(dbSetProp.QualifiedName);
      if dbSetType <> nil then
      begin
        instanceType := dbSetType.AsInstance;
        dbSetObject := instanceType.GetMethod('Create')
          .Invoke(instanceType.MetaclassType, [FConnection, pName]);
        Prop.SetValue(self, dbSetObject);
      end;
    end;
  except
    on e: Exception do
    begin
      writeln(e.Message);
      readln;
    end;
  end;
  dbSetType.Free;
  ClassType.Free;
  RttiContext.Free;
end;

{ DB }

function TDBSet<T>.Insert(item: T; props: TArray<string>;
  isReverse: boolean = false): boolean;
type
  TParamRecord = record
    PValue: Variant;
    PType: TFType;
  end;

var
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  adoq: TADOQuery;
  qText, propName, columnName, attrName, vals: string;
  attr: TPropAtrributes;
  values: TDictionary<string, TParamRecord>;
  pr: TParamRecord;
  ou: integer;

begin
  values := TDictionary<string, TParamRecord>.Create;
  RttiContext := TRttiContext.Create;
  RttiType := RttiContext.GetType(TypeInfo(T));
  adoq := TADOQuery.Create(nil);

  adoq.Close;
  adoq.Connection := FConnection;
  qText := 'INSERT ' + Name + ' (';
  vals := ' VALUES(';
  for var Prop in RttiType.GetProperties do
  begin
    propName := Prop.name;
    if Length(props) > 0 then
    begin
      if TArray.BinarySearch<string>(props, propName, ou) then
      begin
        if isReverse then
          continue;
      end
      else
      begin
        if not isReverse then
          continue;
      end;
    end;
    attr := TPropAtrributes(Prop.GetAttribute(TPropAtrributes));
    columnName := Prop.name;
    pr.PType := ftUnknown;
    if attr <> nil then
    begin
      attrName := attr.name;
      if attrName <> '' then
        columnName := attrName;
      pr.PType := attr.FieldType;
    end;

    try
      qText := qText + columnName + ',';
      vals := vals + ':' + columnName + ',';
      pr.PValue := Prop.GetValue(PPointer(@item)^).AsVariant;
      values.Add(columnName, pr);
    except
      on ex: Exception do
      begin
        writeln(ex.Message);
        readln;
      end;
    end;
  end;
  RttiContext.Free;

  qText[qText.Length] := ')';
  vals[vals.Length] := ')';
  vals := vals + ';';
  qText := qText + vals;
  adoq.SQL.Text := qText;
  try
    for var column in values.Keys do
    begin
      var
      prc := values[column];
      if prc.PType <> ftUnknown then
        adoq.Parameters.ParamByName(column).DataType := prc.PType;
      adoq.Parameters.ParamByName(column).Value := prc.PValue;
    end;
  except
    on ex: Exception do
    begin
      writeln(ex.Message);
      readln;
    end;
  end;
  try
    result := adoq.ExecSQL > 0;
    adoq.Close;
    adoq.FreeOnRelease;
  except
    on ex: Exception do
    begin
      writeln(ex.Message);
      readln;
    end;
  end;
end;

constructor TDBSet<T>.Create(cconnection: TDBConnection; cname: string);
begin
  FConnection := cconnection;
  FName := cname;
end;

function TDBSet<T>.Select(props: TArray<string>; sqlString: string = ';')
  : TList<T>;
var
  cols, qText: string;
  adoq: TADOQuery;
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  PropType: TRttiProperty;
  attr: TPropAtrributes;
  colName: string;
  columns: TDictionary<string, string>;
  tInstance: TRttiInstanceType;
  tObject, rValue: TValue;
begin
  cols := '';
  qText := 'SELECT ';
  result := TList<T>.Create;
  columns := TDictionary<string, string>.Create;
  adoq := TADOQuery.Create(nil);
  adoq.Connection := FConnection;
  RttiContext := TRttiContext.Create;
  RttiType := RttiContext.GetType(TypeInfo(T));
  tInstance := RttiType.AsInstance;

  for var Prop in RttiType.GetProperties do
  begin
    attr := TPropAtrributes(Prop.GetAttribute(TPropAtrributes));
    if attr <> nil then
    begin
      if attr.name <> '' then
        columns.Add(Prop.name, attr.name)
      else
        columns.Add(Prop.name, Prop.name);
    end
    else
      columns.Add(Prop.name, Prop.name);
  end;

  if Length(props) >= 1 then
  begin
    for var i := 0 to Length(props) - 1 do
      cols := cols + columns[props[i]] + ',';
    cols := cols.Remove(cols.Length - 1, 1);
  end
  else
    cols := '*';

  qText := qText + cols + ' FROM ' + Name + ' ' + sqlString;
  adoq.SQL.Text := qText;
  adoq.Open;
  try
    while not adoq.Eof do
    begin
      tObject := tInstance.GetMethod('Create')
        .Invoke(tInstance.MetaclassType, []);

      if cols = '*' then
      begin
        for var cKey in columns.Keys do
        begin
          rValue := TValue.FromVariant(adoq.FieldByName(columns[cKey])
            .AsVariant);
          PropType := RttiType.GetProperty(cKey);
          PropType.SetValue((PPointer(@(tObject.AsType<T>))^), rValue);
        end;
      end
      else
      begin
        for var i := 0 to Length(props) - 1 do
        begin
          rValue := TValue.FromVariant(adoq.FieldByName(columns[props[i]])
            .AsVariant);
          PropType := RttiType.GetProperty(props[i]);
          PropType.SetValue((PPointer(@(tObject.AsType<T>))^), rValue);
        end;
      end;
      result.Add(tObject.AsType<T>);
      tObject := nil;
      adoq.Next;
    end;
    adoq.Close;
    adoq.FreeOnRelease;
  except
    on ex: Exception do
    begin
      writeln(ex.Message);
      readln;
    end;
  end;
end;

{ TDBAtrributes }

constructor TPropAtrributes.Create(ft: TFType = ftUnknown; name: string = '');
begin
  FName := name;
  FType := ft;
end;

begin

end.
