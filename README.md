# Aimbot UI

An all-in-one interface addon suite for **World of Warcraft Forever** (interface 16001).

Despite the name, Aimbot UI only changes how your interface looks and what it shows. It does not play, aim or target for you.

**Current version: 2.8.7**

Open it in game with `/aimbot` (or `/aui`). Every module has its own tab and its own on/off switch, and if one module hits a problem it reports in chat and the rest keep running.

## What's new in 2.8.7

- Diminish (new tab "Diminish", or /aimbot dr): diminishing returns icons on your target and focus frames, on enemy nameplates, and for yourself (under your player frame). One icon per kind of crowd control (stuns, incapacitates, disorients, roots, silences, and optionally disarms). The border shows what the NEXT one will do: green 50%, yellow 25%, red immune, and the timer counts down to the reset. "Show test icons" lets you line them up. Size, spacing, colours, timer / % text and the position of each group can be changed. Inspired by the Diminish addon by Wardz (MIT); new code. Forever closes the combat log that Diminish used, so this reads the game's own DR event, and falls back to crowd-control debuffs the game lets addons see (classic rules: 18 s reset, 50% / 25% / immune; a 2-step mode is in Tracking). FIRST VERSION, written without being able to test it in game: run /aimbot diag after some PvP. It records what the game's DR event sends, so it can be fixed for Forever. Grey icons mean the game sent the DR with hidden (secret) details.

See [CHANGELOG.md](CHANGELOG.md) for every version.

## Download

Download **[AimbotUI.zip](https://github.com/itsalotoflust/Aimbot-UI-WoW-Forever-/raw/main/AimbotUI.zip)**. The addon source is also in the `AimbotUI` folder in this repo.

## Install

1. Delete any old copies of `AimbotUI`, `ForeverDark` and `ForeverSparkle` from your AddOns folder.
2. Unzip, then copy the `AimbotUI` folder into:
   `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`
   You should end up with `...\AddOns\AimbotUI\AimbotUI.toc`.
3. Start the game. On the character screen click **AddOns** and make sure Aimbot UI is ticked. If it is greyed out, tick "Load out of date AddOns".
4. In game, type `/aimbot`.

## What is inside

| Module | What it does |
| --- | --- |
| **General** | Drag, resize and lock the window. Scale, opacity, text size and colours. Module list with a switch for each tab. Reset. |
| **Lorti Style** | The Lorti UI look, rebuilt for Forever's frames: flat dark action buttons, short keybind text, class coloured health bars, class portraits, darkened frame art, hidden gryphons, dark windows, minimap wheel zoom. Each option is separate. |
| **Damage Font** | Eight NiceDamage fonts for floating combat text. Needs a full game restart, `/reload` is not enough. |
| **Button Sparkle** | The classic jButtonFlash look by default: a white star pops to 1.5x and shrinks away, spinning 90 degrees in 0.3 seconds. Presets, live preview, press or release trigger, colour modes, size, speed, extra layers. Also flashes Bartender4, Dominos and ElvUI buttons. |
| **Mana Cost** | Shows the mana or resource cost on action bar spells, with position options. |
| **Range Alert** | Action button icons turn red when your target is out of range. Optional distance readout. |
| **Spell Trainer** | A WhatsTraining-style list of what you can learn. Open your class trainer once per class to fill it. |
| **Chat Mute** | Mute players, guilds and words, with speak times when muted people may talk, a never-mute list, and filters for links, shouting, repeats and strangers. |
| **FPS / MS** | Frame rate and latency counter at the bottom centre of the screen. |
| **Privacy** | Stream mode: fake name and BattleTag, class names, whisper inbox (or an "Allow whispers from everyone" switch that shows them normally), and a Be right back screen. |
| **Diminish** | Diminishing returns icons on target, focus, enemy nameplates and yourself. Border shows what the next crowd control will do (green 50%, yellow 25%, red immune), with a reset timer. First version, not yet tested in game. |
| **Double Press** | Optional. Every action bar key presses twice, on key down and key up. Off by default. |
| **Memory Cleaner** | A Clear Cache button that runs a garbage collection without freezing the game. |

## Slash commands

```
/aimbot  or  /aui            open or close the window
/aimbot lorti | damage | sparkle | mana | range | trainer | double | mute | fps | privacy | dr | general
/sparkle on | off | test
/amute target | guild | allow 15 | stop | status | unmute NAME | on | off
/aprivacy on | off | toggle | inbox | brb | status
/aimbot diag                 print a diagnostic report to chat
```

## If something does not look right

Forever's frame names could not all be tested from outside the game. Run `/aimbot diag` and send the output with your report. Some options need a `/reload` to fully undo after you turn them off. Lorti's "Thick Frames" option is not included.

## Credits and licences

- **Lorti UI Classic** artwork in `media/`, and its look and feature set: Lorti, Chordsy, Macumba, Knall, Jozh, Xyz, Arrone and Redskin. The logic was rewritten for Forever's frames.
- **NiceDamage** fonts in `media/fonts/`: Montyburns.
- **What's Training?** by Sveng (MIT licence): the spell, quest spell and weapon skill data in `Data/` is taken from that addon. See `Data/LICENSE-WhatsTraining.txt`.
- **Diminish** by Wardz (MIT licence): the idea and look of the Diminish tab. The Aimbot UI version is new code; nothing was copied.
- The window, Button Sparkle, Spell Trainer, Mana Cost, Range Alert and the other modules are original to Aimbot UI. See `CREDITS.txt` in the addon folder.

World of Warcraft is a trademark of Blizzard Entertainment. Aimbot UI is a fan-made addon and is not affiliated with Blizzard or with the authors above.
