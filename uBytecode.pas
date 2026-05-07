unit uBytecode;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAST, uLexer, uBuiltins;

const
  O_NOOP = $8000;
  O_CONST = $8001;
  O_CRITICAL_START = $8002;
  O_CRITICAL_DONE = $8003;
  O_JMP = $8004;
  O_CALL = $8005;
  O_CALL_AT = $8006;
  O_CALL_CONDITION = $8007;
  O_CALLSTART = $8008;
  O_EXEC = $8009;
  O_SPAWN = $800A;
  O_FORK = $800B;
  O_A_TO_D = $800C;
  O_D_TO_A = $800D;
  O_EXIT = $800E;
  O_DETACH = $800F;
  O_EXIT_PROG = $8010;
  O_STOP_PROG = $8011;
  O_FETCH_GLOBAL = $8012;
  O_STORE_GLOBAL = $8013;
  O_FETCH_EXTERNAL = $8014;
  O_STORE_EXTERNAL = $8015;
  O_EXPORT_VAR = $8016;
  O_EXPORT_PROC = $8017;
  O_SWAP = $8018;
  O_SWAPA = $8019;
  O_POP = $801A;
  O_DUP = $801B;
  O_POP_RETURN = $801C;
  O_POP_EXIT = $801D;
  O_POP_ADDRESS = $801E;
  O_POP_FLAGS = $801F;
  O_POP_FLAGS_RETURN = $8020;
  O_POP_FLAGS_EXIT = $8021;
  O_POP_FLAGS_RETURN_EXTERN = $8022;
  O_POP_FLAGS_EXIT_EXTERN = $8023;
  O_POP_FLAGS_RETURN_VAL_EXTERN = $8024;
  O_POP_FLAGS_RETURN_VAL_EXIT = $8025;
  O_POP_FLAGS_RETURN_VAL_EXIT_EXTERN = $8026;
  O_CHECK_ARG_COUNT = $8027;
  O_LOOKUP_STRING_PROC = $8028;
  O_POP_BASE = $8029;
  O_POP_TO_BASE = $802A;
  O_PUSH_BASE = $802B;
  O_SET_GLOBAL = $802C;
  O_FETCH_PROC_ADDRESS = $802D;
  O_DUMP = $802E;
  O_IF = $802F;
  O_WHILE = $8030;
  O_STORE = $8031;
  O_FETCH = $8032;
  O_EQUAL = $8033;
  O_NOT_EQUAL = $8034;
  O_LESS_EQUAL = $8035;
  O_GREATER_EQUAL = $8036;
  O_LESS = $8037;
  O_GREATER = $8038;
  O_ADD = $8039;
  O_SUB = $803A;
  O_MUL = $803B;
  O_DIV = $803C;
  O_MOD = $803D;
  O_AND = $803E;
  O_OR = $803F;
  O_BWAND = $8040;
  O_BWOR = $8041;
  O_BWXOR = $8042;
  O_BWNOT = $8043;
  O_FLOOR = $8044;
  O_NOT = $8045;
  O_NEGATE = $8046;
  O_WAIT = $8047;
  O_CANCEL = $8048;
  O_CANCELALL = $8049;
  O_STARTCRITICAL = $804A;
  O_ENDCRITICAL = $804B;
  O_END_CORE = $804C;
  O_RET = $804D;

  O_INTOP = $C001;
  O_STRINGOP = $9000;
  O_FLOATOP = $A000;

type
  TBytecodeInstruction = record
    Opcode: Word;
    Value: LongInt;
    Str: string;
  end;

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

  TBytecodeGenerator = class
  private
    FProcedures: TObjectList<TProcedureBytecode>;
    FCurrentProc: TProcedureBytecode;
    FStringTable: TList<string>;
    FGlobalVars: TList<string>;
    FBuiltins: TBuiltinDatabase;
    FScriptName: string;
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

constructor TBytecodeGenerator.Create;
begin
  inherited;
  FProcedures := TObjectList<TProcedureBytecode>.Create;
  FStringTable := TList<string>.Create;
  FGlobalVars := TList<string>.Create;
  FBuiltins := TBuiltinDatabase.Create;
  FBuiltins.InitializeFallout2Builtins;
end;

destructor TBytecodeGenerator.Destroy;
begin
  FProcedures.Free;
  FStringTable.Free;
  FGlobalVars.Free;
  FBuiltins.Free;
  inherited;
end;

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
    FCurrentProc.AddOp($9000);
    FCurrentProc.AddString(TASTStringLiteral(Expr).Value);
  end
  else if Expr is TASTUnaryOp then
  begin
    UnOp := TASTUnaryOp(Expr);
    GenerateExpression(UnOp.Operand);
    case UnOp.Op of
      tkMinus: FCurrentProc.AddOp(O_NEGATE);
      tkNot: FCurrentProc.AddOp(O_NOT);
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
      GenerateExpression(ExprStmt.Expr);
    FCurrentProc.AddOp(O_POP_TO_BASE);
    FCurrentProc.AddOp(O_POP_BASE);
    FCurrentProc.AddOp(O_POP_RETURN);
  end;
end;

procedure TBytecodeGenerator.Generate(AST: TASTScript; const AScriptName: string);
var
  I, J: Integer;
  Proc: TASTProcedureDecl;
begin
  FScriptName := AScriptName;
  for I := 0 to AST.Procedures.Count - 1 do
  begin
    Proc := TASTProcedureDecl(AST.Procedures[I]);
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
end;

end.