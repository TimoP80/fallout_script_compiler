# IX Preprocessor: Comprehensive Technical Guide

## Table of Contents

1. [Introduction](#1-introduction)
2. [Architecture Overview](#2-architecture-overview)
3. [Core Directives Reference](#3-core-directives-reference)
4. [Modularizing Large Scripts](#4-modularizing-large-scripts)
5. [Managing Preprocessor Directives Across Multiple Files](#5-managing-preprocessor-directives-across-multiple-files)
6. [Namespace Collision Prevention](#6-namespace-collision-prevention)
7. [Conditional Compilation Patterns](#7-conditional-compilation-patterns)
8. [Code Readability and Debuggability](#8-code-readability-and-debuggability)
9. [Performance Optimization](#9-performance-optimization)
10. [Practical Examples: Monolithic to Modular](#10-practical-examples-monolithic-to-modular)
11. [Advanced Patterns](#11-advanced-patterns)
12. [Common Pitfalls and Troubleshooting](#12-common-pitfalls-and-troubleshooting)

---

## 1. Introduction

The IX Preprocessor is a C-style text preprocessor built into the Fallout 2 SSL Compiler (`sslc`). It operates as the first stage of the compilation pipeline, transforming source `.ssl` files through macro expansion, file inclusion, and conditional compilation before the lexer and parser process the resulting text.

### Preprocessor Pipeline

```
Source (.ssl)                   ← Raw authoring with directives
       ↓
[ TPreprocessor.Process ]       ← Directive resolution, include recursion
       ↓
[ TPreprocessor.ExpandMacros ]  ← Final macro text substitution
       ↓
Preprocessed source             ← Clean SSL ready for lexing
       ↓
[ TLexer ] → [ TParser ] → [ TBytecodeGenerator ] → [ TINTWriter ]
```

### Key Implementation File

All preprocessor logic resides in a single unit:

- **`uPreprocessor.pas`** (365 lines) — The complete `TPreprocessor` class

Understanding this file is essential for effective use of the preprocessor.

---

## 2. Architecture Overview

### 2.1 Internal State

The `TPreprocessor` class maintains three pieces of private state:

```pascal
FMacros: TDictionary<string, string>;    // Active macro definitions
FIncludePaths: TList<string>;            // Search paths for #include
FDefines: TList<string>;                 // Predefined macro names (defined externally)
```

### 2.2 Processing Model

The preprocessor uses a **single-pass, recursive** model:

1. **`Process(Source, BasePath)`** — Entry point. Creates a `TStringList`, delegates to `ProcessFile`, then calls `ExpandMacros` on the collected output.
2. **`ProcessFile(Source, BasePath, Output, ...)`** — Line-by-line scan. Recognized directives are handled inline; all other lines are appended to the `Output` list.
3. **`ProcessInclude(...)`** — When `#include` is encountered, the file is loaded, and `ProcessFile` is called **recursively**. Conditional state is saved/restored around the recursive call.
4. **`ExpandMacros(Source)`** — After all includes are resolved, a final pass replaces all macro keys with their values across the entire collected text.

### 2.3 Critical Design Property: Two-Phase Operation

The preprocessor strictly separates **directive processing** from **macro expansion**:

- **Phase 1 (ProcessFile/Process):** Resolves `#include`, `#define`, `#ifdef`, `#ifndef`, `#else`, `#endif`, `#undef`. Produces a clean text stream with directives removed.
- **Phase 2 (ExpandMacros):** Performs all text substitution on the Phase 1 output.

This means macros are **not** expanded during directive processing. A `#define` inside an `#ifdef` block that is skipped will still be active if the condition changes later. This is by design and matches C preprocessor semantics.

---

## 3. Core Directives Reference

### 3.1 `#define`

```ssl
#define MACRO_NAME value
```

Defines a macro. If `value` is omitted, the macro is defined as empty. Macros are stored in `FMacros` and can be redefined at any point (last definition wins).

```pascal
// Implementation
procedure TPreprocessor.ProcessDefine(const Line: string);
```

### 3.2 `#undef`

```ssl
#undef MACRO_NAME
```

Removes a macro from `FMacros`. Subsequent uses of the macro name will not be expanded.

### 3.3 `#include`

```ssl
#include "relative/path/file.h"
#include <library_file.h>
```

Both quoted (`"..."`) and angle-bracket (`<...>`) syntax are supported. The resolution order is:

1. Relative to the current file's directory (`BasePath`)
2. Relative to each path in `FIncludePaths` (in order)

**Critical behavior:** Include processing is **recursive** — included files can contain their own `#include` directives. Conditional state is preserved across include boundaries.

### 3.4 `#ifdef` / `#ifndef` / `#else` / `#endif`

```ssl
#ifdef DEBUG_MODE
  // only compiled if DEBUG_MODE is defined
#else
  // compiled if DEBUG_MODE is not defined
#endif

#ifndef ALREADY_INCLUDED
#define ALREADY_INCLUDED
// inclusion guard content
#endif
```

Conditional nesting is supported via a `ConditionalLevel` counter. The preprocessor tracks:
- `InConditional: Boolean` — Are we inside any `#ifdef`/`#ifndef` block?
- `SkipUntilElse: Boolean` — Should lines be skipped until `#else`?
- `ConditionalLevel: Integer` — Current nesting depth

---

## 4. Modularizing Large Scripts

### 4.1 The Problem

A monolithic Fallout 2 script (like `NHMYRON.SSL` at 2016 lines) presents severe challenges:

- **Navigation:** Finding specific procedures in 2000+ lines is impractical
- **Collaboration:** Multiple authors cannot work on the same file concurrently
- **Testing:** Individual script sections cannot be tested in isolation
- **Compilation:** Full recompilation on every change, regardless of scope
- **Reuse:** Common definitions are copy-pasted across scripts

### 4.2 The Preprocessor Solution: Domain-Based Decomposition

The key insight is that Fallout 2 scripts have a well-defined structure that maps naturally to modular decomposition:

```
Monolithic Script
├── Header Block (script ID, version, includes)
├── Forward Declarations
├── Start Procedure
├── Spatial Procedure
├── Description Procedure
├── Pickup Procedure
├── ──────────────────────
│   Domain: COMBAT
├── Combat Procedure      ← Extract to combat.ssl
├── Damage Procedure      ← Extract to combat.ssl
├── Push Procedure        ← Extract to combat.ssl
│   ──────────────────────
│   Domain: DIALOGUE
├── Talk Procedure        ← Extract to dialogue.ssl
├── Use Skill on Procedure← Extract to dialogue.ssl
├── Node Procedures       ← Extract to dialogue_nodes.ssl
│   ──────────────────────
│   Domain: MAP STATE
├── Map Enter Procedure   ← Extract to map_state.ssl
├── Map Update Procedure  ← Extract to map_state.ssl
└── Timed Event Procedure ← Extract to map_state.ssl
```

### 4.3 Implementation Pattern: Assembly via Include

Create a **master script** that assembles domain modules:

```ssl
// scripts/npc_dialogue_master.ssl
// ============================================================
// MASTER SCRIPT: Assembles all modular procedure blocks
// ============================================================

#include "config/npc_defines.h"
#include "headers/SCRIPTS.H"
#include "headers/COMMAND.H"

// Forward declarations for all procedures
procedure start;
procedure critter_p_proc;
procedure pickup_p_proc;
procedure talk_p_proc;
procedure destroy_p_proc;

// Include domain-specific procedure implementations
#include "procedures/combat_procedures.ssl"
#include "procedures/dialogue_procedures.ssl"
#include "procedures/node_procedures.ssl"

// Master start procedure (inline, not extracted)
procedure start begin
  // Initialization code
end
```

Each included file contains **only the procedure bodies** for its domain:

```ssl
// procedures/dialogue_procedures.ssl
// ============================================================
// DIALOGUE PROCEDURES
// ============================================================

procedure talk_p_proc begin
  // Dialogue logic here
  if (local_var(0) == 0) then begin
    call Node001;
  end else begin
    call Node101;
  end
end
```

### 4.4 Implementation Pattern: Script-Specific Configuration

```ssl
// config/npc_defines.h
// ============================================================
// Per-Script Configuration
// Override these before including master script
// ============================================================

// Required: script identity
#ifndef SCRIPT_NAME
  #define SCRIPT_NAME SCRIPT_NHMYRON
#endif

// Required: town reputation variable
#ifndef TOWN_REP_VAR
  #define TOWN_REP_VAR GVAR_TOWN_REP_NEW_RENO
#endif

// Optional: enable debug logging
//#define DEBUG_DIALOGUE

// Optional: enable combat logging
#define DEBUG_COMBAT
```

Then in the master script:

```ssl
// scripts/npc_dialogue_master.ssl
#include "config/npc_defines.h"
#include "headers/SCRIPTS.H"

// Now SCRIPT_NAME and TOWN_REP_VAR are available globally
```

---

## 5. Managing Preprocessor Directives Across Multiple Files

### 5.1 Header File Organization

Organize `#include` paths by function:

```
project/
├── config/              ← Per-script overrides
│   └── npc_defines.h
├── headers/             ← Shared constant libraries (project-supplied)
│   ├── DEFINE.H
│   ├── COMMAND.H
│   ├── SCRIPTS.H
│   └── GLOBAL.H
├── procedures/          ← Domain-specific script modules
│   ├── combat_procedures.ssl
│   ├── dialogue_procedures.ssl
│   └── node_procedures.ssl
├── lib/                 ← Shared utility modules
│   ├── debug_utils.ssl
│   └── common_macros.h
└── scripts/             ← Master assembly scripts (compile targets)
    └── npc_master.ssl
```

### 5.2 Include Path Configuration

Register include paths at the compiler level:

```pascal
// In the CLI entry point or build system
Compiler := TCompiler.Create;
Compiler.AddIncludePath('config');
Compiler.AddIncludePath('headers');
Compiler.AddIncludePath('procedures');
Compiler.AddIncludePath('lib');
```

Or at the code level within a master script:

```ssl
// Multiple include syntaxes work:
#include "headers/COMMAND.H"        // Relative to script location
#include "procedures/combat.ssl"    // Relative to script location
```

### 5.3 Directive Ordering Rules

Follow a strict ordering convention to prevent subtle bugs:

```ssl
// ============================================================
// CORRECT ORDERING
// ============================================================

// 1. Include guards (prevent double-inclusion of headers)
//    Handled automatically by #ifndef guards in .h files

// 2. Global configuration macros
#define DEBUG_MODE
#define NPC_ID SCRIPT_NHMYRON

// 3. Header includes (constants, function IDs)
#include "headers/SCRIPTS.H"
#include "headers/COMMAND.H"

// 4. Library includes (utility procedures)
#include "lib/debug_utils.ssl"

// 5. Forward declarations
procedure start;
procedure talk_p_proc;

// 6. Procedure implementations
#include "procedures/dialogue_procedures.ssl"

// 7. Master procedure blocks
procedure start begin
  // ...
end
```

### 5.4 Shared Macro Libraries

Create reusable macro packages:

```ssl
// lib/common_macros.h
// ============================================================
// COMMON MACRO LIBRARY
// ============================================================

// Debug printing helper
#ifdef DEBUG_MODE
  #define DEBUG_MSG(msg) display_msg(msg)
#else
  #define DEBUG_MSG(msg)
#endif

// Common animation sequences
#define ANIM_STAND   100
#define ANIM_WALK    101
#define ANIM_RUN     102
#define ANIM_FIRE    103
#define ANIM_DIE     104

// Standard skill macros
#define SKILL_SMALL_GUNS   (0)
#define SKILL_BIG_GUNS     (1)
#define SKILL_ENERGY_WEAPONS (2)
#define SKILL_UNARMED      (3)
```

### 5.5 Macro Scoping Convention

Use prefixed naming to prevent collisions in shared headers:

```ssl
// GOOD: Prefixed macro names
#define COMBAT_CRITICAL_CHANCE  (30)
#define DIALOGUE_PERSUASION_MOD (5)
#define MAP_EXIT_GRID_X        (150)
#define MAP_EXIT_GRID_Y        (200)

// BAD: Generic names that collide
#define CHANCE     (30)    // Too generic — collisions likely
#define MOD        (5)     // Too generic
#define EXIT_X     (150)   // May collide in map scripts
```

---

## 6. Namespace Collision Prevention

### 6.1 The Problem

In a large codebase with dozens of scripts sharing headers, macro name collisions are inevitable. The preprocessor's simple `StringReplace`-based expansion (`ExpandMacros`) means that any identifier matching a macro key gets replaced, regardless of context.

### 6.2 Naming Convention Strategy

Establish and enforce a prefix-based naming convention:

| Prefix | Domain | Example |
|--------|--------|---------|
| `SCRIPT_` | Script IDs | `SCRIPT_NHMYRON` |
| `GVAR_` | Global variables | `GVAR_TOWN_REP` |
| `LVAR_` | Local variables | `LVAR_NPC_STATE` |
| `BONUS_` | Skill bonuses | `BONUS_LOCKPICK` |
| `PERK_` | Perk IDs | `PERK_bonus_hth_attacks` |
| `TRAIT_` | Trait IDs | `TRAIT_PERK` |
| `COMBAT_` | Combat constants | `COMBAT_CRIT_CHANCE` |
| `DMG_` | Damage types | `DMG_NORMAL` |
| `ITEM_` | Item definitions | `ITEM_stimpak` |
| `MAP_` | Map-specific | `MAP_EXIT_GRID_X` |
| `ANIM_` | Animation frames | `ANIM_STAND` |

### 6.3 Include Guard Idiom

Every header file **must** use include guards to prevent double-inclusion:

```ssl
// headers/BONUS.H — CORRECT
#ifndef BONUS_H
#define BONUS_H

#define BONUS_Lockpicks          (10)
#define BONUS_Super_Tool_Kit     (20)

#endif
```

The `TPreprocessor` supports `#ifndef`/`#define`/`#endif` correctly, including nested state tracking.

### 6.4 Hierarchical Guard Pattern

For complex projects with headers that include other headers:

```ssl
// Define the master guard
#ifndef PROJECT_DEFS_H
#define PROJECT_DEFS_H

  // Inner guards still needed in case of direct inclusion
  #ifndef _SCRIPT_IDS_H
  #define _SCRIPT_IDS_H
  #define SCRIPT_OBJ_DUDE     (1)
  #define SCRIPT_NHMYRON      (2000)
  #endif

  #ifndef _GVAR_IDS_H
  #define _GVAR_IDS_H
  #define GVAR_TOWN_REP       (220)
  #define GVAR_KARMA          (300)
  #endif

#endif
```

### 6.5 Undef-and-Redefine Guard

When a macro's meaning must change between sections:

```ssl
#define DAMAGE_TYPE DMG_NORMAL
// ... use DAMAGE_TYPE ...

#undef DAMAGE_TYPE
#define DAMAGE_TYPE DMG_EXPLOSION
// ... use DAMAGE_TYPE with new meaning ...

#undef DAMAGE_TYPE  // Clean up when done
```

---

## 7. Conditional Compilation Patterns

### 7.1 Basic Pattern

```ssl
#ifdef DEBUG_MODE
  // Debug-only code
  display_msg("Debug: NPC state = " + local_var(0));
#endif
```

### 7.2 If/Else Pattern

```ssl
#ifdef FULL_GAME
  #include "content/full_game_dialogue.ssl"
#else
  #include "content/demo_dialogue.ssl"
#endif
```

### 7.3 Feature Toggle Pattern

Compile different behavior for different build targets:

```ssl
// config/build_target.h
#define TARGET_FALLOUT_2_STANDARD
//#define TARGET_SALLOW_POINTS
//#define TARGET_MOD_COMPAT

// In script code:
#ifdef TARGET_FALLOUT_2_STANDARD
  // Standard FO2 behavior
  #define EXP_BASE     (100)
  #define REPAIR_MULT  (2)
#endif

#ifdef TARGET_SALLOW_POINTS
  // Sallow Points variant
  #define EXP_BASE     (150)
  #define REPAIR_MULT  (3)
#endif
```

### 7.4 Platform/Environment Detection Pattern

When the compiler is invoked from different build systems:

```pascal
// Build system sets macros:
Compiler.DefineMacro('PLATFORM_WINDOWS', '1');
Compiler.DefineMacro('MOD_VERSION', '"2.1"');
```

```ssl
// In scripts:
#ifdef PLATFORM_WINDOWS
  // Windows-specific paths or workarounds
#endif
```

### 7.5 Guarded Inclusion Pattern

Prevent double-inclusion without relying solely on header guards:

```ssl
// In a master config file:
#ifndef INCLUDED_CONFIG
  #define INCLUDED_CONFIG
  #define NPC_NAME "Harold"
  #define NPC_FACTION 3
  #define NPC_REACTION_VAR 7
#endif
```

### 7.6 Conditional Debug Logging

A practical pattern for debug logging that compiles to zero-cost in release:

```ssl
// lib/debug_utils.ssl
#ifdef DEBUG_MODE
  procedure debug_log begin
    display_msg("DEBUG: " + debug_message);
  end
#else
  // In release builds, debug_log is a no-op
  // The preprocessor removes all calls entirely
#endif
```

---

## 8. Code Readability and Debuggability

### 8.1 The Readability Problem

Extensive macro usage degrades readability:

```ssl
// BAD: Opaque macro-heavy code
display_msg(mstr(NPC_REACTION_VAR));
giQ_Option(NPC_REACTION_VAR, NAME, 100, 0, GOOD_REACTION);

// What do these macros expand to? Hard to tell at a glance.
```

### 8.2 Strategy: Inline Documentation

Document every macro with its expansion visible:

```ssl
// COMMAND.H — Documented macros
#define mstr(x)             message_str(NAME,x)
// Expands to: message_str(NAME, x)
// Returns: The message string for the current script and message number

#define Reply(x)            gSay_Reply(NAME,x)
// Expands to: gSay_Reply(NAME, x)
// Purpose: NPC replies during dialogue

#define GOption(x,y,z)      giQ_Option(z,NAME,x,y,GOOD_REACTION)
// Expands to: giQ_Option(z, NAME, x, y, GOOD_REACTION)
// Purpose: Good reaction dialogue option
```

### 8.3 Strategy: Source Maps via Comments

Include origin markers in assembled files:

```ssl
// ============================================================
// [SOURCE: procedures/combat_procedures.ssl]
// Domain: Combat procedures
// Last modified: 2026-05-10
// ============================================================

procedure critter_p_proc begin
  // ...
end
```

### 8.4 Strategy: Minimal Inline Expansion for Critical Paths

For code where correctness depends on understanding the expansion:

```ssl
// Instead of relying on macro expansion:
critter_is_armed(dude_obj)
// Which expands to:
// (((obj_item_subtype(critter_inven_obj(dude_obj,INVEN_TYPE_RIGHT_HAND))) == item_type_weapon) or ((obj_item_subtype(critter_inven_obj(dude_obj,INVEN_TYPE_LEFT_HAND))) == item_type_weapon))

// Consider a well-named wrapper:
#define IS_NPC_ARMED(critter) critter_is_armed(critter)
```

### 8.5 Strategy: Debug Preprocessor Output

Add a debug mode to emit preprocessor state:

```pascal
// Enhancement to uPreprocessor.pas — Add verbose mode
procedure TPreprocessor.ProcessFile(...);
begin
  // ... existing code ...
  {$IFDEF PREPROC_VERBOSE}
  WriteLn(Format('[PREPROC] Line %d: %s', [i, Trimmed]));
  {$ENDIF}
end;
```

### 8.6 Diff-Friendly Organization

Structure files so that includes map to logical sections:

```ssl
// npc_master.ssl — Well-organized master script
// ──────────────── SECTION: Configuration ────────────────
#include "config/npc_defines.h"

// ──────────────── SECTION: Constants ────────────────
#include "headers/DEFINE.H"
#include "headers/COMMAND.H"

// ──────────────── SECTION: Utilities ────────────────
#include "lib/debug_utils.ssl"

// ──────────────── SECTION: Forward Declarations ────────────────
procedure start;
procedure talk_p_proc;
// ...

// ──────────────── SECTION: Combat Logic ────────────────
#include "procedures/combat.ssl"

// ──────────────── SECTION: Dialogue Logic ────────────────
#include "procedures/dialogue.ssl"

// ──────────────── SECTION: Master Procedures ────────────────
procedure start begin
  // ...
end
```

---

## 9. Performance Optimization

### 9.1 Understanding Performance Characteristics

The current `TPreprocessor.Implementation` has the following complexity:

| Operation | Time Complexity | Notes |
|-----------|----------------|-------|
| `ProcessFile` | O(L × D) | L = lines, D = directives per line |
| `ExpandMacros` | O(L × M × K) | L = lines, M = macros, K = avg line length |
| `#include` resolution | O(I × P) | I = includes, P = include paths |
| `#ifdef`/`#ifndef` | O(1) per directive | Constant-time stack operations |

### 9.2 The Expansion Bottleneck

`ExpandMacros` is the primary bottleneck — it iterates every macro against every line:

```pascal
// Current implementation — O(M × L × K)
for j := 0 to FMacros.Count - 1 do
begin
  MacroKey := FMacros.Keys.ToArray[j];
  MacroValue := FMacros[MacroKey];
  Line := StringReplace(Line, MacroKey, MacroValue, [rfReplaceAll]);
end;
```

### 9.3 Optimization: Minimize Macro Count

Keep the active macro set small. In a 5000-line project with 200 macros, `ExpandMacros` performs 1,000,000 string searches. Strategies:

**a) Scope macros tightly:**

```ssl
// Define macro only when needed, undefine immediately after
#define REPAIR_BONUS (20)
// ... use REPAIR_BONUS in 3 places ...
#undef REPAIR_BONUS
```

**b) Use conditional compilation to eliminate inactive code before expansion:**

```ssl
#ifdef COMBAT_BUILD
  #define DAMAGE_MULTIPLIER (2)
#else
  #define DAMAGE_MULTIPLIER (1)
#endif
// The preprocessor removes one branch, reducing the text for ExpandMacros
```

**c) Avoid macros for single-use values:**

```ssl
// BAD: Macro for a value used once
#define TEMP_VAR (42)
if (local_var(0) == TEMP_VAR) then begin
  // ...
end
#undef TEMP_VAR

// GOOD: Just use the value directly
if (local_var(0) == 42) then begin
  // ...
end
```

### 9.4 Optimization: Reduce Include Depth

Deeply nested includes multiply processing time:

```
Level 0: main.ssl         (1 file)
  Level 1: defines.h      (+1 = 2)
    Level 2: types.h      (+1 = 3)
      Level 3: base.h     (+1 = 4)
  Level 1: commands.h     (+1 = 5)
    Level 2: actions.h    (+1 = 6)
      Level 3: combat.h   (+1 = 7)
```

**Strategy: Flatten include hierarchies**

```ssl
// Instead of:
#include "actions.h"  // Which includes combat.h, which includes types.h...

// Use selective inclusion:
#include "combat/combat_defs.h"    // Only what you need
```

### 9.5 Optimization: Include Guard Effectiveness

Always use include guards — without them, recursive or repeated inclusion causes exponential blowup:

```ssl
// CORRECT: Every header has guards
#ifndef COMBAT_DEFS_H
#define COMBAT_DEFS_H
// Content
#endif
```

### 9.6 Precomputed Include Ordering

For projects with stable file structure, precompute the optimal include order (most-stable headers first) to maximize OS filesystem caching:

```ssl
// Include order optimized for cache locality
#include "headers/DEFINE.H"       // Stable, rarely changes
#include "headers/SCRIPTS.H"      // Stable
#include "headers/GLOBAL.H"       // Stable
#include "headers/COMMAND.H"      // Moderately stable
#include "config/npc_defines.h"   // Changes per-script
#include "procedures/combat.ssl"  // Changes frequently
```

---

## 10. Practical Examples: Monolithic to Modular

### 10.1 Starting Point: Monolithic Script

**`scripts/npc_nhmyron.ssl`** (simplified monolithic version)

```ssl
/*
    Name: Herbert "Herbert" N'Myron
    Location: New Reno
    Description: Arguably the worst character in Fallout 2
*/

#include "..\headers\define.h"
#define NAME                    SCRIPT_NHMYRON
#define TOWN_REP_VAR            GVAR_TOWN_REP_NEW_RENO
#include "..\headers\ModReact.h"
#include "..\headers\command.h"
#include "..\headers\NewReno.h"
#include "..\headers\PartyBkg.h"
#include "..\headers\command.h"

// 50+ lines of global variable declarations...

procedure start;
procedure critter_p_proc;
procedure pickup_p_proc;
procedure talk_p_proc;
procedure destroy_p_proc;
procedure look_at_p_proc;
procedure description_p_proc;
procedure use_skill_on_p_proc;
procedure damage_p_proc;
procedure map_enter_p_proc;
procedure map_update_p_proc;
procedure timed_event_p_proc;
procedure push_p_proc;
procedure use_obj_on_p_proc;
procedure combat_p_proc;

procedure Node998;     // Always combat
procedure Node999;     // Always ending

// 40+ node procedure declarations...
procedure Node002;
procedure Node003;
// ... up to Node128+

// ============================================================
// START PROCEDURE
// ============================================================
procedure start begin
  // 80 lines of initialization
end

// ============================================================
// CRITTER PROC
// ============================================================
procedure critter_p_proc begin
  // 200 lines of critter behavior logic
end

// ============================================================
// TALK PROCEDURE
// ============================================================
procedure talk_p_proc begin
  // 400 lines of dialogue tree
end

// ============================================================
// COMBAT PROCEDURE
// ============================================================
procedure combat_p_proc begin
  // 150 lines of combat logic
end

// ============================================================
// NODE PROCEDURES (2000+ lines)
// ============================================================
procedure Node002 begin
  // Node 002 logic
end
// ... hundreds more
```

**Problems:** 2000+ lines, impossible to navigate, full recompilation on any edit.

### 10.2 Refactored: Modular Architecture

#### Directory Structure

```
project/
├── scripts/
│   └── npc_nhmyron.ssl         ← Master assembly (compile target)
├── config/
│   └── npc_nhmyron_defs.h      ← Per-script configuration
├── procedures/
│   ├── npc_defaults.ssl        ← Default procedures (inheritance-like)
│   ├── combat_basics.ssl       ← Generic combat logic
│   └── dialogue_npc.ssl        ← Dialogue tree for this NPC
├── lib/
│   ├── debug_utils.ssl         ← Debug utilities
│   └── common_procs.ssl        ← Shared procedure templates
└── include/
    └── mod_headers.h           ← Consolidated include guard
```

#### Step 1: Create Configuration Header

**`config/npc_nhmyron_defs.h`**

```ssl
// ============================================================
// NPC: Herbert N'Myron — Configuration
// ============================================================

#ifndef NPC_NHMYRON_DEFS
#define NPC_NHMYRON_DEFS

// Script identity
#define NPC_SCRIPT_NAME    SCRIPT_NHMYRON
#define NPC_TOWN_REP_VAR   GVAR_TOWN_REP_NEW_RENO

// NPC behavior configuration
#define NPC_HAS_COMBAT     1
#define NPC_HAS_DIALOGUE   1
#define NPC_HAS_PICKUP     1
#define NPC_HAS_CRITTER    1

// Dialogue configuration
#define DIALOGUE_MAX_NODES  (128)
#define DIALOGUE_USE_GREET  1

// Debug features
//#define DEBUG_NPC_AI
//#define DEBUG_NPC_DAMAGE

#endif
```

#### Step 2: Create Domain Modules

**`procedures/npc_defaults.ssl`** — Common/default procedure stubs:

```ssl
// ============================================================
// DEFAULT PROCEDURE STUBS
// NPCs that don't need complex behavior use these no-ops
// ============================================================

#ifdef NPC_HAS_PICKUP
procedure pickup_p_proc begin
  // Default: no pickup behavior
end
#endif

procedure look_at_p_proc begin
  display_msg("You see " + NPC_NAME + ".");
end

procedure description_p_proc begin
  display_msg("A sad, old figure.");
end

procedure map_enter_p_proc begin
  // Default: no special behavior on map enter
end

procedure map_update_p_proc begin
  // Default: no special behavior on map update
end
```

**`procedures/combat_basics.ssl`** — Combat procedure module:

```ssl
// ============================================================
// COMBAT PROCEDURES
// Source: procedures/combat_basics.ssl
// ============================================================

#ifdef NPC_HAS_COMBAT

procedure combat_p_proc begin
  // Generic combat behavior
  if (local_var(5) == 0) then begin
    // First time in combat
    set_local_var(5, 1);
    float_msg(self_obj, "Oh no, not again!", 8);
  end
end

procedure damage_p_proc begin
  if (source_obj == dude_obj) then begin
    set_global_var(NPC_TOWN_REP_VAR, global_var(NPC_TOWN_REP_VAR) - 1);
  end
end

#endif // NPC_HAS_COMBAT
```

**`procedures/dialogue_npc.ssl`** — Dialogue tree module:

```ssl
// ============================================================
// DIALOGUE TREE
// Source: procedures/dialogue_npc.ssl
// ============================================================

#ifdef NPC_HAS_DIALOGUE

procedure talk_p_proc begin
  // Dialogue entry point
  start_gdialog(NPC_SCRIPT_NAME, self_obj, 4, -1, -1);
  gsay_start;
  call Node001;
  gsay_end;
  end_dialogue;
end

procedure Node001 begin
  gsay_reply(100, "Oh, hello dear.");
  giq_option(1, NODE, 100, 102, 50);  // Good option → Node102
  giq_option(4, NODE, 101, 103, 40);  // Neutral option → Node103
end

procedure Node102 begin
  gsay_message(102, "How kind of you!", 8);
  call Node999;
end

procedure Node999 begin
  // Exit node
end

#endif // NPC_HAS_DIALOGUE
```

#### Step 3: Create Master Assembly Script

**`scripts/npc_nhmyron.ssl`** — The compile target:

```ssl
/*
    Name: Herbert "Herbert" N'Myron
    Location: New Reno
    Description: Arguably the worst character in Fallout 2

    STRUCTURE:
    ===========
    [1] Configuration
    [2] Headers
    [3] Forward Declarations
    [4] Default Procedures
    [5] Combat Procedures
    [6] Dialogue Procedures
    [7] Master Procedures (start, critter, etc.)
*/

// ============================================================
// [1] CONFIGURATION
// Source: config/npc_nhmyron_defs.h
// ============================================================
#include "config/npc_nhmyron_defs.h"

// ============================================================
// [2] HEADERS
// Source: include/mod_headers.h
// ============================================================
#include "include/mod_headers.h"

// ============================================================
// [3] FORWARD DECLARATIONS
// ============================================================
procedure start;
procedure critter_p_proc;
procedure talk_p_proc;
procedure pickup_p_proc;
procedure look_at_p_proc;
procedure description_p_proc;
procedure combat_p_proc;
procedure damage_p_proc;
procedure map_enter_p_proc;
procedure map_update_p_proc;
procedure Node001;
procedure Node102;
procedure Node999;

// ============================================================
// [4] DEFAULT PROCEDURES
// Source: procedures/npc_defaults.ssl
// ============================================================
#include "procedures/npc_defaults.ssl"

// ============================================================
// [5] COMBAT PROCEDURES
// Source: procedures/combat_basics.ssl
// ============================================================
#include "procedures/combat_basics.ssl"

// ============================================================
// [6] DIALOGUE PROCEDURES
// Source: procedures/dialogue_npc.ssl
// ============================================================
#include "procedures/dialogue_npc.ssl"

// ============================================================
// [7] MASTER PROCEDURES
// These are unique to this NPC and live inline
// ============================================================

procedure start begin
  // NPC initialization
  only_once;
  // ... start procedure logic
end

procedure critter_p_proc begin
  // Critter-specific AI
  if (fixed_param > 2) then begin
    // Handle timed events
  end
end
```

#### Comparison

| Aspect | Monolithic | Modular |
|--------|-----------|---------|
| Lines in main file | 2000+ | ~80 |
| Testable units | 0 | Per-procedure files |
| Navigation | Search through entire file | Jump to include |
| Recompilation on edit | Full (all 2000+ lines) | Only changed module + assembly |
| Collaboration | Single file conflicts | Parallel work on separate modules |
| Configurability | Hard-coded constants | Per-script config header |

---

## 11. Advanced Patterns

### 11.1 Compile-Time Script Feature Matrix

Use conditional compilation to build multiple script variants from a single source:

```ssl
// config/feature_matrix.h
#define HAS_COMBAT     1
#define HAS_STEAL      1
#define HAS_TRAPS      0
#define HAS_BARTER     1

// In procedures:
#ifdef HAS_COMBAT
  procedure combat_p_proc begin
    // Combat AI
  end
#endif

#ifdef HAS_STEAL
  procedure pickup_p_proc begin
    // Steal detection logic
  end
#endif

#ifdef HAS_BARTER
  procedure use_obj_on_p_proc begin
    // Barter interaction
  end
#endif
```

Build different NPCs by changing only the config header:

```text
# Compile variants:
# Merchant NPC: HAS_COMBAT=0, HAS_STEAL=0, HAS_TRAPS=0, HAS_BARTER=1
# Guard NPC:    HAS_COMBAT=1, HAS_STEAL=0, HAS_TRAPS=1, HAS_BARTER=0
# Thief NPC:    HAS_COMBAT=1, HAS_STEAL=1, HAS_TRAPS=0, HAS_BARTER=1
```

### 11.2 Macro-Based Code Generation

Generate repetitive procedure stubs:

```ssl
// lib/gen_procedures.h
// Usage: GENERATE_PROCEDURE(start)
// Expands the start procedure declaration

// This pattern works when combined with the preprocessor's text substitution
// For generating numbered nodes:

#define NODE_BASE  100

// Instead of manual declarations, use a build script to generate:
// procedure Node100;
// procedure Node101;
// ...
```

### 11.3 Layered Architecture Pattern

```ssl
// ============================================================
// LAYER 1: Engine Abstractions (lib/)
// ============================================================
// Abstracts raw Fallout 2 commands into readable operations

#define NPC_SAY(msg)    display_msg(msg)
#define GIVE_XP(amt)    give_exp_points(amt)
#define HAS_SKILL(sk)   (has_skill(dude_obj, sk) > 0)

// ============================================================
// LAYER 2: Domain Logic (procedures/)
// ============================================================
// Uses Layer 1 abstractions to implement NPC behavior

// ============================================================
// LAYER 3: Assembly (scripts/)
// ============================================================
// Only combines layers and sets configuration
```

---

## 12. Common Pitfalls and Troubleshooting

### 12.1 Infinite Include Loops

**Symptom:** Compiler hangs or stack overflow.

**Cause:** Circular `#include` references.

**Fix:** Always use include guards (`#ifndef`/`#define`/`#endif`). The preprocessor correctly tracks nesting depth but cannot detect circular references through file content alone.

### 12.2 Macro Expansion in Wrong Scope

**Symptom:** A macro defined in an included file affects code that shouldn't see it.

**Cause:** Macros are file-scoped, not block-scoped. The preprocessor has no concept of C++ namespaces or local scopes.

**Fix:** Use `#undef` after the section that needs the macro, or use highly-prefixed names:

```ssl
#define COMBAT_DAMAGE_BONUS (5)  // Specific prefix prevents collisions
// ... use it ...
#undef COMBAT_DAMAGE_BONUS
```

### 12.3 `#ifdef`/`#ifndef` Not Working as Expected

**Symptom:** Code inside `#ifdef` block is always (or never) included.

**Cause:** `#ifdef` checks only `FMacros` (runtime-defined macros) and `FDefines` (externally-predefined macros). It does **not** evaluate expressions or check for macro values.

```ssl
// This works:
#define ENABLE_FEATURE
#ifdef ENABLE_FEATURE
  // This code IS included
#endif

// This does NOT work as expected:
#define FEATURE_LEVEL 2
#ifdef (FEATURE_LEVEL > 1)  // ERROR: #ifdef only checks definition, not value
  // Never reached
#endif
```

**Fix:** Use `#ifdef` only for presence/absence checks. For value-based conditions, use runtime `if` statements.

### 12.4 Macro Replacing Unintended Text

**Symptom:** A macro replacement happens inside a string literal or identifier that shouldn't be replaced.

**Cause:** `ExpandMacros` uses `StringReplace` with `rfReplaceAll`, which replaces **all** occurrences including those inside strings.

```ssl
#define MSG "hello"
// Later in code:
display_msg("MSG is a macro");  // BUG: "MSG" inside the string gets replaced
```

**Fix:** Avoid using common words as macro names. Prefer all-caps with domain prefix:

```ssl
// BAD: Common word
#define MSG "something"

// GOOD: Prefixed, unique
#define NPC_GREET_MSG "something"
```

### 12.5 File Not Found on Include

**Symptom:** Preprocessor silently ignores `#include` (file not found, no error reported).

**Cause:** The preprocessor silently skips files that don't exist. The include path resolution checks:
1. Relative to BasePath (current file's directory)
2. Each path in FIncludePaths

**Fix:** Verify include paths are registered with `AddIncludePath()`. Use forward slashes or double backslashes in paths. Check that the file exists at the expected location relative to each include path.

### 12.6 Conditional State Not Preserved Across Includes

**Symptom:** `#ifdef` block that spans an `#include` doesn't work correctly.

**Cause:** The preprocessor does correctly save/restore conditional state around includes (see `ProcessInclude` implementation). This was a known bug that was fixed — verify you are using the fixed version.

---

## Appendix A: TPreprocessor API Reference

```pascal
// Construction and Destruction
constructor Create;
destructor Destroy; override;

// Macro Management
procedure DefineMacro(const Name, Value: string);  // Define or update a macro
procedure UndefMacro(const Name: string);            // Remove a macro
function IsDefined(const Name: string): Boolean;     // Check if macro exists
function GetMacroValue(const Name: string): string;  // Get macro value

// Include Path Management
procedure AddIncludePath(const Path: string);        // Add search path for #include
function ResolveInclude(const FileName: string): string; // Resolve file path

// Processing
function Process(const Source: string; BasePath: string): string;    // Full process with base path
function ProcessString(const Source: string): string;                // Process without file context
```

## Appendix B: Compiler Integration

The `TCompiler` class wraps preprocessor access:

```pascal
// In uCompiler.pas
procedure TCompiler.AddIncludePath(const Path: string);
begin
  FPreprocessor.AddIncludePath(Path);
end;

procedure TCompiler.DefineMacro(const Name, Value: string);
begin
  FPreprocessor.DefineMacro(Name, Value);
end;
```

The preprocessor is invoked automatically during `CompileFile`:

```pascal
function TCompiler.CompileFile(const SourceFile, OutputFile: string): TCompileResult;
begin
  Source := LoadFile(SourceFile);
  BasePath := ExtractFilePath(SourceFile);
  FPreprocessor.AddIncludePath(BasePath);
  Source := FPreprocessor.Process(Source, BasePath);
  // ... continue with lexing and parsing
end;
```

## Appendix C: Quick Reference Card

| Directive | Syntax | Purpose |
|-----------|--------|---------|
| `#define` | `#define NAME value` | Define a macro |
| `#undef` | `#undef NAME` | Remove a macro |
| `#ifdef` | `#ifdef NAME` | Include if macro defined |
| `#ifndef` | `#ifndef NAME` | Include if macro NOT defined |
| `#else` | `#else` | Alternative branch |
| `#endif` | `#endif` | End conditional block |
| `#include` | `#include "file"` or `#include <file>` | Include another file |

## Appendix D: Enhanced Preprocessor Unit (uPreprocessor.pas)

The enhanced `TPreprocessor` class (included in this project at `uPreprocessor.pas`) adds the following features beyond the original implementation:

### Additional Configuration (`TPreprocessorOptions`)

```pascal
TPreprocessorOptions = record
  Verbose: Boolean;           // Emit trace messages via OutputDebugString
  MaxIncludeDepth: Integer;   // Cycle/deep-nesting guard (default: 64)
  PreserveDirectives: Boolean; // Keep directives as // PRESERVED: comments
end;
```

### Cycle Detection

The enhanced preprocessor tracks the current include stack in `FIncludeStack: TStack<string>`. When an `#include` would reference a file already in the stack, it raises `EPreprocessorError`:

```pascal
raise EPreprocessorError.CreateFmt('Include cycle detected: %s', [ResolvedPath]);
```

### Depth Guard

Configurable maximum include nesting depth prevents runaway recursion:

```pascal
if FIncludeStack.Count > FOptions.MaxIncludeDepth then
  raise EPreprocessorError.CreateFmt(
    'Include nesting depth exceeded maximum of %d at file: %s',
    [FOptions.MaxIncludeDepth, FileName]);
```

### Performance Metrics

Three read-only properties report statistics after each `Process()` call:

- `ProcessedIncludeCount` — number of `#include` files resolved
- `ProcessedLineCount` — total source lines scanned
- `MacroExpansionCount` — number of macro substitutions performed

### Optimized Macro Expansion

The enhanced `ExpandMacros` caches the macro key array to avoid repeated `TDictionary.Keys.ToArray` calls, applies an early `Pos()` check before calling `StringReplace`, and short-circuits entirely when no macros are defined.

### Usage Example

```pascal
var
  Preproc: TPreprocessor;
begin
  Preproc := TPreprocessor.Create;
  try
    Preproc.Options.MaxIncludeDepth := 32;
    Preproc.Options.Verbose := True;
    Preproc.AddIncludePath('C:\project\headers');
    Preproc.DefineMacro('DEBUG', '1');

    Result := Preproc.Process(Source, 'C:\project\scripts\');

    WriteLn(Format('Processed %d includes, %d lines, %d expansions',
      [Preproc.ProcessedIncludeCount,
       Preproc.ProcessedLineCount,
       Preproc.MacroExpansionCount]));
  finally
    Preproc.Free;
  end;
end;
```

## Appendix E: Modular Example Directory Structure

The project includes a complete modular example in `TestScripts\ModularExample\`:

```
TestScripts\ModularExample\
├── scripts\
│   ├── npc_nhmyron_monolithic.ssl    ← Original monolithic version (comparison)
│   └── npc_nhmyron_modular.ssl       ← Refactored modular master assembly
├── config\
│   └── npc_nhmyron_defs.h            ← Per-script configuration & feature flags
├── procedures\
│   ├── npc_default_procedures.ssl    ← Shared default procedure stubs
│   ├── npc_combat_procedures.ssl     ← Combat domain logic
│   └── npc_dialogue_procedures.ssl   ← Dialogue tree domain logic
├── lib\
│   └── common_defines.h              ← Shared macro library (guarded)
├── include\
│   └── npc_headers.h                 ← Consolidated header inclusion (guarded)
└── docs\
    ├── advanced_conditional_patterns.ssl  ← 7 advanced patterns
    ├── companion_npc_example.ssl          ← Slink companion NPC notes
    ├── NPC_TEMPLATE_README.ssl            ← Template usage instructions
    ├── npc_slink_modular_notes.ssl        ← Modular vs monolithic comparison
    └── performance_analysis.ssl           ← Benchmark scenarios & recommendations
```

## Appendix F: Build Commands

### CLI Compiler (sslc)

```bash
# Basic compilation with include paths
sslc.exe -I config -I headers -I procedures scripts/npc_nhmyron_modular.ssl

# With output directory
sslc.exe -o output\ -I config -I headers scripts/npc_nhmyron_modular.ssl

# Verbose mode (if compiled with debug support)
sslc.exe -v -I config scripts/npc_nhmyron_modular.ssl
```

### GUI Compiler

1. Open `FalloutCompiler.exe`
2. Configure include paths via the compiler options
3. Open an `.ssl` master assembly script
4. Click **Compile**
5. View output (including any preprocessor trace messages) in the right panel