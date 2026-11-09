# Changelog

All notable changes to Aimbot UI, newest first. The latest version is also summarised under "What's new" in [README.md](README.md).

## 2.12.0

- **Combat Indicator:** "+Combat" (red) and "-Combat" (green) in the middle of your screen when you enter and leave combat. Text size, both colors, how long it stays, and "Lock position" (untick it and drag the text anywhere). Each of +Combat / -Combat can be turned off, and there is a Test button. The target / focus icons are unchanged.
- **Party Death Alert:** a skull icon after "<Name> died" (can be turned off).

## 2.11.0

- **Aura Timers** (Combat, new module): time-left numbers on buff and debuff icons, so you can see how long your DoTs and crowd control have left on your target, focus and enemy nameplates. The game counts the time itself, so it keeps working even where the client hides aura times from addons. Choose target / focus / nameplates and the number size for each. It is a new file, so **fully restart the game once** after updating. Shortcut: `/aimbot timers`.

## 2.10.0

Three new on-screen alerts, each with its own tab and on/off switch. They are new files, so **fully restart the game once** after updating; `/reload` is not enough the first time. Only you see them; nothing is sent to chat. Each has text size, color, a Test button and "Lock position": untick it and drag the text anywhere, then lock it again.

- **Party Death Alert** (Combat): "<Name> died" in the middle of your screen when a party member dies, name in class color, with a sound. Fades after a few seconds (adjustable). Optional for raid members too. Feign Death is ignored. With Privacy's private mode on it shows the class instead of the name.
- **Durability Alert** (Quality of life): a pulsing "Repair your gear: 35%" that stays on screen while your gear is below 40% (adjustable), until you repair. Measures your most damaged item or the average of all gear, counts broken items, sound when it first drops.
- **Talent Point Alert** (Quality of life): a pulsing "1 unspent talent point" that stays on screen until you spend it. Hidden in combat and while the talent window is open (both optional), sound when you get a new point.
- New `/aimbot` shortcuts: `death`, `repair`, `talent`.

## 2.9.4

- **Lorti Style:** new "Hide the colored background behind names" option under "Frame art and portraits" (on by default). Removes the red / yellow / green strip behind the target and focus name. Untick it to bring the strip back.

## 2.9.3

- Removed the Lorti Style "Solid name background" option from 2.9.1 / 2.9.2. The strip behind unit names is the game's own art again, exactly as before.

## 2.9.2

- **Lorti Style "Solid name background":** the solid bar now lines up with the health bar under it (same width, same height as the game's strip) instead of running under the portrait. The game's faded strip is hidden while it is on and comes back when you untick it.

## 2.9.1

- **Lorti Style:** new "Solid name background (no fade)" option under "Frame art and portraits" (on by default). The colored strip behind the target and focus name (red, yellow, green) is the game's own art, which fades out toward the edge; it is now drawn as a solid bar in the same color. Untick it to get the game's faded art back. `/aimbot diag` lists the name bars it found.

## 2.9.0

Four new modules, each with its own tab and on/off switch. They are new files, so **fully restart the game once** after updating; `/reload` is not enough the first time.

- **Queue Timer** (Quality of life): when a dungeon, battleground or arena queue pops, a bar counts down the seconds left to accept, a sound plays through the Master channel (heard even with game sounds down), it ticks every second near the end, and the game's taskbar icon flashes. Battlegrounds and arenas show the real time left; the dungeon finder counts from 40. Has a Test button, and the bar can be resized and moved.
- **Nameplate Icons** (Combat): class icon above friendly players (optionally instead of their name, or only while Privacy's private mode is on), a healer icon on healers (enemy healers in arenas from their spec, anywhere else once they cast a healer-only spell; your group's healers from their role), and enemy players' PvP racial (Will of the Forsaken, Every Man for Himself, Stoneform...) next to their health bar.
- **Combat Indicator** (Combat): crossed swords next to your target / focus frame while they are in combat, "Zzz" while they are not. Optional on yourself too, with size and position sliders.
- **Interrupt Ready** (Combat): while an enemy casts, your interrupt (Kick, Pummel, Shield Bash, Counterspell, Earth Shock, Silence, Spell Lock...) shows next to their cast bar on nameplates, target and focus: green edge = ready, grey with a timer = on cooldown. Hides on casts that can't be interrupted.
- New `/aimbot` shortcuts: `queue`, `plates`, `combat`, `kick`.

## 2.8.18

- Privacy: new "Friendly name range (yards)" slider under "Show friendly players' names above heads" (default 60). While friendly names are on it raises how far away nameplates show, so friendly names appear from further away (this also applies to enemy plates). The game has its own maximum; the note under the slider shows the distance the game is really using. Your own range is put back when private mode is turned off. `/aimbot diag` shows it on the "friendly names" line.

## 2.8.17

- Privacy "Show friendly players' names above heads" now actually turns on. This client uses the newer names for the friendly nameplate settings (`nameplateShowFriendlyPlayers`, `nameplateShowOnlyNameForFriendlyPlayerUnits`...), and 2.8.14 only set the older names, which the game ignored. Both sets are now listed and whichever exists is used. While it is on, friendly pet, guardian, minion and totem plates are also off so only players get a name; everything is put back when private mode is turned off. `/aimbot diag` shows the real values of these settings.
- Side menu a little wider again so "Double Press (Wannabe AHK)" fits without "...".

## 2.8.16

- Renamed "Button Sparkle" to "Button Flash". Your settings carry over. `/sparkle` still works, and `/aimbot flash` now opens its tab too.
- Renamed "Double Press" to "Double Press (Wannabe AHK)". The side menu is a little wider, and a "(...)" note at the end of a name is drawn smaller and grey so the full name fits.

## 2.8.15

- Fixed the "AddOn 'AimbotUI' tried to call the protected function 'UNKNOWN()'" error from Double Press. The invisible key watcher (used to flash Button Sparkle on your doubled keys) re-set a keyboard setting on every key press, and the game blocks that call in combat. It is now set once, out of combat, and the key presses themselves no longer touch it. The "never double" key picker got the same guard.

## 2.8.14

- Privacy: new option "Show friendly players' names above heads (as their Privacy name)". While private mode is on it turns on the game's friendly nameplates in names-only mode (no health bar) and swaps each friendly player's name for your Privacy name (class, "Player" or nothing), so you can still see who is on your side. Friendly NPC plates stay off and your own name is not shown. Your nameplate settings are put back when private mode is turned off.
- In dungeons and raids the game locks friendly nameplates (an addon can't change their text), so they stay off there and come back when you leave. Nameplate settings can't change in combat, so a change waits until combat ends.

## 2.8.13

- New **Classic** style for the window, made to look like the game's own option panels: a stone (or gold) dialog border, a dark textured background, gold labels with white section titles and a divider under each, the game's checkboxes on the left of each setting, red game-style buttons, game-style sliders and drop-down boxes. This is now the default look.
- Real drop-down lists: clicking a choice box (themes, modes, positions...) opens a list to pick from, instead of stepping through the options one click at a time. Works in both styles.
- More themes (General tab > Theme). Classic: Stone, Gold trim, Rock, Marble, Tooltip, Horde, Alliance. Modern: Aimbot Blue, Crimson, Emerald, Violet, Gold, Ember, Frost, Fel, Rose, Graphite, Pure black. Plus "Style" (Classic or Modern), "Classic border" (Stone, Gold trim, Thin, None) and "Classic background" (Dark, Rock, Marble, Plain color). Switching between Classic and Modern needs a reload ("Reload now" button); borders, backgrounds and colors change live.
- "Reset all window colors" now resets to the theme you picked instead of always Aimbot Blue.

## 2.8.12

- A more modern look for the Aimbot UI window: round toggle switches (pill track with a round knob), round slider handles and round on/off dots in the side menu; flat buttons with a soft accent wash on hover; flatter text boxes; softer cards with a faint top light, a round accent dot before the title and their short description underneath; a bigger page title with an accent underline and "On"/"Off" next to each tab's switch; the version as a small chip in the title bar, a close button that turns red on hover, a soft shadow around the window and a thinner scrollbar.
- The round shapes use a new image (`media/ui/circle.tga`), so fully restart the game once after updating. Until then they show as squares and everything still works.
- Fixed: in 2.8.11 the General tab stopped part way (the module on/off list was missing). It builds fully again.

## 2.8.11

- Side menu tidied up. Diminish and Spell Trainer moved into Quality of Life, so each group now shows once: LOOK, COMBAT, then QUALITY OF LIFE, with the modules A-Z inside each group (the module list on the General tab uses the same order). Group names have a thin divider line and a bit more space above them, the on/off dots are a little smaller and the +/- markers are softer.
- Help: the list of `/aimbot` tab names now includes mute, fps, privacy and dr.

## 2.8.10

- Privacy: targeting yourself (or anyone) no longer flashes the real name for a moment before your Privacy name shows. The name on the target, target-of-target and focus frames is now swapped in the same instant the game draws it, instead of on the next check a moment later. The name texts are looked up once and remembered, and the fix only runs when you change target or focus, so there is no extra work every frame and no FPS cost. `/aimbot diag` now shows how many instant fixes ran.

## 2.8.9

- Every slider in the window now lets you type a value. Click the number on the right of a slider, type the value you want and press Enter. Escape, or clicking somewhere else, puts the old value back. A typed value is kept inside the slider's range and rounded to its step, and you can type "%" or "s" after it or use a comma for the decimal point. The drag bar still works as before.

## 2.8.8

- Diminish: YOUR own DR icons now sit in the middle of the screen, just below your character, instead of under the player frame, and you can drag them anywhere. Diminish tab > Your icons: tick "Unlock your icons to drag them", drag the blue box, then untick it to lock them. They have their own size slider (bigger by default), "Back to the middle of the screen" resets them, and "Your icons go" switches back to the player frame if you prefer.

## 2.8.7

- Diminish (new tab "Diminish", or /aimbot dr): diminishing returns icons on your target and focus frames, on enemy nameplates, and for yourself (under your player frame). One icon per kind of crowd control (stuns, incapacitates, disorients, roots, silences, and optionally disarms). The border shows what the NEXT one will do: green 50%, yellow 25%, red immune, and the timer counts down to the reset. "Show test icons" lets you line them up. Size, spacing, colours, timer / % text and the position of each group can be changed. Inspired by the Diminish addon by Wardz (MIT); new code. Forever closes the combat log that Diminish used, so this reads the game's own DR event, and falls back to crowd-control debuffs the game lets addons see (classic rules: 18 s reset, 50% / 25% / immune; a 2-step mode is in Tracking). FIRST VERSION, written without being able to test it in game: run /aimbot diag after some PvP. It records what the game's DR event sends, so it can be fixed for Forever. Grey icons mean the game sent the DR with hidden (secret) details.

## 2.8.6

- Privacy: new switch "Allow whispers from everyone (real names)" (Privacy tab > Chat). While private mode is on, whispers from everyone - other characters AND Battle.net friends, ones you get and ones you send - show in chat exactly as normal, with the sender's real name instead of "Player" or a class name, so you can see who it is and reply with R or by clicking the name. Off by default. It wins over "Keep whispers out of chat". Names in those whispers WILL be visible on stream.
- /aimbot diag now says how whispers are being handled.

## 2.8.5

- Double Press + Button Sparkle FIX: Double Press was reading its own key bindings back as if they were yours, so every rescan wrapped the action button in another hidden helper button (194 of them instead of about 50) and the sparkle was drawn on an invisible helper. It now always finds the real button, so the sparkle shows on the button you pressed. The helper buttons also stop piling up.
- The raw-key backup path no longer gets stuck if a key release is missed.

## 2.8.4

- Privacy performance fix (FPS drop / lag with nameplates): private mode no longer re-scans every frame several times a second. Names are now changed only when the game redraws that one name (raid frames, nameplates) or when you target / focus / group changes, with a light once-a-second safety check. Chat bubble and minimap settings are only touched when something actually changes.

## 2.8.3

- Privacy: private mode is now ALWAYS switched on at login and /reload (no toggle needed each time). The key / /aprivacy still toggles it for the current session; the Privacy tab's Enabled switch turns the whole module off.

## 2.8.2

- "/aimbot diag" (and Maintenance > Run diagnostics) now opens a copy window with the whole report (Ctrl+A, Ctrl+C to copy it), still prints it to chat, and also saves it in your settings file as "lastDiag" (written to disk when you /reload or log out).
- Double Press + Button Sparkle: the flash now also listens on the real action button itself, so any press that reaches it (including the Double Press proxy buttons) flashes, whatever path it took.
- Diagnostics for Sparkle now show real-button clicks seen, the last few triggers, and why any flash was dropped (hidden button, empty slot, debounce, combat-only, module off).

## 2.8.1

- Privacy fix: your name on the player frame / portrait (and target, focus, party) is now found by what the text says, anywhere inside the unit frame, so it works with restyled frames such as BetterBlizzFrames instead of relying on a guessed path.
- Privacy: new option "Hide the names the game draws above heads (including yours)": the green name over your character (and other players / pets, plus guild and title lines) is the game's own setting, so it is switched off while private and put back afterwards (also after a crash or logout).
- "/aimbot diag" Privacy lines now list every name text found and what it currently shows.

## 2.8.0

- Privacy / stream mode (new tab "Privacy", or /aprivacy). One switch (a key in Key Bindings > Aimbot UI, /aprivacy, or "turn on at login") makes the game safe to show on stream:
  - other players' names on unit frames, party/raid frames and nameplates become their class, "Player" or nothing; NPCs and pets keep theirs
  - YOUR name shows as a name you type (optionally in a colour), and your BattleTag in the friends window shows as a made-up one
  - chat shows the same swapped names (your own lines use your made-up name); emotes too
  - whispers are kept out of chat and stored in a private inbox you read later; chat only says how many are waiting; chat bubbles are hidden (and put back afterwards, even after a crash)
  - minimap zone name and clock can be hidden; optional small PRIVATE MODE tag
  - Be right back screen: /aprivacy brb or its key covers the screen with your message and a timer Turn private mode off and everything is put back. This is NEW CODE written for Aimbot UI from the public feature description of ForeverEnhancedPrivacy. That addon is "All rights reserved" and forbids copying, so none of its code was used or read. Not covered (the game does not let addons change them, or I did not attempt them): names in tooltips, some right-click menu titles, the guild roster / news / mail / group finder names, gold, the world map, zone-change banners. See the "Good to know" area. It is not a security tool. If ForeverEnhancedPrivacy is also loaded, turn one of the two off.

## 2.7.1

- Double Press + Button Sparkle: the flash now has a second, independent trigger. An invisible key watcher in Double Press listens to the real key down / key up of every doubled key and tells Button Sparkle which button was pressed (it lets the key carry on to the game, so nothing is blocked). It works alongside the old hand-off from the hidden click-buttons; duplicates are dropped. "/aimbot diag" now shows how many key downs / ups the watcher saw and how many it handed to the sparkle.

## 2.7.0

- Search box at the top of the side menu. Type part of a setting's name (e.g. "red color", "lock", "outline") and the side menu turns into a list of matches from every tab, each showing which tab and area it lives in. Click one (or press Enter for the first) and it jumps there and flashes the setting. Escape or the x clears the search. Tab names and area names are searchable too.
- FPS / MS counter (new tab "FPS / MS", or /aimbot fps). Shows frame rate and latency at the bottom centre of the screen, e.g. "144 fps   23 / 41 ms" (home / world latency). Choose home, world or both, show or hide either number, colour them green / yellow / red by how good they are, change size, outline and background, and unlock it to drag it anywhere ("Back to bottom centre" resets it).

## 2.6.2

- The big "Choose an area" list and the "< All areas" button are gone: the side menu dropdown replaces them. Clicking a tab opens its first area straight away (Chat Mute opens on Muted players), and the dropdown rows switch areas. The side menu is wider, rows have a guide line, the current area has an accent bar, and notes in brackets are left off the short side labels.

## 2.6.1

- Side menu dropdowns: every tab now has a + / - on the right. Click a tab and it opens a list of its areas right under it (like a settings tree); click an area to jump straight to it, click the tab again to close the list. Only one list is open at a time, the current area is highlighted, and the side menu scrolls with the mouse wheel when a list is long. The "< All areas" button inside the page still works.

## 2.6.0

- Chat Mute (new tab "Mute", or /amute). Mute players, whole guilds, words and phrases (* is a wildcard), plus optional filters for links, ALL-CAPS shouting, repeated messages and strangers in public chat. Muted people are hidden from chat (and their speech bubbles in the open world), and their old lines are cleared from your chat windows. SPEAK TIMES: set when muted people may talk, e.g. "mon-fri 6pm-9pm" or "daily 8:00-10:00" (local or server time, midnight crossing works). Mode "Muted, except during these times" or the reverse. Quick "let them talk for N minutes" button and /amute allow 15, /amute stop. A "Never mute" list (players, guilds, friends, your guild, your group) always wins. Guilds are learned passively when you target or mouse over a player, or see them in your group (no /who spam). A mute of a guild only works for people the game has shown you. Optional: auto-decline guild/group invites, duels and trades from muted people. /amute target, /amute guild, /amute unmute NAME, /amute status. This is NEW CODE written for Aimbot UI from OlympusMute's public feature list. OlympusMute is "All Rights Reserved", so none of its code was copied. They can run side by side, but then turn one of them off so lines are not filtered twice. Not included: a tooltip line, /who scans.
- Range Alert: the red is now Bartender's look: the whole button icon turns red (default 0.8, 0.1, 0.1) while your target is out of range, and goes back to normal when you are in range. It replaces the old see-through red overlay. Same idea as Bartender, original code (Bartender is also "All Rights Reserved"). "Per button" and "Whole bar" modes and the distance readout are unchanged.

## 2.5.0

- Spell Trainer now uses the Forever spell data from the What's Training? addon you have installed (class spells with costs, required ranks and talents, quest-reward spells, weapon skills and the cities that teach them). The data is built in, so you no longer need to visit a trainer first. Hover a spell for details, right-click to ignore it, shift-click to link it. Colors are editable. Not included: hunter pet abilities, warlock demon tomes and profession recipes.

## 2.4.1

- Memory Cleaner: fixed stutter. Automatic cleans are now done in tiny slices (no freeze), stop when combat starts, and happen at most every 5 minutes. "Clean after combat" is off by default. The heavy per-addon memory scan now runs only on its button and about every 20 minutes while idle.

## 2.4.0

- Cleaner window: every tab now opens a LIST OF AREAS. Click an area to see just its options, then click "All areas" (or the tab name again) to go back. No more giant scrolling pages. Previews (Button Sparkle, Damage Font) stay on screen while you tweak.
- Color themes for the window (General > Theme) plus separate colors for the background, title bar, side menu, border, highlight and text.
- More colors: Mana Costs (one color per resource, can't-afford color, font, opacity), Range (readout in/out of range colors, outline), Lorti Style (your own health and mana bar colors, macro name and item count colors). Lorti's options are split into 7 areas.

## 2.3.0

- Memory Cleaner (QoL tab, or /aimbot clean): "Clear Cache" button that runs a full garbage collection, optional automatic cleaning (timed, after loading screens, after combat - never in combat), and a Leak Watch that lists the biggest addons and warns when one stays far above its starting size after a clean. It can't free memory an addon is truly holding on to (only /reload does) and can't delete the game's Cache folder on disk.

## 2.2.4

- Damage Font checks that the game has registered the font file, and says so if not (fully quit and restart WoW once after installing new files).

## 2.2.3

- Button Sparkle: survives secret-value geometry errors (e.g. in combat) and reports them in /aimbot diag.

## 2.2.2

- Button Sparkle works again for keys handled by Double Press.

## 2.2.1

- Fixed "execution tainted by AimbotUI" errors (health bars / pet frame / WeakAuras). Lorti Style no longer calls Blizzard's health bar code itself. Do a /reload.
- Damage Font: re-applied after every addon loads, warns about other combat text addons (e.g. the standalone NiceDamage - disable it, this tab replaces it), shows whether floating damage numbers are on, and has a button to turn them on. A new font needs you to LOG OUT TO THE CHARACTER SELECT SCREEN and back in. /reload is not enough.
