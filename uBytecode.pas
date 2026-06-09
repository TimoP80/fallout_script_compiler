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
    function  ComputeReachable(AST: TASTScript): TDictionary<string, Boolean>;
    procedure GenerateStatement(Stmt: TASTStatement);
    procedure GenerateExpression(Expr: TASTExpression);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Generate(AST: TASTScript; const AScriptName: string);
    property Procedures: TObjectList<TProcedureBytecode> read FProcedures;
    property StringTable: TList<string> read FStringTable;
    property GlobalVars: TList<string> read FGlobalVars;
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
end;

destructor TBytecodeGenerator.Destroy;
begin
  FReachable.Free;
  FProcedures.Free;
  FStringTable.Free;
  FGlobalVars.Free;
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
      // Add string to global string table if not already present
      var StringLiteral := TASTStringLiteral(Expr).Value;
      if FStringTable.IndexOf(StringLiteral) < 0 then
        FStringTable.Add(StringLiteral);
      
      FCurrentProc.AddOp(O_STRINGOP);
      FCurrentProc.AddString(StringLiteral);
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
  else if Expr is TASTFunctionCall then
  begin
    Call := TASTFunctionCall(Expr);
    FCurrentProc.AddInt(0);
    FCurrentProc.AddOp(O_D_TO_A);
    FCurrentProc.AddInt(FindBuiltinID(Call.Name, FBuiltins));
    FCurrentProc.AddOp(O_LOOKUP_STRING_PROC);
    FCurrentProc.AddOp(O_CALL);
    FCurrentProc.AddOp(O_POP);
  end;
end;

// ---------------------------------------------------------------------------
// ComputeReachable — iterative worklist-based call-graph walk
// Seeds with the script entry-point 'start' and follows TASTProcedureCall
// edges. Returns a dictionary where every key is a reachable procedure name.
// ---------------------------------------------------------------------------
function TBytecodeGenerator.ComputeReachable(AST: TASTScript): TDictionary<string, Boolean>;
var
  I, J: Integer;
  ProcDecl: TASTProcedureDecl;
  CallProc: TASTProcedureCall;
  Stmt: TASTStatement;
  NameMap: TDictionary<string, TASTProcedureDecl>;
  Worklist: TStringList;
begin
  Result := TDictionary<string, Boolean>.Create;
  NameMap := TDictionary<string, TASTProcedureDecl>.Create;
  try
    // Build name → declaration map
    for I := 0 to AST.Procedures.Count - 1 do
    begin
      ProcDecl := TASTProcedureDecl(AST.Procedures[I]);
      NameMap.AddOrSetValue(ProcDecl.Name, ProcDecl);
    end;

    Worklist := TStringList.Create;
    try
      // Seed with the script entry point
      if NameMap.TryGetValue('start', ProcDecl) then
      begin
        Worklist.Add('start');
        Result.AddOrSetValue('start', True);
      end;

      while Worklist.Count > 0 do
      begin
        ProcDecl := NameMap[Worklist[0]];
        Worklist.Delete(0);
        if not Assigned(ProcDecl.Body) then Continue;

        for J := 0 to ProcDecl.Body.Statements.Count - 1 do
        begin
          Stmt := ProcDecl.Body.Statements[J];
          if Stmt is TASTProcedureCall then
          begin
            CallProc := TASTProcedureCall(Stmt);
            // 'start' is a built-in entry-point; always reachable
            if SameText(CallProc.Name, 'start') then
            begin
              if not Result.ContainsKey('start') then
              begin
                Worklist.Add('start');
                Result.AddOrSetValue('start', True);
              end;
            end
            else if NameMap.ContainsKey(CallProc.Name) and not Result.ContainsKey(CallProc.Name) then
            begin
              Worklist.Add(CallProc.Name);
              Result.AddOrSetValue(CallProc.Name, True);
            end;
          end;
        end;
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
    FCurrentProc.AddInt(0);
    FCurrentProc.AddOp(O_STORE);
  end
  else if Stmt is TASTProcedureCall then
  begin
    Call := TASTProcedureCall(Stmt);
    FCurrentProc.AddInt(0);
    FCurrentProc.AddOp(O_D_TO_A);
    FCurrentProc.AddInt(FindBuiltinID(Call.Name, FBuiltins));
    FCurrentProc.AddOp(O_LOOKUP_STRING_PROC);
    FCurrentProc.AddOp(O_CALL);
    FCurrentProc.AddOp(O_POP);
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
  Reachable := ComputeReachable(AST);
  try
    FReachable := Reachable;
    for I := 0 to AST.Procedures.Count - 1 do
    begin
      Proc := TASTProcedureDecl(AST.Procedures[I]);
      // Only emit bytecode for procedures reachable from the entry point 'start'
      if not Reachable.ContainsKey(Proc.Name) then
        Continue;
      FCurrentProc := TProcedureBytecode.Create(Proc.Name);
      FProcedures.Add(FCurrentProc);
      FCurrentProc.NumArgs := Proc.LocalVars.Count;
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
    for I := 0 to AST.GlobalVars.Count - 1 do
      FGlobalVars.Add(TASTVarDecl(AST.GlobalVars[I]).Name);
  finally
    FReachable := nil;
    Reachable.Free;
  end;
end;

end.
