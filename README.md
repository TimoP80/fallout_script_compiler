# Fallout 2 SSL Compiler (sslc)

A native Delphi/Object Pascal implementation of a Fallout 2 SSL script compiler that produces binary-compatible .int files.

## Features

- **Complete SSL Parser** - Handles all Fallout 2 scripting syntax
- **Lexer/Tokenizer** - Full lexical analysis with error reporting
- **AST Generation** - Clean Abstract Syntax Tree architecture
- **Bytecode Generator** - Produces Fallout 2 virtual machine opcodes
- **INT File Writer** - Creates binary-compatible .int files
- **Built-in Function Database** - Supports 100+ Fallout 2 script functions
- **Preprocessor** - Supports `#include`, `#define`, `#ifdef`/`#ifndef`/`#else`/`#endif`
- **CLI Compiler** - Command-line interface (`sslc.exe`)
- **VCL GUI** - Optional Windows GUI frontend

## Supported Syntax

```pascal
procedure start begin
  display_msg("Hello Wasteland");
end

if (local_var(0) == 1) then begin
  give_exp_points(100);
end

while (counter < 10) do begin
  counter := counter + 1;
end

switch (flag_value) begin
  case 1: display_msg("Case 1"); break;
  case 2: display_msg("Case 2"); break;
  default: display_msg("Default");
end
```

## Preprocessor Directives

The compiler supports C-style preprocessor directives:

```pascal
#define NPC_REACTION_VAR 7
#include "headers/define.h"

#ifdef DEBUG_MODE
  display_msg("Debug mode enabled");
#endif
```

- `#define` / `#undef` - Define/remove macros
- `#include` - Include other script files (both `"file"` and `<file>` syntax)
- `#ifdef` / `#ifndef` / `#else` / `#endif` - Conditional compilation

### Preprocessor Options

The preprocessor supports configuration via `TPreprocessorOptions`:

- **Verbose** - Emits trace messages during processing (useful for debugging include chains and macro expansion)
- **MaxIncludeDepth** - Maximum nesting depth (default: 64), prevents runaway recursion
- **PreserveDirectives** - Keeps preprocessor directives as comments in output for source mapping

The preprocessor also includes **include cycle detection** and **performance counters** (`ProcessedIncludeCount`, `ProcessedLineCount`, `MacroExpansionCount`).

## Building

### Requirements

- Delphi 12 Athens or newer (Win64 target)
- Windows 10/11

### CLI Compiler

1. Open `sslc.dproj` in Delphi IDE
2. Select **Win64** platform
3. Build (Shift+F9)
4. Output: `bin\sslc.exe`

### GUI Version

1. Open `FalloutCompiler.dproj` in Delphi IDE
2. Select **Win64** platform
3. Build (Shift+F9)
4. Output: `bin\FalloutCompiler.exe`

## Usage

### CLI

```bash
# Compile single file
sslc.exe script.ssl

# Specify output directory
sslc.exe -o output\ script.ssl

# Add include path for #include resolution
sslc.exe -I headers\ script.ssl

# Verbose output (shows preprocessor trace)
sslc.exe -v script.ssl
```

### GUI

1. Run `FalloutCompiler.exe`
2. Click **Open** to load an .ssl file
3. Click **Compile** to compile
4. View output in the right panel

## Architecture

```
Source (.ssl)
    ↓
[Preprocessor] → Processed source (macros expanded, includes resolved)
    ↓
[TLexer] → Tokens
    ↓
[TParser] → AST (Abstract Syntax Tree)
    ↓
[TBytecodeGenerator] → Bytecode
    ↓
[TINTWriter] → Binary .int file
```

## Unit Structure

| Unit | Description |
|------|-------------|
| `uBuiltins.pas` | Built-in function database and opcode definitions |
| `uLexer.pas` | Tokenizer for SSL syntax |
| `uAST.pas` | Abstract Syntax Tree node types |
| `uParser.pas` | SSL parser producing AST |
| `uBytecode.pas` | Bytecode generator |
| `uINTWriter.pas` | Binary INT file writer |
| `uPreprocessor.pas` | C-style preprocessor (`#include`, `#define`, `#ifdef`, cycle detection, macro scoping) |
| `uCompiler.pas` | Main compiler orchestration |
| `sslc.dpr` | CLI entry point |
| `FalloutCompiler.dpr` | GUI entry point |

## Compatibility

Generated .int files are compatible with:
- Fallout 2 (original)
- Fallout Et Tu (UP+)
- sfall / mods using standard INT format

## Test Scripts

Example scripts are in `TestScripts\`:
- `hello.ssl` - Basic display message
- `variables.ssl` - Variable usage and conditionals
- `skillcheck.ssl` - Skill check example
- `test_include.ssl` - Include directive example

## License

MIT License

## Notes

This is a functional compiler, not a mock implementation. All systems are designed for real Fallout 2 modding workflows.

## Recent Changes

**v1.1.0 (2026-05-13)** — see [CHANGELOG.md](CHANGELOG.md) for full details.

Key highlights:
- **Preprocessor rewrite**: Recursive include processing with cycle detection, configurable options, and performance metrics
- **Binary expression support**: Full arithmetic, comparison, and logical operators with correct Fallout 2 VM opcodes
- **CLI `-I` flag**: Specify include paths for `#include` resolution
- **Bug fixes**: Preprocessor infinite loop on nested includes, incorrect opcode constants, local variable scope issues