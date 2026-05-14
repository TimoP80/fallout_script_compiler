unit uPreprocessor;

interface

uses
   System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
   System.Diagnostics, Winapi.Windows;

type
  EPreprocessorError = class(Exception);

  /// <summary>
  /// Configuration options that control preprocessor behavior.
  /// Set these before calling Process() to tune performance and output.
  /// </summary>
  TPreprocessorOptions = record
    /// When true, emits trace messages to OutputDebugString during processing
    Verbose: Boolean;
    /// Maximum include nesting depth (prevents runaway recursion)
    MaxIncludeDepth: Integer;
    /// When true, preserves preprocessor directives as comments in the output
    /// (useful for debugging and source mapping)
    PreserveDirectives: Boolean;
  end;

  TPreprocessor = class
  private
    FMacros: TDictionary<string, string>;
    FIncludePaths: TList<string>;
    FDefines: TList<string>;
    FOptions: TPreprocessorOptions;
    FIncludeStack: TStack<string>; // Tracks current include chain for cycle detection
    FIncludeStackSet: TDictionary<string, Boolean>; // For fast cycle detection
    FProcessedIncludeCount: Integer;
    FProcessedLineCount: Integer;
    FMacroExpansionCount: Integer;
    procedure ProcessDefine(const Line: string);
    procedure ProcessUndef(const Line: string);
    procedure ProcessIfdef(const Line: string; var InConditional, SkipUntilElse: Boolean; var ConditionalLevel: Integer);
    procedure ProcessIfndef(const Line: string; var InConditional, SkipUntilElse: Boolean; var ConditionalLevel: Integer);
    procedure ProcessElse(var InConditional: Boolean; var SkipUntilElse: Boolean; ConditionalLevel: Integer);
    procedure ProcessEndif(var InConditional: Boolean; var SkipUntilElse: Boolean; var ConditionalLevel: Integer);
    procedure ProcessInclude(const Line, BasePath: string; Output: TStringList;
      var InConditional, SkipUntilElse: Boolean; var ConditionalLevel: Integer);
    function ExpandMacros(const Source: string): string;
    procedure ProcessFile(const Source: string; BasePath: string; Output: TStringList;
      var InConditional, SkipUntilElse: Boolean; var ConditionalLevel: Integer);
    procedure Trace(const Msg: string);
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Options controlling preprocessor behavior</summary>
    property Options: TPreprocessorOptions read FOptions write FOptions;

    /// <summary>Number of #include files processed last run</summary>
    property ProcessedIncludeCount: Integer read FProcessedIncludeCount;
    /// <summary>Number of source lines processed last run</summary>
    property ProcessedLineCount: Integer read FProcessedLineCount;
    /// <summary>Number of macro expansions performed last run</summary>
    property MacroExpansionCount: Integer read FMacroExpansionCount;

    procedure DefineMacro(const Name, Value: string);
    procedure UndefMacro(const Name: string);
    function IsDefined(const Name: string): Boolean;
    function GetMacroValue(const Name: string): string;
    function GetAllMacroNames: TArray<string>;

    procedure AddIncludePath(const Path: string);
    function ResolveInclude(const FileName: string): string;

    function Process(const Source: string; BasePath: string): string;
    function ProcessString(const Source: string): string;
  end;

implementation

constructor TPreprocessor.Create;
begin
  inherited;
  FMacros := TDictionary<string, string>.Create;
  FIncludePaths := TList<string>.Create;
  FDefines := TList<string>.Create;
  FIncludeStack := TStack<string>.Create;
  FIncludeStackSet := TDictionary<string, Boolean>.Create;
  FOptions.PreserveDirectives := False;
  FOptions.Verbose := False;
  FOptions.MaxIncludeDepth := 64; // Reasonable default; catches loops well before stack overflow
end;

destructor TPreprocessor.Destroy;
begin
  FIncludeStack.Free;
  FIncludeStackSet.Free;
  FDefines.Free;
  FIncludePaths.Free;
  FMacros.Free;
  inherited;
end;

procedure TPreprocessor.Trace(const Msg: string);
begin
  if FOptions.Verbose then
    OutputDebugString(PChar('[PREPROC] ' + Msg));
end;

// ============================================================
// Macro Management
// ============================================================

procedure TPreprocessor.DefineMacro(const Name, Value: string);
begin
  FMacros.AddOrSetValue(Trim(Name), Trim(Value));
end;

procedure TPreprocessor.UndefMacro(const Name: string);
begin
  FMacros.Remove(Trim(Name));
end;

function TPreprocessor.IsDefined(const Name: string): Boolean;
begin
  Result := FMacros.ContainsKey(Trim(Name)) or FDefines.Contains(Trim(Name));
end;

function TPreprocessor.GetMacroValue(const Name: string): string;
begin
  if not FMacros.TryGetValue(Trim(Name), Result) then
    Result := '';
end;

function TPreprocessor.GetAllMacroNames: TArray<string>;
begin
  Result := FMacros.Keys.ToArray;
end;

// ============================================================
// Include Path Management
// ============================================================

procedure TPreprocessor.AddIncludePath(const Path: string);
var
  Normalized: string;
begin
  Normalized := IncludeTrailingPathDelimiter(Path);
  if FIncludePaths.IndexOf(Normalized) < 0 then
    FIncludePaths.Add(Normalized);
end;

function TPreprocessor.ResolveInclude(const FileName: string): string;
var
  i: Integer;
  TestPath: string;
begin
  Result := '';
  // First try relative to current include context
  if FileExists(FileName) then
  begin
    Result := FileName;
    Exit;
  end;

  // Then search registered include paths
  for i := 0 to FIncludePaths.Count - 1 do
  begin
    TestPath := FIncludePaths[i] + FileName;
    if FileExists(TestPath) then
    begin
      Result := TestPath;
      Exit;
    end;
  end;
end;

// ============================================================
// Directive Handlers
// ============================================================

procedure TPreprocessor.ProcessDefine(const Line: string);
var
  Name, Value, Temp: string;
  P: Integer;
begin
  Temp := Trim(Copy(Line, 8)); // Skip '#define '
  if Temp = '' then Exit;

  P := Pos(' ', Temp);
  if P > 0 then
  begin
    Name := Copy(Temp, 1, P - 1);
    Value := Copy(Temp, P + 1);
  end
  else
  begin
    Name := Temp;
    Value := '';
  end;

  Name := Trim(Name);
  Value := Trim(Value);

  Trace(Format('DEFINE %s = "%s"', [Name, Value]));
  FMacros.AddOrSetValue(Name, Value);
end;

procedure TPreprocessor.ProcessUndef(const Line: string);
var
  Name: string;
begin
  Name := Trim(Copy(Line, 8)); // Skip '#undef '
  if Name <> '' then
  begin
    Trace(Format('UNDEF %s', [Name]));
    FMacros.Remove(Name);
  end;
end;

procedure TPreprocessor.ProcessIfdef(const Line: string; var InConditional, SkipUntilElse: Boolean;
  var ConditionalLevel: Integer);
var
  Name: string;
  Defined: Boolean;
begin
  Name := Trim(Copy(Line, 7)); // Skip '#ifdef '
  Defined := IsDefined(Name);

  Trace(Format('IFDEF %s => %s', [Name, BoolToStr(Defined, True)]));

  if not InConditional then
  begin
    InConditional := True;
    ConditionalLevel := 1;
    SkipUntilElse := not Defined;
  end
  else
  begin
    Inc(ConditionalLevel);
  end;
end;

procedure TPreprocessor.ProcessIfndef(const Line: string; var InConditional, SkipUntilElse: Boolean;
  var ConditionalLevel: Integer);
var
  Name: string;
  Defined: Boolean;
begin
  Name := Trim(Copy(Line, 8)); // Skip '#ifndef '
  Defined := IsDefined(Name);

  Trace(Format('IFNDEF %s => %s', [Name, BoolToStr(not Defined, True)]));

  if not InConditional then
  begin
    InConditional := True;
    ConditionalLevel := 1;
    SkipUntilElse := Defined;  // Opposite of #ifdef
  end
  else
  begin
    Inc(ConditionalLevel);
  end;
end;

procedure TPreprocessor.ProcessElse(var InConditional: Boolean; var SkipUntilElse: Boolean;
  ConditionalLevel: Integer);
begin
  if InConditional and (ConditionalLevel = 1) then
  begin
    SkipUntilElse := not SkipUntilElse;
    Trace('#else branch');
  end;
end;

procedure TPreprocessor.ProcessEndif(var InConditional: Boolean; var SkipUntilElse: Boolean;
  var ConditionalLevel: Integer);
begin
  if ConditionalLevel > 0 then
    Dec(ConditionalLevel);

  if ConditionalLevel = 0 then
  begin
    InConditional := False;
    SkipUntilElse := False;
  end;
  Trace('#endif');
end;

// ============================================================
// Include Processing with Cycle Detection
// ============================================================

procedure TPreprocessor.ProcessInclude(const Line, BasePath: string; Output: TStringList;
  var InConditional, SkipUntilElse: Boolean; var ConditionalLevel: Integer);
var
  FileName, IncludePath, Temp, ResolvedPath: string;
  IncludeContent: string;
  SavedInConditional, SavedSkipUntilElse: Boolean;
  SavedConditionalLevel: Integer;
begin
  Temp := Trim(Copy(Line, 10)); // Skip '#include '
  if Temp = '' then Exit;

  // Strip quotes or angle brackets
  if (Temp.StartsWith('"')) and (Temp.EndsWith('"')) then
    FileName := Copy(Temp, 2, Length(Temp) - 2)
  else if (Temp.StartsWith('<')) and (Temp.EndsWith('>')) then
    FileName := Copy(Temp, 2, Length(Temp) - 2)
  else
    FileName := Temp;

  // === CYCLE DETECTION ===
  // Build the absolute path that would be included
  IncludePath := TPath.Combine(BasePath, FileName);
  if not FileExists(IncludePath) then
    IncludePath := ResolveInclude(FileName);

  if IncludePath <> '' then
  begin
ResolvedPath := TPath.GetFullPath(IncludePath);
     if FIncludeStackSet.ContainsKey(ResolvedPath) then
     begin
       Trace(Format('CYCLE DETECTED: %s', [ResolvedPath]));
       raise EPreprocessorError.CreateFmt(
         'Include cycle detected: %s', [ResolvedPath]);
     end;
     FIncludeStack.Push(ResolvedPath);
     FIncludeStackSet.Add(ResolvedPath, True);
  end;

  // Check include depth guard
  if FIncludeStack.Count > FOptions.MaxIncludeDepth then
  begin
    FIncludeStack.Pop;
    raise EPreprocessorError.CreateFmt(
      'Include nesting depth exceeded maximum of %d at file: %s',
      [FOptions.MaxIncludeDepth, FileName]);
  end;

  // === PROCESS INCLUDED FILE ===
  try
    IncludePath := TPath.Combine(BasePath, FileName);
    if not FileExists(IncludePath) then
      IncludePath := ResolveInclude(FileName);

    if FileExists(IncludePath) then
    begin
      IncludeContent := TFile.ReadAllText(IncludePath, TEncoding.UTF8);
      Trace(Format('INCLUDE: %s (depth=%d)', [IncludePath, FIncludeStack.Count]));

      // Save conditional state — critical for correct nesting
      SavedInConditional := InConditional;
      SavedSkipUntilElse := SkipUntilElse;
      SavedConditionalLevel := ConditionalLevel;
      try
        ProcessFile(IncludeContent, ExtractFilePath(IncludePath), Output,
          InConditional, SkipUntilElse, ConditionalLevel);
      finally
        // Restore parent state
        InConditional := SavedInConditional;
        SkipUntilElse := SavedSkipUntilElse;
        ConditionalLevel := SavedConditionalLevel;
      end;

      Inc(FProcessedIncludeCount);
    end
    else if FOptions.Verbose then
    begin
      Trace(Format('INCLUDE NOT FOUND: %s (searched in %s)', [FileName, BasePath]));
    end;
  finally
if FIncludeStack.Count > 0 then
     begin
       FIncludeStackSet.Remove(FIncludeStack.Peek);
       FIncludeStack.Pop;
     end
  end;
end;

// ============================================================
// Core Processing
// ============================================================

procedure TPreprocessor.ProcessFile(const Source: string; BasePath: string; Output: TStringList;
  var InConditional, SkipUntilElse: Boolean; var ConditionalLevel: Integer);
var
  Lines: TStringList;
  i: Integer;
  Line, Trimmed: string;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := Source;
    i := 0;
    while i < Lines.Count do
    begin
      Line := Lines[i];
      Trimmed := Trim(Line);
      Inc(FProcessedLineCount);

      if Trimmed.StartsWith('#define') then
      begin
        ProcessDefine(Trimmed);
        Inc(i);
        Continue;
      end
      else if Trimmed.StartsWith('#undef') then
      begin
        ProcessUndef(Trimmed);
        Inc(i);
        Continue;
      end
      else if Trimmed.StartsWith('#ifdef') then
      begin
        ProcessIfdef(Trimmed, InConditional, SkipUntilElse, ConditionalLevel);
        if FOptions.PreserveDirectives and not SkipUntilElse then
          Output.Add('// PRESERVED: ' + Line);
        Inc(i);
        Continue;
      end
      else if Trimmed.StartsWith('#ifndef') then
      begin
        ProcessIfndef(Trimmed, InConditional, SkipUntilElse, ConditionalLevel);
        if FOptions.PreserveDirectives and not SkipUntilElse then
          Output.Add('// PRESERVED: ' + Line);
        Inc(i);
        Continue;
      end
      else if Trimmed.StartsWith('#else') then
      begin
        ProcessElse(InConditional, SkipUntilElse, ConditionalLevel);
        if FOptions.PreserveDirectives then
          Output.Add('// PRESERVED: ' + Line);
        Inc(i);
        Continue;
      end
      else if Trimmed.StartsWith('#endif') then
      begin
        ProcessEndif(InConditional, SkipUntilElse, ConditionalLevel);
        if FOptions.PreserveDirectives then
          Output.Add('// PRESERVED: ' + Line);
        Inc(i);
        Continue;
      end
      else if Trimmed.StartsWith('#include') then
      begin
        if not SkipUntilElse then
          ProcessInclude(Trimmed, BasePath, Output, InConditional, SkipUntilElse, ConditionalLevel);
        if FOptions.PreserveDirectives and not SkipUntilElse then
          Output.Add('// PRESERVED: ' + Line);
        Inc(i);
        Continue;
      end;

      if not SkipUntilElse then
        Output.Add(Line);
      Inc(i);
    end;
  finally
    Lines.Free;
  end;
end;

function TPreprocessor.Process(const Source: string; BasePath: string): string;
var
  Output: TStringList;
  InConditional: Boolean;
  ConditionalLevel: Integer;
  SkipUntilElse: Boolean;
  sw: TStopwatch;
begin
  // Reset counters
  FProcessedIncludeCount := 0;
  FProcessedLineCount := 0;
  FMacroExpansionCount := 0;

  sw := TStopwatch.StartNew;

  Output := TStringList.Create;
  try
    InConditional := False;
    ConditionalLevel := 0;
    SkipUntilElse := False;

    // Ensure base path has trailing delimiter for correct combining
    if (BasePath <> '') and not BasePath.EndsWith(PathDelim) then
      BasePath := BasePath + PathDelim;

    ProcessFile(Source, BasePath, Output, InConditional, SkipUntilElse, ConditionalLevel);

    Trace(Format('Phase 1 complete: %d lines, %d includes',
      [FProcessedLineCount, FProcessedIncludeCount]));

    Result := ExpandMacros(Output.Text);

    sw.Stop;
    Trace(Format('Total process time: %dms', [sw.ElapsedMilliseconds]));
  finally
    Output.Free;
  end;
end;

function TPreprocessor.ProcessString(const Source: string): string;
begin
  Result := Process(Source, '');
end;

// ============================================================
// Optimized Macro Expansion
// Original: O(L*M*K) where L=lines, M=macros, K=line length
// Improved: Early termination for non-macro lines, reduced StringReplace calls
// ============================================================

function TPreprocessor.ExpandMacros(const Source: string): string;
var
  Lines: TStringList;
  i, j: Integer;
  Line, Trimmed: string;
  MacroKey, MacroValue: string;
  HadReplacement: Boolean;
  MacroCount: Integer;
  Keys: TArray<string>;
begin
  if FMacros.Count = 0 then
  begin
    Result := Source; // No macros defined — no work to do
    Exit;
  end;

  Lines := TStringList.Create;
  try
    Lines.Text := Source;

    // Cache keys array to avoid repeated TDictionary.Keys.ToArray calls per line
    // This was the major performance bottleneck in the original implementation
    MacroCount := FMacros.Count;
    SetLength(Keys, MacroCount);
    for i := 0 to MacroCount - 1 do
      Keys[i] := FMacros.Keys.ToArray[i];

    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      Trimmed := Trim(Line);

      // Skip empty lines, comments, and preprocessor directives in output
      if (Trimmed = '') or Trimmed.StartsWith('//') or Trimmed.StartsWith('/*') then
      begin
        Lines[i] := Line;
        Continue;
      end;

      HadReplacement := False;
      for j := 0 to MacroCount - 1 do
      begin
        // Quick check: does the line even contain the macro name?
        // This avoids the expensive StringReplace call for non-matching lines
        if Pos(Keys[j], Line) > 0 then
        begin
          MacroValue := FMacros[Keys[j]];
          if MacroValue <> '' then
          begin
            Line := StringReplace(Line, Keys[j], MacroValue, [rfReplaceAll]);
            HadReplacement := True;
            Inc(FMacroExpansionCount);
          end
          else
          begin
            // Macro value is empty — remove the identifier
            Line := StringReplace(Line, Keys[j], '', [rfReplaceAll]);
            HadReplacement := True;
            Inc(FMacroExpansionCount);
          end;
        end;
      end;

      Lines[i] := Line;
    end;

    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

end.