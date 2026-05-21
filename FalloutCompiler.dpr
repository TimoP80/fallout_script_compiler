program FalloutCompiler;

uses
  Vcl.Forms,
  uCompilerGUI in 'uCompilerGUI.pas' {frmCompilerGUI};

{$R *.res}

begin
  Application.Title := 'Fallout 2 SSL Compiler ' +
    IntToStr(VER_MAJOR) + '.' + IntToStr(VER_MINOR) + '.' + IntToStr(VER_RELEASE);
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmCompilerGUI, frmCompilerGUI);
  Application.Run;
end.