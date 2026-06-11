program sslc;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils,
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
  WriteLn('  -v            Verbose output');
  WriteLn('  -d            Debug mode');
  WriteLn('  -t <type>     Template type for FMF conversion: basic, pushable, terminal, floaters, time/timeevent (default: basic)');
  WriteLn('  -h            This help');
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
  CompileResult: TCompileResult;
  InputFile: string;
  OutputDir: string;
  OutputFile: string;
  Verbose: Boolean;
  Debug: Boolean;
  TemplateType: string;
  I: Integer;
  Arg: string;

begin
  try
    WriteLn('Fallout 2 SSL Compiler',
      '.', VER_MAJOR, '.', VER_MINOR, '.', VER_RELEASE);
    WriteLn('');

    if ParamCount = 0 then
    begin
      PrintUsage;
      Halt(1);
    end;

    // Parse command-line arguments
    InputFile := '';
    OutputDir := '';
    Verbose := False;
    Debug := False;
    TemplateType := '';

    Compiler := TCompiler.Create;
    try
      // Add the directory of the executable as an include path for standard headers
      Compiler.AddIncludePath(ExtractFilePath(ParamStr(0)));

      I := 1;
      while I <= ParamCount do
      begin
        Arg := ParamStr(I);
        if Arg = '-h' then
        begin
          PrintUsage;
          Halt(0);
        end
        else if Arg = '-o' then
        begin
          Inc(I);
          if I <= ParamCount then
            OutputDir := IncludeTrailingPathDelimiter(ParamStr(I))
          else
          begin
            WriteLn('Error: -o requires a directory argument');
            Halt(1);
          end;
        end
        else if Arg = '-I' then
        begin
          Inc(I);
          if I <= ParamCount then
            Compiler.AddIncludePath(ParamStr(I))
          else
          begin
            WriteLn('Error: -I requires a directory argument');
            Halt(1);
          end;
        end
        else if Arg = '-v' then
          Verbose := True
        else if Arg = '-d' then
          Debug := True
        else if Arg = '-t' then
        begin
          Inc(I);
          if I <= ParamCount then
            TemplateType := LowerCase(ParamStr(I))
          else
          begin
            WriteLn('Error: -t requires a template type argument');
            Halt(1);
          end;
        end
        else if InputFile = '' then
          InputFile := Arg
        else
        begin
          WriteLn('Error: Unknown option or multiple input files: ' + Arg);
          Halt(1);
        end;
        Inc(I);
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

      // Determine output file path
      if OutputDir = '' then
        OutputDir := ExtractFilePath(InputFile);
      if OutputDir = '' then
        OutputDir := GetCurrentDir;
      if not DirectoryExists(OutputDir) then
        ForceDirectories(OutputDir);

      OutputFile := TPath.Combine(OutputDir, ChangeFileExt(ExtractFileName(InputFile), '.int'));

      if Verbose then
        WriteLn('Compiling: ' + InputFile);

      // Set template type for FMF conversion
      if TemplateType <> '' then
      begin
        if TemplateType = 'pushable' then
          Compiler.FMFTemplateType := dtPushable
        else if TemplateType = 'terminal' then
          Compiler.FMFTemplateType := dtTerminal
        else if TemplateType = 'floaters' then
          Compiler.FMFTemplateType := dtFloaters
        else if (TemplateType = 'time') or (TemplateType = 'timeevent') then
          Compiler.FMFTemplateType := dtTimeEvent
        else if TemplateType <> 'basic' then
        begin
          WriteLn('Error: Unknown template type: ' + TemplateType);
          WriteLn('Valid types: basic, pushable, terminal, floaters, time, timeevent');
          Halt(1);
        end;
      end;

      // Compile
      CompileResult := Compiler.CompileFile(InputFile, OutputFile);

      if CompileResult.Success then
        begin
          WriteLn('Compilation successful: ' + CompileResult.OutputFile);
          if CompileResult.WarningCount > 0 then
            WriteLn('Warnings: ' + CompileResult.WarningCount.ToString);
          if Debug then
          begin
            WriteLn('');
            WriteLn('=== Debug Info ===');
            WriteLn('Output file: ' + CompileResult.OutputFile);
            WriteLn('Errors: ' + CompileResult.ErrorCount.ToString);
            WriteLn('Warnings: ' + CompileResult.WarningCount.ToString);
          end;
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
