unit uPreprocessor;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils;

type
  TPreprocessor = class
  private
    FMacros: TDictionary<string, string>;
    FIncludePaths: TList<string>;
    FDefines: TList<string>;
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
  public
    constructor Create;
    destructor Destroy; override;

    procedure DefineMacro(const Name, Value: string);
    procedure UndefMacro(const Name: string);
    function IsDefined(const Name: string): Boolean;
    function GetMacroValue(const Name: string): string;

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
end;

destructor TPreprocessor.Destroy;
begin
  FMacros.Free;
  FIncludePaths.Free;
  FDefines.Free;
  inherited;
end;

procedure TPreprocessor.DefineMacro(const Name, Value: string);
begin
  FMacros.AddOrSetValue(Name, Value);
end;

procedure TPreprocessor.UndefMacro(const Name: string);
begin
  FMacros.Remove(Name);
end;

function TPreprocessor.IsDefined(const Name: string): Boolean;
begin
  Result := FMacros.ContainsKey(Name) or FDefines.Contains(Name);
end;

function TPreprocessor.GetMacroValue(const Name: string): string;
begin
  if not FMacros.TryGetValue(Name, Result) then
    Result := '';
end;

procedure TPreprocessor.AddIncludePath(const Path: string);
begin
  FIncludePaths.Add(Path);
end;

function TPreprocessor.ResolveInclude(const FileName: string): string;
var
  i: Integer;
  TestPath: string;
begin
  Result := '';
  if FileExists(FileName) then
  begin
    Result := FileName;
    Exit;
  end;

  for i := 0 to FIncludePaths.Count - 1 do
  begin
    TestPath := IncludeTrailingPathDelimiter(FIncludePaths[i]) + FileName;
    if FileExists(TestPath) then
    begin
      Result := TestPath;
      Exit;
    end;
  end;
end;

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

      if Trimmed.StartsWith('#define') then
      begin
        ProcessDefine(Trimmed);
        Inc(i);
        continue;
      end
      else if Trimmed.StartsWith('#undef') then
      begin
        ProcessUndef(Trimmed);
        Inc(i);
        continue;
      end
      else if Trimmed.StartsWith('#ifdef') then
      begin
        ProcessIfdef(Trimmed, InConditional, SkipUntilElse, ConditionalLevel);
        Inc(i);
        continue;
      end
      else if Trimmed.StartsWith('#ifndef') then
      begin
        ProcessIfndef(Trimmed, InConditional, SkipUntilElse, ConditionalLevel);
        Inc(i);
        continue;
      end
      else if Trimmed.StartsWith('#else') then
      begin
        ProcessElse(InConditional, SkipUntilElse, ConditionalLevel);
        Inc(i);
        continue;
      end
      else if Trimmed.StartsWith('#endif') then
      begin
        ProcessEndif(InConditional, SkipUntilElse, ConditionalLevel);
        Inc(i);
        continue;
      end
      else if Trimmed.StartsWith('#include') then
      begin
        ProcessInclude(Trimmed, BasePath, Output, InConditional, SkipUntilElse, ConditionalLevel);
        Inc(i);
        continue;
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
begin
  Output := TStringList.Create;
  try
    InConditional := False;
    ConditionalLevel := 0;
    SkipUntilElse := False;

    ProcessFile(Source, BasePath, Output, InConditional, SkipUntilElse, ConditionalLevel);

    Result := ExpandMacros(Output.Text);
  finally
    Output.Free;
  end;
end;

procedure TPreprocessor.ProcessDefine(const Line: string);
var
  Name, Value, Temp: string;
  P: Integer;
begin
  Temp := Trim(Copy(Line, 8));
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
  FMacros.AddOrSetValue(Trim(Name), Trim(Value));
end;

procedure TPreprocessor.ProcessUndef(const Line: string);
var
  Name: string;
begin
  Name := Trim(Copy(Line, 8));
  if Name <> '' then
    FMacros.Remove(Name);
end;

procedure TPreprocessor.ProcessIfdef(const Line: string; var InConditional, SkipUntilElse: Boolean;
  var ConditionalLevel: Integer);
var
  Name: string;
  Defined: Boolean;
begin
  Name := Trim(Copy(Line, 7));
  Defined := FMacros.ContainsKey(Name);
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
  Name := Trim(Copy(Line, 8));
  Defined := FMacros.ContainsKey(Name);
  if not InConditional then
  begin
    InConditional := True;
    ConditionalLevel := 1;
    SkipUntilElse := Defined;
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
    SkipUntilElse := not SkipUntilElse;
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
end;

procedure TPreprocessor.ProcessInclude(const Line, BasePath: string; Output: TStringList;
  var InConditional, SkipUntilElse: Boolean; var ConditionalLevel: Integer);
var
  FileName, IncludePath, Temp: string;
  IncludeContent: string;
  SavedInConditional, SavedSkipUntilElse: Boolean;
  SavedConditionalLevel: Integer;
begin
  Temp := Trim(Copy(Line, 10));
  if Temp = '' then Exit;
  
  if (Temp.StartsWith('"')) and (Temp.EndsWith('"')) then
    FileName := Copy(Temp, 2, Length(Temp) - 2)
  else if (Temp.StartsWith('<')) and (Temp.EndsWith('>')) then
    FileName := Copy(Temp, 2, Length(Temp) - 2)
  else
    FileName := Temp;

  IncludePath := TPath.Combine(BasePath, FileName);
  if not FileExists(IncludePath) then
    IncludePath := ResolveInclude(FileName);

  if FileExists(IncludePath) then
  begin
    IncludeContent := TFile.ReadAllText(IncludePath, TEncoding.UTF8);
    // Save current conditional state
    SavedInConditional := InConditional;
    SavedSkipUntilElse := SkipUntilElse;
    SavedConditionalLevel := ConditionalLevel;
    try
      ProcessFile(IncludeContent, ExtractFilePath(IncludePath), Output,
        InConditional, SkipUntilElse, ConditionalLevel);
    finally
      // Restore conditional state
      InConditional := SavedInConditional;
      SkipUntilElse := SavedSkipUntilElse;
      ConditionalLevel := SavedConditionalLevel;
    end;
  end;
end;

function TPreprocessor.ProcessString(const Source: string): string;
begin
  Result := Process(Source, '');
end;

function TPreprocessor.ExpandMacros(const Source: string): string;
var
  Lines: TStringList;
  i: Integer;
  Line, Trimmed: string;
  j: Integer;
  MacroKey, MacroValue: string;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := Source;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      Trimmed := Trim(Line);
      if (Trimmed <> '') and not Trimmed.StartsWith('//') then
      begin
        for j := 0 to FMacros.Count - 1 do
        begin
          MacroKey := FMacros.Keys.ToArray[j];
          MacroValue := FMacros[MacroKey];
          Line := StringReplace(Line, MacroKey, MacroValue, [rfReplaceAll]);
        end;
        Lines[i] := Line;
      end;
    end;
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

end.
