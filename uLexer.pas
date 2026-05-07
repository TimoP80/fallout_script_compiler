unit uLexer;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TTokenType = (
    tkEOF, tkIdentifier, tkNumber, tkString, tkHexNumber,
    tkPlus, tkMinus, tkMul, tkDiv, tkMod,
    tkAssign, tkEq, tkNe, tkLt, tkGt, tkLe, tkGe,
    tkAnd, tkOr, tkNot,
    tkLParen, tkRParen, tkLBracket, tkRBracket, tkLBrace, tkRBrace,
    tkComma, tkSemicolon, tkColon, tkDot, tkArrow,
    tkIf, tkThen, tkElse, tkBegin, tkEnd,
    tkProcedure, tkCall, tkWhile, tkDo, tkFor, tkTo, tkDownto,
    tkSwitch, tkCase, tkBreak, tkDefault,
    tkVar, tkConst, tkInclude, tkTrue, tkFalse, tkUnknown
  );

  TToken = record
    TokenType: TTokenType;
    Text: string;
    Value: Int64;
    StrValue: string;
    Line: Integer;
    Column: Integer;
  end;

  TTokenList = TList<TToken>;

  TLexer = class
  private
    FSource: string;
    FPosition: Integer;
    FLine: Integer;
    FColumn: Integer;
    FTokens: TTokenList;
    FErrors: TStringList;
    procedure AddError(const Msg: string);
    function PeekChar(Ahead: Integer = 0): Char;
    function AdvanceChar: Char;
    function IsAtEnd: Boolean;
    procedure SkipWhitespace;
    procedure SkipComment;
    function ReadString: string;
    function ReadNumber: string;
    function ReadIdentifier: string;
    function MatchKeyword(const Ident: string): TTokenType;
    function DoCreateToken(AType: TTokenType; const AText: string; ALine, ACol: Integer): TToken;
    function DoCreateNumToken(AType: TTokenType; const AText: string; AValue: Int64; ALine, ACol: Integer): TToken;
    function DoCreateStrToken(AType: TTokenType; const AText, AStr: string; ALine, ACol: Integer): TToken;
  public
    constructor Create(const ASource: string);
    destructor Destroy; override;
    function Tokenize: TTokenList;
    property Errors: TStringList read FErrors;
  end;

implementation

constructor TLexer.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
  FPosition := 1;
  FLine := 1;
  FColumn := 1;
  FTokens := TTokenList.Create;
  FErrors := TStringList.Create;
end;

destructor TLexer.Destroy;
begin
  FTokens.Free;
  FErrors.Free;
  inherited Destroy;
end;

procedure TLexer.AddError(const Msg: string);
begin
  FErrors.Add(FLine.ToString + ',' + FColumn.ToString + ': ' + Msg);
end;

function TLexer.PeekChar(Ahead: Integer = 0): Char;
begin
  if FPosition + Ahead > Length(FSource) then
    Result := #0
  else
    Result := FSource[FPosition + Ahead];
end;

function TLexer.AdvanceChar: Char;
begin
  Result := PeekChar;
  Inc(FPosition);
  if Result = #10 then
  begin
    Inc(FLine);
    FColumn := 1;
  end
  else
    Inc(FColumn);
end;

function TLexer.IsAtEnd: Boolean;
begin
  Result := FPosition > Length(FSource);
end;

procedure TLexer.SkipWhitespace;
begin
  while not IsAtEnd do
  begin
    if PeekChar = '/' then
    begin
      if PeekChar(1) = '/' then
      begin
        while not IsAtEnd do
        begin
          if PeekChar = #10 then Break;
          AdvanceChar;
        end;
      end
      else if PeekChar(1) = '*' then
      begin
        AdvanceChar;
        AdvanceChar;
        while not IsAtEnd do
        begin
          if (PeekChar = '*') and (PeekChar(1) = '/') then
          begin
            AdvanceChar;
            AdvanceChar;
            Break;
          end;
          AdvanceChar;
        end;
      end
      else
        Break;
    end
    else if (PeekChar = #9) or (PeekChar = #10) or (PeekChar = #13) or (PeekChar = ' ') then
      AdvanceChar
    else
      Break;
  end;
end;

procedure TLexer.SkipComment;
begin
  if PeekChar = '/' then
  begin
    if PeekChar(1) = '/' then
    begin
      while not IsAtEnd do
      begin
        if PeekChar = #10 then Break;
        AdvanceChar;
      end;
    end
    else if PeekChar(1) = '*' then
    begin
      while not IsAtEnd do
      begin
        if (PeekChar = '*') and (PeekChar(1) = '/') then
        begin
          AdvanceChar;
          AdvanceChar;
          Break;
        end;
        AdvanceChar;
      end;
    end;
  end
  else
    AdvanceChar;
end;

function TLexer.ReadString: string;
var
  Quote: Char;
begin
  Result := '';
  Quote := AdvanceChar;
  while not IsAtEnd do
  begin
    if PeekChar = Quote then
    begin
      AdvanceChar;
      Break;
    end;
    if PeekChar = '\' then
    begin
      AdvanceChar;
      case PeekChar of
        'n': Result := Result + #10;
        't': Result := Result + #9;
        'r': Result := Result + #13;
        '\': Result := Result + '\';
        '"': Result := Result + '"';
        '''': Result := Result + '''';
      else
        Result := Result + PeekChar;
      end;
      AdvanceChar;
    end
    else
      Result := Result + AdvanceChar;
  end;
end;

function TLexer.ReadNumber: string;
begin
  Result := '';
  if (PeekChar = '0') and (UpCase(PeekChar(1)) = 'X') then
  begin
    Result := Result + AdvanceChar;
    Result := Result + AdvanceChar;
    while not IsAtEnd and CharInSet(PeekChar, ['0'..'9', 'A'..'F', 'a'..'f']) do
      Result := Result + AdvanceChar;
  end
  else
    while not IsAtEnd and CharInSet(PeekChar, ['0'..'9', '.']) do
      Result := Result + AdvanceChar;
end;

function TLexer.ReadIdentifier: string;
begin
  Result := '';
  while not IsAtEnd and CharInSet(PeekChar, ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
    Result := Result + AdvanceChar;
end;

function TLexer.DoCreateToken(AType: TTokenType; const AText: string; ALine, ACol: Integer): TToken;
begin
  Result.TokenType := AType;
  Result.Text := AText;
  Result.Value := 0;
  Result.StrValue := '';
  Result.Line := ALine;
  Result.Column := ACol;
end;

function TLexer.DoCreateNumToken(AType: TTokenType; const AText: string; AValue: Int64; ALine, ACol: Integer): TToken;
begin
  Result := DoCreateToken(AType, AText, ALine, ACol);
  Result.Value := AValue;
end;

function TLexer.DoCreateStrToken(AType: TTokenType; const AText, AStr: string; ALine, ACol: Integer): TToken;
begin
  Result := DoCreateToken(AType, AText, ALine, ACol);
  Result.StrValue := AStr;
end;

function TLexer.MatchKeyword(const Ident: string): TTokenType;
var
  LowerIdent: string;
begin
  LowerIdent := LowerCase(Ident);
  if LowerIdent = 'if' then Result := tkIf
  else if LowerIdent = 'then' then Result := tkThen
  else if LowerIdent = 'else' then Result := tkElse
  else if LowerIdent = 'begin' then Result := tkBegin
  else if LowerIdent = 'end' then Result := tkEnd
  else if LowerIdent = 'procedure' then Result := tkProcedure
  else if LowerIdent = 'call' then Result := tkCall
  else if LowerIdent = 'while' then Result := tkWhile
  else if LowerIdent = 'do' then Result := tkDo
  else if LowerIdent = 'for' then Result := tkFor
  else if LowerIdent = 'to' then Result := tkTo
  else if LowerIdent = 'downto' then Result := tkDownto
  else if LowerIdent = 'switch' then Result := tkSwitch
  else if LowerIdent = 'case' then Result := tkCase
  else if LowerIdent = 'break' then Result := tkBreak
  else if LowerIdent = 'default' then Result := tkDefault
  else if LowerIdent = 'var' then Result := tkVar
  else if LowerIdent = 'const' then Result := tkConst
  else if LowerIdent = 'and' then Result := tkAnd
  else if LowerIdent = 'or' then Result := tkOr
  else if LowerIdent = 'not' then Result := tkNot
  else if LowerIdent = 'true' then Result := tkTrue
  else if LowerIdent = 'false' then Result := tkFalse
  else Result := tkIdentifier;
end;

function TLexer.Tokenize: TTokenList;
var
  StartLine, StartCol: Integer;
  Ident, NumStr: string;
  NumVal: Int64;
  Tok: TToken;
begin
  while not IsAtEnd do
  begin
    SkipWhitespace;
    if IsAtEnd then Break;
    StartLine := FLine;
    StartCol := FColumn;

    case PeekChar of
      'a'..'z', 'A'..'Z', '_':
        begin
          Ident := ReadIdentifier;
          Tok := DoCreateToken(MatchKeyword(Ident), Ident, StartLine, StartCol);
          FTokens.Add(Tok);
        end;
      '0'..'9':
        begin
          NumStr := ReadNumber;
          if (Length(NumStr) > 2) and (NumStr[1] = '0') and (UpCase(NumStr[2]) = 'X') then
          begin
            NumVal := StrToInt64('$' + Copy(NumStr, 3, MaxInt));
            Tok := DoCreateNumToken(tkHexNumber, NumStr, NumVal, StartLine, StartCol);
          end
          else
          begin
            NumVal := Round(StrToFloat(NumStr));
            Tok := DoCreateNumToken(tkNumber, NumStr, NumVal, StartLine, StartCol);
          end;
          FTokens.Add(Tok);
        end;
      '"', '''':
        begin
          Ident := ReadString;
          Tok := DoCreateStrToken(tkString, 'string', Ident, StartLine, StartCol);
          FTokens.Add(Tok);
        end;
      '+': begin AdvanceChar; FTokens.Add(DoCreateToken(tkPlus, '+', StartLine, StartCol)); end;
      '-': begin AdvanceChar; FTokens.Add(DoCreateToken(tkMinus, '-', StartLine, StartCol)); end;
      '*': begin AdvanceChar; FTokens.Add(DoCreateToken(tkMul, '*', StartLine, StartCol)); end;
      '/': begin AdvanceChar; FTokens.Add(DoCreateToken(tkDiv, '/', StartLine, StartCol)); end;
      '%': begin AdvanceChar; FTokens.Add(DoCreateToken(tkMod, '%', StartLine, StartCol)); end;
      '=':
        begin
          AdvanceChar;
          if PeekChar = '=' then
          begin
            AdvanceChar;
            FTokens.Add(DoCreateToken(tkEq, '==', StartLine, StartCol));
          end
          else
            FTokens.Add(DoCreateToken(tkAssign, '=', StartLine, StartCol));
        end;
      '!':
        begin
          AdvanceChar;
          if PeekChar = '=' then
          begin
            AdvanceChar;
            FTokens.Add(DoCreateToken(tkNe, '!=', StartLine, StartCol));
          end
          else
            AddError('Unexpected character: !');
        end;
      '<':
        begin
          AdvanceChar;
          if PeekChar = '=' then
          begin
            AdvanceChar;
            FTokens.Add(DoCreateToken(tkLe, '<=', StartLine, StartCol));
          end
          else
            FTokens.Add(DoCreateToken(tkLt, '<', StartLine, StartCol));
        end;
      '>':
        begin
          AdvanceChar;
          if PeekChar = '=' then
          begin
            AdvanceChar;
            FTokens.Add(DoCreateToken(tkGe, '>=', StartLine, StartCol));
          end
          else
            FTokens.Add(DoCreateToken(tkGt, '>', StartLine, StartCol));
        end;
      '(': begin AdvanceChar; FTokens.Add(DoCreateToken(tkLParen, '(', StartLine, StartCol)); end;
      ')': begin AdvanceChar; FTokens.Add(DoCreateToken(tkRParen, ')', StartLine, StartCol)); end;
      '[': begin AdvanceChar; FTokens.Add(DoCreateToken(tkLBracket, '[', StartLine, StartCol)); end;
      ']': begin AdvanceChar; FTokens.Add(DoCreateToken(tkRBracket, ']', StartLine, StartCol)); end;
      '{': begin AdvanceChar; FTokens.Add(DoCreateToken(tkLBrace, '{', StartLine, StartCol)); end;
      '}': begin AdvanceChar; FTokens.Add(DoCreateToken(tkRBrace, '}', StartLine, StartCol)); end;
      ',': begin AdvanceChar; FTokens.Add(DoCreateToken(tkComma, ',', StartLine, StartCol)); end;
      ';': begin AdvanceChar; FTokens.Add(DoCreateToken(tkSemicolon, ';', StartLine, StartCol)); end;
      ':': begin AdvanceChar; FTokens.Add(DoCreateToken(tkColon, ':', StartLine, StartCol)); end;
      '.': begin AdvanceChar; FTokens.Add(DoCreateToken(tkDot, '.', StartLine, StartCol)); end;
      '#':
        begin
          AdvanceChar;
          Ident := ReadIdentifier;
          if LowerCase(Ident) = 'include' then
            FTokens.Add(DoCreateToken(tkInclude, '#include', StartLine, StartCol))
          else
            AddError('Unknown preprocessor directive: #' + Ident);
        end;
    else
      AddError('Unexpected character: ' + PeekChar);
      AdvanceChar;
    end;
  end;

  FTokens.Add(DoCreateToken(tkEOF, '', FLine, FColumn));
  Result := TTokenList.Create;
  Result.AddRange(FTokens);
end;

end.
