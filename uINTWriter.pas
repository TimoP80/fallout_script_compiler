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
    class procedure WriteNameList(Stream: TStream; Entries: TList<string>);
  public
    class function Save(AProcedures: TObjectList<TProcedureBytecode>;
      AStringTable: TList<string>; AGlobalVars: TList<string>;
      ANameRefs: TList<string>; const FileName: string): Boolean; static;
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

// ---------------------------------------------------------------------------
// WriteNameList — write a name/string list in INT format
//   [4 bytes: total data size (excludes this size field)]
//   [entries: 2-byte length (even-padded) + data bytes]*
//   [4 bytes: $FFFFFFFF terminator]
// If empty, just writes $FFFFFFFF.
// ---------------------------------------------------------------------------
class procedure TINTWriter.WriteNameList(Stream: TStream; Entries: TList<string>);
var
  TotalDataSize: Integer;
  EntryBytes: TBytes;
  EntryLen: Word;
  i: Integer;
begin
  if (Entries = nil) or (Entries.Count = 0) then
  begin
    WriteLongToStream(Stream, $FFFFFFFF);
    Exit;
  end;

  TotalDataSize := 0;
  for i := 0 to Entries.Count - 1 do
  begin
    EntryBytes := TEncoding.ASCII.GetBytes(Entries[i] + #0);
    EntryLen := Length(EntryBytes);
    if (EntryLen mod 2) <> 0 then
      Inc(EntryLen);
    Inc(TotalDataSize, 2 + EntryLen);
  end;

  WriteLongToStream(Stream, Cardinal(TotalDataSize));

  for i := 0 to Entries.Count - 1 do
  begin
    EntryBytes := TEncoding.ASCII.GetBytes(Entries[i] + #0);
    EntryLen := Length(EntryBytes);
    if (EntryLen mod 2) <> 0 then
    begin
      SetLength(EntryBytes, EntryLen + 1);
      EntryBytes[EntryLen] := 0;
      Inc(EntryLen);
    end;
    WriteWordToStream(Stream, EntryLen);
    Stream.WriteBuffer(EntryBytes[0], EntryLen);
  end;

  WriteLongToStream(Stream, $FFFFFFFF);
end;

// ---------------------------------------------------------------------------
// Save — write a complete .int file
// ---------------------------------------------------------------------------
// INT format (matching sfall reference binary output):
//   1. Startup code (42 bytes): O_CRITICAL_START, writeInt(18), O_D_TO_A,
//      writeInt(init_offset), O_JMP, O_EXIT_PROG, stack unwind handlers
//   2. Procedure table: numProcs + 24 bytes per entry
//   3. Name list
//   4. String list
//   5. Init code: $802C, writeInt(0 args + critical_done), writeInt(body_offset), O_JMP
//   6. Procedure bodies (with prologue/epilogue from bytecode generator)
// ---------------------------------------------------------------------------
class function TINTWriter.Save(AProcedures: TObjectList<TProcedureBytecode>;
  AStringTable: TList<string>; AGlobalVars: TList<string>;
  ANameRefs: TList<string>; const FileName: string): Boolean;
var
  Stream: TMemoryStream;
  NamesList: TList<string>;
  NameEntryOffsets: TDictionary<string, Integer>;
  StringOffsets: TDictionary<string, Integer>;
  BodyOffsetPositions: TArray<Integer>;
  StartAddrPos: Integer;
  BodyPatchPos: Integer;
  StartProcIndex: Integer;
  i, j: Integer;
begin
  Result := False;

  // -----------------------------------------------------------------------
  // Build name list: dummy entry + procedure names + global vars + name refs
  // -----------------------------------------------------------------------
  NamesList := TList<string>.Create;
  NameEntryOffsets := TDictionary<string, Integer>.Create;
  StringOffsets := TDictionary<string, Integer>.Create;
  try
    // First entry is always the 14-character dummy name (padding for index 0)
    NamesList.Add('..............');
    for i := 0 to AProcedures.Count - 1 do
      NamesList.Add(AProcedures[i].Name);
    for i := 0 to AGlobalVars.Count - 1 do
      NamesList.Add(AGlobalVars[i]);
    // Add name refs (strings used via O_NAMEREF, e.g. string literals)
    for i := 0 to ANameRefs.Count - 1 do
      if NamesList.IndexOf(ANameRefs[i]) < 0 then
        NamesList.Add(ANameRefs[i]);

    // Pre-compute name offsets within the name list data section
    var NameDataOfs: Integer := 4; // skip the 4-byte size header
    for i := 0 to NamesList.Count - 1 do
    begin
      var NB := TEncoding.ASCII.GetBytes(NamesList[i] + #0);
      var NL := Length(NB);
      if (NL mod 2) <> 0 then Inc(NL);
      NameEntryOffsets.AddOrSetValue(NamesList[i], NameDataOfs + 2); // +2 for length word
      Inc(NameDataOfs, 2 + NL);
    end;

    // Pre-compute string offsets (same layout as name list)
    var StrDataOfs: Integer := 4;
    for i := 0 to AStringTable.Count - 1 do
    begin
      var SB := TEncoding.ASCII.GetBytes(AStringTable[i] + #0);
      var SL := Length(SB);
      if (SL mod 2) <> 0 then Inc(SL);
      StringOffsets.AddOrSetValue(AStringTable[i], StrDataOfs + 2);
      Inc(StrDataOfs, 2 + SL);
    end;

    Stream := TMemoryStream.Create;
    try
      // ================================================================
      // 1. STARTUP CODE (42 bytes)
      // ================================================================
      WriteOpToStream(Stream, O_CRITICAL_START); // $8002
      WriteIntToStream(Stream, 18);              // version
      WriteOpToStream(Stream, O_D_TO_A);         // $800D

      // Placeholder for init code offset (patched after name/string lists)
      StartAddrPos := Integer(Stream.Position);
      WriteIntToStream(Stream, 0);

      WriteOpToStream(Stream, O_JMP);            // $8004 — jump to init code

      // Exit handler at offset 18 (start returns here)
      WriteOpToStream(Stream, O_EXIT_PROG);      // $8010

      // Stack unwind handlers for various calling conventions
      WriteOpToStream(Stream, $801A); WriteOpToStream(Stream, $8020);
      WriteOpToStream(Stream, $801A); WriteOpToStream(Stream, $8021);
      WriteOpToStream(Stream, $801A); WriteOpToStream(Stream, $8022);
      WriteOpToStream(Stream, $801A); WriteOpToStream(Stream, $8023);
      WriteOpToStream(Stream, $8024);
      WriteOpToStream(Stream, $8025);
      WriteOpToStream(Stream, $8026);

      // ================================================================
      // 2. PROCEDURE TABLE
      // ================================================================
      WriteLongToStream(Stream, Cardinal(AProcedures.Count));
      SetLength(BodyOffsetPositions, AProcedures.Count);

      for i := 0 to AProcedures.Count - 1 do
      begin
        var Proc := AProcedures[i];
        // Name offset into name list data
        if NameEntryOffsets.TryGetValue(Proc.Name, j) then
          WriteLongToStream(Stream, Cardinal(j))
        else
          WriteLongToStream(Stream, 0);
        WriteLongToStream(Stream, 0); // type (no flags)
        WriteLongToStream(Stream, 0); // time (not timed)
        WriteLongToStream(Stream, 0); // expr offset (placeholder)
        BodyOffsetPositions[i] := Integer(Stream.Position);
        WriteLongToStream(Stream, 0); // body offset (placeholder)
        WriteLongToStream(Stream, Cardinal(Proc.NumArgs));
      end;

      // ================================================================
      // 3. NAME LIST
      // ================================================================
      WriteNameList(Stream, NamesList);

      // ================================================================
      // 4. STRING LIST
      // ================================================================
      WriteNameList(Stream, AStringTable);

      // ================================================================
      // Patch startup code's placeholder to point to init code
      // ================================================================
      var InitCodePos := Integer(Stream.Position);
      var SavedPos := Stream.Position;
      Stream.Seek(StartAddrPos + 2, soFromBeginning); // skip O_INTOP
      WriteLongToStream(Stream, Cardinal(InitCodePos));
      Stream.Seek(SavedPos, soFromBeginning);

      // ================================================================
      // 5. SCRIPT INIT CODE
      // ================================================================
      WriteOpToStream(Stream, $802C);   // script object init marker

      // Push 0 args for the start procedure call
      WriteIntToStream(Stream, 0);
      // O_CRITICAL_DONE ($8003) + start body offset — transfers to start procedure
      WriteOpToStream(Stream, $8003);
      BodyPatchPos := Integer(Stream.Position);
      WriteIntToStream(Stream, 0);

      // ================================================================
      // 6. PROCEDURE BODIES
      // ================================================================
      StartProcIndex := -1;
      for i := 0 to AProcedures.Count - 1 do
        if SameText(AProcedures[i].Name, 'start') then
        begin
          StartProcIndex := i;
          Break;
        end;

      var StartBodyOffset: Integer := 0;

      for i := 0 to AProcedures.Count - 1 do
      begin
        var Proc := AProcedures[i];

        // Patch procedure table body offset to current position
        var BodyPos := Integer(Stream.Position);
        var PatchPos := BodyOffsetPositions[i];
        SavedPos := Stream.Position;
        Stream.Seek(PatchPos, soFromBeginning);
        WriteLongToStream(Stream, Cardinal(BodyPos));
        Stream.Seek(SavedPos, soFromBeginning);

        if i = StartProcIndex then
          StartBodyOffset := BodyPos;

        // Write all instructions for this procedure
        // (bytecode generator already emits O_PUSH_BASE prologue and
        //  O_POP_TO_BASE + O_POP_BASE + O_POP_RETURN epilogue)
        for var Instr in Proc.Instructions do
        begin
          if Instr.Opcode = O_INTOP then
            WriteIntToStream(Stream, Instr.Value)
          else if Instr.Opcode = O_STRINGOP then
          begin
            WriteOpToStream(Stream, O_STRINGOP);
            if StringOffsets.TryGetValue(Instr.Str, j) then
              WriteLongToStream(Stream, Cardinal(j))
            else
              WriteLongToStream(Stream, 0);
          end
          else if Instr.Opcode = O_NAMEREF then
          begin
            WriteOpToStream(Stream, O_NAMEREF);
            if NameEntryOffsets.TryGetValue(Instr.Str, j) then
              WriteLongToStream(Stream, Cardinal(j))
            else
              WriteLongToStream(Stream, 0);
          end
          else
            WriteOpToStream(Stream, Instr.Opcode);
        end;
      end;

      // Patch the init code's O_JMP target to point to start procedure body
      if (StartProcIndex >= 0) and (StartBodyOffset > 0) then
      begin
        SavedPos := Stream.Position;
        Stream.Seek(BodyPatchPos + 2, soFromBeginning); // skip O_INTOP
        WriteLongToStream(Stream, Cardinal(StartBodyOffset));
        Stream.Seek(SavedPos, soFromBeginning);
      end;

      Stream.SaveToFile(FileName);
      Result := True;
    finally
      Stream.Free;
    end;
  finally
    StringOffsets.Free;
    NameEntryOffsets.Free;
    NamesList.Free;
  end;
end;

end.
