// ============================================================
// COMMON MACRO LIBRARY
// Source: lib/common_defines.h
//
// Shared macro definitions used across multiple scripts.
// Always guarded with include guards (#ifndef).
// Prefix convention: LIB_ for library-level macros
// ============================================================

#ifndef COMMON_DEFINES_H
#define COMMON_DEFINES_H

// ============================================================
// Debug Macros
// ============================================================

#ifdef DEBUG_MODE
  // In debug mode, display debug messages
  #define DEBUG_PRINT(msg)    display_msg("DEBUG: " + msg)
  #define DEBUG_PRINT_INT(msg, val)  display_msg("DEBUG: " + msg + " = " + val)
#else
  // In release builds, expand to nothing — zero overhead
  #define DEBUG_PRINT(msg)
  #define DEBUG_PRINT_INT(msg, val)
#endif

// ============================================================
// Game State Shortcuts
// ============================================================

// Global variable shortcuts
#define GVAR(name)    global_var(GVAR_##name)

// Common GVAR references (add more as needed)
#define GVAR_TOWN_REP     GVAR_TOWN_REP_NEW_RENO

// Karma shortcuts
#define KARMA_GOOD    0
#define KARMA_NEUTRAL 1
#define KARMA_EVIL    2

// ============================================================
// NPC Behavior Constants
// ============================================================

// Reaction levels
#define REACTION_LOVE      4
#define REACTION_LIKE      3
#define REACTION_NEUTRAL   2
#define REACTION_DISLIKE   1
#define REACTION_HATE      0

// Hostility modes
#define HOSTILE_PASSIVE    0
#define HOSTILE_ACTIVE     1
#define HOSTILE_RUN_AWAY   2

// ============================================================
// Animation Shortcuts
// ============================================================

#define ANIM_STAND         100
#define ANIM_WALK          101
#define ANIM_RUN           102
#define ANIM_FIRE_PISTOL   103
#define ANIM_FIRE_RIFLE    104
#define ANIM_DIE_FRONT     110
#define ANIM_DIE_BACK      111

// ============================================================
// Dialog Shortcuts
// ============================================================

#define SAY(msg)           display_msg(msg)
#define SAY_INTRO          display_msg("Nice to meet you.")
#define SAY_GOODBYE        display_msg("Take care, friend.")
#define SAY_HOSTILE        display_msg("I don't like your attitude.")

#endif // COMMON_DEFINES_H