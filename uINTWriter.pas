unit uINTWriter;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uBytecode, uBuiltins;

type
  TINTWriter = class
  private
    class procedure WriteWordToStream(Stream: TStream; Value: Word);
    class procedure WriteLongToStream(Stream: TStream; Value: Cardinal);
    class procedure WriteOpToStream(Stream: TStream; Op: Word);
    class procedure WriteIntToStream(Stream: TStream; Value: Integer);
    class procedure WritePadByte(Stream: TStream);
  public
    class function Save(AProcedures: TObjectList<TProcedureBytecode>;
      AStringTable: TList<string>; AGlobalVars: TList<string>;
      const FileName: string): Boolean; static;
  end;

implementation

class procedure TINTWriter.WriteWordToStream(Stream: TStream; Value: Word);
var
  B: Byte;
begin
  B := Hi(Value);
  Stream.WriteBuffer(B, 1);
  B := Lo(Value);
  Stream.WriteBuffer(B, 1);
end;

class procedure TINTWriter.WriteLongToStream(Stream: TStream; Value: Cardinal);
var
  W: array[0..1] of Word absolute Value;
begin
  WriteWordToStream(Stream, W[1]);
  WriteWordToStream(Stream, W[0]);
end;

class procedure TINTWriter.WriteOpToStream(Stream: TStream; Op: Word);
begin
  WriteWordToStream(Stream, Op);
end;

class procedure TINTWriter.WriteIntToStream(Stream: TStream; Value: Integer);
begin
  WriteOpToStream(Stream, $C001);
  WriteLongToStream(Stream, Cardinal(Value));
end;

class procedure TINTWriter.WritePadByte(Stream: TStream);
var
  B: Byte;
begin
  B := 0;
  Stream.WriteBuffer(B, 1);
end;

class function TINTWriter.Save(AProcedures: TObjectList<TProcedureBytecode>;
  AStringTable: TList<string>; AGlobalVars: TList<string>;
  const FileName: string): Boolean;
var
  Stream: TStream;
  NameOffsets: TDictionary<string, Integer>;
  i, Pad: Integer;
begin
  Result := False;
  Stream := TFileStream.Create(FileName, fmCreate);
  NameOffsets := TDictionary<string, Integer>.Create;
  try
    WriteOpToStream(Stream, $8002);
    WriteIntToStream(Stream, 18);
    WriteOpToStream(Stream, $800D);
    WriteIntToStream(Stream, 0);
    WriteOpToStream(Stream, $800D);
    WriteOpToStream(Stream, $8010);
    WriteOpToStream(Stream, $801A);
    WriteOpToStream(Stream, $8020);
    WriteOpToStream(Stream, $801A);
    WriteOpToStream(Stream, $8021);
    WriteOpToStream(Stream, $801A);
    WriteOpToStream(Stream, $8022);
    WriteOpToStream(Stream, $801A);
    WriteOpToStream(Stream, $8023);
    WriteOpToStream(Stream, $8024);
    WriteOpToStream(Stream, $8025);
    WriteOpToStream(Stream, $8026);

    WriteLongToStream(Stream, AProcedures.Count);
    for i := 0 to AProcedures.Count - 1 do
    begin
      WriteLongToStream(Stream, 0);
      WriteLongToStream(Stream, 0);
      WriteLongToStream(Stream, 0);
      WriteLongToStream(Stream, 0);
      WriteLongToStream(Stream, 0);
      WriteLongToStream(Stream, Cardinal(AProcedures[i].NumArgs));
    end;

     WriteLongToStream(Stream, AStringTable.Count);
     for i := 0 to AStringTable.Count - 1 do
     begin
       NameOffsets.AddOrSetValue(AStringTable[i], Integer(Stream.Position));
       Stream.WriteBuffer(PAnsiChar(AnsiString(AStringTable[i]))^, Length(AnsiString(AStringTable[i])));
       WritePadByte(Stream);
       while (Stream.Position mod 4) > 0 do
         WritePadByte(Stream);
     end;
    for i := 0 to AProcedures.Count - 1 do
    begin
      NameOffsets.AddOrSetValue(AProcedures[i].Name, Integer(Stream.Position));
      Stream.WriteBuffer(PAnsiChar(AnsiString(AProcedures[i].Name))^, Length(AnsiString(AProcedures[i].Name)));
      WritePadByte(Stream);
      while (Stream.Position mod 4) > 0 do
        WritePadByte(Stream);
    end;

    WriteLongToStream(Stream, $FFFFFFFF);
    WriteLongToStream(Stream, $FFFFFFFF);
    WriteOpToStream(Stream, $802C);
    WriteIntToStream(Stream, 0);
    WriteOpToStream(Stream, $8003);

    for i := 0 to AProcedures.Count - 1 do
    begin
      WriteOpToStream(Stream, $802B);
      for var InstrIdx := 0 to AProcedures[i].Instructions.Count - 1 do
      begin
        var Instr := AProcedures[i].Instructions[InstrIdx];
        WriteOpToStream(Stream, Instr.Opcode);
        if Instr.Opcode = $C001 then
          WriteLongToStream(Stream, Cardinal(Instr.Value))
        else if Instr.Opcode = $9000 then
          WriteLongToStream(Stream, Cardinal(NameOffsets[Instr.Str]));
      end;
      WriteOpToStream(Stream, $8029);
      WriteOpToStream(Stream, $801C);
      Pad := Stream.Position mod 4;
      if Pad > 0 then
        WritePadByte(Stream);
    end;
    Result := True;
  finally
    NameOffsets.Free;
    Stream.Free;
  end;
end;

end.