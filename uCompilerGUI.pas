unit uCompilerGUI;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Menus, System.Generics.Collections,
  uCompiler, uLexer, uParser, uAST, uBytecode, uINTWriter, uBuiltins;

type
  TfrmCompilerGUI = class(TForm)
    mainMenu: TMainMenu;
    mnuFile: TMenuItem;
    mnuOpen: TMenuItem;
    mnuExit: TMenuItem;
    mnuCompile: TMenuItem;
    mnuCompileFile: TMenuItem;
    mnuSettings: TMenuItem;
    pnlLeft: TPanel;
    pnlRight: TPanel;
    splitMain: TSplitter;
    memEditor: TMemo;
    memOutput: TMemo;
    lblEditor: TLabel;
    lblOutput: TLabel;
    btnCompile: TButton;
    btnOpen: TButton;
    btnSave: TButton;
    openDialog: TOpenDialog;
    saveDialog: TSaveDialog;
    procedure FormCreate(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
    procedure btnCompileClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure mnuOpenClick(Sender: TObject);
    procedure mnuCompileFileClick(Sender: TObject);
    procedure mnuExitClick(Sender: TObject);
  private
    FCurrentFile: string;
    FCompiler: TCompiler;
    procedure CompileCurrentFile;
    procedure UpdateTheme;
  public
    { Public declarations }
  end;

var
  frmCompilerGUI: TfrmCompilerGUI;

implementation

{$R *.dfm}

procedure TfrmCompilerGUI.FormCreate(Sender: TObject);
begin
  FCompiler := TCompiler.Create;
  FCurrentFile := '';
  UpdateTheme;
end;

procedure TfrmCompilerGUI.UpdateTheme;
begin
  // Fallout-inspired theme
  Self.Color := clBlack;
  memEditor.Color := clBlack;
  memEditor.Font.Color := clLime;
  memEditor.Font.Name := 'Courier New';
  memOutput.Color := clBlack;
  memOutput.Font.Color := clLime;
  memOutput.Font.Name := 'Courier New';
  pnlLeft.Color := clGreen;
  pnlRight.Color := clGreen;
end;

procedure TfrmCompilerGUI.btnOpenClick(Sender: TObject);
begin
  mnuOpenClick(Sender);
end;

procedure TfrmCompilerGUI.mnuOpenClick(Sender: TObject);
begin
  openDialog.Filter := 'SSL Files (*.ssl)|*.ssl|FMF Files (*.fmf)|*.fmf|All Files (*.*)|*.*';
  if openDialog.Execute then
  begin
    FCurrentFile := openDialog.FileName;
    memEditor.Lines.LoadFromFile(FCurrentFile);
    lblEditor.Caption := 'Editor - ' + ExtractFileName(FCurrentFile);
  end;
end;

procedure TfrmCompilerGUI.btnSaveClick(Sender: TObject);
begin
  if FCurrentFile = '' then
  begin
    saveDialog.Filter := 'SSL Files (*.ssl)|*.ssl|FMF Files (*.fmf)|*.fmf|All Files (*.*)|*.*';
    if saveDialog.Execute then
      FCurrentFile := saveDialog.FileName;
  end;

  if FCurrentFile <> '' then
  begin
    memEditor.Lines.SaveToFile(FCurrentFile);
    lblEditor.Caption := 'Editor - ' + ExtractFileName(FCurrentFile);
  end;
end;

procedure TfrmCompilerGUI.btnCompileClick(Sender: TObject);
begin
  CompileCurrentFile;
end;

procedure TfrmCompilerGUI.mnuCompileFileClick(Sender: TObject);
begin
  CompileCurrentFile;
end;

procedure TfrmCompilerGUI.CompileCurrentFile;
var
  Result: TCompileResult;
  OutputFile: string;
  i: Integer;
begin
  if FCurrentFile = '' then
  begin
    mnuOpenClick(nil);
    if FCurrentFile = '' then Exit;
  end;

  // Save current file first
  memEditor.Lines.SaveToFile(FCurrentFile);

  // Determine output file
  OutputFile := ChangeFileExt(FCurrentFile, '.int');

  memOutput.Lines.Clear;
  memOutput.Lines.Add('Compiling: ' + FCurrentFile);
  memOutput.Lines.Add('-----------------------------------');

  Result := FCompiler.CompileFile(FCurrentFile, OutputFile);

  if Result.Success then
  begin
    memOutput.Lines.Add('Compilation successful!');
    memOutput.Lines.Add('Output: ' + Result.OutputFile);
    if Result.WarningCount > 0 then
      memOutput.Lines.Add('Warnings: ' + Result.WarningCount.ToString);
  end
  else
  begin
    memOutput.Lines.Add('Compilation failed with ' + Result.ErrorCount.ToString + ' error(s):');
    for i := 0 to FCompiler.Errors.Count - 1 do
      memOutput.Lines.Add('ERROR: ' + FCompiler.Errors[i]);
  end;

  if FCompiler.Warnings.Count > 0 then
  begin
    memOutput.Lines.Add('');
    memOutput.Lines.Add('Warnings:');
    for i := 0 to FCompiler.Warnings.Count - 1 do
      memOutput.Lines.Add('WARNING: ' + FCompiler.Warnings[i]);
  end;
end;

procedure TfrmCompilerGUI.mnuExitClick(Sender: TObject);
begin
  Close;
end;

end.