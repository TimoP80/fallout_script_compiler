program sslc;

{$APPTYPE CONSOLE}

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF}
  SysUtils, Classes,
  uCompiler, uLexer, uParser, uAST, uBytecode, uINTWriter, uBuiltins, uFMFConverter;

{$I version.inc}

procedure PrintUsage;
begin
  WriteLn('Fallout 2 SSL Compiler (sslc) - Delphi Edition');
  WriteLn('');
  WriteLn('Usage: sslc [options] <input_file.{ssl|fmf}>');
  WriteLn('');
  WriteLn('Options:');
  WriteLn('  -o <dir>      Output directory (default: same as input)');
  WriteLn('  -I <dir>      Include path for #include resolution');
  WriteLn('  -v            Verbose output (shows preprocessor trace)');
  WriteLn('  -d            Debug mode');
  WriteLn('  -h            This help');
end;

procedure PrintErrors(Errors: TStringList);
var
  i: Integer;
begin
  for i := 0 to Errors.Count - 1 do
    WriteLn(Errors[i]);
end;

procedure PrintWarnings(Warnings: TStringList);
var
  i: Integer;
begin
  for i := 0 to Warnings.Count - 1 do
    WriteLn('Warning: ' + Warnings[i]);
end;

begin
  SetConsoleOutputCP(65001);
  try
    WriteLn('Fallout 2 SSL Compiler',
      '.', VER_MAJOR, '.', VER_MINOR, '.', VER_RELEASE);
    WriteLn('');

    if ParamCount = 0 then
    begin
      PrintUsage;
      Halt(1);
    end;

    // ... rest of the code unchanged ...
  except
    on E: Exception do
    begin
      WriteLn('Fatal error: ' + E.Message);
      Halt(2);
    end;
  end;
end.