# Changelog

All notable changes to the Fallout 2 SSL Compiler will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-06-14

### Added
- **Direct sfall opcode emission for builtins** — Each builtin function in `uBuiltins.pas` now carries an `SfallOpcode` field, mapping the SSL name directly to the corresponding Fallout 2 engine opcode from `opextra.h` / `oplib.h`. The bytecode generator emits the direct opcode instead of going through `O_LOOKUP_STRING_PROC` + `O_CALL` for any builtin with a known sfall mapping.
- **`O_NAMEREF` opcode** (`$9001`, defined as `O_STRINGOP or 1`) — A new opcode encoding a 4-byte offset into the script's name table. Used for procedure references, global variable references, and string literals whose targets live in the name list rather than the string list.
- **Complete Fallout 2 engine opcode coverage** in `uBuiltins.pas`:
  - **Library opcodes** (`oplib.h`, `O_SAYQUIT`..`O_TOKENIZE`): dialogue (`say_*`), windows (`create_win`, `delete_win`, `select_win`, `resize_win`, `scale_win`, `show_win`, `fill_win*`, `fill_rect`), display (`display`, `display_gfx`, `display_raw`, `load_palette_table`, `fade_in`, `fade_out`, `goto_xy`, `print`, `format`, `print_rect`, `set_font`, `set_text_flags/color/highlight_color`), movie (`play_movie`, `stop_movie`, `play_movie_rect`, `play_movie_alpha*`), regions (`add_region*`, `delete_region`, `activate_region`, `check_region`), buttons (`add_button*`, `delete_button`), mouse (`hide_mouse`, `show_mouse`, `mouse_shape`, `refresh_mouse`, `set_global_mouse_func`), named events (`add_named_event`, `add_named_handler`, `clear_named`, `signal_named`), keys (`add_key`, `delete_key`), sound (`sound_play/pause/resume/stop/rewind/delete`, `set_one_opt_pause`), file/token utilities (`select_file_list`, `tokenize`).
  - **Engine opcodes** (`opextra.h`, `O_GIVE_EXP_POINTS`..`O_CRITTER_STOP_ATTACK`): object queries (`obj_name`, `obj_pid`, `obj_art_fid`, `obj_can_see_obj`, `obj_can_hear_obj`, `obj_type`, `obj_item_subtype`), critter (`get_critter_stat`, `set_critter_stat`, `critter_heal/dmg/state/injure`, `critter_attempt_placement`, `critter_add_trait/rm_trait`, `critter_mod_skill`, `critter_inven_obj`, `critter_is_fleeing`, `critter_set_flee`, `critter_stop_attacking`), inventory (`add_obj_to_inven`, `rm_obj_from_inven`, `add_mult_objs`, `rm_mult_objs`, `wield_obj_critter`, `use_obj`, `inven_unwield`, `move_obj_inven`, `pickup_obj`, `drop_obj`, `destroy_object`, `destroy_mult_objs`, `use_obj_on_obj`), map/world (`tile_*`, `world_map`, `set_map_start`, `override_map_start`, `set_map_music`, `load_map`, `set_exit_grids`, `elevation`, `cur_map_index`, `days_since_visited`), combat/AI (`attack`, `attack_complex`, `attack_setup`, `combat_is_initialized`, `combat_difficulty`, `terminate_combat`, `difficulty_level`), dialogue (`start_gdialog`, `end_dialogue`, `dialogue_system_enter`, `gsay_*`, `giq_option`, `gdialog_set_barter_mod`, `dialogue_reaction`, `metarule`, `metarule3`), time/events (`game_time*`, `game_ticks`, `add_timer_event`, `rm_timer_event`, `fix_timer_event` — note: `fix_timer_event` still uses string-proc lookup), radiation (`radiation_inc/dec`), scripts (`script_action`, `script_overrides`), object lifecycle (`kill_critter/type`, `poison/get_poison`), UI/game (`game_ui_disable/enable/is_disabled`, `gfade_in/out`, `endgame_slideshow/movie`), bartering (`set_barter_mod`, `item_caps_total`, `item_caps_adj`), registration anims (`reg_anim_*`), sfx builders (`sfx_build_*`, `play_sfx`), misc (`anim`, `anim_busy`, `art_anim`, `anim_action_frame`, `make_daytime`, `set_light_level`, `obj_set_light_level`, `explosion`, `play_gmovie`, `rotation_to_tile`, `jam_lock`, `obj_on_screen`, `obj_is_locked/open`, `obj_lock/unlock/open/close`, `running_burning_guy`), and all of the `self_obj`/`source_obj`/`target_obj`/`dude_obj`/`party_*` family.
- **`FindSfallOpcode` method** on `TBuiltinDatabase` — Looks up a builtin by name and returns its `SfallOpcode` (or `0` for builtins that still fall back to the string-proc lookup path).
- **`AddNameRef` method** on `TProcedureBytecode` — Records a name (procedure, global var, or string) to be added to the script's name table.
- **`GenerateSfallBuiltinCall` method** on `TBytecodeGenerator` — Emits a direct engine opcode for builtin calls that have an `SfallOpcode` mapping, avoiding the runtime `LOOKUP_STRING_PROC` indirection.
- **Identifier-resolution helpers** in `uBytecode.pas`:
  - `ScanStatementForProcs` / `ScanExpressionForProcs` / `ScanArgsForProcs` / `CollectIdentifiers` — Recursive walkers that discover all identifiers referenced by an expression or statement, used by the reachability analyser and the global-variable collector.
- **`FNameRefs` and `FCurrentProcLocals` fields** on `TBytecodeGenerator` — Track name-table references emitted by the current procedure and the local variables it declares, respectively.
- **Name-list output in INT writer** — `TINTWriter.Save` now writes a dedicated name list (procedures + global variables + `O_NAMEREF` targets) alongside the existing string list, with the dummy `..............` 14-character padding entry at index 0.

### Changed
- **`uBuiltins.pas` — opcode numbering shift**:
  - Reorganised the core opcodes so that `O_POP_TO_BASE` (`$802A`) and `O_PUSH_BASE` (`$802B`) no longer collide with `O_POP_BASE` (`$8029`). `O_PUSH_BASE` is now `O_OPERATOR + 43` (was `41`), `O_POP_TO_BASE` is now `O_OPERATOR + 42` (was `40`), `O_POP_BASE` remains at `O_OPERATOR + 41`. The new `O_END_CORE` is `O_OPERATOR + 76`; library/engine opcodes are now derived from `O_END_CORE` and `O_END_LIB` (was: directly from `O_OPERATOR + 39..`).
  - `O_CHECK_ARG_COUNT`, `O_LOOKUP_STRING_PROC`, `O_SET_GLOBAL`, `O_FETCH_PROC_ADDRESS`, `O_DUMP`, `O_IF`, `O_WHILE`, `O_STORE`, `O_FETCH`, and all comparison/arithmetic opcodes shifted by `−2` to make room for the new `O_PUSH_BASE` and `O_POP_TO_BASE` slot separation.
  - **`TBuiltinFunction` record** now has a 5th field, `SfallOpcode: Word`, with `RegisterFunction` extended to accept an optional 5th parameter (`ASfallOpcode: Word = 0`).
  - **All builtin registrations** in `InitializeFallout2Builtins` updated to pass their sfall opcode where one exists. The second duplicate set (IDs `$1000`..`$10A5`) is retained as a legacy compatibility shim for callers that still use the historical ID.
- **`uBytecode.pas` — bytecode generation**:
  - **String-literal emission** now goes through `O_NAMEREF` (name table) instead of `O_STRINGOP` (string table). Each emitted string literal is added to `FNameRefs` so the INT writer can include it in the name list.
  - **Identifier expressions** (`TASTIdentifier`) now resolve in the order: local variable → global variable → procedure name. Procedures resolved by name are added via `AddNameRef` and emitted as `O_NAMEREF`.
  - **`TASTFunctionCall`** generation now branches on `Builtin.SfallOpcode`: when non-zero, `GenerateSfallBuiltinCall` emits the direct engine opcode; otherwise it falls back to the original `O_LOOKUP_STRING_PROC` + `O_CALL` sequence.
- **`uINTWriter.pas` — INT binary format**:
  - `TINTWriter` now takes a fourth parameter, `ANameRefs: TList<string>`, on `Save`. All name-table targets (procedures, globals, and `O_NAMEREF` strings) are emitted in a single name list before the string list.
  - New `WriteNameList` helper writes the standard `[size][entries…][$FFFFFFFF]` layout used by both the name list and the string list, with ASCII NUL termination and even-padded entry lengths.
  - `Save` now patches the startup-code placeholder (at `StartAddrPos`) to point at the init code and patches the init code's `O_JMP` target to the start procedure's body offset, instead of relying on a hard-coded sequence.
  - Procedure bodies are written with full prologue/epilogue already present on `Proc.Instructions`; the writer no longer injects them. `O_INTOP` is rendered as a 4-byte integer operand (`$C001` + value); `O_STRINGOP` and `O_NAMEREF` are rendered as opcode + 4-byte name/string-list offset.
- **`test_programmatic.dpr`** — `uses` clause switched to namespaced units (`System.SysUtils`, `System.Classes`); trailing `ReadLn` pause prompt removed for cleaner CI/scripted runs.

### Fixed
- **O_POP_TO_BASE / O_PUSH_BASE collision** — `O_POP_TO_BASE` and `O_PUSH_BASE` both had the same value as `O_POP_BASE` (`$8029`) in the old numbering, causing the bytecode generator's epilogue to be indistinguishable from the local-scope-restore opcode. Resolved by giving each opcode a distinct slot (`$802A`, `$802B`, `$8029` respectively).
- **Builtin calls going through runtime string lookup** — Builtins that have a direct engine opcode were always being emitted as `O_LOOKUP_STRING_PROC("display_msg", …) + O_CALL`, forcing a runtime hashtable lookup. The new direct-opcode path eliminates the lookup and produces a smaller, faster `.int`.
- **String literals sharing slots with procedure names** — Both string literals and procedure names were being written to a single string list, which prevented the engine from resolving them as name references. They now live in separate name and string lists with the correct opcode (`O_NAMEREF` vs `O_STRINGOP`).
- **Reachability analyser missing indirect calls** — `ComputeReachable` previously only followed direct `TASTProcedureCall` nodes. The new `ScanExpressionForProcs` / `ScanArgsForProcs` helpers ensure that procedure names appearing inside any expression (e.g. as callback arguments) are also discovered, so the call graph stays correct.

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
- **Lexer** — `variable` keyword now recognized as `tkVar` (alias for `var`).
- **Lexer** — `=` is now `tkEq` (equality); `:=` is `tkAssign` (assignment).
- **`uParser.pas`** — `FLoopDepth` tracking prevents `break` from being used outside of loops or switch statements.
- **`uParser.pas`** — `for` loop now accepts both `:=` and `=` for the assignment operator.
- **Test harness** (`test_programmatic.dpr`) — Updated all test cases for new syntax: parenthesized conditions, `:=` assignment, `var` keyword.

### Fixed
- `.msg` file was empty — `FMFToMSG` was called after `Source` had been overwritten by `FMFToSSL`; reordered to save original FMF source first.
- `-t timeevent` not accepted — CLI only matched `time`; added `timeevent` alias.
- `dtPushable` erroneously included floater logic in `talk_p_proc` — condition tightened from `dtFloaters, dtPushable` to `dtFloaters` only.
- Time event `code = {` brace-on-same-line parsing — `Trimmed.EndsWith('{')` check before brace-line search.
- Code block string parsing — `StripQuotes` reordered to strip trailing comma before quotes.
- **FMF parser robustness** — All brace detection (`{` / `}`) now uses `Pos()` instead of standalone `Trimmed =` comparisons, handling inline braces throughout the parser (Node header, Node body, options block, conditions block, FloatNode header, TimeEvent code block, and ParseStringList).
- **FMF parser content-before-brace ordering** — `notes`/`is_wtg` checked before `{` in Node header; `NPCText`/`NPCFemaleText` checked before `}` in Node body (prevents false positives when content literally contains braces).
- **FMF parser trailing brace stripping** — `notes` lines with trailing `{` (e.g., `notes "text" {`) now strip the brace before storing, preventing the node body opening brace from being consumed.
- **FMF parser empty-node skipping** — `Node ""` and `Floatnode ""` entries (FMF designer tool artifacts) are now skipped during parsing with proper brace-depth counting.
- **FMF parser empty/malformed TimeEvent skipping** — TimeEvents without a `code =` block are skipped; unrecognized lines in the property loop trigger a safety break to prevent consuming subsequent content.
- **FMF parser `= → :=`** — Generated SSL now uses `:=` for assignment matching the lexer change (`=` is now equality).

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