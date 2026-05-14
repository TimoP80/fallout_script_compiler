program sslc;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uCompiler, uLexer, uParser, uAST, uBytecode, uINTWriter, uBuiltins;

procedure PrintUsage;
begin
  WriteLn('Fallout 2 SSL Compiler (sslc) - Delphi Edition');
  WriteLn('');
  WriteLn('Usage: sslc [options] <input_file.ssl>');
  WriteLn('');
  WriteLn('Options:');
  WriteLn('  -o <dir>      Output directory (default: same as input)');
  WriteLn('  -v, --verbose  Verbose output');
  WriteLn('  -d, --debug    Generate debug information');
  WriteLn('  -I <path>      Add include path');
  WriteLn('  -h, --help     Show this help');
  WriteLn('');
  WriteLn('Example:');
  WriteLn('  sslc scripts\test.ssl');
  WriteLn('  sslc -o output\ scripts\test.ssl');
end;

procedure PrintErrors(Errors: TStringList);
var
  i: Integer;
begin
  WriteLn('');
  WriteLn('Compilation failed with ' + Errors.Count.ToString + ' error(s):');
  WriteLn('-----------------------------------');
  for i := 0 to Errors.Count - 1 do
    WriteLn('ERROR: ' + Errors[i]);
end;

procedure PrintWarnings(Warnings: TStringList);
var
  i: Integer;
begin
  if Warnings.Count > 0 then
  begin
    WriteLn('');
    WriteLn('Warnings (' + Warnings.Count.ToString + '):');
    for i := 0 to Warnings.Count - 1 do
      WriteLn('WARNING: ' + Warnings[i]);
  end;
end;

var
  Compiler: TCompiler;
  Result: TCompileResult;
  InputFile, OutputFile, OutputDir: string;
  i: Integer;
  Verbose: Boolean;
begin
  try
    WriteLn('Fallout 2 SSL Compiler v1.0');
    WriteLn('');

    if ParamCount = 0 then
    begin
      PrintUsage;
      Halt(1);
    end;

InputFile := '';
     OutputDir := '';
     Verbose := False;
     Compiler := TCompiler.Create;

     i := 1;
     while i <= ParamCount do
     begin
       if (ParamStr(i) = '-h') or (ParamStr(i) = '--help') then
       begin
         PrintUsage;
         Halt(0);
       end
       else if (ParamStr(i) = '-v') or (ParamStr(i) = '--verbose') then
       begin
         Verbose := True;
       end
       else if (ParamStr(i) = '-d') or (ParamStr(i) = '--debug') then
       begin
         // Debug mode flag
       end
       else if ParamStr(i) = '-o' then
       begin
         Inc(i);
         if i > ParamCount then
         begin
           WriteLn('Error: -o requires a directory argument');
           Halt(1);
         end;
         OutputDir := ParamStr(i);
       end
       else if ParamStr(i) = '-I' then
       begin
         Inc(i);
         if i > ParamCount then
         begin
           WriteLn('Error: -I requires a directory argument');
           Halt(1);
         end;
         Compiler.AddIncludePath(ParamStr(i));
       end
       else if not ParamStr(i).StartsWith('-') then
       begin
         InputFile := ParamStr(i);
       end;
       Inc(i);
     end;

    if InputFile = '' then
    begin
      WriteLn('Error: No input file specified');
      Halt(1);
    end;

    if not FileExists(InputFile) then
    begin
      WriteLn('Error: Input file not found: ' + InputFile);
      Halt(1);
    end;

    // Determine output file
    if OutputDir = '' then
      OutputDir := ExtractFilePath(InputFile);
    
    if OutputDir = '' then
      OutputDir := GetCurrentDir;

    if not DirectoryExists(OutputDir) then
      ForceDirectories(OutputDir);

    OutputFile := TPath.Combine(OutputDir, ChangeFileExt(ExtractFileName(InputFile), '.int'));

if Verbose then
       WriteLn('Compiling: ' + InputFile);

     try
      Result := Compiler.CompileFile(InputFile, OutputFile);

      if Result.Success then
      begin
        WriteLn('Compilation successful: ' + Result.OutputFile);
        if Result.WarningCount > 0 then
          WriteLn('Warnings: ' + Result.WarningCount.ToString);
      end
      else
      begin
        PrintErrors(Compiler.Errors);
        PrintWarnings(Compiler.Warnings);
        Halt(1);
      end;
    finally
      Compiler.Free;
    end;

  except
    on E: Exception do
    begin
      WriteLn('Fatal error: ' + E.ClassName + ': ' + E.Message);
      Halt(2);
    end;
  end;
end.
