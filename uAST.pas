unit uAST;

interface

uses
  System.SysUtils, System.Generics.Collections, uLexer;

type
  TASTNode = class
  public
    Line: Integer;
    Column: Integer;
    constructor Create(ALine, ACol: Integer);
  end;

  TASTExpression = class(TASTNode)
  end;

  TASTStatement = class(TASTNode)
  end;

  // Expressions
  TASTNumberLiteral = class(TASTExpression)
  public
    Value: Int64;
    constructor Create(ALine, ACol: Integer; AValue: Int64); reintroduce;
  end;

  TASTStringLiteral = class(TASTExpression)
  public
    Value: string;
    constructor Create(ALine, ACol: Integer; const AValue: string); reintroduce;
  end;

  TASTIdentifier = class(TASTExpression)
  public
    Name: string;
    constructor Create(ALine, ACol: Integer; const AName: string); reintroduce;
  end;

  TASTBinaryOp = class(TASTExpression)
  public
    Op: TTokenType;
    Left, Right: TASTExpression;
    constructor Create(ALine, ACol: Integer; AOp: TTokenType; ALeft, ARight: TASTExpression); reintroduce;
  end;

  TASTUnaryOp = class(TASTExpression)
  public
    Op: TTokenType;
    Operand: TASTExpression;
    constructor Create(ALine, ACol: Integer; AOp: TTokenType; AOperand: TASTExpression); reintroduce;
  end;

  TASTFunctionCall = class(TASTExpression)
  public
    Name: string;
    Args: TList<TASTExpression>;
    constructor Create(ALine, ACol: Integer; const AName: string); reintroduce;
    destructor Destroy; override;
  end;

  TASTArrayAccess = class(TASTExpression)
  public
    Name: string;
    Index: TASTExpression;
    constructor Create(ALine, ACol: Integer; const AName: string; AIndex: TASTExpression); reintroduce;
  end;

  // Statements
  TASTBlock = class(TASTStatement)
  public
    Statements: TList<TASTStatement>;
    constructor Create(ALine, ACol: Integer); reintroduce;
    destructor Destroy; override;
  end;

  TASTAssignment = class(TASTStatement)
  public
    Name: string;
    Value: TASTExpression;
    constructor Create(ALine, ACol: Integer; const AName: string; AValue: TASTExpression); reintroduce;
  end;

  TASTIfStatement = class(TASTStatement)
  public
    Condition: TASTExpression;
    ThenBlock: TASTBlock;
    ElseBlock: TASTBlock;
    constructor Create(ALine, ACol: Integer); reintroduce;
    destructor Destroy; override;
  end;

  TASTWhileStatement = class(TASTStatement)
  public
    Condition: TASTExpression;
    Body: TASTBlock;
    constructor Create(ALine, ACol: Integer); reintroduce;
    destructor Destroy; override;
  end;

  TASTForStatement = class(TASTStatement)
  public
    Variable: string;
    StartExpr, EndExpr: TASTExpression;
    IsDownTo: Boolean;
    Body: TASTBlock;
    constructor Create(ALine, ACol: Integer); reintroduce;
    destructor Destroy; override;
  end;

  TASTProcedureCall = class(TASTStatement)
  public
    Name: string;
    Args: TList<TASTExpression>;
    constructor Create(ALine, ACol: Integer; const AName: string); reintroduce;
    destructor Destroy; override;
  end;

  TASTProcedureDecl = class(TASTNode)
  public
    Name: string;
    Body: TASTBlock;
    LocalVars: TList<string>;
    constructor Create(ALine, ACol: Integer; const AName: string); reintroduce;
    destructor Destroy; override;
  end;

  TASTSwitchCase = class
  public
    CaseValue: TASTExpression;
    Body: TASTBlock;
    IsDefault: Boolean;
    constructor Create;
    destructor Destroy;
  end;

  TASTSwitchStatement = class(TASTStatement)
  public
    Expression: TASTExpression;
    Cases: TList<TASTSwitchCase>;
    constructor Create(ALine, ACol: Integer); reintroduce;
    destructor Destroy; override;
  end;

  TASTVarDecl = class(TASTStatement)
  public
    Name: string;
    InitialValue: TASTExpression;
    constructor Create(ALine, ACol: Integer; const AName: string); reintroduce;
  end;

  TASTConstDecl = class(TASTStatement)
  public
    Name: string;
    Value: TASTExpression;
    constructor Create(ALine, ACol: Integer; const AName: string); reintroduce;
  end;

  TASTBreakStatement = class(TASTStatement)
  end;

  TASTExpressionStatement = class(TASTStatement)
  public
    Expr: TASTExpression;
    constructor Create(ALine, ACol: Integer; AExpr: TASTExpression); reintroduce;
    destructor Destroy; override;
  end;

  // Script (top-level)
  TASTScript = class
  public
    Procedures: TList<TASTProcedureDecl>;
    GlobalVars: TList<TASTVarDecl>;
    Includes: TList<string>;
    constructor Create;
    destructor Destroy; override;
  end;

implementation

constructor TASTNode.Create(ALine, ACol: Integer);
begin
  inherited Create;
  Line := ALine;
  Column := ACol;
end;

constructor TASTNumberLiteral.Create(ALine, ACol: Integer; AValue: Int64);
begin
  inherited Create(ALine, ACol);
  Value := AValue;
end;

constructor TASTStringLiteral.Create(ALine, ACol: Integer; const AValue: string);
begin
  inherited Create(ALine, ACol);
  Value := AValue;
end;

constructor TASTIdentifier.Create(ALine, ACol: Integer; const AName: string);
begin
  inherited Create(ALine, ACol);
  Name := AName;
end;

constructor TASTBinaryOp.Create(ALine, ACol: Integer; AOp: TTokenType; ALeft, ARight: TASTExpression);
begin
  inherited Create(ALine, ACol);
  Op := AOp;
  Left := ALeft;
  Right := ARight;
end;

constructor TASTUnaryOp.Create(ALine, ACol: Integer; AOp: TTokenType; AOperand: TASTExpression);
begin
  inherited Create(ALine, ACol);
  Op := AOp;
  Operand := AOperand;
end;

constructor TASTFunctionCall.Create(ALine, ACol: Integer; const AName: string);
begin
  inherited Create(ALine, ACol);
  Name := AName;
  Args := TList<TASTExpression>.Create;
end;

destructor TASTFunctionCall.Destroy;
begin
  Args.Free;
  inherited;
end;

constructor TASTArrayAccess.Create(ALine, ACol: Integer; const AName: string; AIndex: TASTExpression);
begin
  inherited Create(ALine, ACol);
  Name := AName;
  Index := AIndex;
end;

constructor TASTBlock.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  Statements := TList<TASTStatement>.Create;
end;

destructor TASTBlock.Destroy;
var
  Stmt: TASTStatement;
begin
  for Stmt in Statements do
    Stmt.Free;
  Statements.Free;
  inherited;
end;

constructor TASTAssignment.Create(ALine, ACol: Integer; const AName: string; AValue: TASTExpression);
begin
  inherited Create(ALine, ACol);
  Name := AName;
  Value := AValue;
end;

constructor TASTIfStatement.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
end;

destructor TASTIfStatement.Destroy;
begin
  ThenBlock.Free;
  if Assigned(ElseBlock) then
    ElseBlock.Free;
  inherited;
end;

constructor TASTWhileStatement.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
end;

destructor TASTWhileStatement.Destroy;
begin
  Body.Free;
  inherited;
end;

constructor TASTForStatement.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
end;

destructor TASTForStatement.Destroy;
begin
  Body.Free;
  inherited;
end;

constructor TASTProcedureCall.Create(ALine, ACol: Integer; const AName: string);
begin
  inherited Create(ALine, ACol);
  Name := AName;
  Args := TList<TASTExpression>.Create;
end;

destructor TASTProcedureCall.Destroy;
begin
  Args.Free;
  inherited;
end;

constructor TASTProcedureDecl.Create(ALine, ACol: Integer; const AName: string);
begin
  inherited Create(ALine, ACol);
  Name := AName;
  LocalVars := TList<string>.Create;
end;

destructor TASTProcedureDecl.Destroy;
begin
  Body.Free;
  LocalVars.Free;
  inherited;
end;

constructor TASTSwitchCase.Create;
begin
  IsDefault := False;
end;

destructor TASTSwitchCase.Destroy;
begin
  if Assigned(CaseValue) then
    CaseValue.Free;
  Body.Free;
end;

constructor TASTSwitchStatement.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  Cases := TList<TASTSwitchCase>.Create;
end;

destructor TASTSwitchStatement.Destroy;
var
  CaseItem: TASTSwitchCase;
begin
  for CaseItem in Cases do
    CaseItem.Free;
  Cases.Free;
  inherited;
end;

constructor TASTVarDecl.Create(ALine, ACol: Integer; const AName: string);
begin
  inherited Create(ALine, ACol);
  Name := AName;
end;

constructor TASTConstDecl.Create(ALine, ACol: Integer; const AName: string);
begin
  inherited Create(ALine, ACol);
  Name := AName;
end;

constructor TASTExpressionStatement.Create(ALine, ACol: Integer; AExpr: TASTExpression);
begin
  inherited Create(ALine, ACol);
  Expr := AExpr;
end;

destructor TASTExpressionStatement.Destroy;
begin
  Expr.Free;
  inherited;
end;

constructor TASTScript.Create;
begin
  Procedures := TList<TASTProcedureDecl>.Create;
  GlobalVars := TList<TASTVarDecl>.Create;
  Includes := TList<string>.Create;
end;

destructor TASTScript.Destroy;
var
  Proc: TASTProcedureDecl;
  VarDecl: TASTVarDecl;
  Inc: string;
begin
  for Proc in Procedures do
    Proc.Free;
  for VarDecl in GlobalVars do
    VarDecl.Free;
  Procedures.Free;
  GlobalVars.Free;
  Includes.Free;
  inherited;
end;

end.
