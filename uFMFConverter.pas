unit uFMFConverter;

interface

type
  TTemplateType = (dtBasic, dtPushable, dtTerminal, dtFloaters, dtTimeEvent);

function FMFToSSL(const FMFSource, ScriptName: string; TemplateType: TTemplateType = dtBasic): string;
function FMFToMSG(const FMFSource: string): string;

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, System.Generics.Collections;

type
  TFMFNode = record
    NodeID: string;
    NPCText: string;
    NPCFemaleText: string;
    Notes: string;
    IsWTG: Boolean;
  end;

  TFMFOption = record
    IntReq: Integer;
    Reaction: string;
    PlayerText: string;
    LinkTo: string;
    Notes: string;
  end;

  TFMFNodeData = class
    Node: TFMFNode;
    Options: TList<TFMFOption>;
    constructor Create;
    destructor Destroy; override;
  end;

  TMsgEntry = record
    MsgNum: Integer;
    Text: string;
  end;

  TFloatNode = record
    Name: string;
    Notes: string;
    Messages: TArray<string>;
  end;

  TTimeEvent = record
    ParamName: string;
    Enum: Integer;
    IsRandom: Boolean;
    IntervalMin: Integer;
    IntervalMax: Integer;
    CodeLines: TArray<string>;
  end;

constructor TFMFNodeData.Create;
begin
  inherited;
  Options := TList<TFMFOption>.Create;
end;

destructor TFMFNodeData.Destroy;
begin
  Options.Free;
  inherited;
end;

// Shared parsing state
type
  TParseState = record
    NPCName, Location, Description: string;
    Nodes: TObjectList<TFMFNodeData>;
    FirstNodeID: string;
    MsgEntries: TList<TMsgEntry>;
    NextMsgNum: Integer;
    FloatNodes: TList<TFloatNode>;
    TimeEvents: TList<TTimeEvent>;
    DefaultEvent: Integer;
  end;

function ExtractQuoted(const S: string): string;
var
  StartPos, EndPos: Integer;
begin
  Result := '';
  StartPos := Pos('"', S);
  if StartPos = 0 then Exit;
  EndPos := Pos('"', S, StartPos + 1);
  if EndPos = 0 then Exit;
  Result := Copy(S, StartPos + 1, EndPos - StartPos - 1);
end;

function StripQuotes(const S: string): string;
begin
  Result := Trim(S);
  if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

function EscapeSSLStr(const S: string): string;
begin
  Result := StringReplace(S, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
end;

function NodeIDToProcName(const NodeID: string): string;
var
  N: Integer;
begin
  if NodeID = '' then
    Result := 'NodeGen001'
  else if TryStrToInt(NodeID, N) then
  begin
    if N < 0 then
      Result := 'NodeN' + Format('%.2d', [Abs(N)])
    else
      Result := 'Node' + Format('%.3d', [N]);
  end
  else
    Result := 'Node' + NodeID;
end;

function NormalizeLinkTo(const LinkTo: string): string;
begin
  if LinkTo = 'done' then
    Result := 'Node999'
  else if LinkTo = 'combat' then
    Result := 'Node998'
  else
    Result := NodeIDToProcName(LinkTo);
end;

function ReactionToValue(const Reaction: string): Integer;
var
  Upper: string;
begin
  Upper := UpperCase(Reaction);
  if Upper = 'REACTION_NEUTRAL' then Result := 50
  else if Upper = 'REACTION_GOOD' then Result := 49
  else if Upper = 'REACTION_BAD' then Result := 51
  else if Upper = 'REACTION_HOSTILE' then Result := 50
  else Result := 50;
end;

// Assign a message number for a text string (deduplicates)
function AssignMsgNum(var State: TParseState; const Text: string): Integer;
var
  I: Integer;
begin
  if Text = '' then
    Exit(0);
  // Check if this text already has a number
  for I := 0 to State.MsgEntries.Count - 1 do
  begin
    if State.MsgEntries[I].Text = Text then
      Exit(State.MsgEntries[I].MsgNum);
  end;
  // Assign new number
  Result := State.NextMsgNum;
  Inc(State.NextMsgNum);
  var Entry: TMsgEntry;
  Entry.MsgNum := Result;
  Entry.Text := Text;
  State.MsgEntries.Add(Entry);
end;

// Shared FMF parser
procedure ParseFMF(const FMFSource: string; var State: TParseState);
var
  Lines: TStringList;
  I, LineNo: Integer;
  Line, Trimmed, S, ValuePart: string;
  CurrentNode: TFMFNodeData;
  Opt: TFMFOption;
  P: Integer;

  procedure ParseHeaderField(const Line: string; var Dest: string; const Key: string);
  begin
    ValuePart := Copy(Line, Length(Key) + 1, MaxInt);
    Dest := StripQuotes(Trim(ValuePart));
  end;

  // Parse comma-separated quoted strings within braces
  procedure ParseStringList(var Arr: TArray<string>);
  var
    Text: string;
  begin
    while LineNo < Lines.Count do
    begin
      Line := Lines[LineNo];
      Trimmed := Trim(Line);
      if Trimmed = '}' then
        Break;
      if Trimmed.EndsWith(',') then
        SetLength(Trimmed, Length(Trimmed) - 1);
      Text := StripQuotes(Trim(Trimmed));
      if Text <> '' then
      begin
        SetLength(Arr, Length(Arr) + 1);
        Arr[High(Arr)] := Text;
        AssignMsgNum(State, Text);
      end;
      Inc(LineNo);
    end;
  end;

begin
  State.NPCName := '';
  State.Location := '';
  State.Description := '';
  State.FirstNodeID := '';
  State.DefaultEvent := -1;

  Lines := TStringList.Create;
  try
    Lines.Text := FMFSource;

    CurrentNode := nil;
    LineNo := 0;
    while LineNo < Lines.Count do
    begin
      Line := Lines[LineNo];
      Trimmed := Trim(Line);

      if (Trimmed = '') or Trimmed.StartsWith('/*') or Trimmed.StartsWith('//') then
      begin
        Inc(LineNo);
        Continue;
      end;

      // === Floatnode parsing ===
      if Trimmed.StartsWith('Floatnode ') then
      begin
        var FlNode: TFloatNode;
        FlNode.Name := ExtractQuoted(Trimmed);
        FlNode.Notes := '';
        Inc(LineNo);
        while LineNo < Lines.Count do
        begin
          Line := Lines[LineNo];
          Trimmed := Trim(Line);
          if Trimmed = '{' then
            Break
          else if Trimmed.StartsWith('notes ') then
            FlNode.Notes := StripQuotes(Copy(Trimmed, 7, MaxInt));
          Inc(LineNo);
        end;
        Inc(LineNo); // Skip '{'
        ParseStringList(FlNode.Messages);
        Inc(LineNo); // Skip '}'
        State.FloatNodes.Add(FlNode);
        Continue;
      end;

      // === Time event parsing ===
      if Trimmed.StartsWith('TimeEvent ') or Trimmed.StartsWith('EventRepeat ') then
      begin
        var Ev: TTimeEvent;
        Ev.IsRandom := False;
        Ev.IntervalMin := 1;
        Ev.IntervalMax := 5;
        Ev.Enum := 0;
        Ev.ParamName := '';
        // Parse comma-separated key=value pairs on this line
        S := Trimmed;
        P := Pos('fixed_param_name=', S);
        if P > 0 then
          Ev.ParamName := ExtractQuoted(Copy(S, P + 17, MaxInt));
        P := Pos('enum=', S);
        if P > 0 then
        begin
          ValuePart := Trim(Copy(S, P + 5, MaxInt));
          if ValuePart.EndsWith(',') then
            SetLength(ValuePart, Length(ValuePart) - 1);
          Ev.Enum := StrToIntDef(ValuePart, 0);
        end;
        // Read subsequent property lines and code block
        Inc(LineNo);
        while LineNo < Lines.Count do
        begin
          Line := Lines[LineNo];
          Trimmed := Trim(Line);
          if Trimmed.StartsWith('code =') then
          begin
            // Find opening brace (may be on same line e.g. 'code = {')
            if not Trimmed.EndsWith('{') then
            begin
              while (LineNo < Lines.Count) and (Trim(Lines[LineNo]) <> '{') do
                Inc(LineNo);
            end;
            Inc(LineNo); // Skip past the brace line
            while LineNo < Lines.Count do
            begin
              Line := Lines[LineNo];
              Trimmed := Trim(Line);
              if Trimmed = '}' then
                Break;
              var CodeLine: string := Trim(Trimmed);
              // Strip trailing comma first (FMF format: "text",)
              if CodeLine.EndsWith(',') then
                SetLength(CodeLine, Length(CodeLine) - 1);
              // Then strip surrounding quotes
              CodeLine := StripQuotes(Trim(CodeLine));
              if CodeLine <> '' then
              begin
                SetLength(Ev.CodeLines, Length(Ev.CodeLines) + 1);
                Ev.CodeLines[High(Ev.CodeLines)] := CodeLine;
              end;
              Inc(LineNo);
            end;
            Inc(LineNo); // Skip '}'
            Break;
          end
          else if Trimmed.StartsWith('IsRandomInterval') then
            Ev.IsRandom := Pos('true', LowerCase(Trimmed)) > 0
          else if Trimmed.StartsWith('IntervalMin=') then
            Ev.IntervalMin := StrToIntDef(Trim(Copy(Trimmed, 13, MaxInt)), 1)
          else if Trimmed.StartsWith('IntervalMax=') then
            Ev.IntervalMax := StrToIntDef(Trim(Copy(Trimmed, 13, MaxInt)), 5);
          Inc(LineNo);
        end;
        State.TimeEvents.Add(Ev);
        Continue;
      end;

      // === Default_Event ===
      if Trimmed.StartsWith('Default_Event ') then
      begin
        ValuePart := Trim(Copy(Trimmed, 15, MaxInt));
        State.DefaultEvent := StrToIntDef(ValuePart, -1);
        Inc(LineNo);
        Continue;
      end;

      // === Header fields ===
      if Trimmed.StartsWith('NPCName ') then
        ParseHeaderField(Trimmed, State.NPCName, 'NPCName ')
      else if Trimmed.StartsWith('Location ') then
        ParseHeaderField(Trimmed, State.Location, 'Location ')
      else if Trimmed.StartsWith('Description ') then
        ParseHeaderField(Trimmed, State.Description, 'Description ')
      else if Trimmed.StartsWith('Unknown_Desc ') then
        { ignored }
      else if Trimmed.StartsWith('Known_Desc ') then
        { ignored }
      else if Trimmed.StartsWith('Detailed_Desc ') then
        { ignored }
      else if Trimmed.StartsWith('Node ') then
      begin
        if CurrentNode <> nil then
          State.Nodes.Add(CurrentNode);

        CurrentNode := TFMFNodeData.Create;
        CurrentNode.Node.NodeID := ExtractQuoted(Trimmed);
        Inc(LineNo);
        while LineNo < Lines.Count do
        begin
          Line := Lines[LineNo];
          Trimmed := Trim(Line);
          if Trimmed = '{' then
            Break
          else if Trimmed.StartsWith('notes ') then
            CurrentNode.Node.Notes := StripQuotes(Copy(Trimmed, 7, MaxInt))
          else if Trimmed.StartsWith('is_wtg ') then
            CurrentNode.Node.IsWTG := Pos('true', LowerCase(Trimmed)) > 0;
          Inc(LineNo);
        end;
        Inc(LineNo); // Skip '{'
        while LineNo < Lines.Count do
        begin
          Line := Lines[LineNo];
          Trimmed := Trim(Line);
          if Trimmed = '}' then
            Break
          else if Trimmed.StartsWith('NPCText ') then
          begin
            S := Copy(Trimmed, 9, MaxInt);
            CurrentNode.Node.NPCText := StripQuotes(Trim(S));
            AssignMsgNum(State, CurrentNode.Node.NPCText);
          end
          else if Trimmed.StartsWith('NPCFemaleText ') then
          begin
            S := Copy(Trimmed, 15, MaxInt);
            CurrentNode.Node.NPCFemaleText := StripQuotes(Trim(S));
            AssignMsgNum(State, CurrentNode.Node.NPCFemaleText);
          end
          else if Trimmed.StartsWith('options ') then
          begin
            while (LineNo < Lines.Count) and (Trim(Lines[LineNo]) <> '{') do
              Inc(LineNo);
            Inc(LineNo);
            while LineNo < Lines.Count do
            begin
              Line := Lines[LineNo];
              Trimmed := Trim(Line);
              if Trimmed = '}' then
                Break;
              if Trimmed = '' then
              begin
                Inc(LineNo);
                Continue;
              end;
              if Trimmed.StartsWith('conditions ') then
              begin
                while (LineNo < Lines.Count) and (Trim(Lines[LineNo]) <> '}') do
                  Inc(LineNo);
                Inc(LineNo);
                Continue;
              end;
              if Trimmed <> '' then
              begin
                Opt := Default(TFMFOption);
                S := Trimmed;
                P := Pos('int=', S);
                if P > 0 then
                begin
                  ValuePart := Copy(S, P + 4, MaxInt);
                  Opt.IntReq := StrToIntDef(Trim(Copy(ValuePart, 1, Pos(' ', ValuePart + ' ') - 1)), 4);
                end;
                P := Pos('Reaction=', S);
                if P > 0 then
                begin
                  ValuePart := Copy(S, P + 9, MaxInt);
                  Opt.Reaction := Trim(Copy(ValuePart, 1, Pos(' ', ValuePart + ' ') - 1));
                end;
                P := Pos('playertext ', S);
                if P > 0 then
                begin
                  Opt.PlayerText := ExtractQuoted(Copy(S, P + 11, MaxInt));
                  AssignMsgNum(State, Opt.PlayerText);
                end;
                P := Pos('linkto ', S);
                if P > 0 then
                begin
                  Opt.LinkTo := ExtractQuoted(Copy(S, P + 7, MaxInt));
                end;
                CurrentNode.Options.Add(Opt);
              end;
              Inc(LineNo);
            end;
          end;
          Inc(LineNo);
        end;
        if State.FirstNodeID = '' then
          State.FirstNodeID := CurrentNode.Node.NodeID;
      end;
      Inc(LineNo);
    end;
    if CurrentNode <> nil then
      State.Nodes.Add(CurrentNode);
  finally
    Lines.Free;
  end;
end;

// Convert the FMF timed event code block lines to sslc-compatible SSL
function TranslateTimeEventCode(const Line: string): string;
begin
  Result := Line;
  // Strip trailing semicolons if any (will be added by caller)
  if Result.EndsWith(';') then
    SetLength(Result, Length(Result) - 1);
  // Replace 'call X' with 'X()' since parser doesn't handle 'call' keyword
  if Result.StartsWith('call ') then
    Result := Copy(Result, 6, MaxInt) + '()'
  // Replace known FMF designer functions with sslc equivalents
  else if Result.StartsWith('flush_add_timer_event_sec(') then
  begin
    // flush_add_timer_event_sec(obj, time, event_id) -> add_timer_event(obj, time, event_id)
    Result := StringReplace(Result, 'flush_add_timer_event_sec(', 'add_timer_event(', []);
  end;
end;

function FMFToMSG(const FMFSource: string): string;
var
  State: TParseState;
  I: Integer;
  SB: TStringBuilder;
begin
  State.Nodes := TObjectList<TFMFNodeData>.Create(True);
  State.MsgEntries := TList<TMsgEntry>.Create;
  State.NextMsgNum := 100;
  State.FloatNodes := TList<TFloatNode>.Create;
  State.TimeEvents := TList<TTimeEvent>.Create;
  try
    ParseFMF(FMFSource, State);

    SB := TStringBuilder.Create;
    try
      for I := 0 to State.MsgEntries.Count - 1 do
      begin
        SB.Append('{' + IntToStr(State.MsgEntries[I].MsgNum) + '}{}{');
        SB.Append(State.MsgEntries[I].Text);
        SB.AppendLine('}');
      end;
      Result := SB.ToString;
    finally
      SB.Free;
    end;
  finally
    State.MsgEntries.Free;
    State.FloatNodes.Free;
    State.TimeEvents.Free;
    State.Nodes.Free;
  end;
end;

function FMFToSSL(const FMFSource, ScriptName: string; TemplateType: TTemplateType = dtBasic): string;
var
  State: TParseState;
  I, LineNo: Integer;
  NodeData: TFMFNodeData;
  Opt: TFMFOption;
  UpperScriptName: string;
  SB: TStringBuilder;
  DescEscaped: string;
  MsgNum: Integer;
  Ev: TTimeEvent;
  FlNode: TFloatNode;
  J, MsgStart, MsgEnd: Integer;
  CodeLine: string;
begin
  State.Nodes := TObjectList<TFMFNodeData>.Create(True);
  State.MsgEntries := TList<TMsgEntry>.Create;
  State.NextMsgNum := 100;
  State.FloatNodes := TList<TFloatNode>.Create;
  State.TimeEvents := TList<TTimeEvent>.Create;
  SB := TStringBuilder.Create;
  try
    ParseFMF(FMFSource, State);

    UpperScriptName := UpperCase(ScriptName);
    DescEscaped := EscapeSSLStr(State.Description);

    // === Header ===
    SB.AppendLine('/*');
    SB.AppendLine('        Name:           ' + State.NPCName);
    SB.AppendLine('        Location:       ' + State.Location);
    SB.AppendLine('        Description:    ' + State.Description);
    SB.AppendLine('');
    SB.AppendLine('           Created: ' + FormatDateTime('mmmm d, yyyy', Now));
    SB.AppendLine('*/');
    SB.AppendLine('');
    SB.AppendLine('/* Include Files */');
    SB.AppendLine('');
    SB.AppendLine('#define NPC_REACTION_VAR        7');
    SB.AppendLine('');
    SB.AppendLine('#include "..\\headers\\define.h"');
    SB.AppendLine('');
    SB.AppendLine('#define NAME                    SCRIPT_' + UpperScriptName);
    SB.AppendLine('');
    SB.AppendLine('#define TOWN_REP_VAR            (0)');
    SB.AppendLine('');
    SB.AppendLine('#include "..\\headers\\command.h"');
    SB.AppendLine('#include "..\\headers\\ModReact.h"');
    SB.AppendLine('');

    // === Procedure declarations ===
    SB.AppendLine('/* Standard Script Procedures */');
    SB.AppendLine('');
    SB.AppendLine('procedure start;');
    SB.AppendLine('procedure critter_p_proc;');
    if TemplateType = dtTerminal then
      SB.AppendLine('procedure use_p_proc;')
    else
      SB.AppendLine('procedure pickup_p_proc;');
    SB.AppendLine('procedure talk_p_proc;');
    SB.AppendLine('procedure destroy_p_proc;');
    SB.AppendLine('procedure look_at_p_proc;');
    SB.AppendLine('procedure description_p_proc;');
    SB.AppendLine('procedure use_skill_on_p_proc;');
    SB.AppendLine('procedure damage_p_proc;');
    SB.AppendLine('procedure map_enter_p_proc;');
    SB.AppendLine('procedure timed_event_p_proc;');
    if TemplateType = dtPushable then
      SB.AppendLine('procedure push_p_proc;');
    SB.AppendLine('');

    SB.AppendLine('/* Script Specific Procedure Calls */');
    SB.AppendLine('procedure Node998;');
    SB.AppendLine('procedure Node999;');
    SB.AppendLine('');

    for I := 0 to State.Nodes.Count - 1 do
    begin
      NodeData := State.Nodes[I];
      if NodeData.Node.NodeID <> '' then
        SB.AppendLine('procedure ' + NodeIDToProcName(NodeData.Node.NodeID) + ';');
    end;

    // Float node procedure declarations (timed event only)
    if TemplateType = dtTimeEvent then
      for I := 0 to State.FloatNodes.Count - 1 do
        SB.AppendLine('procedure ' + State.FloatNodes[I].Name + ';');

    SB.AppendLine('');

    SB.AppendLine('//~~~~~~~~~~~~~~~~ DESIGNER TOOL STARTS HERE');
    SB.AppendLine('//~~~~~~~~~~~~~~~~ DESIGN TOOL ENDS HERE');
    SB.AppendLine('');

    // === Variables ===
    SB.AppendLine('/* Local Variables which are saved. */');
    SB.AppendLine('#define LVAR_Herebefore                 (4)');
    SB.AppendLine('#define LVAR_Hostile                    (5)');
    SB.AppendLine('#define LVAR_Personal_Enemy             (6)');
    SB.AppendLine('#define LVAR_Caught_Thief               (7)');

    // Timed event tracking variable
    if TemplateType = dtTimeEvent then
      SB.AppendLine('#define LVAR_TimedEvent                  (10)');

    if TemplateType = dtFloaters then
    begin
      SB.AppendLine('#define LVAR_floatnode                  (8)');
      SB.AppendLine('#define LVAR_dofloat                    (9)');
    end;
    SB.AppendLine('');

    // Float message macros
    if (TemplateType = dtTimeEvent) and (State.FloatNodes.Count > 0) then
    begin
      // Calculate message ranges for float nodes
      MsgStart := 100;
      for I := 0 to State.FloatNodes.Count - 1 do
      begin
        FlNode := State.FloatNodes[I];
        if Length(FlNode.Messages) = 0 then Continue;
        MsgEnd := MsgStart + Length(FlNode.Messages) - 1;
        SB.AppendLine('#define FLMSG_' + UpperCase(FlNode.Name) + '_First       (' + IntToStr(MsgStart) + ')');
        for J := 0 to Length(FlNode.Messages) - 1 do
          SB.AppendLine('#define FLMSG_' + UpperCase(FlNode.Name) + '_' + Format('%.2d', [J + 1]) +
            '       (' + IntToStr(MsgStart + J) + ')');
        SB.AppendLine('#define FLMSG_' + UpperCase(FlNode.Name) + '_Last        (' + IntToStr(MsgEnd) + ')');
        MsgStart := MsgEnd + 1;
        SB.AppendLine('');
      end;
    end;

    // Timed event enum macros
    if (TemplateType = dtTimeEvent) and (State.TimeEvents.Count > 0) then
    begin
      SB.AppendLine('/* Timed event enums */');
      for I := 0 to State.TimeEvents.Count - 1 do
      begin
        Ev := State.TimeEvents[I];
        if Ev.ParamName <> '' then
          SB.AppendLine('#define TE_' + UpperCase(Ev.ParamName) + '               (' + IntToStr(Ev.Enum) + ')');
      end;
      SB.AppendLine('');
    end;

    SB.AppendLine('var Only_Once = 0;');
    SB.AppendLine('');

    // === Standard procedure bodies ===
    SB.AppendLine('procedure start begin');
    if TemplateType = dtTimeEvent then
    begin
      // Initialize timed events
      SB.AppendLine('   if (local_var(LVAR_TimedEvent) == 0) then begin');
      SB.AppendLine('      set_local_var(LVAR_TimedEvent, 1);');
      if State.TimeEvents.Count > 0 then
      begin
        // Use DefaultEvent to pick the initial event, or fall back to first
        var InitIdx: Integer := State.DefaultEvent;
        if (InitIdx < 0) or (InitIdx >= State.TimeEvents.Count) then
          InitIdx := 0;
        Ev := State.TimeEvents[InitIdx];
        SB.AppendLine('      add_timer_event(self_obj(), game_time_in_seconds() + random(' +
          IntToStr(Ev.IntervalMin) + ', ' + IntToStr(Ev.IntervalMax) + '), ' + IntToStr(Ev.Enum) + ');');
      end;
      SB.AppendLine('   end');
    end;
    SB.AppendLine('end');
    SB.AppendLine('');

    SB.AppendLine('procedure map_enter_p_proc begin');
    SB.AppendLine('   Only_Once = 0;');
    SB.AppendLine('end');
    SB.AppendLine('');

    SB.AppendLine('procedure critter_p_proc begin');
    SB.AppendLine('   if ((local_var(LVAR_Hostile) != 0) and (obj_can_see_obj(self_obj(), dude_obj()))) then begin');
    SB.AppendLine('       set_local_var(LVAR_Hostile, 1);');
    SB.AppendLine('       self_attack_dude();');
    SB.AppendLine('   end');
    SB.AppendLine('end');
    SB.AppendLine('');

    SB.AppendLine('procedure damage_p_proc begin');
    SB.AppendLine('   if (obj_in_party(source_obj())) then begin');
    SB.AppendLine('       set_local_var(LVAR_Personal_Enemy, 1);');
    SB.AppendLine('   end');
    SB.AppendLine('end');
    SB.AppendLine('');

    // pickup_p_proc or use_p_proc
    if TemplateType = dtTerminal then
    begin
      SB.AppendLine('procedure use_p_proc begin');
      SB.AppendLine('   script_overrides();');
      SB.AppendLine('   start_gdialog(NAME, self_obj(), 4, -1, -1);');
      SB.AppendLine('   gsay_start();');
      if State.FirstNodeID <> '' then
        SB.AppendLine('      ' + NodeIDToProcName(State.FirstNodeID) + '();')
      else
        SB.AppendLine('      Node999();');
      SB.AppendLine('   gsay_end();');
      SB.AppendLine('   end_dialogue();');
      SB.AppendLine('end');
    end
    else
    begin
      SB.AppendLine('procedure pickup_p_proc begin');
      SB.AppendLine('   if (source_obj() == dude_obj()) then begin');
      SB.AppendLine('       set_local_var(LVAR_Hostile, 2);');
      SB.AppendLine('   end');
      SB.AppendLine('end');
    end;
    SB.AppendLine('');

    // talk_p_proc
    SB.AppendLine('procedure talk_p_proc begin');
    if TemplateType = dtFloaters then
    begin
      SB.AppendLine('   if (local_var(LVAR_Hostile) == 0) then begin');
      SB.AppendLine('      start_gdialog(NAME, self_obj(), 4, -1, -1);');
      SB.AppendLine('      gsay_start();');
      if State.FirstNodeID <> '' then
        SB.AppendLine('         ' + NodeIDToProcName(State.FirstNodeID) + '();')
      else
        SB.AppendLine('         Node999();');
      SB.AppendLine('      gsay_end();');
      SB.AppendLine('      end_dialogue();');
      SB.AppendLine('      if (local_var(LVAR_dofloat) != 0) then begin');
      SB.AppendLine('         set_local_var(LVAR_dofloat, 0);');
      SB.AppendLine('         // TODO: floatnode dispatch via local_var(LVAR_floatnode)');
      SB.AppendLine('         debug_msg("Floater triggered");');
      SB.AppendLine('      end');
      SB.AppendLine('   end else begin');
      SB.AppendLine('      self_attack_dude();');
      SB.AppendLine('   end');
    end
    else
    begin
      SB.AppendLine('   start_gdialog(NAME, self_obj(), 4, -1, -1);');
      SB.AppendLine('   gsay_start();');
      if State.FirstNodeID <> '' then
        SB.AppendLine('      ' + NodeIDToProcName(State.FirstNodeID) + '();')
      else
        SB.AppendLine('      Node999();');
      SB.AppendLine('   gsay_end();');
      SB.AppendLine('   end_dialogue();');
    end;
    SB.AppendLine('end');
    SB.AppendLine('');

    // timed_event_p_proc
    SB.AppendLine('procedure timed_event_p_proc begin');
    if TemplateType = dtTimeEvent then
    begin
      if State.TimeEvents.Count > 0 then
      begin
        for I := 0 to State.TimeEvents.Count - 1 do
        begin
          Ev := State.TimeEvents[I];
          if I = 0 then
            SB.AppendLine('   if (fixed_param() == ' + IntToStr(Ev.Enum) + ') then begin')
          else
            SB.AppendLine('   end else if (fixed_param() == ' + IntToStr(Ev.Enum) + ') then begin');

          // Emit code block lines
          for J := 0 to Length(Ev.CodeLines) - 1 do
          begin
            CodeLine := TranslateTimeEventCode(Ev.CodeLines[J]);
            SB.AppendLine('      ' + CodeLine + ';');
          end;

          // Re-schedule the timer
          if Ev.IsRandom then
            SB.AppendLine('      add_timer_event(self_obj(), game_time_in_seconds() + random(' +
              IntToStr(Ev.IntervalMin) + ', ' + IntToStr(Ev.IntervalMax) + '), ' + IntToStr(Ev.Enum) + ');')
          else
            SB.AppendLine('      add_timer_event(self_obj(), game_time_in_seconds() + ' +
              IntToStr(Ev.IntervalMin) + ', ' + IntToStr(Ev.Enum) + ');');
        end;
        SB.AppendLine('   end');
      end;
    end;
    SB.AppendLine('end');
    SB.AppendLine('');

    SB.AppendLine('procedure destroy_p_proc begin');
    SB.AppendLine('   inc_good_critter();');
    SB.AppendLine('end');
    SB.AppendLine('');

    // push_p_proc for pushable template
    if TemplateType = dtPushable then
    begin
      SB.AppendLine('procedure push_p_proc begin');
      SB.AppendLine('end');
      SB.AppendLine('');
    end;

    // look_at_p_proc
    SB.AppendLine('procedure look_at_p_proc begin');
    SB.AppendLine('   script_overrides();');
    SB.AppendLine('   if (local_var(LVAR_Herebefore) == 0) then');
    SB.AppendLine('      display_msg("' + EscapeSSLStr(State.NPCName) + '");');
    SB.AppendLine('   else');
    SB.AppendLine('      display_msg("' + EscapeSSLStr(State.NPCName) + ' (familiar)");');
    SB.AppendLine('end');
    SB.AppendLine('');

    // description_p_proc
    SB.AppendLine('procedure description_p_proc begin');
    SB.AppendLine('   script_overrides();');
    SB.AppendLine('   display_msg("' + DescEscaped + '");');
    SB.AppendLine('end');
    SB.AppendLine('');

    SB.AppendLine('procedure use_skill_on_p_proc begin');
    SB.AppendLine('end');
    SB.AppendLine('');

    // Node998 (Combat)
    SB.AppendLine('procedure Node998 begin');
    SB.AppendLine('   set_local_var(LVAR_Hostile, 2);');
    SB.AppendLine('end');
    SB.AppendLine('');

    // Node999 (End Dialogue)
    SB.AppendLine('procedure Node999 begin');
    SB.AppendLine('   debug_msg("LVAR_Herebefore == " + local_var(LVAR_Herebefore));');
    SB.AppendLine('   if (local_var(LVAR_Herebefore) == 0) then begin');
    SB.AppendLine('      set_local_var(LVAR_Herebefore, 1);');
    SB.AppendLine('   end');
    SB.AppendLine('end');
    SB.AppendLine('');

    // === Float node procedures (timed event only) ===
    if TemplateType = dtTimeEvent then
    begin
      for I := 0 to State.FloatNodes.Count - 1 do
      begin
        FlNode := State.FloatNodes[I];
        if Length(FlNode.Messages) = 0 then
          Continue;

        SB.AppendLine('// Float node: ' + FlNode.Name);
        if FlNode.Notes <> '' then
          SB.AppendLine('// ' + StringReplace(FlNode.Notes, '\', '\\', [rfReplaceAll]));

        SB.AppendLine('procedure ' + FlNode.Name + ' begin');

        // Use floater_rand to pick and display a random message
        var Prefix: string := 'FLMSG_' + UpperCase(FlNode.Name);
        SB.AppendLine('   floater_rand(' + Prefix + '_First, ' + Prefix + '_Last);');
        SB.AppendLine('end');
        SB.AppendLine('');
      end;
    end;

    // === Individual node procedures ===
    for I := 0 to State.Nodes.Count - 1 do
    begin
      NodeData := State.Nodes[I];
      if NodeData.Node.NodeID = '' then
        Continue;

      SB.AppendLine('procedure ' + NodeIDToProcName(NodeData.Node.NodeID) + ' begin');

      // Designer notes as comment
      if NodeData.Node.Notes <> '' then
        SB.AppendLine('   // Designer notes: ' + StringReplace(NodeData.Node.Notes, '\', '\\', [rfReplaceAll]));

      // NPC Text
      if (NodeData.Node.NPCFemaleText <> '') and (NodeData.Node.NPCText <> '') then
      begin
        SB.AppendLine('   if (dude_is_female()) then begin');
        SB.AppendLine('      gsay_reply(NAME, "' + EscapeSSLStr(NodeData.Node.NPCFemaleText) + '");');
        SB.AppendLine('   end else begin');
        SB.AppendLine('      gsay_reply(NAME, "' + EscapeSSLStr(NodeData.Node.NPCText) + '");');
        SB.AppendLine('   end');
      end
      else if NodeData.Node.NPCText <> '' then
      begin
        SB.AppendLine('   gsay_reply(NAME, "' + EscapeSSLStr(NodeData.Node.NPCText) + '");');
      end;

      // Options
      for LineNo := 0 to NodeData.Options.Count - 1 do
      begin
        Opt := NodeData.Options[LineNo];
        if Opt.Notes <> '' then
          SB.AppendLine('   // Option notes: ' + StringReplace(Opt.Notes, '\', '\\', [rfReplaceAll]));
        SB.AppendLine('   giq_option(' + IntToStr(Opt.IntReq) + ', NAME, "' +
          EscapeSSLStr(Opt.PlayerText) + '", ' +
          NormalizeLinkTo(Opt.LinkTo) + ', ' + IntToStr(ReactionToValue(Opt.Reaction)) + ');');
      end;

      SB.AppendLine('end');
      SB.AppendLine('');
    end;

    Result := SB.ToString;
  finally
    SB.Free;
    State.MsgEntries.Free;
    State.FloatNodes.Free;
    State.TimeEvents.Free;
    State.Nodes.Free;
  end;
end;

end.
