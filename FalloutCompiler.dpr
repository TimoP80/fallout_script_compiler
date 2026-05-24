program FalloutCompiler;

uses
  Vcl.Forms, System.SysUtils,
  uCompilerGUI in 'uCompilerGUI.pas' {frmCompilerGUI};

{$R *.res}
{$I version.inc}

begin
  Application.Title := 'Fallout 2 SSL Compiler ' +
    IntToStr(VER_MAJOR) + '.' + IntToStr(VER_MINOR) + '.' + IntToStr(VER_RELEASE);
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmCompilerGUI, frmCompilerGUI);
  Application.Run;
end.