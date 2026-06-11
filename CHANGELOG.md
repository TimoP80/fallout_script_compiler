# Changelog

All notable changes to the Fallout 2 SSL Compiler will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-06-11

### Added
- **FMF to SSL Converter** (`uFMFConverter.pas`) — Converts `.fmf` dialogue files (FMF Dialogue Tool format) into compilable `.ssl` scripts.
- **Auto-generated `.msg` files** — `FMFToMSG` generates companion `.msg` files with sequential message numbers for all `NPCText`/`playertext` strings using `{num}{}{text}` format.
- **Designer notes preserved as comments** — FMF `notes` fields are emitted as `// Designer notes:` and `// Option notes:` comments above nodes and options in the generated SSL.
- **Multiple template types** — `TTemplateType` enum (`dtBasic`, `dtTerminal`, `dtPushable`, `dtFloaters`, `dtTimeEvent`) controls which procedures and variables the generated script includes.
- **`-t` CLI flag** — Template type selection via `sslc -t <terminal|pushable|floaters|timeevent|time>` for FMF sources.
- **Timed event template** — Full `dtTimeEvent` implementation:
  - `TFloatNode` and `TTimeEvent` types with `Messages`/`CodeLines` parsing
  - `start` procedure with `add_timer_event` initialization (uses `DefaultEvent`)
  - `timed_event_p_proc` with `fixed_param` dispatch and automatic re-scheduling
  - Float node procedures using `floater_rand(FLMSG_First, FLMSG_Last)` for random message display
  - `LVAR_TimedEvent`, `FLMSG_*`, and `TE_*` macro defines
  - `TranslateTimeEventCode()` for `call X` → `X()` and `flush_add_timer_event_sec` → `add_timer_event` conversion
- **`floater_rand` builtin** (`$10A5`, 2 params) registered in `uBuiltins.pas`.

### Changed
- **`uCompiler.pas`** — `TCompiler.FMFTemplateType` property; `.msg` file written alongside `.ssl` for `.fmf` sources; `MsgSource` variable captures original FMF before `FMFToSSL` overwrites `Source`.
- **`sslc.dpr`** — Parses `-t` flag and sets `Compiler.FMFTemplateType`; accepts both `time` and `timeevent` aliases.
- **`uBuiltins.pas`** — Added `floater_rand` ($10A5, 2 params, return 0).

### Fixed
- `.msg` file was empty — `FMFToMSG` was called after `Source` had been overwritten by `FMFToSSL`; reordered to save original FMF source first.
- `-t timeevent` not accepted — CLI only matched `time`; added `timeevent` alias.
- `dtPushable` erroneously included floater logic in `talk_p_proc` — condition tightened from `dtFloaters, dtPushable` to `dtFloaters` only.
- Time event `code = {` brace-on-same-line parsing — `Trimmed.EndsWith('{')` check before brace-line search.
- Code block string parsing — `StripQuotes` reordered to strip trailing comma before quotes.

## [1.3.0] - 2026-06-09
### Fixed
- **Critical**: Parser infinite loop when `else` keyword appeared in block context — `ParseBlock` would loop forever because `ParseStatement` returned `nil` for `tkElse` but the token was never consumed.
- **Critical**: `TASTSwitchCase.Body` was never allocated (null pointer) — constructor only set `IsDefault := False`, causing access violation when any switch case was parsed.
- **ParseIfStatement** — Single-statement bodies after `then`/`else` were silently ignored (empty `TASTBlock` created instead of parsing the actual statement). Statements leaked into the parent block, and `else` was left unprocessed.
- **ParseWhileStatement** — Single-statement bodies after the while condition were ignored, same pattern as ParseIfStatement.
- **ParseForStatement** — Single-statement bodies after the for loop were ignored, same pattern.
- **ParseSwitchStatement** — `nil` results from `ParseStatement` inside case bodies were blindly added to the statement list, risking crashes in downstream consumers.
- **Lexer** — Unknown preprocessor directives (`#define`, `#ifdef`, `#ifndef`, `#else`, `#endif`, `#undef`) generated spurious errors when they reached the lexer (via `CompileString`), instead of being silently skipped.
- **Bytecode ExpressionStatement** — Incorrectly emitted `O_POP_TO_BASE`, `O_POP_BASE`, `O_POP_RETURN` (procedure epilogue opcodes) for every expression statement, corrupting the bytecode stack.

### Changed
- **uParser.pas**:
  - `ParseBlock` — Added `tkElse` to while-loop exit condition; added semicolon consumption after `Expect(tkEnd)` for `begin..end;` patterns.
  - `ParseIfStatement` — Now calls `ParseStatement` for single-statement then/else bodies with guard conditions against block boundary tokens.
  - `ParseWhileStatement` — Same single-statement body fix.
  - `ParseForStatement` — Same single-statement body fix.
  - `ParseSwitchStatement` — Now guards against nil from `ParseStatement` before adding to case body.
- **uAST.pas**:
  - `TASTSwitchCase.Body` is now initialized to `TASTBlock.Create(0, 0)` in the constructor.
  - Constructor calls `inherited Create`; destructor changed from `virtual` to `override` and calls `inherited`.
- **uBytecode.pas**:
  - `GenerateStatement` for `TASTExpressionStatement` now emits `O_POP` to clean the stack instead of spurious procedure epilogue.
- **uLexer.pas**:
  - Unknown `#` directives are now silently skipped (rest-of-line consumed) instead of generating errors.
- **sslc.dpr**:
  - Moved `{$I version.inc}` after the `uses` clause for Delphi compatibility (const declarations can't precede uses).
  - Added conditional compilation guards for the `Windows` unit.

### Added
- **Switch test scripts** — 8 new edge-case test scripts in `TestScripts/`:
  - `switch_basic.ssl` — Basic switch with case, default, break
  - `switch_multi_case.ssl` — 4 separate cases with different branches
  - `switch_fallthrough.ssl` — Shared case body (`case 0: case 1:`)
  - `switch_no_breaks.ssl` — Full fall-through (no break statements)
  - `switch_only_default.ssl` — Default-only switch
  - `switch_multi_stmt.ssl` — Multiple statements per case without begin/end
  - `switch_nested_if.ssl` — Nested if-else inside a case
  - `switch_with_start.ssl` — Switch called from a `start` procedure
- **Programmatic test harness** (`test_programmatic.dpr`) — 40 tests across 8 categories covering the full compiler pipeline (lexer, parser, bytecode gen) using `TCompiler.CompileString` against inline SSL sources.

## [1.2.0] - 2026-05-21

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
- **Critical**: Preprocessor infinite loop when processing `#include` directives
  - The original implementation used `StringReplace` to replace include lines in the entire source text
  - This caused an infinite loop when processing files with multiple includes
  - Fixed by refactoring to use recursive processing with proper state management
  - Conditional compilation state (`#ifdef`/`#ifndef`/`#else`/`#endif`) is now correctly preserved across nested includes
- Incorrect binary operation opcodes in `uBytecode.pas` (hardcoded values misaligned with Fallout 2 VM spec)
  - Replaced hardcoded hex constants with proper `O_*` definitions from `uBuiltins.pas`
  - Removed duplicate opcode constant definitions, now uses single source of truth

### Changed
- `TBytecodeGenerator` carries a new `FReachable` field (`TDictionary<string, Boolean>`) and `ComputeReachable()` method; `Create`/`Destroy` updated to initialise and free it; `Generate` signature unchanged (backward-compatible API contract).
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