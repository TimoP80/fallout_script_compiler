program TestHangLocal;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uCompiler in 'uCompiler.pas';

var
  Compiler: TCompiler;
  Res: TCompileResult;
  I: Integer;
begin
  try
    Compiler := TCompiler.Create;
    try
      WriteLn('Testing complex condition (run 1)...');
      Res := Compiler.CompileString(
        'procedure start begin if (local_var(0) >= 0 and local_var(0) <= 10) then display_msg("in range"); end',
        'test', '');
      if Res.Success then WriteLn('  PASS: ok') else WriteLn('  FAIL');

      WriteLn('Testing while loop (run 2)...');
      Res := Compiler.CompileString(
        'procedure start begin while (local_var(0) < 10) do display_msg("looping"); end',
        'test', '');
      if Res.Success then WriteLn('  PASS: ok') else WriteLn('  FAIL');

      WriteLn('Testing for loop (run 3)...');
      Res := Compiler.CompileString(
        'procedure start begin for (i = 0 to 10) do display_msg("count"); end',
        'test', '');
      if Res.Success then WriteLn('  PASS: ok') else WriteLn('  FAIL');

      WriteLn('Testing switch (run 4)...');
      Res := Compiler.CompileString(
        'procedure start begin switch (local_var(0)) begin case 0: display_msg("zero"); break; default: break; end; end',
        'test', '');
      if Res.Success then WriteLn('  PASS: ok') else WriteLn('  FAIL');

      WriteLn('');
      WriteLn('ALL TESTS PASSED');
    finally
      Compiler.Free;
    end;
  except
    on E: Exception do
      WriteLn('FATAL: ' + E.ClassName + ': ' + E.Message);
  end;
end.
