# Aimbot UI

An all-in-one interface addon suite for **World of Warcraft Forever** (interface 16001).

**Current version: 2.28.2**

Open it in game with `/aimbot` (or `/aui`). Every module has its own tab and its own on/off switch, and if one module hits a problem it reports in chat and the rest keep running.

## What's new in 2.32.2

- **Frame Style:** reworked toward the reference look: round portraits with their own mask (the player portrait is back), classic glossy bars in class / power colours, all leftover frame decoration hidden, name centred. Saves a short frame report to help match the layout exactly. `/reload` is enough.

## What's new in 2.32.1

- **Cast Bar:** a Scale slider makes the whole bar bigger without stretching the classic border; Height now goes up to 40. `/reload` is enough.

## What's new in 2.32.0

- **New: Frame Style** (Style tab). Restyles the game's player, target and target-of-target frames: name above a big health bar with the number, a thin power bar, black borders, round class-icon portraits with a red ring in combat. Still the game's frames, so menus and targeting keep working. New file: needs a full game restart, not just `/reload`.

## What's new in 2.31.2

- **Cast Bar:** the game's own cast bar no longer shows its red "Interrupted" when a cast is stopped or interrupted. `/reload` is enough.

## What's new in 2.31.1

- **Cast Bar:** spell name and timer centred in the bar, with a "Text up / down" slider to fine-tune. `/reload` is enough.

## What's new in 2.31.0

- **New: Cast Bar** (Combat tab). A classic-style cast bar for your own casts in place of the game's modern one: classic border, spark and flash, yellow casts, green channels, red "Interrupted". Hides the game's bar while it's on. Movable, with options for icon, timer, latency and colours. New file: needs a full game restart, not just `/reload`.

## What's new in 2.30.3

- **Buff Bar:** all elixirs, flasks and scrolls show (the tooltip check now only applies to food and "other"), and potions that give a buff go with the elixirs. `/reload` is enough.

## What's new in 2.30.2

- **Buff Bar:** finds elixirs and flasks the game files under other categories (anything named "Elixir" or "Flask"), reads "Lasts 1 hour" style durations, keeps checking tooltips that load late, and has a new "Print what the bar sees in my bags" button that says where each item went or why it was left out. `/reload` is enough.

## What's new in 2.30.1

- **Buff Bar:** hover a button to open its list of the other items of that kind; no arrow to click. Works in combat. `/reload` is enough.

## What's new in 2.30.0

- **Buff Bar:** one button per kind (food, elixirs & flasks, scrolls, oils & stones ...). Hovering the button opens a list of the other items of that kind, going upwards. Picking one uses it and makes it that kind's main button. The list works in combat; the main button swaps after combat. Options: group by kind, and open upwards, downwards or away from the screen edge. `/reload` is enough.

## What's new in 2.29.2

- **Buff Bar:** items such as the Basic Campfire Kit, whose text mentions a time only as a condition ("nearby for 1 min will gain benefits"), are no longer shown.
- **Buff Bar:** a switch for each kind: Food & Drink, Elixirs & Flasks, Potions, Scrolls, Weapon Oils & Stones, Bandages, Other Usable, with "Reset kinds" and "Show hidden items again". `/reload` is enough.

## What's new in 2.29.1

- **Buff Bar:** only shows items that actually give a buff. Each item's "Use:" text must say how long the effect lasts ("for 30 min", "well fed"), so plain food and water, healing and mana potions are left out. Pinned items always show. `/reload` is enough.

## What's new in 2.29.0

- **New: Buff Bar** (Quality of Life tab). A bar of buttons for the buff items in your bags: food, elixirs, flasks, scrolls, weapon oils and stones. Click to use; weapon oils and stones go on the main hand with a click and the off hand with a right-click.
  - Fills itself from your bags, starts at the top centre of the screen, and can be dragged anywhere until you lock it.
  - Buttons dim and show the time left when the buff is already on you (or hide instead). Low stacks turn red.
  - Shift+right-click hides an item, Ctrl+right-click pins it.
  - New file: needs a full game restart, not just `/reload`.

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
| **Button Flash** | The classic jButtonFlash look by default: a white star pops to 1.5x and shrinks away, spinning 90 degrees in 0.3 seconds. Presets, live preview, press or release trigger, colour modes, size, speed, extra layers. Also flashes Bartender4, Dominos and ElvUI buttons. |
| **Mana Cost** | Shows the mana or resource cost on action bar spells, with position options. |
| **Range Alert** | Action button icons turn red when your target is out of range. Optional distance readout. |
| **Spell Trainer** | A WhatsTraining-style list of what you can learn. Open your class trainer once per class to fill it. |
| **Chat Mute** | Mute players, guilds and words, with speak times when muted people may talk, a never-mute list, and filters for links, shouting, repeats and strangers. |
| **FPS / MS** | Frame rate and latency counter at the bottom centre of the screen. |
| **Privacy** | Stream mode: fake name and BattleTag, class names, whisper inbox (or an "Allow whispers from everyone" switch that shows them normally), and a Be right back screen. |
| **Diminish** | Diminishing returns icons on target, focus, enemy nameplates and yourself (your own icons can be dragged anywhere, by default just below your character). Border shows what the next crowd control will do (green 50%, yellow 25%, red immune), with a reset timer. First version, not yet tested in game. |
| **Queue Timer** | Countdown bar, sound and taskbar flash when a dungeon, battleground or arena queue pops. |
| **Nameplate Icons** | Class icons above friendly players, healer icons on healers, and enemy players' PvP racial on their nameplate. |
| **Combat Indicator** | Crossed swords or "Zzz" next to your target and focus frames, so you can see whether they are in combat. |
| **Interrupt Ready** | Your interrupt next to enemy cast bars: green when it's ready, grey with a timer when it isn't. |
| **Double Press (Wannabe AHK)** | Optional. Every action bar key presses twice, on key down and key up. Off by default. |
| **Memory Cleaner** | A Clear Cache button that runs a garbage collection without freezing the game. |
| **Frame Style** | Restyles the player, target and target-of-target frames: big health bar with the number, thin power bar, black borders, round class-icon portraits. |
| **Cast Bar** | Classic-style player cast bar (classic border, spark, flash) in place of the game's modern one. Yellow casts, green channels, red interrupts. |
| **Buff Bar** | Clickable buttons for the food, elixirs, flasks, scrolls and weapon oils in your bags. Dims buffs you already have, shows time left, red count when low. Movable, starts at the top centre. |

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
- The window, Button Flash, Spell Trainer, Mana Cost, Range Alert and the other modules are original to Aimbot UI. See `CREDITS.txt` in the addon folder.

World of Warcraft is a trademark of Blizzard Entertainment. Aimbot UI is a fan-made addon and is not affiliated with Blizzard or with the authors above.
