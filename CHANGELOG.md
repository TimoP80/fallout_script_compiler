# Changelog

All notable changes to the Fallout 2 SSL Compiler will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Lazarus IDE project support (`.lpi` / `.lpr`)
  - New `FalloutCompiler.lpi` — Lazarus Project Information file with all 11 source units registered, LCL v1 VCL compatibility layer, source path and unit output path configured, and the existing `sslc_Icon.ico` embedded as the application icon
  - New `FalloutCompiler.lpr` — Lazarus program source using `{$mode objfpc}{$H+}`, with LCL bootstrap via `Interfaces` / `Forms`, and `RequireDerivedFormResource` preserving Delphi's `{$R *.res}` behaviour
  - No modifications were made to any existing `.pas`, `.dfm`, or `.dpr` files — the Lazarus project is a drop-in companion alongside the existing Delphi project

### Fixed
- **Unused procedure record** — `TBytecodeGenerator.Generate()` emitted a bytecode record for every procedure declared in the script, including those never called anywhere. For a script like `variables.ssl` (which declares `talk_p_proc` but never invokes it) this added exactly one 28-byte procedure record, inflating the output by 28 bytes vs the C sslc reference output.
  - `ComputeReachable()` introduced: iterative worklist-based call-graph walk starting from the `start` entry-point; each body is scanned for `TASTProcedureCall` nodes to discover directly-called procedures.
  - `Generate()` now calls `ComputeReachable()` before writing any bytecode and skips any procedure whose name is absent from the reachable set — unused forward declarations are silently omitted.
- **INT writer header selector** — `TINTWriter.Save()` wrote `$8004` (format selector = 4) at byte-offset 16 where the C sslc reference writes `$800D` (format selector = 13, `local_vars preamble`). All subsequent position fields shifted by ±3 bytes in the Delphi output relative to the C reference. Replaced with `$800D` so the preamble encoding matches the original format.
- **INT writer procedure epilogue sequence** — `Save()` emitted `$802A` + `$8029` + `$801C` (3 trailing opcodes) per procedure, versus the C sslc's `$8029` + `$801C` (2 trailing opcodes). Removed the spurious `$802A` to match the original epilogue sequence.

### Changed
- `TBytecodeGenerator` carries a new `FReachable` field (`TDictionary<string, Boolean>`) and `ComputeReachable()` method; `Create`/`Destroy` updated to initialise and free it; `Generate` signature unchanged (backward-compatible API contract).

### Fixed
- **Critical**: Preprocessor infinite loop when processing `#include` directives
  - The original implementation used `StringReplace` to replace include lines in the entire source text
  - This caused an infinite loop when processing files with multiple includes
  - Fixed by refactoring to use recursive processing with proper state management
  - Conditional compilation state (`#ifdef`/`#ifndef`/`#else`/`#endif`) is now correctly preserved across nested includes
- Incorrect binary operation opcodes in `uBytecode.pas` (hardcoded values misaligned with Fallout 2 VM spec)
  - Replaced hardcoded hex constants with proper `O_*` definitions from `uBuiltins.pas`
  - Removed duplicate opcode constant definitions, now uses single source of truth

### Changed
- Refactored `TPreprocessor.ProcessFile` from `for` loop to `while` loop with manual index management
- Rewrote `TPreprocessor.ProcessInclude` to recursively process included files instead of text replacement
- Added proper state save/restore for conditional compilation across includes
- Enhanced `TPreprocessor` with cycle detection, include depth guard, and performance metrics
- Updated `TParser` to correctly handle binary expression precedence and reject local variable declarations inside procedures
- Modified `TAST` destructors for proper polymorphism (virtual destructor)
- Updated `sslc.dpr` to implement `-I` include path flag and improved error handling
- Updated architecture documentation to include preprocessor in the compilation pipeline

### Added
- Full binary operation support in expressions: arithmetic (+, -, *, /, %), comparison (==, !=, <, >, <=, >=), logical (and, or)
- Preprocessor configuration options (`TPreprocessorOptions`) with verbose mode, max depth, and directive preservation
- Include cycle detection with `EPreprocessorError` exception
- Performance counters: `ProcessedIncludeCount`, `ProcessedLineCount`, `MacroExpansionCount`
- Comprehensive preprocessor guide (`docs/IX_PREPROCESSOR_GUIDE.md`) covering modular scripting, patterns, and optimization
- Modular example suite in `TestScripts/ModularExample/` demonstrating domain-based decomposition
- New test script: `simple.ssl`
- Include guards and macro scoping conventions in examples

### Technical Details

**Preprocessor Include Fix:**
The original `ProcessInclude` used `StringReplace` on the entire source text while iterating, causing infinite loops when includes referenced each other. The fixed version uses recursive file processing with explicit stack (`FIncludeStack`) and state save/restore (`InConditional`, `SkipUntilElse`, `ConditionalLevel`) around each recursive call. This correctly preserves conditional compilation state across file boundaries and prevents cycles via depth guard and cycle detection.

**Binary Ops Fix:**
The bytecode generator now correctly emits Fallout 2 VM opcodes:
```pascal
case BinOp.Op of
  tkPlus: FCurrentProc.AddOp(O_ADD);      // $8037
  tkMinus: FCurrentProc.AddOp(O_SUB);    // $8038
  tkMul: FCurrentProc.AddOp(O_MUL);      // $8039
  tkDiv: FCurrentProc.AddOp(O_DIV);      // $803A
  tkMod: FCurrentProc.AddOp(O_MOD);      // $803B
  tkEq: FCurrentProc.AddOp(O_EQUAL);    // $8031
  tkNe: FCurrentProc.AddOp(O_NOT_EQUAL);// $8032
  tkLt: FCurrentProc.AddOp(O_LESS);     // $8035
  tkGt: FCurrentProc.AddOp(O_GREATER);  // $8036
  tkLe: FCurrentProc.AddOp(O_LESS_EQUAL);   // $8033
  tkGe: FCurrentProc.AddOp(O_GREATER_EQUAL); // $8034
  tkAnd: FCurrentProc.AddOp(O_AND);     // $803C
  tkOr: FCurrentProc.AddOp(O_OR);       // $803D
end;
```

**Preprocessor Performance:**
Macro expansion is now O(L×M) with early-exit checks and cached macro keys.

## [1.0.0] - 2026-05-07

### Added
- Initial release
- Complete SSL parser with lexer, parser, AST, and bytecode generator
- Support for all Fallout 2 scripting constructs
- CLI compiler (`sslc.exe`)
- VCL GUI frontend (`FalloutCompiler.exe`)
- Built-in function database (100+ functions)
- Binary INT file writer
- Test scripts and examples

### Features
- Procedure declarations and calls
- Variable declarations (local and global)
- Control flow: if/then/else, while, for, switch/case
- Expressions: arithmetic, logical, comparison
- Function calls (built-in and user-defined)
- Comments: `/* */` and `//`
- Basic preprocessor support (limited before this fix)