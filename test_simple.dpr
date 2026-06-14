program TestFMFToSSL;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  uFMFConverter;

var
  FMFSource, SSLSource: string;
begin
  try
    FMFSource := TFile.ReadAllText('simple.fmf', TEncoding.UTF8);
    Writeln('=== FMF Source ===');
    Writeln(FMFSource);
    Writeln('');
    
    SSLSource := FMFToSSL(FMFSource, 'test');
    Writeln('=== Converted SSL ===');
    Writeln(SSLSource);
    Writeln('');
    
    TFile.WriteAllText('simple_converted.ssl', SSLSource, TEncoding.UTF8);
    Writeln('Saved converted SSL to simple_converted.ssl');
  except
    on E: Exception do
      Writeln('Error: ', E.Message);
  end;
end.