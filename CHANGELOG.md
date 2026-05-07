# Changelog

All notable changes to the Fallout 2 SSL Compiler will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] - 2026-05-07

### Fixed
- **Critical**: Preprocessor infinite loop when processing `#include` directives
  - The original implementation used `StringReplace` to replace include lines in the entire source text
  - This caused an infinite loop when processing files with multiple includes
  - Fixed by refactoring to use recursive processing with proper state management
  - Conditional compilation state (`#ifdef`/`#ifndef`/`#else`/`#endif`) is now correctly preserved across nested includes

### Changed
- Refactored `TPreprocessor.ProcessFile` from `for` loop to `while` loop with manual index management
- Rewrote `TPreprocessor.ProcessInclude` to recursively process included files instead of text replacement
- Added proper state save/restore for conditional compilation across includes
- Updated architecture documentation to include preprocessor in the compilation pipeline

### Added
- Preprocessor now fully supports:
  - `#include` directives (both `"file"` and `<file>` syntax)
  - `#define` / `#undef` for macro definitions
  - `#ifdef` / `#ifndef` / `#else` / `#endif` for conditional compilation
- Updated README with preprocessor documentation and usage examples
- Added `test_include.ssl` to TestScripts directory

### Technical Details

**Before (Broken):**
```pascal
// ProcessInclude used StringReplace on entire text
Lines.Text := StringReplace(Lines.Text, Line, IncludeContent, [rfReplaceAll]);
// This modified the text being iterated, causing infinite loops
```

**After (Fixed):**
```pascal
// ProcessInclude recursively processes included file
// State is saved before and restored after processing
SavedInConditional := InConditional;
SavedSkipUntilElse := SkipUntilElse;
SavedConditionalLevel := ConditionalLevel;
try
  ProcessFile(IncludeContent, ExtractFilePath(IncludePath), Output,
    InConditional, SkipUntilElse, ConditionalLevel);
finally
  // Restore parent file's state
  InConditional := SavedInConditional;
  SkipUntilElse := SavedSkipUntilElse;
  ConditionalLevel := SavedConditionalLevel;
end;
```

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