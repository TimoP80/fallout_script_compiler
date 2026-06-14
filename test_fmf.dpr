program TestFMFToSSL;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  uFMFConverter in 'uFMFConverter.pas';

var
  FMFSource, SSLSource: string;
  InFile, OutFile: string;
  SL: TStringList;
  OutFileSSL: TextFile;
begin
  try
    if ParamCount < 1 then
    begin
      Writeln('Usage: test_fmf <input.fmf>');
      Halt(1);
    end;

    InFile := ParamStr(1);
    OutFile := ChangeFileExt(InFile, '.ssl');

    SL := TStringList.Create;
    try
      SL.LoadFromFile(InFile);
      FMFSource := Trim(SL.Text);
    finally
      SL.Free;
    end;
    Writeln('=== FMF Source ===');
    Writeln(FMFSource);
    Writeln('');
    
    SSLSource := FMFToSSL(FMFSource, ChangeFileExt(ExtractFileName(InFile), ''));
    Writeln('=== Converted SSL ===');
    Writeln(SSLSource);
    Writeln('');
    
    AssignFile(OutFileSSL, OutFile);
    Rewrite(OutFileSSL);
    Write(OutFileSSL, SSLSource);
    CloseFile(OutFileSSL);
    Writeln('Saved converted SSL to ' + OutFile);
  except
    on E: Exception do
      Writeln('Error: ', E.Message);
  end;
end.