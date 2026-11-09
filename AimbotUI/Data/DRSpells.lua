--[[
  Aimbot UI - crowd control spells for the Diminish module (aura fallback).

  Written for Aimbot UI (not taken from DRList or any other addon). Spells are listed by
  NAME, so every rank matches. The groups follow the game's own diminishing return
  categories (Enum.SpellDiminishCategory): stun, incapacitate, disorient, root, silence,
  disarm. When the game's own DR event works, it decides; this list is only used when
  the module has to work DR out from debuffs it can see.

  English client names. A name that is wrong or missing just means that spell is not
  tracked from debuffs.
]]
local ADDON_NAME, NS = ...

NS.DRSpells = {
    stun = {
        "Cheap Shot", "Kidney Shot", "Hammer of Justice", "Bash", "Pounce", "Charge Stun",
        "Intercept Stun", "Concussion Blow", "Intimidation", "War Stomp", "Shadowfury",
        "Impact", "Mace Stun Effect", "Stoneclaw Stun", "Blackout", "Starfire Stun",
        "Revenge Stun", "Seal of Justice", "Inferno Effect", "Deep Freeze", "Shockwave",
        "Storm Bolt", "Leg Sweep", "Gnaw",
    },
    incapacitate = {
        "Polymorph", "Sap", "Gouge", "Repentance", "Freezing Trap Effect", "Freezing Trap",
        "Wyvern Sting", "Hibernate", "Shackle Undead", "Maim", "Hex", "Incapacitating Roar",
        "Death Coil", "Mortal Coil", "Banish",
    },
    disorient = {
        "Fear", "Psychic Scream", "Howl of Terror", "Intimidating Shout", "Seduction",
        "Scare Beast", "Blind", "Cyclone", "Scatter Shot", "Dragon's Breath", "Turn Evil",
        "Turn Undead", "Mind Control", "Hungering Cold", "Sleep",
    },
    root = {
        "Frost Nova", "Entangling Roots", "Freeze", "Frostbite", "Improved Hamstring",
        "Improved Wing Clip", "Entrapment", "Earthgrab", "Shattered Barrier", "Mass Entanglement",
    },
    silence = {
        "Silence", "Silenced - Improved Counterspell", "Counterspell - Silenced",
        "Garrote - Silence", "Silenced - Gag Order", "Silenced - Improved Kick",
        "Kick - Silenced", "Arcane Torrent", "Spell Lock", "Strangulate", "Silencing Shot",
        "Silenced - Shield Bash",
    },
    disarm = {
        "Disarm", "Riposte", "Dismantle", "Grapple Weapon",
    },
}
