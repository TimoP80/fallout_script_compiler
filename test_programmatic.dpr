program TestProgrammatic;

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes,
  uCompiler in 'uCompiler.pas',
  uLexer in 'uLexer.pas',
  uAST in 'uAST.pas',
  uParser in 'uParser.pas',
  uBytecode in 'uBytecode.pas',
  uBuiltins in 'uBuiltins.pas',
  uINTWriter in 'uINTWriter.pas',
  uPreprocessor in 'uPreprocessor.pas',
  uFMFConverter in 'uFMFConverter.pas';

type
  TTestResult = record
    Name: string;
    Passed: Boolean;
    ErrorMsg: string;
  end;

  TTestResults = array of TTestResult;

var
  GCompiler: TCompiler;
  GTotalTests, GPassedTests: Integer;

procedure Log(const Msg: string);
begin
  WriteLn(Msg);
end;

function RunTest(const Name, Source: string; ExpectSuccess: Boolean): TTestResult;
var
  CompileResult: TCompileResult;
begin
  Result.Name := Name;
  Result.Passed := False;
  Result.ErrorMsg := '';
  GCompiler.Errors.Clear;
  GCompiler.Warnings.Clear;

  CompileResult := GCompiler.CompileString(Source, 'test', '');

  Result.Passed := (CompileResult.Success = ExpectSuccess);
  if not Result.Passed then
  begin
    if ExpectSuccess then
      Result.ErrorMsg := 'Expected success but got failure'
    else
      Result.ErrorMsg := 'Expected failure but got success';

    if GCompiler.Errors.Count > 0 then
      Result.ErrorMsg := Result.ErrorMsg + '. Errors: ' + GCompiler.Errors.Text;
  end
  else
    Inc(GPassedTests);
end;

procedure PrintResults(const Results: TTestResults);
var
  i: Integer;
begin
  for i := 0 to Length(Results) - 1 do
  begin
    if Results[i].Passed then
      WriteLn('  PASS: ' + Results[i].Name)
    else
      WriteLn('  FAIL: ' + Results[i].Name + ' - ' + Results[i].ErrorMsg);
  end;
end;

// ============================================================
// Test suites
// ============================================================

procedure TestBasicProcedures;
var
  Results: TTestResults;
begin
  Log('');
  Log('=== Basic Procedures ===');

  SetLength(Results, 4);

  // Simple procedure with display_msg
  Results[0] := RunTest(
    'procedure with display_msg',
    'procedure start begin display_msg("Hello"); end',
    True
  );

  // Procedure with multiple statements
  Results[1] := RunTest(
    'procedure with multiple statements',
    'procedure start begin display_msg("Hello"); display_msg("World"); end',
    True
  );

  // Empty procedure
  Results[2] := RunTest(
    'empty procedure',
    'procedure test begin end',
    True
  );

  // Procedure with no body (just declaration)
  Results[3] := RunTest(
    'procedure with parameters',
    'procedure test param1 param2 begin end',
    True
  );

  PrintResults(Results);
  GTotalTests := GTotalTests + Length(Results);
end;

procedure TestIfStatements;
var
  Results: TTestResults;
begin
  Log('');
  Log('=== If/Else Statements ===');

  SetLength(Results, 8);

  // Basic if with single statement body (our fix)
  Results[0] := RunTest(
    'if with single statement body',
    'procedure start begin if (local_var(0) = 0) then display_msg("zero"); end',
    True
  );

  // If-else with single statement bodies (our fix)
  Results[1] := RunTest(
    'if-else with single statement bodies',
    'procedure start begin if (local_var(0) = 0) then display_msg("zero"); else display_msg("other"); end',
    True
  );

  // If with begin..end block
  Results[2] := RunTest(
    'if with begin..end block',
    'procedure start begin if (local_var(0) = 0) then begin display_msg("zero"); display_msg("still zero"); end; end',
    True
  );

  // If-else with begin..end blocks (our fix: semicolon after end before else)
  Results[3] := RunTest(
    'if-else with begin..end blocks',
    'procedure start begin if (local_var(0) = 0) then begin display_msg("zero"); end else begin display_msg("other"); end; end',
    True
  );

  // Nested if-else
  Results[4] := RunTest(
    'nested if-else',
    'procedure start begin if (local_var(0) = 0) then if (local_var(1) = 1) then display_msg("both"); else display_msg("first only"); end',
    True
  );

  // If with semicolons before else (our fix)
  Results[5] := RunTest(
    'if with semicolon before else',
    'procedure start begin if (local_var(0) = 0) then display_msg("zero"); else display_msg("other"); end',
    True
  );

  // Multiple elseif pattern (if-else-if)
  Results[6] := RunTest(
    'if-else-if chain',
    'procedure start begin if (local_var(0) = 0) then display_msg("zero"); else if (local_var(0) = 1) then display_msg("one"); else display_msg("other"); end',
    True
  );

  // If with complex condition
  Results[7] := RunTest(
    'if with complex condition',
    'procedure start begin if (local_var(0) >= 0 and local_var(0) <= 10) then display_msg("in range"); end',
    True
  );

  PrintResults(Results);
  GTotalTests := GTotalTests + Length(Results);
end;

procedure TestWhileLoops;
var
  Results: TTestResults;
begin
  Log('');
  Log('=== While Loops ===');

  SetLength(Results, 4);

  // Basic while with single statement body (our fix)
  Results[0] := RunTest(
    'while with single statement body',
    'procedure start begin while (local_var(0) < 10) do display_msg("looping"); end',
    True
  );

  // While with begin..end block
  Results[1] := RunTest(
    'while with begin..end block',
    'procedure start begin while (local_var(0) < 10) do begin display_msg("loop"); set_local_var(0, local_var(0) + 1); end; end',
    True
  );

  // While without 'do' keyword (allowed in some dialects)
  Results[2] := RunTest(
    'while without do keyword',
    'procedure start begin while (local_var(0) < 10) display_msg("looping"); end',
    True
  );

  // While with comparison
  Results[3] := RunTest(
    'while with inequality',
    'procedure start begin while (local_var(0) <> 0) do display_msg("not zero"); end',
    True
  );

  PrintResults(Results);
  GTotalTests := GTotalTests + Length(Results);
end;

procedure TestForLoops;
var
  Results: TTestResults;
begin
  Log('');
  Log('=== For Loops ===');

  SetLength(Results, 3);

  // Basic for loop with single statement (our fix)
  Results[0] := RunTest(
    'for loop with single statement body',
    'procedure start begin for (i = 0 to 10) do display_msg("count"); end',
    True
  );

  // For loop with begin..end block
  Results[1] := RunTest(
    'for loop with begin..end block',
    'procedure start begin for (i = 0 to 10) do begin display_msg("count"); set_local_var(1, i); end; end',
    True
  );

  // For loop without 'do' keyword
  Results[2] := RunTest(
    'for loop without do keyword',
    'procedure start begin for (i = 0 to 10) display_msg("count"); end',
    True
  );

  PrintResults(Results);
  GTotalTests := GTotalTests + Length(Results);
end;

procedure TestSwitchStatements;
var
  Results: TTestResults;
begin
  Log('');
  Log('=== Switch Statements ===');

  SetLength(Results, 8);

  // Basic switch with case and default
  Results[0] := RunTest(
    'basic switch with case and default',
    'procedure start begin switch (local_var(0)) begin case 0: display_msg("zero"); break; default: break; end; end',
    True
  );

  // Switch with multiple cases
  Results[1] := RunTest(
    'switch with multiple cases',
    'procedure start begin switch (local_var(0)) begin case 0: display_msg("zero"); break; case 1: display_msg("one"); break; case 2: display_msg("two"); break; default: break; end; end',
    True
  );

  // Switch with fall-through (no break)
  Results[2] := RunTest(
    'switch with fall-through',
    'procedure start begin switch (local_var(0)) begin case 0: display_msg("zero"); case 1: display_msg("one"); default: display_msg("default"); end; end',
    True
  );

  // Switch with shared case body (empty case before next)
  Results[3] := RunTest(
    'switch with shared case body',
    'procedure start begin switch (local_var(0)) begin case 0: case 1: display_msg("zero or one"); break; default: break; end; end',
    True
  );

  // Switch with only default
  Results[4] := RunTest(
    'switch with only default',
    'procedure start begin switch (local_var(0)) begin default: display_msg("always"); break; end; end',
    True
  );

  // Empty switch
  Results[5] := RunTest(
    'empty switch body',
    'procedure start begin switch (local_var(0)) begin end; end',
    True
  );

  // Switch with multiple statements per case
  Results[6] := RunTest(
    'switch with multiple statements per case',
    'procedure start begin switch (local_var(0)) begin case 0: display_msg("line1"); display_msg("line2"); display_msg("line3"); break; default: break; end; end',
    True
  );

  // Switch with nested if inside case
  Results[7] := RunTest(
    'switch with nested if in case',
    'procedure start begin switch (local_var(0)) begin case 0: if (local_var(1) = 1) then display_msg("both"); else display_msg("zero only"); break; default: break; end; end',
    True
  );

  PrintResults(Results);
  GTotalTests := GTotalTests + Length(Results);
end;

procedure TestVariables;
var
  Results: TTestResults;
begin
  Log('');
  Log('=== Variable Declarations ===');

  SetLength(Results, 3);

  // Global variable declaration
  Results[0] := RunTest(
    'global variable declaration',
    'var test_var; procedure start begin end',
    True
  );

  // Global variable with initial value
  Results[1] := RunTest(
    'global variable with initial value',
    'var myvar := 42; procedure start begin end',
    True
  );

  // Assignment statement
  Results[2] := RunTest(
    'variable assignment',
    'procedure start begin myvar := 42; end',
    True
  );

  PrintResults(Results);
  GTotalTests := GTotalTests + Length(Results);
end;

procedure TestPreprocessorDirectives;
var
  Results: TTestResults;
begin
  Log('');
  Log('=== Preprocessor Directives (Lexer Graceful Skip) ===');

  SetLength(Results, 4);

  // #define directive should be silently skipped by lexer
  Results[0] := RunTest(
    '#define directive in source',
    '#define DEBUG 1'#13#10 +
    'procedure start begin display_msg("test"); end',
    True
  );

  // Multiple preprocessor directives
  Results[1] := RunTest(
    'multiple preprocessor directives',
    '#define FOO 1'#13#10 +
    '#define BAR "hello"'#13#10 +
    'procedure start begin display_msg("test"); end',
    True
  );

  // #ifdef / #endif pair
  Results[2] := RunTest(
    '#ifdef and #endif directives',
    '#ifdef DEBUG'#13#10 +
    'procedure start begin display_msg("debug"); end'#13#10 +
    '#endif',
    True
  );

  // Mixed preprocessor and code
  Results[3] := RunTest(
    'mixed directives and code',
    '#ifdef PLATFORM'#13#10 +
    '  #define VERSION 2'#13#10 +
    '#endif'#13#10 +
    'procedure start begin display_msg("test"); end',
    True
  );

  PrintResults(Results);
  GTotalTests := GTotalTests + Length(Results);
end;

procedure TestEdgeCases;
var
  Results: TTestResults;
begin
  Log('');
  Log('=== Edge Cases ===');

  SetLength(Results, 6);

  // Procedure call as statement
  Results[0] := RunTest(
    'procedure call statement',
    'procedure start begin call myProc; end',
    False  // 'call' keyword may not be fully parsed yet
  );

  // Break without switch context
  Results[1] := RunTest(
    'break outside switch (should fail)',
    'procedure start begin break; end',
    False
  );

  // Just a variable declaration (no procedures)
  Results[2] := RunTest(
    'global variables only (valid in headers)',
    'var x; var y; var z := 100;',
    True
  );

  // String with escape sequences
  Results[3] := RunTest(
    'string with escape sequences',
    'procedure start begin display_msg("Line1\nLine2\tTabbed"); end',
    True
  );

  // Hex numbers
  Results[4] := RunTest(
    'hex number literal',
    'procedure start begin if (local_var(0) = 0xFF) then display_msg("hex"); end',
    True
  );

  // Complex expression
  Results[5] := RunTest(
    'complex expression',
    'procedure start begin if (local_var(0) + local_var(1)) * 2 > 10 then display_msg("big"); end',
    True
  );

  PrintResults(Results);
  GTotalTests := GTotalTests + Length(Results);
end;

// ============================================================
// Main test runner
// ============================================================

begin
  WriteLn('Fallout 2 SSL Compiler - Programmatic Test Suite');
  WriteLn('================================================');
  WriteLn('Note: Some tests may fail if certain features are not yet implemented.');
  WriteLn('');

  GCompiler := TCompiler.Create;
  try
    GTotalTests := 0;
    GPassedTests := 0;

    TestBasicProcedures;
    TestIfStatements;
    TestWhileLoops;
    TestForLoops;
    TestSwitchStatements;
    TestVariables;
    TestPreprocessorDirectives;
    TestEdgeCases;

    Log('');
    Log('================================================');
    Log(Format('Total: %d tests, %d passed, %d failed',
      [GTotalTests, GPassedTests, GTotalTests - GPassedTests]));
  finally
    GCompiler.Free;
  end;

  // Pause if running from IDE
  WriteLn('');
  Write('Press Enter to exit...');
  ReadLn;
end.
