program FalloutCompiler;

uses
  Vcl.Forms,
  uCompilerGUI in 'uCompilerGUI.pas' {frmCompilerGUI};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmCompilerGUI, frmCompilerGUI);
  Application.Run;
end.