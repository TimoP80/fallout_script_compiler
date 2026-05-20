program FalloutCompiler;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  cmem,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // this includes LCL, Lazarus-Code, FCL and other needed units
  Forms,
  uCompilerGUI
  { you can add units after this };

{$R *.res}

begin
  {$IFDEF USE_HEAPTRC}
  HeapTrc.Init;
  {$ENDIF}
  Application.Title := 'Fallout 2 SSL Compiler';
  RequireDerivedFormResource:=True;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmCompilerGUI, frmCompilerGUI);
  Application.Run;
end.

