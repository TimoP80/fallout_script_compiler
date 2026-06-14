unit uBytecode;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAST, uLexer, uBuiltins;

type

  // ---------------------------------------------------------------------------
  // Bytecode instruction record
  // ---------------------------------------------------------------------------
  TBytecodeInstruction = record
    Opcode: Word;
    Value: LongInt;
    Str: string;
  end;

  // ---------------------------------------------------------------------------
  // Per-procedure bytecode container
  // ---------------------------------------------------------------------------
  TProcedureBytecode = class
  public
    Name: string;
    Instructions: TList<TBytecodeInstruction>;
    NumArgs: Integer;
    constructor Create(const AName: string);
    destructor Destroy; override;
    procedure AddOp(Opcode: Word);
    procedure AddInt(Value: LongInt);
    procedure AddString(const Value: string);
    procedure AddNameRef(const Value: string);
  end;

  // ---------------------------------------------------------------------------
  // Top-level bytecode generator
  // ---------------------------------------------------------------------------
  TBytecodeGenerator = class
  private
    FProcedures: TObjectList<TProcedureBytecode>;
    FCurrentProc: TProcedureBytecode;
    FStringTable: TList<string>;
    FGlobalVars: TList<string>;
    FBuiltins: TBuiltinDatabase;
    FScriptName: string;
    FReachable: TDictionary<string, Boolean>;
    FCurrentProcLocals: TList<string>;  // local var names of current procedure
    FNameRefs: TList<string>;          // strings used via O_NAMEREF (go in name list, matching sfall)
    function  ComputeReachable(AST: TASTScript): TDictionary<string, Boolean>;
    procedure GenerateStatement(Stmt: TASTStatement);
    procedure GenerateExpression(Expr: TASTExpression);
    procedure GenerateSfallBuiltinCall(const Name: string; Args: TList<TASTExpression>; SfallOpcode: Word);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Generate(AST: TASTScript; const AScriptName: string);
    property Procedures: TObjectList<TProcedureBytecode> read FProcedures;
    property StringTable: TList<string> read FStringTable;
    property GlobalVars: TList<string> read FGlobalVars;
    property NameRefs: TList<string> read FNameRefs;
    property Builtins: TBuiltinDatabase read FBuiltins;
  end;

implementation

// ============================================================
// TProcedureBytecode
// ============================================================

constructor TProcedureBytecode.Create(const AName: string);
begin
  inherited Create;
  Name := AName;
  Instructions := TList<TBytecodeInstruction>.Create;
  NumArgs := 0;
end;

destructor TProcedureBytecode.Destroy;
begin
  Instructions.Free;
  inherited;
end;

procedure TProcedureBytecode.AddOp(Opcode: Word);
var
  Instr: TBytecodeInstruction;
begin
  Instr.Opcode := Opcode;
  Instr.Value := 0;
  Instr.Str := '';
  Instructions.Add(Instr);
end;

procedure TProcedureBytecode.AddInt(Value: LongInt);
var
  Instr: TBytecodeInstruction;
begin
  Instr.Opcode := O_INTOP;
  Instr.Value := Value;
  Instr.Str := '';
  Instructions.Add(Instr);
end;

procedure TProcedureBytecode.AddString(const Value: string);
var
  Instr: TBytecodeInstruction;
begin
  Instr.Opcode := O_STRINGOP;
  Instr.Value := 0;
  Instr.Str := Value;
  Instructions.Add(Instr);
end;

procedure TProcedureBytecode.AddNameRef(const Value: string);
var
  Instr: TBytecodeInstruction;
begin
  Instr.Opcode := O_NAMEREF;
  Instr.Value := 0;
  Instr.Str := Value;
  Instructions.Add(Instr);
end;

// ============================================================
// TBytecodeGenerator
// ============================================================

constructor TBytecodeGenerator.Create;
begin
  inherited;
  FProcedures := TObjectList<TProcedureBytecode>.Create;
  FStringTable := TList<string>.Create;
  FGlobalVars := TList<string>.Create;
  FBuiltins := TBuiltinDatabase.Create;
  FBuiltins.InitializeFallout2Builtins;
  FReachable := TDictionary<string, Boolean>.Create;
  FNameRefs := TList<string>.Create;
end;

destructor TBytecodeGenerator.Destroy;
begin
  FReachable.Free;
  FProcedures.Free;
  FStringTable.Free;
  FGlobalVars.Free;
  FNameRefs.Free;
  FBuiltins.Free;
  inherited;
end;

// ---------------------------------------------------------------------------
// Helper — look up a builtin function name in the database, return -1 on miss
// ---------------------------------------------------------------------------
function FindBuiltinID(const Name: string; Builtins: TBuiltinDatabase): Integer;
var
  Func: TBuiltinFunction;
begin
  try
    Func := Builtins.FindByName(Name);
    Result := Func.OpcodeID;
  except
    Result := -1;
  end;
end;

// ---------------------------------------------------------------------------
// GenerateSfallBuiltinCall — emit direct opcode pattern for a builtin
// that has a known sfall opcode.
//
// Sfall pattern: [args] → sfall_opcode → O_INTOP(0) → O_D_TO_A → O_SWAPA
// ---------------------------------------------------------------------------
procedure TBytecodeGenerator.GenerateSfallBuiltinCall(const Name: string;
  Args: TList<TASTExpression>; SfallOpcode: Word);
begin
  // Evaluate each argument expression — push results on the value stack
  for var Arg in Args do
    GenerateExpression(Arg);
  // Emit the direct sfall opcode
  FCurrentProc.AddOp(SfallOpcode);
  // Cleanup / return-address pattern matching sfall's writeCallFunc
  FCurrentProc.AddInt(0);
  FCurrentProc.AddOp(O_D_TO_A);
  FCurrentProc.AddOp(O_SWAPA);
end;

// ---------------------------------------------------------------------------
// GenerateExpression — emits bytecode for an expression node
// ---------------------------------------------------------------------------
procedure TBytecodeGenerator.GenerateExpression(Expr: TASTExpression);
var
  BinOp: TASTBinaryOp;
  UnOp: TASTUnaryOp;
  Call: TASTFunctionCall;
begin
  if Expr is TASTNumberLiteral then
  begin
    FCurrentProc.AddOp(O_CONST);
    FCurrentProc.AddInt(TASTNumberLiteral(Expr).Value);
  end
    else if Expr is TASTStringLiteral then
    begin
      var StringLiteral := TASTStringLiteral(Expr).Value;
      // Sfall convention: put string constants in the NAME list,
      // referenced via O_NAMEREF instead of O_STRINGOP + string table.
      if FNameRefs.IndexOf(StringLiteral) < 0 then
        FNameRefs.Add(StringLiteral);
      FCurrentProc.AddNameRef(StringLiteral);
    end
  else if Expr is TASTUnaryOp then
  begin
    UnOp := TASTUnaryOp(Expr);
    GenerateExpression(UnOp.Operand);
    case UnOp.Op of
      tkMinus: FCurrentProc.AddOp(O_NEGATE);
      tkNot:   FCurrentProc.AddOp(O_NOT);
    end;
  end
   else if Expr is TASTBinaryOp then
   begin
     BinOp := TASTBinaryOp(Expr);
     GenerateExpression(BinOp.Left);
     GenerateExpression(BinOp.Right);
     case BinOp.Op of
       tkPlus: FCurrentProc.AddOp(O_ADD);
       tkMinus: FCurrentProc.AddOp(O_SUB);
       tkMul: FCurrentProc.AddOp(O_MUL);
       tkDiv: FCurrentProc.AddOp(O_DIV);
       tkMod: FCurrentProc.AddOp(O_MOD);
       tkEq: FCurrentProc.AddOp(O_EQUAL);
       tkNe: FCurrentProc.AddOp(O_NOT_EQUAL);
       tkLt: FCurrentProc.AddOp(O_LESS);
       tkGt: FCurrentProc.AddOp(O_GREATER);
       tkLe: FCurrentProc.AddOp(O_LESS_EQUAL);
       tkGe: FCurrentProc.AddOp(O_GREATER_EQUAL);
       tkAnd: FCurrentProc.AddOp(O_AND);
       tkOr:  FCurrentProc.AddOp(O_OR);
     end;
   end
  else if Expr is TASTIdentifier then
  begin
    var IdentName := TASTIdentifier(Expr).Name;
    var VarIndex: Integer;

    // 1) Local variable of the current procedure — emit O_FETCH + index
    VarIndex := FCurrentProcLocals.IndexOf(IdentName);
    if VarIndex >= 0 then
    begin
      FCurrentProc.AddInt(VarIndex);
      FCurrentProc.AddOp(O_FETCH);
    end
    else
    begin
      // 2) Global variable — emit O_FETCH_GLOBAL + index
      VarIndex := FGlobalVars.IndexOf(IdentName);
      if VarIndex >= 0 then
      begin
        FCurrentProc.AddInt(VarIndex);
        FCurrentProc.AddOp(O_FETCH_GLOBAL);
      end
      else
      begin
        // 3) Procedure name reference (e.g. Node001 passed to giq_option)
        // Emit a name-table reference so the INT writer encodes this as
        // an offset into the name list.
        FCurrentProc.AddNameRef(IdentName);
      end;
    end;
  end
  else if Expr is TASTFunctionCall then
  begin
    Call := TASTFunctionCall(Expr);
    // Check if this builtin has a known sfall opcode
    var SfallOp := FBuiltins.FindSfallOpcode(Call.Name);
    if SfallOp <> 0 then
    begin
      // Direct sfall opcode pattern
      GenerateSfallBuiltinCall(Call.Name, Call.Args, SfallOp);
    end
    else
    begin
      // Fallback: LOOKUP_STRING_PROC + CALL pattern
      for var Arg in Call.Args do
        GenerateExpression(Arg);
      FCurrentProc.AddInt(0);
      FCurrentProc.AddOp(O_D_TO_A);
      FCurrentProc.AddInt(FindBuiltinID(Call.Name, FBuiltins));
      FCurrentProc.AddOp(O_LOOKUP_STRING_PROC);
      FCurrentProc.AddOp(O_CALL);
      FCurrentProc.AddOp(O_POP);
    end;
  end;
end;

// ---------------------------------------------------------------------------
// CollectIdentifiers — recursively walk an expression tree and add all
// TASTIdentifier names to the given list.
// ---------------------------------------------------------------------------
procedure CollectIdentifiers(Expr: TASTExpression; Idents: TList<string>);
begin
  if Expr = nil then Exit;

  if Expr is TASTIdentifier then
    Idents.Add(TASTIdentifier(Expr).Name)
  else if Expr is TASTBinaryOp then
  begin
    CollectIdentifiers(TASTBinaryOp(Expr).Left, Idents);
    CollectIdentifiers(TASTBinaryOp(Expr).Right, Idents);
  end
  else if Expr is TASTUnaryOp then
    CollectIdentifiers(TASTUnaryOp(Expr).Operand, Idents)
  else if Expr is TASTFunctionCall then
  begin
    for var Arg in TASTFunctionCall(Expr).Args do
      CollectIdentifiers(Arg, Idents);
  end
  else if Expr is TASTArrayAccess then
  begin
    Idents.Add(TASTArrayAccess(Expr).Name);
    if Assigned(TASTArrayAccess(Expr).Index) then
      CollectIdentifiers(TASTArrayAccess(Expr).Index, Idents);
  end;
end;

// ---------------------------------------------------------------------------
// ScanArgsForProcs — look through a list of expressions for identifier names
// that match user-defined procedure declarations, and add matching procs to
// the worklist and reachable set.
// ---------------------------------------------------------------------------
procedure ScanArgsForProcs(Args: TList<TASTExpression>;
  NameMap: TDictionary<string, TASTProcedureDecl>;
  Worklist: TStringList; Reachable: TDictionary<string, Boolean>);
var
  Idents: TList<string>;
  Ident: string;
begin
  Idents := TList<string>.Create;
  try
    for var Arg in Args do
      CollectIdentifiers(Arg, Idents);
    for Ident in Idents do
      if NameMap.ContainsKey(Ident) and not Reachable.ContainsKey(Ident) then
      begin
        Worklist.Add(Ident);
        Reachable.AddOrSetValue(Ident, True);
      end;
  finally
    Idents.Free;
  end;
end;

// ---------------------------------------------------------------------------
// ScanExpressionForProcs — scan a single expression for identifier names that
// match user-defined procedure declarations.
// ---------------------------------------------------------------------------
procedure ScanExpressionForProcs(Expr: TASTExpression;
  NameMap: TDictionary<string, TASTProcedureDecl>;
  Worklist: TStringList; Reachable: TDictionary<string, Boolean>);
var
  Idents: TList<string>;
  Ident: string;
begin
  if Expr = nil then Exit;
  Idents := TList<string>.Create;
  try
    CollectIdentifiers(Expr, Idents);
    for Ident in Idents do
      if NameMap.ContainsKey(Ident) and not Reachable.ContainsKey(Ident) then
      begin
        Worklist.Add(Ident);
        Reachable.AddOrSetValue(Ident, True);
      end;
  finally
    Idents.Free;
  end;
end;

// ---------------------------------------------------------------------------
// ScanStatementForProcs — recursively scan a statement tree for procedure
// references. Handles all statement types including nested control flow:
// if/while/for/switch blocks.
// ---------------------------------------------------------------------------
procedure ScanStatementForProcs(Stmt: TASTStatement;
  NameMap: TDictionary<string, TASTProcedureDecl>;
  Worklist: TStringList; Reachable: TDictionary<string, Boolean>);
var
  CallProc: TASTProcedureCall;
  IfStmt: TASTIfStatement;
  WhileStmt: TASTWhileStatement;
  ForStmt: TASTForStatement;
  SwitchStmt: TASTSwitchStatement;
  I: Integer;
begin
  if Stmt = nil then Exit;

  if Stmt is TASTProcedureCall then
  begin
    CallProc := TASTProcedureCall(Stmt);
    // Check if the call target itself is a user procedure
    if SameText(CallProc.Name, 'start') then
    begin
      if not Reachable.ContainsKey('start') then
      begin
        Worklist.Add('start');
        Reachable.AddOrSetValue('start', True);
      end;
    end
    else if NameMap.ContainsKey(CallProc.Name) and not Reachable.ContainsKey(CallProc.Name) then
    begin
      Worklist.Add(CallProc.Name);
      Reachable.AddOrSetValue(CallProc.Name, True);
    end;
    // Also scan args for identifiers that may be procedure references
    // (e.g. Node001 in giq_option(5, NAME, "text", Node001, 50))
    ScanArgsForProcs(CallProc.Args, NameMap, Worklist, Reachable);
  end
  else if Stmt is TASTExpressionStatement then
  begin
    var Expr := TASTExpressionStatement(Stmt).Expr;
    if Expr is TASTFunctionCall then
      ScanArgsForProcs(TASTFunctionCall(Expr).Args, NameMap, Worklist, Reachable)
    else
      ScanExpressionForProcs(Expr, NameMap, Worklist, Reachable);
  end
  else if Stmt is TASTAssignment then
    ScanExpressionForProcs(TASTAssignment(Stmt).Value, NameMap, Worklist, Reachable)
  else if Stmt is TASTIfStatement then
  begin
    IfStmt := TASTIfStatement(Stmt);
    // Scan the condition expression for procedure references
    ScanExpressionForProcs(IfStmt.Condition, NameMap, Worklist, Reachable);
    // Recurse into then-block
    if Assigned(IfStmt.ThenBlock) then
      for I := 0 to IfStmt.ThenBlock.Statements.Count - 1 do
        ScanStatementForProcs(TASTStatement(IfStmt.ThenBlock.Statements[I]),
          NameMap, Worklist, Reachable);
    // Recurse into else-block
    if Assigned(IfStmt.ElseBlock) then
      for I := 0 to IfStmt.ElseBlock.Statements.Count - 1 do
        ScanStatementForProcs(TASTStatement(IfStmt.ElseBlock.Statements[I]),
          NameMap, Worklist, Reachable);
  end
  else if Stmt is TASTWhileStatement then
  begin
    WhileStmt := TASTWhileStatement(Stmt);
    // Scan the condition expression
    ScanExpressionForProcs(WhileStmt.Condition, NameMap, Worklist, Reachable);
    // Recurse into body
    if Assigned(WhileStmt.Body) then
      for I := 0 to WhileStmt.Body.Statements.Count - 1 do
        ScanStatementForProcs(TASTStatement(WhileStmt.Body.Statements[I]),
          NameMap, Worklist, Reachable);
  end
  else if Stmt is TASTForStatement then
  begin
    ForStmt := TASTForStatement(Stmt);
    // Scan start and end expressions
    ScanExpressionForProcs(ForStmt.StartExpr, NameMap, Worklist, Reachable);
    ScanExpressionForProcs(ForStmt.EndExpr, NameMap, Worklist, Reachable);
    // Recurse into body
    if Assigned(ForStmt.Body) then
      for I := 0 to ForStmt.Body.Statements.Count - 1 do
        ScanStatementForProcs(TASTStatement(ForStmt.Body.Statements[I]),
          NameMap, Worklist, Reachable);
  end
  else if Stmt is TASTSwitchStatement then
  begin
    SwitchStmt := TASTSwitchStatement(Stmt);
    // Scan the switch expression
    ScanExpressionForProcs(SwitchStmt.Expression, NameMap, Worklist, Reachable);
    // Recurse into each case's body
    for I := 0 to SwitchStmt.Cases.Count - 1 do
    begin
      var CaseItem := TASTSwitchCase(SwitchStmt.Cases[I]);
      // Scan case value expression
      if Assigned(CaseItem.CaseValue) then
        ScanExpressionForProcs(CaseItem.CaseValue, NameMap, Worklist, Reachable);
      // Scan case body statements
      if Assigned(CaseItem.Body) then
      begin
        for var J := 0 to CaseItem.Body.Statements.Count - 1 do
          ScanStatementForProcs(TASTStatement(CaseItem.Body.Statements[J]),
            NameMap, Worklist, Reachable);
      end;
    end;
  end
  else if Stmt is TASTVarDecl then
    ScanExpressionForProcs(TASTVarDecl(Stmt).InitialValue, NameMap, Worklist, Reachable)
  else if Stmt is TASTConstDecl then
    ScanExpressionForProcs(TASTConstDecl(Stmt).Value, NameMap, Worklist, Reachable);
  // TASTBreakStatement — nothing to scan
end;

// ---------------------------------------------------------------------------
// ComputeReachable — iterative worklist-based call-graph walk
// Seeds with Fallout 2 engine entry points and recursively scans every
// statement inside each reachable procedure for procedure references.
// ---------------------------------------------------------------------------
function TBytecodeGenerator.ComputeReachable(AST: TASTScript): TDictionary<string, Boolean>;
var
  I: Integer;
  ProcDecl: TASTProcedureDecl;
  NameMap: TDictionary<string, TASTProcedureDecl>;
  Worklist: TStringList;
begin
  Result := TDictionary<string, Boolean>.Create;
  NameMap := TDictionary<string, TASTProcedureDecl>.Create;
  try
    // Build name to declaration map
    for I := 0 to AST.Procedures.Count - 1 do
    begin
      ProcDecl := TASTProcedureDecl(AST.Procedures[I]);
      NameMap.AddOrSetValue(ProcDecl.Name, ProcDecl);
    end;

    Worklist := TStringList.Create;
    try
      // Seed with all Fallout 2 engine entry points — the engine calls these
      // directly, so they and everything they reference must be reachable.
      var EntryPoints: TArray<string> := ['start', 'critter_p_proc',
        'pickup_p_proc', 'use_p_proc', 'talk_p_proc', 'destroy_p_proc',
        'look_at_p_proc', 'description_p_proc', 'use_skill_on_p_proc',
        'damage_p_proc', 'map_enter_p_proc', 'timed_event_p_proc',
        'push_p_proc', 'spatial_p_proc'];
      for var EP in EntryPoints do
        if NameMap.TryGetValue(EP, ProcDecl) then
        begin
          Worklist.Add(EP);
          Result.AddOrSetValue(EP, True);
        end;

      while Worklist.Count > 0 do
      begin
        ProcDecl := NameMap[Worklist[0]];
        Worklist.Delete(0);
        if not Assigned(ProcDecl.Body) then Continue;

        // Recursively scan every statement in the procedure body,
        // descending into if/while/for/switch blocks.
        for I := 0 to ProcDecl.Body.Statements.Count - 1 do
          ScanStatementForProcs(TASTStatement(ProcDecl.Body.Statements[I]),
            NameMap, Worklist, Result);
      end;
    finally
      Worklist.Free;
    end;
  finally
    NameMap.Free;
  end;
end;

// ---------------------------------------------------------------------------
// GenerateStatement — emits bytecode for a single statement node
// ---------------------------------------------------------------------------
procedure TBytecodeGenerator.GenerateStatement(Stmt: TASTStatement);
var
  Assign: TASTAssignment;
  Call: TASTProcedureCall;
  IfStmt: TASTIfStatement;
  WhileStmt: TASTWhileStatement;
  ExprStmt: TASTExpressionStatement;
  I: Integer;
begin
  if Stmt is TASTAssignment then
  begin
    Assign := TASTAssignment(Stmt);
    GenerateExpression(Assign.Value);

    // Determine variable target: local or global
    var VarIndex: Integer;
    VarIndex := FCurrentProcLocals.IndexOf(Assign.Name);
    if VarIndex >= 0 then
    begin
      FCurrentProc.AddInt(VarIndex);
      FCurrentProc.AddOp(O_STORE);
    end
    else
    begin
      VarIndex := FGlobalVars.IndexOf(Assign.Name);
      if VarIndex >= 0 then
      begin
        FCurrentProc.AddInt(VarIndex);
        FCurrentProc.AddOp(O_STORE_GLOBAL);
      end
      else
      begin
        // Unknown variable — fall back to index 0
        FCurrentProc.AddInt(0);
        FCurrentProc.AddOp(O_STORE);
      end;
    end;
  end
  else if Stmt is TASTProcedureCall then
  begin
    Call := TASTProcedureCall(Stmt);
    // Check if this builtin has a known sfall opcode
    var SfallOp := FBuiltins.FindSfallOpcode(Call.Name);
    if SfallOp <> 0 then
    begin
      // Direct sfall opcode pattern
      GenerateSfallBuiltinCall(Call.Name, Call.Args, SfallOp);
    end
    else
    begin
      // Fallback: LOOKUP_STRING_PROC + CALL pattern
      for var Arg in Call.Args do
        GenerateExpression(Arg);
      FCurrentProc.AddInt(0);
      FCurrentProc.AddOp(O_D_TO_A);
      FCurrentProc.AddInt(FindBuiltinID(Call.Name, FBuiltins));
      FCurrentProc.AddOp(O_LOOKUP_STRING_PROC);
      FCurrentProc.AddOp(O_CALL);
      FCurrentProc.AddOp(O_POP);
    end;
  end
  else if Stmt is TASTIfStatement then
  begin
    IfStmt := TASTIfStatement(Stmt);
    FCurrentProc.AddInt(0);
    GenerateExpression(IfStmt.Condition);
    FCurrentProc.AddOp(O_IF);
    if Assigned(IfStmt.ThenBlock) then
    begin
      for I := 0 to IfStmt.ThenBlock.Statements.Count - 1 do
        GenerateStatement(TASTStatement(IfStmt.ThenBlock.Statements[I]));
    end;
    if Assigned(IfStmt.ElseBlock) then
    begin
      FCurrentProc.AddInt(0);
      FCurrentProc.AddOp(O_JMP);
      for I := 0 to IfStmt.ElseBlock.Statements.Count - 1 do
        GenerateStatement(TASTStatement(IfStmt.ElseBlock.Statements[I]));
    end;
  end
  else if Stmt is TASTWhileStatement then
  begin
    WhileStmt := TASTWhileStatement(Stmt);
    FCurrentProc.AddInt(0);
    GenerateExpression(WhileStmt.Condition);
    FCurrentProc.AddOp(O_WHILE);
    if Assigned(WhileStmt.Body) then
    begin
      for I := 0 to WhileStmt.Body.Statements.Count - 1 do
        GenerateStatement(TASTStatement(WhileStmt.Body.Statements[I]));
    end;
    FCurrentProc.AddInt(0);
    FCurrentProc.AddOp(O_JMP);
  end
  else if Stmt is TASTExpressionStatement then
  begin
    ExprStmt := TASTExpressionStatement(Stmt);
    if Assigned(ExprStmt.Expr) then
    begin
      GenerateExpression(ExprStmt.Expr);
      // Pop the unused expression result from the stack
      FCurrentProc.AddOp(O_POP);
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Generate — entry point.  Computes reachable set then emits bytecode only
// for procedures reachable from the 'start' entry point.
// ---------------------------------------------------------------------------
procedure TBytecodeGenerator.Generate(AST: TASTScript; const AScriptName: string);
var
  I, J: Integer;
  Proc: TASTProcedureDecl;
  Reachable: TDictionary<string, Boolean>;
begin
  FScriptName := AScriptName;

  // Populate global vars list before bytecode generation so
  // GenerateExpression can distinguish global vars from procedure names.
  for I := 0 to AST.GlobalVars.Count - 1 do
    FGlobalVars.Add(TASTVarDecl(AST.GlobalVars[I]).Name);

  Reachable := ComputeReachable(AST);
  try
    FReachable := Reachable;
    for I := 0 to AST.Procedures.Count - 1 do
    begin
      Proc := TASTProcedureDecl(AST.Procedures[I]);
      // Only emit bytecode for procedures reachable from the engine entry points
      if not Reachable.ContainsKey(Proc.Name) then
        Continue;
      FCurrentProc := TProcedureBytecode.Create(Proc.Name);
      FProcedures.Add(FCurrentProc);
      FCurrentProc.NumArgs := Proc.LocalVars.Count;
      // Set the local variable name list so GenerateExpression/GenerateStatement
      // can resolve local variable references to their index.
      FCurrentProcLocals := Proc.LocalVars;
      FCurrentProc.AddOp(O_PUSH_BASE);
      if Assigned(Proc.Body) then
      begin
        for J := 0 to Proc.Body.Statements.Count - 1 do
          GenerateStatement(TASTStatement(Proc.Body.Statements[J]));
      end;
      FCurrentProc.AddOp(O_POP_TO_BASE);
      FCurrentProc.AddOp(O_POP_BASE);
      FCurrentProc.AddOp(O_POP_RETURN);
    end;
  finally
    FReachable := nil;
    Reachable.Free;
  end;
end;

end.
