# Changelog

All notable changes to Aimbot UI, newest first. The latest version is also summarised under "What's new" in [README.md](README.md).

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
