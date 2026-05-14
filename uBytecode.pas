unit uBytecode;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAST, uLexer, uBuiltins;

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
     FCurrentProc.AddOp(O_STRINGOP);
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
       tkOr: FCurrentProc.AddOp(O_OR);
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