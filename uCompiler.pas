unit uCompiler;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.IOUtils,
  uLexer, uParser, uAST, uBytecode, uINTWriter, uBuiltins, uPreprocessor;

type
  TCompileResult = record
    Success: Boolean;
    ErrorCount: Integer;
    WarningCount: Integer;
    OutputFile: string;
  end;

  TCompiler = class
  private
    FLexer: TLexer;
    FParser: TParser;
    FBytecodeGen: TBytecodeGenerator;
    FPreprocessor: TPreprocessor;
    FErrors: TStringList;
    FWarnings: TStringList;
    function LoadFile(const FileName: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddIncludePath(const Path: string);
    procedure DefineMacro(const Name, Value: string);

    function CompileFile(const SourceFile, OutputFile: string): TCompileResult;
    function CompileString(const Source, ScriptName, OutputFile: string): TCompileResult;

    property Errors: TStringList read FErrors;
    property Warnings: TStringList read FWarnings;
  end;

implementation

constructor TCompiler.Create;
begin
  inherited;
  FErrors := TStringList.Create;
  FWarnings := TStringList.Create;
  FBytecodeGen := TBytecodeGenerator.Create;
  FPreprocessor := TPreprocessor.Create;
end;

destructor TCompiler.Destroy;
begin
  FBytecodeGen.Free;
  FPreprocessor.Free;
  FErrors.Free;
  FWarnings.Free;
  inherited;
end;

procedure TCompiler.AddIncludePath(const Path: string);
begin
  FPreprocessor.AddIncludePath(Path);
end;

procedure TCompiler.DefineMacro(const Name, Value: string);
begin
  FPreprocessor.DefineMacro(Name, Value);
end;

function TCompiler.LoadFile(const FileName: string): string;
begin
  if not FileExists(FileName) then
    raise Exception.Create('File not found: ' + FileName);
  Result := TFile.ReadAllText(FileName, TEncoding.UTF8);
end;

function TCompiler.CompileFile(const SourceFile, OutputFile: string): TCompileResult;
var
  Source: string;
  BasePath: string;
begin
  Result.Success := False;
  Result.ErrorCount := 0;
  Result.WarningCount := 0;
  Result.OutputFile := '';

  FErrors.Clear;
  FWarnings.Clear;

  try
    Source := LoadFile(SourceFile);
    BasePath := ExtractFilePath(SourceFile);
    FPreprocessor.AddIncludePath(BasePath);
    Source := FPreprocessor.Process(Source, BasePath);

    Result := CompileString(Source, ChangeFileExt(ExtractFileName(SourceFile), ''), OutputFile);
  except
    on E: Exception do
    begin
      FErrors.Add('Fatal error: ' + E.Message);
      Result.ErrorCount := FErrors.Count;
    end;
  end;
end;

function TCompiler.CompileString(const Source, ScriptName, OutputFile: string): TCompileResult;
var
  Tokens: TList<TToken>;
  AST: TASTScript;
  I: Integer;
begin
  Result.Success := False;
  Result.ErrorCount := 0;
  Result.WarningCount := 0;
  Result.OutputFile := '';

  FErrors.Clear;
  FWarnings.Clear;

  FLexer := TLexer.Create(Source);
  Tokens := FLexer.Tokenize;

  try
    if FLexer.Errors.Count > 0 then
      FErrors.AddStrings(FLexer.Errors);
  finally
    FLexer.Free;
    FLexer := nil;
  end;

  if FErrors.Count > 0 then
  begin
    Result.ErrorCount := FErrors.Count;
    Exit;
  end;

  FParser := TParser.Create(Tokens);
  try
    AST := FParser.Parse;
    if FParser.Errors.Count > 0 then
    begin
      for I := 0 to FParser.Errors.Count - 1 do
        FErrors.Add(Format('Line %d, Col %d: %s', [
          FParser.Errors[I].Line, FParser.Errors[I].Column, FParser.Errors[I].Message]));
    end;
  finally
    FParser.Free;
  end;

  if FErrors.Count > 0 then
  begin
    Result.ErrorCount := FErrors.Count;
    if Assigned(AST) then AST.Free;
    Exit;
  end;

  FBytecodeGen.Generate(AST, ScriptName);
  AST.Free;

  if OutputFile <> '' then
  begin
    TINTWriter.Save(FBytecodeGen.Procedures, FBytecodeGen.StringTable,
      FBytecodeGen.GlobalVars, OutputFile);
    Result.OutputFile := OutputFile;
  end;

  Result.Success := FErrors.Count = 0;
  Result.ErrorCount := FErrors.Count;
  Result.WarningCount := FWarnings.Count;
end;

end.
