{ Compile-time version constants — included by sslc.dpr and FalloutCompiler.dpr }
{$IFDEF FPC}
  {$DEFINE VER_MAJOR := 1}
  {$DEFINE VER_MINOR := 4}
  {$DEFINE VER_RELEASE := 0}
  {$DEFINE VER_BUILD := 0}
{$ELSE}
  const
    VER_MAJOR  = 1;
    VER_MINOR  = 4;
    VER_RELEASE = 0;
    VER_BUILD   = 0;
{$ENDIF}
