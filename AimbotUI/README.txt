AIMBOT UI  v2.8.13  -  for World of Warcraft "Forever"
=====================================================

INSTALL
1. Delete any old copies first: AimbotUI, ForeverDark, ForeverSparkle.
2. Copy the folder "AimbotUI" into:
     C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\
   You should end up with ...\AddOns\AimbotUI\AimbotUI.toc
3. Start the game. At the character screen click "AddOns" and make sure
   Aimbot UI is ticked (tick "Load out of date AddOns" if it is greyed).
4. In game type  /aimbot  (or /aui) to open the window.

NEW IN 2.8.13
  - New CLASSIC style for the Aimbot UI window, made to look like the game's own option panels: a stone
    (or gold) dialog border, a dark textured background, gold labels with white section titles and a
    divider under each, the game's checkboxes (on the left of each setting), red game-style buttons,
    game-style sliders and drop-down boxes. This is now the default look.
  - Real drop-down lists: clicking a choice box (themes, modes, positions...) opens a list to pick
    from, instead of stepping through the options one click at a time. Works in both styles.
  - More themes (General tab > Theme), each with its own look:
      Classic: Stone, Gold trim, Rock, Marble, Tooltip (thin border), Horde, Alliance
      Modern:  Aimbot Blue, Crimson, Emerald, Violet, Gold, Ember, Frost, Fel, Rose, Graphite, Pure black
    plus "Style" (Classic or Modern), "Classic border" (Stone, Gold trim, Thin, None) and
    "Classic background" (Dark, Rock, Marble, Plain color). Switching between Classic and Modern
    needs a reload, so there is a "Reload now" button; borders, backgrounds and colors change live.
  - "Reset all window colors" now resets to the theme you picked instead of always Aimbot Blue.

NEW IN 2.8.12
  - A more modern look for the Aimbot UI window:
      * round toggle switches (pill track with a round knob), round slider handles and round on/off
        dots in the side menu
      * flat buttons with a soft accent wash on hover, and flatter text boxes and slider value boxes
      * cards have a softer background, a faint top light, a round accent dot before the title and
        their short description underneath
      * a bigger page title with a short accent underline, and "On"/"Off" next to each tab's switch
      * the version shows as a small chip in the title bar, the close button turns red on hover
      * a soft shadow around the window, a thinner scrollbar, and a little more breathing room
    The round shapes use a new image (media\ui\circle.tga), so FULLY RESTART the game once (a
    /reload will not find a new file). Until then they show as squares and everything still works.
  - Fixed: in 2.8.11 the General tab stopped part way (the module on/off list was missing) because
    of the new side menu sorting. It builds fully again.

NEW IN 2.8.11
  - Side menu tidied up. Diminish and Spell Trainer moved into Quality of Life, so each group now shows
    once: LOOK, COMBAT, then QUALITY OF LIFE, with the modules A-Z inside each group (the module list on
    the General tab uses the same order). Group names have a thin divider line and a bit more space
    above them, the on/off dots are a little smaller and the +/- markers are softer.
  - Help: the list of /aimbot tab names now includes mute, fps, privacy and dr.

NEW IN 2.8.10
  - Privacy: targeting yourself (or anyone) no longer flashes the real name for a moment before your
    Privacy name shows. The name on the target, target-of-target and focus frames is now swapped in the
    same instant the game draws it, instead of on the next check a moment later. The name texts are
    looked up once and remembered, and the fix only runs when you change target or focus, so there is no
    extra work every frame and no FPS cost. /aimbot diag now shows how many instant fixes ran.

NEW IN 2.8.9
  - Every slider in the window now lets you type a value. Click the number on the right of a slider,
    type the value you want and press Enter. Escape, or clicking somewhere else, puts the old value
    back. A typed value is kept inside the slider's range and rounded to its step, and you can type
    "%" or "s" after it or use a comma for the decimal point. The drag bar still works as before.

NEW IN 2.8.8
  - Diminish: YOUR own DR icons now sit in the middle of the screen, just below your character, instead of
    under the player frame, and you can drag them anywhere. Diminish tab > Your icons: tick "Unlock your
    icons to drag them", drag the blue box, then untick it to lock them. They have their own size slider
    (bigger by default), "Back to the middle of the screen" resets them, and "Your icons go" switches
    back to the player frame if you prefer.

NEW IN 2.8.7
  - Diminish (new tab "Diminish", or /aimbot dr): diminishing returns icons on your target and focus
    frames, on enemy nameplates, and for yourself (under your player frame). One icon per kind of crowd
    control (stuns, incapacitates, disorients, roots, silences, and optionally disarms). The border shows
    what the NEXT one will do: green 50%, yellow 25%, red immune, and the timer counts down to the reset.
    "Show test icons" lets you line them up. Size, spacing, colours, timer / % text and the position of
    each group can be changed.
    Inspired by the Diminish addon by Wardz (MIT); new code. Forever closes the combat log that Diminish
    used, so this reads the game's own DR event, and falls back to crowd-control debuffs the game lets
    addons see (classic rules: 18 s reset, 50% / 25% / immune; a 2-step mode is in Tracking).
    FIRST VERSION, written without being able to test it in game: run /aimbot diag after some PvP. It
    records what the game's DR event sends, so it can be fixed for Forever. Grey icons mean the game
    sent the DR with hidden (secret) details.

NEW IN 2.8.6
  - Privacy: new switch "Allow whispers from everyone (real names)" (Privacy tab > Chat). While private
    mode is on, whispers from everyone - other characters AND Battle.net friends, ones you get and ones
    you send - show in chat exactly as normal, with the sender's real name instead of "Player" or a
    class name, so you can see who it is and reply with R or by clicking the name. Off by default.
    It wins over "Keep whispers out of chat". Names in those whispers WILL be visible on stream.
  - /aimbot diag now says how whispers are being handled.

NEW IN 2.8.5
  - Double Press + Button Sparkle FIX: Double Press was reading its own key bindings back as if they were
    yours, so every rescan wrapped the action button in another hidden helper button (194 of them instead
    of about 50) and the sparkle was drawn on an invisible helper. It now always finds the real button,
    so the sparkle shows on the button you pressed. The helper buttons also stop piling up.
  - The raw-key backup path no longer gets stuck if a key release is missed.

NEW IN 2.8.4
  - Privacy performance fix (FPS drop / lag with nameplates): private mode no longer re-scans every
    frame several times a second. Names are now changed only when the game redraws that one name
    (raid frames, nameplates) or when you target / focus / group changes, with a light once-a-second
    safety check. Chat bubble and minimap settings are only touched when something actually changes.

NEW IN 2.8.3
  - Privacy: private mode is now ALWAYS switched on at login and /reload (no toggle needed each time).
    The key / /aprivacy still toggles it for the current session; the Privacy tab's Enabled switch turns
    the whole module off.

NEW IN 2.8.2
  - "/aimbot diag" (and Maintenance > Run diagnostics) now opens a copy window with the whole report
    (Ctrl+A, Ctrl+C to copy it), still prints it to chat, and also saves it in your settings file as
    "lastDiag" (written to disk when you /reload or log out).
  - Double Press + Button Sparkle: the flash now also listens on the real action button itself, so any
    press that reaches it (including the Double Press proxy buttons) flashes, whatever path it took.
  - Diagnostics for Sparkle now show real-button clicks seen, the last few triggers, and why any flash
    was dropped (hidden button, empty slot, debounce, combat-only, module off).

NEW IN 2.8.1
  - Privacy fix: your name on the player frame / portrait (and target, focus, party) is now found by
    what the text says, anywhere inside the unit frame, so it works with restyled frames such as
    BetterBlizzFrames instead of relying on a guessed path.
  - Privacy: new option "Hide the names the game draws above heads (including yours)": the green name
    over your character (and other players / pets, plus guild and title lines) is the game's own setting,
    so it is switched off while private and put back afterwards (also after a crash or logout).
  - "/aimbot diag" Privacy lines now list every name text found and what it currently shows.

NEW IN 2.8.0
  - Privacy / stream mode (new tab "Privacy", or /aprivacy). One switch (a key in Key Bindings > Aimbot UI,
    /aprivacy, or "turn on at login") makes the game safe to show on stream:
      * other players' names on unit frames, party/raid frames and nameplates become their class, "Player"
        or nothing; NPCs and pets keep theirs
      * YOUR name shows as a name you type (optionally in a colour), and your BattleTag in the friends
        window shows as a made-up one
      * chat shows the same swapped names (your own lines use your made-up name); emotes too
      * whispers are kept out of chat and stored in a private inbox you read later; chat only says how many
        are waiting; chat bubbles are hidden (and put back afterwards, even after a crash)
      * minimap zone name and clock can be hidden; optional small PRIVATE MODE tag
      * Be right back screen: /aprivacy brb or its key covers the screen with your message and a timer
    Turn private mode off and everything is put back.
    This is NEW CODE written for Aimbot UI from the public feature description of ForeverEnhancedPrivacy.
    That addon is "All rights reserved" and forbids copying, so none of its code was used or read.
    Not covered (the game does not let addons change them, or I did not attempt them): names in tooltips,
    some right-click menu titles, the guild roster / news / mail / group finder names, gold, the world map,
    zone-change banners. See the "Good to know" area. It is not a security tool.
    If ForeverEnhancedPrivacy is also loaded, turn one of the two off.

NEW IN 2.7.1
  - Double Press + Button Sparkle: the flash now has a second, independent trigger. An invisible
    key watcher in Double Press listens to the real key down / key up of every doubled key and tells
    Button Sparkle which button was pressed (it lets the key carry on to the game, so nothing is blocked).
    It works alongside the old hand-off from the hidden click-buttons; duplicates are dropped.
    "/aimbot diag" now shows how many key downs / ups the watcher saw and how many it handed to the sparkle.

NEW IN 2.7.0
  - Search box at the top of the side menu. Type part of a setting's name (e.g. "red color", "lock",
    "outline") and the side menu turns into a list of matches from every tab, each showing which tab and
    area it lives in. Click one (or press Enter for the first) and it jumps there and flashes the
    setting. Escape or the x clears the search. Tab names and area names are searchable too.
  - FPS / MS counter (new tab "FPS / MS", or /aimbot fps). Shows frame rate and latency at the bottom
    centre of the screen, e.g. "144 fps   23 / 41 ms" (home / world latency). Choose home, world or both,
    show or hide either number, colour them green / yellow / red by how good they are, change size, outline
    and background, and unlock it to drag it anywhere ("Back to bottom centre" resets it).

NEW IN 2.6.2
  - The big "Choose an area" list and the "< All areas" button are gone: the side menu dropdown
    replaces them. Clicking a tab opens its first area straight away (Chat Mute opens on Muted
    players), and the dropdown rows switch areas. The side menu is wider, rows have a guide line,
    the current area has an accent bar, and notes in brackets are left off the short side labels.

NEW IN 2.6.1
  - Side menu dropdowns: every tab now has a + / - on the right. Click a tab and it opens a list of
    its areas right under it (like a settings tree); click an area to jump straight to it, click the
    tab again to close the list. Only one list is open at a time, the current area is highlighted,
    and the side menu scrolls with the mouse wheel when a list is long. The "< All areas" button
    inside the page still works.

NEW IN 2.6.0
  - Chat Mute (new tab "Mute", or /amute). Mute players, whole guilds, words and phrases
    (* is a wildcard), plus optional filters for links, ALL-CAPS shouting, repeated messages
    and strangers in public chat. Muted people are hidden from chat (and their speech bubbles in
    the open world), and their old lines are cleared from your chat windows.
    SPEAK TIMES: set when muted people may talk, e.g. "mon-fri 6pm-9pm" or "daily 8:00-10:00"
    (local or server time, midnight crossing works). Mode "Muted, except during these times" or the
    reverse. Quick "let them talk for N minutes" button and /amute allow 15, /amute stop.
    A "Never mute" list (players, guilds, friends, your guild, your group) always wins.
    Guilds are learned passively when you target or mouse over a player, or see them in your group
    (no /who spam). A mute of a guild only works for people the game has shown you.
    Optional: auto-decline guild/group invites, duels and trades from muted people. /amute target,
    /amute guild, /amute unmute NAME, /amute status.
    This is NEW CODE written for Aimbot UI from OlympusMute's public feature list. OlympusMute is
    "All Rights Reserved", so none of its code was copied. They can run side by side, but then
    turn one of them off so lines are not filtered twice. Not included: a tooltip line, /who scans.
  - Range Alert: the red is now Bartender's look: the whole button icon turns red (default 0.8, 0.1,
    0.1) while your target is out of range, and goes back to normal when you are in range. It replaces
    the old see-through red overlay. Same idea as Bartender, original code (Bartender is also
    "All Rights Reserved"). "Per button" and "Whole bar" modes and the distance readout are unchanged.

NEW IN 2.5.0
  - Spell Trainer now uses the Forever spell data from the What's Training? addon you have installed
    (class spells with costs, required ranks and talents, quest-reward spells, weapon skills and the
    cities that teach them). The data is built in, so you no longer need to visit a trainer first.
    Hover a spell for details, right-click to ignore it, shift-click to link it. Colors are editable.
    Not included: hunter pet abilities, warlock demon tomes and profession recipes.

NEW IN 2.4.1
  - Memory Cleaner: fixed stutter. Automatic cleans are now done in tiny slices (no freeze), stop
    when combat starts, and happen at most every 5 minutes. "Clean after combat" is off by default.
    The heavy per-addon memory scan now runs only on its button and about every 20 minutes while idle.

NEW IN 2.4.0
  - Cleaner window: every tab now opens a LIST OF AREAS. Click an area to see just its options,
    then click "All areas" (or the tab name again) to go back. No more giant scrolling pages.
    Previews (Button Sparkle, Damage Font) stay on screen while you tweak.
  - Color themes for the window (General > Theme) plus separate colors for the background,
    title bar, side menu, border, highlight and text.
  - More colors: Mana Costs (one color per resource, can't-afford color, font, opacity),
    Range (readout in/out of range colors, outline), Lorti Style (your own health and mana bar
    colors, macro name and item count colors). Lorti's options are split into 7 areas.

NEW IN 2.3.0
  - Memory Cleaner (QoL tab, or /aimbot clean): "Clear Cache" button that runs a full garbage
    collection, optional automatic cleaning (timed, after loading screens, after combat - never
    in combat), and a Leak Watch that lists the biggest addons and warns when one stays far
    above its starting size after a clean. It can't free memory an addon is truly holding on
    to (only /reload does) and can't delete the game's Cache folder on disk.

NEW IN 2.2.4
  - Damage Font checks that the game has registered the font file, and says so if not
    (fully quit and restart WoW once after installing new files).

NEW IN 2.2.3
  - Button Sparkle: survives secret-value geometry errors (e.g. in combat) and reports them in /aimbot diag.

NEW IN 2.2.2
  - Button Sparkle works again for keys handled by Double Press.

NEW IN 2.2.1
  - Fixed "execution tainted by AimbotUI" errors (health bars / pet frame / WeakAuras).
    Lorti Style no longer calls Blizzard's health bar code itself. Do a /reload.
  - Damage Font: re-applied after every addon loads, warns about other combat text addons
    (e.g. the standalone NiceDamage - disable it, this tab replaces it), shows whether
    floating damage numbers are on, and has a button to turn them on.
    A new font needs you to LOG OUT TO THE CHARACTER SELECT SCREEN and back in. /reload is not enough.

WHAT IS INSIDE (each one is its own tab with its own on/off switch)
  General        Window size, opacity, colors, scale, lock; module list; reset
  Lorti Style    The Lorti UI look, rebuilt for Forever's Retail-style frames:
                 action button borders/shadows/icon crop, hotkey and macro text,
                 dark frame art, class/reaction colored health bars, class
                 portraits, hide hit numbers, buff/debuff borders, dark windows,
                 minimap wheel zoom. Every option can be toggled separately.
                 Every action button gets a solid black edge (thickness and
                 color adjustable) so no stray corner pixels show.
  Damage Font    NiceDamage fonts (8 styles) for floating combat text.
                 IMPORTANT: needs a FULL game restart, /reload is not enough.
  Sparkle        jButtonFlash-style flash on your action buttons. Defaults match
                 jButtonFlash exactly (white star pops to 1.5x, shrinks away
                 spinning 90 degrees in 0.3s). Options: 6 presets, live preview,
                 press or release trigger, keyboard / mouse, 7 shapes, custom /
                 class / random color, opacity, size, speed, padding, linear or
                 eased motion, draw layer, and optional extra layers (burst,
                 ring, flying stars) each with their own timing.
                 Also flashes Bartender4 / Dominos / ElvUI buttons if present.
                 (/sparkle on|off|test)
  Mana Cost      Mana/resource cost on action bar spells. Position: top / bottom /
                 any corner / center, plus left-right and up-down nudge sliders.
  Range Alert    Action button icons turn red when your target is out of range,
                 red clears when in range. Optional distance readout.
  Chat Mute      Mute players / guilds / words, with speak times when they may talk.
  FPS / MS       Frame rate and latency counter, bottom centre of the screen.
  Privacy        Stream mode: fake name / BattleTag, class names, whisper inbox, Be right back screen.
  Diminish       DR icons on target, focus, enemy nameplates and you (green 50%, yellow 25%, red immune).
  Spell Trainer  WhatsTraining-style list. Open your class trainer once per
                 class to fill it, then it is remembered.

  Double Press   (category QoL) RougeUI's "Wannabe AutoHotKey": every action bar key
                 presses twice, on key down and on key up. Off by default; turn on
                 with the Enabled switch. Keys you add to the list stay single
                 (use "Add a key", then press it), and macros with /cancelaura or
                 any /cancel... command are skipped automatically. Click a key in
                 the list to switch it between double and single. Works with the
                 default bars, Dominos and Bartender4. Turn off RougeUI's own
                 AutoHotKey option, or the two will fight over your keys.

COMMANDS
  /aimbot  /aui                open or close the window
  /aimbot lorti | damage | sparkle | mana | range | trainer | double | mute | fps | privacy | dr | general
  /sparkle on | off | test
  /aprivacy  (on | off | toggle | inbox | brb | status)
  /amute  (target | guild | allow 15 | stop | status | unmute NAME | on | off)
  /aimbot diag                 prints a diagnostic report (see below)

IF SOMETHING DOES NOT LOOK RIGHT
  Forever's frame names could not be tested from outside the game. Every part
  of the Lorti Style module is isolated, so if one part cannot find a frame it
  is skipped and the rest keeps working. Open the Lorti Style tab and press
  "Run diagnostics" (or type /aimbot diag) and send me the output.
  Some options need /reload to fully undo after turning them off.

NOT PORTED
  Lorti's "Thick Frames" option is not included (it edits Blizzard frame
  layouts, which is not safe on Forever's engine).

CREDITS
  Lorti UI Classic artwork and feature set: Lorti, Chordsy, Macumba, Knall,
  Jozh, Xyz, Arrone, Redskin. NiceDamage fonts: Montyburns.
  Logic re-written for Forever. See CREDITS.txt inside the addon folder.
