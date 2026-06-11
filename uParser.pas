unit uParser;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uLexer, uAST, uBytecode, uBuiltins;

type
  TParseError = record
    Line, Column: Integer;
    Message: string;
  end;

  TParser = class
  private
    FTokens: TList<TToken>;
    FPosition: Integer;
    FErrors: TList<TParseError>;
    FLoopDepth: Integer;
    function CurrentToken: TToken;
    function PeekToken(Offset: Integer = 1): TToken;
    function Advance: TToken;
    function Expect(TokenType: TTokenType; const ErrorMsg: string = ''): TToken;
    function Match(TokenType: TTokenType): Boolean;
    procedure AddError(const Msg: string; Line, Col: Integer);
    // Expression parsing (matching C parse.c precedence climbing)
    function ParseExpression: TASTExpression;
    function ParseAssignment: TASTExpression;
    function ParseComparison: TASTExpression;
    function ParseTerm: TASTExpression;
    function ParseFactor: TASTExpression;
    function ParseUnary: TASTExpression;
    function ParseCall: TASTExpression;
    function ParsePrimary: TASTExpression;
    // Statement parsing
    function ParseStatement: TASTStatement;
    function ParseBlock: TASTBlock;
    function ParseIfStatement: TASTIfStatement;
    function ParseWhileStatement: TASTWhileStatement;
    function ParseForStatement: TASTForStatement;
    function ParseSwitchStatement: TASTSwitchStatement;
    function ParseProcedureCall: TASTProcedureCall;
    function ParseAssignmentOrCall: TASTStatement;
  public
    constructor Create(ATokens: TList<TToken>);
    destructor Destroy; override;
    function Parse: TASTScript;
    property Errors: TList<TParseError> read FErrors;
  end;

implementation

constructor TParser.Create(ATokens: TList<TToken>);
begin
  inherited Create;
  FTokens := ATokens;
  FPosition := 0;
  FErrors := TList<TParseError>.Create;
  FLoopDepth := 0;
end;

destructor TParser.Destroy;
begin
  FErrors.Free;
  inherited;
end;

function TParser.CurrentToken: TToken;
begin
  if FPosition < FTokens.Count then
    Result := FTokens[FPosition]
  else
  begin
    FillChar(Result, SizeOf(Result), 0);
    Result.TokenType := tkEOF;
  end;
end;

function TParser.PeekToken(Offset: Integer = 1): TToken;
begin
  if FPosition + Offset < FTokens.Count then
    Result := FTokens[FPosition + Offset]
  else
    Result := CurrentToken;
end;

function TParser.Advance: TToken;
begin
  Result := CurrentToken;
  if FPosition < FTokens.Count then
    Inc(FPosition);
end;

function TParser.Expect(TokenType: TTokenType; const ErrorMsg: string = ''): TToken;
begin
  if CurrentToken.TokenType = TokenType then
    Result := Advance
  else
  begin
    if ErrorMsg <> '' then
      AddError(ErrorMsg, CurrentToken.Line, CurrentToken.Column)
    else
      AddError('Unexpected token', CurrentToken.Line, CurrentToken.Column);
    Result := CurrentToken;
  end;
end;

function TParser.Match(TokenType: TTokenType): Boolean;
begin
  Result := CurrentToken.TokenType = TokenType;
  if Result then
    Advance;
end;

procedure TParser.AddError(const Msg: string; Line, Col: Integer);
var
  Err: TParseError;
begin
  Err.Line := Line;
  Err.Column := Col;
  Err.Message := Msg;
  FErrors.Add(Err);
end;

// Expression parsing matching C parse.c precedence climbing
// logical_expression â†’ compare_expression â†’ expression â†’ term â†’ factor

function TParser.ParseExpression: TASTExpression;
begin
  Result := ParseAssignment;
end;

function TParser.ParseAssignment: TASTExpression;
var
  Left: TASTExpression;
  OpTok: TToken;
begin
  Left := ParseComparison;

  if (CurrentToken.TokenType = tkAssign) then
  begin
    OpTok := Advance;
    Result := TASTBinaryOp.Create(Left.Line, Left.Column, tkAssign, Left, ParseAssignment);
  end
  else
    Result := Left;
end;

function TParser.ParseComparison: TASTExpression;
var
  Left, Right: TASTExpression;
  Op: TTokenType;
begin
  Result := nil;
  Left := ParseTerm;
  while CurrentToken.TokenType in [tkEq, tkNe, tkGt, tkLt, tkLe, tkGe] do
  begin
    Op := CurrentToken.TokenType;
    Advance;
    Right := ParseTerm;
    Result := TASTBinaryOp.Create(Left.Line, Left.Column, Op, Left, Right);
    Left := Result;
  end;
  if not Assigned(Result) then
    Result := Left;
end;

function TParser.ParseTerm: TASTExpression;
var
  Left, Right: TASTExpression;
  Op: TTokenType;
begin
  Result := nil;
  Left := ParseFactor;
  while CurrentToken.TokenType in [tkPlus, tkMinus, tkOr] do
  begin
    Op := CurrentToken.TokenType;
    Advance;
    Right := ParseFactor;
    Result := TASTBinaryOp.Create(Left.Line, Left.Column, Op, Left, Right);
    Left := Result;
  end;
  if not Assigned(Result) then
    Result := Left;
end;

function TParser.ParseFactor: TASTExpression;
var
  Left, Right: TASTExpression;
  Op: TTokenType;
begin
  Result := nil;
  Left := ParseUnary;
  while CurrentToken.TokenType in [tkMul, tkDiv, tkMod, tkAnd] do
  begin
    Op := CurrentToken.TokenType;
    Advance;
    Right := ParseUnary;
    Result := TASTBinaryOp.Create(Left.Line, Left.Column, Op, Left, Right);
    Left := Result;
  end;
  if not Assigned(Result) then
    Result := Left;
end;

function TParser.ParseUnary: TASTExpression;
var
  Op: TTokenType;
  Operand: TASTExpression;
begin
  if CurrentToken.TokenType in [tkMinus, tkNot] then
  begin
    Op := CurrentToken.TokenType;
    Advance;
    Operand := ParseUnary;
    Result := TASTUnaryOp.Create(Operand.Line, Operand.Column, Op, Operand);
  end
  else
    Result := ParseCall;
end;

function TParser.ParseCall: TASTExpression;
var
  Expr: TASTExpression;
  IdentName: string;
  CallExpr: TASTFunctionCall;
  Arg: TASTExpression;
begin
  Expr := ParsePrimary;

  if (Expr is TASTIdentifier) and (CurrentToken.TokenType = tkLParen) then
  begin
    IdentName := TASTIdentifier(Expr).Name;
    Expr.Free;

    CallExpr := TASTFunctionCall.Create(CurrentToken.Line, CurrentToken.Column, IdentName);
    Advance; // consume '('

    if CurrentToken.TokenType <> tkRParen then
    begin
      repeat
        Arg := ParseExpression;
        CallExpr.Args.Add(Arg);
      until not Match(tkComma);
    end;

    Expect(tkRParen, 'Expected ")" after arguments');
    Result := CallExpr;
  end
  else
    Result := Expr;
end;

function TParser.ParsePrimary: TASTExpression;
var
  Tok: TToken;
begin
  Tok := CurrentToken;
  case Tok.TokenType of
    tkNumber, tkHexNumber:
      begin
        Advance;
        Result := TASTNumberLiteral.Create(Tok.Line, Tok.Column, Tok.Value);
      end;

    tkString:
      begin
        Advance;
        Result := TASTStringLiteral.Create(Tok.Line, Tok.Column, Tok.StrValue);
      end;

    tkTrue:
      begin
        Advance;
        Result := TASTNumberLiteral.Create(Tok.Line, Tok.Column, 1);
      end;

    tkFalse:
      begin
        Advance;
        Result := TASTNumberLiteral.Create(Tok.Line, Tok.Column, 0);
      end;

    tkIdentifier:
      begin
        Advance;
        Result := TASTIdentifier.Create(Tok.Line, Tok.Column, Tok.Text);
      end;

    tkLParen:
      begin
        Advance;
        Result := ParseExpression;
        Expect(tkRParen, 'Expected ")"');
      end;

  else
    begin
      AddError('Unexpected token', Tok.Line, Tok.Column);
      Result := TASTNumberLiteral.Create(Tok.Line, Tok.Column, 0);
      Advance;
    end;
  end;
end;

// Statement parsing
function TParser.ParseStatement: TASTStatement;
begin
  case CurrentToken.TokenType of
    tkIf: Result := ParseIfStatement;
    tkWhile: Result := ParseWhileStatement;
    tkFor: Result := ParseForStatement;
    tkSwitch: Result := ParseSwitchStatement;
    tkBreak:
      begin
        if FLoopDepth <= 0 then
        begin
          AddError('break outside of switch or loop', CurrentToken.Line, CurrentToken.Column);
          Advance;
          Result := nil;
        end
        else
        begin
          Advance;
          Result := TASTBreakStatement.Create(CurrentToken.Line, CurrentToken.Column);
          Expect(tkSemicolon, 'Expected ";" after break');
        end;
      end;
    tkBegin: Result := ParseBlock;
    tkVar:
      begin
        AddError('Local variable declarations not supported', CurrentToken.Line, CurrentToken.Column);
        Advance;
      end;
    tkIdentifier: Result := ParseAssignmentOrCall;
    tkRParen, tkRBracket, tkRBrace, tkEnd, tkElse, tkEOF:
      Result := nil;
  else
    begin
      Result := TASTExpressionStatement.Create(CurrentToken.Line, CurrentToken.Column, ParseExpression);
      Expect(tkSemicolon, 'Expected ";" after expression');
    end;
  end;
end;

function TParser.ParseBlock: TASTBlock;
var
  Block: TASTBlock;
  Stmt: TASTStatement;
begin
  Block := TASTBlock.Create(CurrentToken.Line, CurrentToken.Column);
  Expect(tkBegin, 'Expected "begin"');
  while not (CurrentToken.TokenType in [tkEnd, tkElse, tkEOF]) do
  begin
    if CurrentToken.TokenType = tkEnd then Break;
    Stmt := ParseStatement;
    if Assigned(Stmt) then Block.Statements.Add(Stmt);
    if CurrentToken.TokenType = tkSemicolon then Advance;
  end;
  Expect(tkEnd, 'Expected "end"');
  // Consume semicolon after "end" for "begin ... end;" patterns
  if CurrentToken.TokenType = tkSemicolon then Advance;
  Result := Block;
end;

function TParser.ParseIfStatement: TASTIfStatement;
var
  Stmt: TASTStatement;
begin
  Result := TASTIfStatement.Create(CurrentToken.Line, CurrentToken.Column);
  Advance; // consume 'if'
  Expect(tkLParen, 'Expected "(" after if');
  Result.Condition := ParseExpression;
  Expect(tkRParen, 'Expected ")" after condition');
  Expect(tkThen, 'Expected "then"');

  if CurrentToken.TokenType = tkBegin then
    Result.ThenBlock := ParseBlock
  else
  begin
    Result.ThenBlock := TASTBlock.Create(CurrentToken.Line, CurrentToken.Column);
    // Parse the single statement after 'then' (not wrapped in begin...end)
    if not (CurrentToken.TokenType in [tkElse, tkEnd, tkSemicolon, tkEOF]) then
    begin
      Stmt := ParseStatement;
      if Assigned(Stmt) then
        Result.ThenBlock.Statements.Add(Stmt);
    end;
  end;

  // Consume any semicolons that appear before 'else'
  if CurrentToken.TokenType = tkSemicolon then Advance;

  if Match(tkElse) then
  begin
    if CurrentToken.TokenType = tkBegin then
      Result.ElseBlock := ParseBlock
    else
    begin
      Result.ElseBlock := TASTBlock.Create(CurrentToken.Line, CurrentToken.Column);
      // Parse the single statement after 'else' (not wrapped in begin...end)
      if not (CurrentToken.TokenType in [tkEnd, tkSemicolon, tkEOF]) then
      begin
        Stmt := ParseStatement;
        if Assigned(Stmt) then
          Result.ElseBlock.Statements.Add(Stmt);
      end;
    end;
  end;
end;

function TParser.ParseWhileStatement: TASTWhileStatement;
var
  Stmt: TASTStatement;
begin
  Result := TASTWhileStatement.Create(CurrentToken.Line, CurrentToken.Column);
  Inc(FLoopDepth);
  Advance; // consume 'while'
  Expect(tkLParen, 'Expected "(" after while');
  Result.Condition := ParseExpression;
  Expect(tkRParen, 'Expected ")" after condition');
  if CurrentToken.TokenType = tkDo then
    Advance;
  if CurrentToken.TokenType = tkBegin then
    Result.Body := ParseBlock
  else
  begin
    Result.Body := TASTBlock.Create(CurrentToken.Line, CurrentToken.Column);
    // Parse the single statement after the while condition (not wrapped in begin...end)
    if not (CurrentToken.TokenType in [tkEnd, tkSemicolon, tkEOF]) then
    begin
      Stmt := ParseStatement;
      if Assigned(Stmt) then
        Result.Body.Statements.Add(Stmt);
    end;
  end;
  Dec(FLoopDepth);
end;

function TParser.ParseForStatement: TASTForStatement;
var
  Stmt: TASTStatement;
begin
  Result := TASTForStatement.Create(CurrentToken.Line, CurrentToken.Column);
  Inc(FLoopDepth);
  Advance; // consume 'for'
  Expect(tkLParen, 'Expected "(" after for');

  if CurrentToken.TokenType = tkIdentifier then
  begin
    Result.Variable := CurrentToken.Text;
    Advance;
  end;    if CurrentToken.TokenType = tkAssign then
      Advance
    else
      Expect(tkEq, 'Expected "=" or ":=" in for loop');
  Result.StartExpr := ParseExpression;
  Expect(tkTo, 'Expected "to" or "downto"');
  Result.EndExpr := ParseExpression;
  Expect(tkRParen, 'Expected ")" after for');
  if CurrentToken.TokenType = tkDo then
    Advance;
  if CurrentToken.TokenType = tkBegin then
    Result.Body := ParseBlock
  else
  begin
    Result.Body := TASTBlock.Create(CurrentToken.Line, CurrentToken.Column);
    // Parse the single statement after the for loop (not wrapped in begin...end)
    if not (CurrentToken.TokenType in [tkEnd, tkSemicolon, tkEOF]) then
    begin
      Stmt := ParseStatement;
      if Assigned(Stmt) then
        Result.Body.Statements.Add(Stmt);
    end;
  end;
  Dec(FLoopDepth);
end;

function TParser.ParseSwitchStatement: TASTSwitchStatement;
var
  CaseItem: TASTSwitchCase;
  Stmt: TASTStatement;
begin
  Result := TASTSwitchStatement.Create(CurrentToken.Line, CurrentToken.Column);
  Inc(FLoopDepth);
  Advance; // consume 'switch'
  Expect(tkLParen, 'Expected "(" after switch');
  Result.Expression := ParseExpression;
  Expect(tkRParen, 'Expected ")" after switch expression');
  Expect(tkBegin, 'Expected "begin" after switch');

  while CurrentToken.TokenType <> tkEnd do
  begin
    CaseItem := TASTSwitchCase.Create;
    if Match(tkCase) then
    begin
      CaseItem.CaseValue := ParseExpression;
      Expect(tkColon, 'Expected ":" after case value');
    end
    else if Match(tkDefault) then
    begin
      CaseItem.IsDefault := True;
      Expect(tkColon, 'Expected ":" after default');
    end;

    while not (CurrentToken.TokenType in [tkCase, tkDefault, tkEnd]) do
    begin
      Stmt := ParseStatement;
      if Assigned(Stmt) then
        CaseItem.Body.Statements.Add(Stmt);
      if CurrentToken.TokenType = tkSemicolon then
        Advance;
    end;
    Result.Cases.Add(CaseItem);
  end;

  Dec(FLoopDepth);
  Expect(tkEnd, 'Expected "end" after switch');
end;

function TParser.ParseProcedureCall: TASTProcedureCall;
var
  Name: string;
  StartLine, StartCol: Integer;
begin
  StartLine := CurrentToken.Line;
  StartCol := CurrentToken.Column;
  Name := CurrentToken.Text;
  Advance;
  Result := TASTProcedureCall.Create(StartLine, StartCol, Name);
  Expect(tkLParen, 'Expected "(" after procedure name');
  while CurrentToken.TokenType <> tkRParen do
  begin
    Result.Args.Add(ParseExpression);
    if not Match(tkComma) then Break;
  end;
  Expect(tkRParen, 'Expected ")" after arguments');
end;

function TParser.ParseAssignmentOrCall: TASTStatement;
var
  IdentToken: TToken;
  Expr: TASTExpression;
  Left: TASTExpression;
begin
  IdentToken := CurrentToken;

  // Peek at next token to see if this is a procedure call
  if FPosition + 1 < FTokens.Count then
  begin
    if FTokens[FPosition + 1].TokenType = tkLParen then
    begin
      Result := ParseProcedureCall;
      Expect(tkSemicolon, 'Expected ";" after statement');
      Exit;
    end;
  end;

  Advance;

  if CurrentToken.TokenType = tkAssign then
  begin
    Advance;
    Expr := ParseExpression;
    Result := TASTAssignment.Create(IdentToken.Line, IdentToken.Column, IdentToken.Text, Expr);
  end
  else
  begin
    Left := TASTIdentifier.Create(IdentToken.Line, IdentToken.Column, IdentToken.Text);
    Result := TASTExpressionStatement.Create(IdentToken.Line, IdentToken.Column, Left);
  end;

  Expect(tkSemicolon, 'Expected ";" after statement');
end;

function TParser.Parse: TASTScript;
var
  Script: TASTScript;
  ProcDecl: TASTProcedureDecl;
  VarDecl: TASTVarDecl;
  Token: TToken;
begin
  Script := TASTScript.Create;

  while FPosition < FTokens.Count do
  begin
    Token := CurrentToken;

    if Token.TokenType = tkEOF then Break;

    if Token.TokenType = tkInclude then
    begin
      Advance;
      if CurrentToken.TokenType = tkString then
      begin
        Script.Includes.Add(CurrentToken.StrValue);
        Advance;
      end;
    end
    else if Token.TokenType = tkVar then
    begin
      Advance;
      if CurrentToken.TokenType = tkIdentifier then
      begin
        VarDecl := TASTVarDecl.Create(CurrentToken.Line, CurrentToken.Column, CurrentToken.Text);
        Advance;
        if Match(tkAssign) then VarDecl.InitialValue := ParseExpression;
        Script.GlobalVars.Add(VarDecl);
        Expect(tkSemicolon, 'Expected ";" after var declaration');
      end;
    end
    else if Token.TokenType = tkProcedure then
    begin
      Advance;
      if CurrentToken.TokenType = tkIdentifier then
      begin
        ProcDecl := TASTProcedureDecl.Create(CurrentToken.Line, CurrentToken.Column, CurrentToken.Text);
        Advance;
        
        while CurrentToken.TokenType = tkIdentifier do
        begin
          ProcDecl.LocalVars.Add(CurrentToken.Text);
          Advance;
          if CurrentToken.TokenType = tkComma then Advance;
        end;
        
        if CurrentToken.TokenType = tkBegin then
          ProcDecl.Body := ParseBlock
        else if CurrentToken.TokenType = tkSemicolon then
        begin
          Advance;
          if CurrentToken.TokenType = tkBegin then ProcDecl.Body := ParseBlock;
        end;
        
        Script.Procedures.Add(ProcDecl);
      end;
    end
    else if Token.TokenType = tkEnd then
    begin
      Advance;
    end
    else
    begin
      AddError('Unexpected token at top level', Token.Line, Token.Column);
      Advance;
    end;
  end;

  Result := Script;
end;

end.
