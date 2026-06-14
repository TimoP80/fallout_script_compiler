program TestFMFConversion;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uFMFConverter in 'uFMFConverter.pas';

var
  FMFSource, SSLSource: string;
begin
  try
    FMFSource := 
      'NPCName "TestNPC"'+#13#10+
      'Location "TestLocation"'+#13#10+
      'Description "A test"'+#13#10+
      #13#10+
      '/* Regular nodes */'+#13#10+
      #13#10+
      'Node "0"'+#13#10+
      'notes ""'+#13#10+
      'is_wtg = false'+#13#10+
      '{'+#13#10+
      'NPCText "Hello from FMF"'+#13#10+
      '        options {'+#13#10+
      '            int=4 Reaction=REACTION_NEUTRAL playertext "OK" linkto "done"  notes ""'+#13#10+
      '                }'+#13#10+
      '}';
      
    Writeln('=== FMF Source ===');
    Writeln(FMFSource);
    Writeln('');
    
    SSLSource := FMFToSSL(FMFSource, 'test');
    Writeln('=== Converted SSL ===');
    Writeln(SSLSource);
    Writeln('');
  except
    on E: Exception do
      Writeln('Error: ', E.Message);
  end;
end.