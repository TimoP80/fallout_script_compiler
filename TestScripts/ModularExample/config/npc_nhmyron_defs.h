// ============================================================
// CONFIGURATION: NPC-specific settings for Hagbard N'Myron
// Source: config/npc_nhmyron_defs.h
//
// This file controls which features are compiled for this NPC.
// Change these flags to customize behavior without touching
// the procedure modules.
// ============================================================

#ifndef NPC_NHMYRON_DEFS
#define NPC_NHMYRON_DEFS

// Script identity — used by dialogue and reputation code
#define NPC_SCRIPT_NAME        SCRIPT_NHMYRON
#define NPC_TOWN_REP_VAR       GVAR_TOWN_REP_NEW_RENO

// Feature flags — set to 0 to disable, 1 to enable
#define NPC_HAS_COMBAT         1
#define NPC_HAS_PICKUP         1
#define NPC_HAS_SPATIAL        0
#define NPC_HAS_CRITTER        1
#define NPC_HAS_DESTROY        1
#define NPC_HAS_DAMAGE         1
#define NPC_HAS_MAP_ENTER      1
#define NPC_HAS_BEGGING        0   // Not used by this NPC

// Reputation tracking
#define REPUTATION_CHANGE_DESTROY   (1)
#define REPUTATION_CHANGE_PICKUP   (-1)
#define REPUTATION_CHANGE_DAMAGE   (-1)

#endif