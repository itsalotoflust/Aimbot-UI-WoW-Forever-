AIMBOT UI  v2.17.0  -  for World of Warcraft "Forever"
=====================================================

INSTALL
1. Delete any old copies first: AimbotUI, ForeverDark, ForeverSparkle.
2. Copy the folder "AimbotUI" into:
     C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\
   You should end up with ...\AddOns\AimbotUI\AimbotUI.toc
3. Start the game. At the character screen click "AddOns" and make sure
   Aimbot UI is ticked (tick "Load out of date AddOns" if it is greyed).
4. In game type  /aimbot  (or /aui) to open the window.

NEW IN 2.17.0
  - Aura Timers: your debuffs and crowd control on your target now come from the icons the
    target's nameplate shows. Your diag showed those icons are visible to addons (the aura
    lookups still find nothing), and the game puts exactly your debuffs and crowd control there
    the moment they land. So while your target has a nameplate:
    * a spell that misses never shows (no icon appears on the plate)
    * a trap shows when it actually catches the target (its crowd-control icon appears)
    * Intimidation shows when the stun lands
    * countdowns are copied from the game's own icon timers, so they're exact; when one can't
      be copied yet, the time comes from your landed cast as before
    * crowd control is listed first
    Without a nameplate (nameplates off, or out of range), the earlier ways are used.
    The cast check also uses the plate now: a cast only counts once a new icon appears on it.
    /aimbot diag shows the nameplate icons used and where each timer came from.

NEW IN 2.16.10
  - Aura Timers diag: /aimbot diag now also looks at the debuff icons your target's nameplate
    draws, and says whether addons can see them (how many icons, whether their pictures can be
    read or are hidden, and their countdowns). This tells whether landed / missed spells can be
    checked against the real debuffs on the nameplate. No change to what you see in game.

NEW IN 2.16.9
  - Aura Timers: placing a Freezing Trap started its timer right away. A trap was taken as landed
    as soon as the target's auras changed, and on this client they change all the time. Placing
    a trap (Freezing, Immolation, Explosive, Frost) now shows nothing; the timer starts only when
    the game reports the trap's effect (Freezing Trap 10 / 15 / 20 s by rank, Immolation 15 s,
    Explosive 20 s), or announces its aura. /aimbot diag shows traps placed and gone off.
    If the trap goes off and still nothing shows, the client isn't reporting the effect to
    addons; paste /aimbot diag after a trap and I'll look at it.

NEW IN 2.16.8
  - Aura Timers: hovering the space between (or just past) the icons showed some other aura's
    tooltip, from the game's hidden icons underneath. A see-through cover now sits under our
    icons and over the game's, as wide as the unit frame and one row lower than ours: hovering a
    gap shows nothing. It only takes mouse movement, so clicks still go through. It's only there
    while our icons show and their tooltips are on.

NEW IN 2.16.7
  - Aura Timers: hovering an icon showed the tooltip of a different aura. Our icons let the mouse
    pass through (2.13.4), so you were really hovering the game's hidden icon underneath, which
    is laid out differently (other size, other row length), so it was a different aura.
    * Our icons now sit on top of the game's hidden icons and show their own tooltip: always
      the aura that icon shows (by the aura's id; a cast-timed icon shows its spell).
    * Saved settings with our tooltips off are switched on once. "My icons show their own
      tooltip" in /aimbot timers still turns them off.

NEW IN 2.16.6
  - Aura Timers: crowd control shows again, with its time. Since 2.16.5 a cast had to change
    the target's auras within a second, but Intimidation stuns on your pet's next hit, seconds
    later, so it was thrown away as a miss.
    * Intimidation waits up to 6 seconds for the stun to land, and traps up to 30 seconds for an
      enemy to step in; their timer starts when it lands, not at the cast.
    * Known crowd control and stings count even when the client says the spell isn't harmful
      (Intimidation is cast on your pet): Intimidation, Scatter Shot, Concussive Shot, Scare
      Beast, Wyvern Sting, Viper / Scorpid Sting, Counterattack, Wing Clip, traps.
    * Known lengths are used before the description: Intimidation 3 s, Scatter Shot 4 s,
      Concussive Shot 4 s, Wyvern Sting 12 s (the game's own length wins once it's announced).
    * Your pet's casts count too (known debuffs only); its stun and your Intimidation show as one.

NEW IN 2.16.5
  - Aura Timers: a spell that missed still showed up as a debuff. A cast can "succeed" and
    still miss, and the game doesn't tell addons. Now a cast only counts once the target's
    auras change right around it (within a second); if they don't, it's treated as a miss and
    never shown.
  - Aura Timers: more ways to get real debuff times. The target's nameplate is now read too
    (the game may share more there), and aura announcements made for the target's nameplate
    count for the target. When either works, the times are the game's own, not estimates.
    /aimbot diag shows casts landed / missed and what the target's nameplate gives.

NEW IN 2.16.4
  - Aura Timers: your debuffs on enemies get their countdown from your own casts. Your diag
    showed that most debuffs you apply reach addons only as a "full update" with no details
    (3 announced vs 94 full updates), and every lookup finds nothing, so there was nothing to
    time. Now, when your harmful spell lands on your target, Aura Timers shows its icon with
    a countdown:
    * the length comes from what the game announced for that spell before (remembered between
      sessions), or else from the spell's description ("over 15 sec", "for 2 min")
    * a recast restarts it, it goes when its time is up, and a new target or a dead one clears it
    * spells without a debuff (Arcane Shot, Auto Shot, self buffs like Rapid Fire) are skipped
    Times from the description can be a little off if a talent changes the length; once the game
    announces that spell once, the real length is used. While your own icons show, the game's
    icons stay hidden, so other players' debuffs on that target aren't shown.
    /aimbot diag shows the casts tracked and how many spell lengths are known.

NEW IN 2.16.3
  - Aura Timers: your debuffs on enemies lost their countdown. Your diag showed the game does
    send the times (11 of 11 readable), but it also sends a "full update" many times a fight
    (112), and each one threw away the remembered debuffs. With nothing left, the game's own
    icons were shown instead, and those have no numbers. Full updates now keep them; a new
    target or focus still clears them, and debuffs whose time ran out are dropped.

NEW IN 2.16.2
  - Aura Timers: buffs and debuffs on the target / focus frame now wrap after 5 icons per row
    (it was 8, which ran far past the frame). Saved settings still on the old 8 are moved to 5;
    if you picked another number it is kept. Change it with "Icons per row" in /aimbot timers.

NEW IN 2.16.1
  - Lorti Style: fixed the error "Backdrop.lua:226: attempt to perform arithmetic on local
    'width' (a secret number value, while execution tainted by 'AimbotUI')". The outer shadow
    used Blizzard's backdrop template, whose code does maths on the frame's size; since 2.15.1
    the aura shadow sits on the icon, and this client keeps the icon's size secret. The shadow
    is now made of eight plain textures (corners and edges) that just follow the icon, so no
    size is ever read. Same look, for action buttons too. Empty slots still get no box.

NEW IN 2.16.0
  - New tab: Auto Shot Timer (/aimbot autoshot), for Hunters. A bar that fills up to your next
    Auto Shot, with a white marker where the shot's wind-up starts (0.5 s before haste). From
    the marker on, moving, jumping, casting something that stops Auto Shot, or the target going
    out of range holds the wind-up, and the bar turns red. Zero means the shot can go; the bar
    waits there until the game reports the shot.
    * Timing comes from the game's own shot reports (PLAYER_SWING), with a successful Auto Shot
      cast as the backup, and follows your ranged haste.
    * Hybrid mode (off by default): shows your main-hand swing while the target is in melee range.
    * Colours by range, Hunter class colour or one colour; width, height, texture, background,
      border, text size, marker, spark and seconds text can all be changed. Unlock to drag it.
    * Test button shows a 10 second preview (works on any class).
    Based on the idea of AutoShotTimer Forever by Antigravity and Gornax_; written new for Aimbot UI.
    If AutoShotTimer_Forever is also installed you'll see two bars: turn one off.
    NEW FILE: needs a full game restart (not just /reload) the first time.

NEW IN 2.15.1
  - Lorti Style: the borders on your own buffs and debuffs sat a little off, and empty slots
    showed dark boxes with nothing in them.
    * The border and shadow now sit on the icon itself, not the whole aura button (which also
      holds the time text, so the border came out too big and shifted).
    * A border only shows while the slot really has an aura. Empty slots and the game's
      placeholder frames get nothing, and when a buff runs out its box goes with it.
    /aimbot diag shows how many aura icons have borders and how many empty slots were skipped.

NEW IN 2.15.0
  - Window: the version number in the title bar is plain small text now, with no coloured box
    behind it. It follows the notes colour, and can be hidden.
  - More ways to style the window (General tab):
    * Look: font (game default, Friz Quadrata, Arial Narrow, Skurri, Morpheus, and two Aimbot
      UI fonts), text outline (none / thin / thick), text shadow, border thickness (modern
      style), and switches for the version number, the coloured mark before the title, the
      line under the title bar and the underline under each tab title.
    * Colors: highlight strength, and your own colour for the "AIMBOT UI" title.
    * Five new themes: Midnight, Ocean, Sand, Blood and Mono.

NEW IN 2.14.4
  - Aura Timers: your debuffs on enemies showed without their time left. The game can hand
    back an empty (zero) time for an enemy aura, and that was taken as "timer set". Every way
    of giving an icon its time is now checked, and a zero time moves on to the next way: the
    aura's own times first, then its id, then hidden times passed straight to the countdown.
    /aimbot diag shows which way each timer came from and what the aura events carried.

NEW IN 2.14.3
  - Aura Timers: your debuffs on an enemy could be missing from the target / focus frame. On
    this client the aura lookups can come back empty for an enemy even while your DoTs are on
    it, and the game's own icons were hidden. Two fixes:
    * The auras the game announces as they are applied (with their icon and time) are now
      remembered and shown, so a DoT you cast on your target shows with its countdown.
    * On an enemy where nothing at all can be read, the game's own icons are shown again (no
      timers, but your debuffs stay visible). An enemy with readable buffs keeps our icons, so
      the 2.13.3 enemy buff timers stay.
    /aimbot diag shows the aura events seen and when the game's icons are used instead.

NEW IN 2.14.2
  - Privacy: the BattleTag swap now covers the social window, which is where this client
    shows your tag (SocialUIFrame ... PersonalBattleTagDisplay, found with /fstack). 2.14.1 only
    looked in the old friends window, whose tag text is hidden here, so it swapped a text you
    never see. The tag is kept swapped while the social window is open, also when the game
    hides the text from addons. /aimbot diag lists where each swapped text lives.

NEW IN 2.14.1
  - Privacy: fixed your real BattleTag still showing in the friends window. The addon only
    changed one fixed text, which may not be the one this client's friends window shows (it
    can draw the name and the "#1234" part separately, next to a copy button). It now finds the
    BattleTag texts by what they show, swaps the name and number parts separately, and keeps
    them swapped while the friends window is open, so a redraw by the game is put right within
    a moment. Friends in your list are never touched.
    /aimbot diag now lists each BattleTag text found and what it is showing.

NEW IN 2.14.0
  - New: Loss of Control (Combat group, /aimbot loc). When you are stunned, feared, silenced,
    rooted and so on, a big icon of the effect shows in the middle of the screen with the time
    left counting down on it and the effect's name underneath. Built on the game's own loss of
    control data, so it covers whatever the game reports.
    Options: show the name, dark swipe, hide the game's own alert, sound, icon / number / name
    size, name colour. Unlock it to drag it anywhere, "Test" shows it for 5 seconds.
    This is a new file: fully restart the game (not just /reload) after updating.

NEW IN 2.13.6
  - Fixed: the repair, talent point, party death and +Combat / -Combat texts could stay
    invisible the first time they should show, until the text was unlocked and moved. The text
    frame was only given its screen position when a setting changed; it now gets it as soon as
    it is created.

NEW IN 2.13.5
  - Talent Point Alert: also reacts to the game's talent point / level change events, so it
    shows sooner after you level. /aimbot diag lists every place the point count can be read.

NEW IN 2.13.4
  - Aura Timers: no more double tooltips. The game's hidden icons still show their tooltip when
    hovered (addons can't turn that off), so our icons no longer show one of their own and let
    the mouse pass through. "My icons show their own tooltip" in the Aura Timers tab turns ours
    back on.

NEW IN 2.13.3
  - Aura Timers: enemy buffs have their time-left numbers again. 2.13.2 switched back to the
    game's icons (no numbers) on any enemy with no debuffs; that fallback is removed, since your
    debuffs on enemies are now read fine.

NEW IN 2.13.2
  - Aura Timers: your debuffs on enemies were invisible (the usual aura lookup returns nothing
    for enemy debuffs on this client, and the game's icons were hidden). Every other way the game
    offers to read auras is now tried in turn. If none works on an enemy, the game's own icons
    are shown instead (no timers, but your debuffs are visible) and ours are hidden so buffs don't
    show twice. /aimbot diag lists what each way returned.

NEW IN 2.13.1
  - Aura Timers: the target / focus aura row now starts right under the mana bar, lined up with
    its left edge. The time text is sized to fit the icon so it no longer spills over the next
    icon (own slider "Time text size", 0 = fit the icon), a little more space between icons,
    and a "Reset position" button.

NEW IN 2.13.0
  - Aura Timers: draws its own buff and debuff icons for your target and focus, each with a
    countdown of the time left. This client draws its own target aura icons where addons can't
    reach them, so they can't be given numbers; the game's icons are hidden instead (can be
    turned off). Buffs first, debuffs with a red border below, stack counts, tooltips on hover.
    Icon size, icons per row, how many, "only my debuffs" and position can be changed in the
    Aura Timers tab.

NEW IN 2.12.5
  - Aura Timers: looks for the target and focus aura icons where this client keeps them
    (TargetFrame.TargetFrameContent.TargetFrameContentContextual.Auras), found with /fstack.
    /aimbot diag now lists what is inside that container, and what the aura functions return
    for the target with other filters.

NEW IN 2.12.4
  - Aura Timers: also finds aura icons kept in icon pools under other names on the target and
    focus frames. /aimbot diag now digs further: how many buffs and debuffs the target really
    has, every cooldown widget on the target frame, its icon pools, and any frame in the game
    carrying an aura id, so the next report shows exactly where this client keeps the icons.

NEW IN 2.12.3
  - Aura Timers: also finds classic style aura buttons (TargetFrameBuff1, TargetFrameDebuff1...)
    and looks up their aura by slot number, so those icons get time-left numbers too.

NEW IN 2.12.2
  - Aura Timers: now finds the buff and debuff icons on this client's target and focus frames
    (they are not kept where the retail client keeps them, so 2.11 / 2.12.1 found none). Nameplate
    icons without a game timer also get the numbers-only timer. /aimbot diag now also lists how
    the target frame's icons are built (the "probe" lines) to help if a layout is still missed.

NEW IN 2.12.1
  - Aura Timers: buffs on enemy players (and any other target / focus aura icon the game draws
    no timer on) now get time-left numbers too. Aura Timers puts its own numbers-only timer on
    those icons, filled from the aura's own time. /aimbot diag shows how many icons got one.

NEW IN 2.12.0
  - Combat Indicator: "+Combat" (red) and "-Combat" (green) in the middle of your screen when you
    enter and leave combat. Text size, both colors, how long it stays, and "Lock position" (untick
    it and drag the text anywhere). Each of +Combat / -Combat can be turned off, and there is a
    Test button. The target / focus icons are unchanged.
  - Party Death Alert: a skull icon after "<Name> died" (can be turned off).

NEW IN 2.11.0
  - New module: Aura Timers (Combat). Time-left numbers on buff and debuff icons, so you can see
    how long your DoTs and crowd control have left on your target, focus and enemy nameplates.
    The game counts the time itself, so it keeps working even where the client hides aura times
    from addons. Choose target / focus / nameplates and the number size for each. It is a new
    file, so FULLY RESTART the game once after updating. Shortcut: /aimbot timers

NEW IN 2.10.0
  Three new on-screen alerts (each has its own tab and on/off switch). They are new files, so
  FULLY RESTART the game once after updating; /reload is not enough the first time.
  Only you see them; nothing is sent to chat. Each has text size, color, a Test button and
  "Lock position": untick it and drag the text anywhere, then lock it again.
  - Party Death Alert (Combat): "<Name> died" in the middle of your screen when a party member
    dies, name in class color, with a sound. Fades after a few seconds (adjustable). Optional for
    raid members too. Feign Death is ignored. With Privacy's private mode on it shows the class
    instead of the name.
  - Durability Alert (Quality of life): a pulsing "Repair your gear: 35%" that stays on screen
    while your gear is below 40% (adjustable), until you repair. Measures your most damaged item
    or the average of all gear, counts broken items, sound when it first drops.
  - Talent Point Alert (Quality of life): a pulsing "1 unspent talent point" that stays on screen
    until you spend it. Hidden in combat and while the talent window is open (both optional),
    sound when you get a new point.
  - New /aimbot shortcuts: death, repair, talent.

NEW IN 2.9.4
  - Lorti Style: new "Hide the colored background behind names" option under "Frame art and
    portraits" (on by default). Removes the red / yellow / green strip behind the target and focus
    name. Untick it to bring the strip back.

NEW IN 2.9.3
  - Removed the Lorti Style "Solid name background" option from 2.9.1 / 2.9.2. The strip behind
    unit names is the game's own art again, exactly as before.

NEW IN 2.9.2
  - Lorti Style "Solid name background": the solid bar now lines up with the health bar under it
    (same width, same height as the game's strip) instead of running under the portrait. The
    game's faded strip is hidden while it is on and comes back when you untick it.

NEW IN 2.9.1
  - Lorti Style: new "Solid name background (no fade)" option under "Frame art and portraits"
    (on by default). The colored strip behind the target and focus name (red, yellow, green) is
    the game's own art, which fades out toward the edge; it is now drawn as a solid bar in the
    same color. Untick it to get the game's faded art back. /aimbot diag lists the name bars found.

NEW IN 2.9.0
  Four new modules (each has its own tab and on/off switch). They are new files, so FULLY RESTART
  the game once after updating; /reload is not enough the first time.
  - Queue Timer (Quality of life): when a dungeon, battleground or arena queue pops, a bar counts
    down the seconds left to accept, a sound plays through the Master channel (heard even with game
    sounds down), it ticks every second near the end, and the game's taskbar icon flashes.
    Battlegrounds and arenas show the real time left; the dungeon finder counts from 40. Has a Test
    button, and the bar can be resized and moved.
  - Nameplate Icons (Combat): class icon above friendly players (optionally instead of their name,
    or only while Privacy's private mode is on), a healer icon on healers (enemy healers in arenas
    from their spec, anywhere else once they cast a healer-only spell; your group's healers from
    their role), and enemy players' PvP racial (Will of the Forsaken, Every Man for Himself,
    Stoneform...) next to their health bar.
  - Combat Indicator (Combat): crossed swords next to your target / focus frame while they are in
    combat, "Zzz" while they are not. Optional on yourself too, with size and position sliders.
  - Interrupt Ready (Combat): while an enemy casts, your interrupt (Kick, Pummel, Shield Bash,
    Counterspell, Earth Shock, Silence, Spell Lock...) shows next to their cast bar on nameplates,
    target and focus: green edge = ready, grey with a timer = on cooldown. Hides on casts that
    can't be interrupted.
  - New /aimbot shortcuts: queue, plates, combat, kick.

NEW IN 2.8.18
  - Privacy: new "Friendly name range (yards)" slider under "Show friendly players' names above heads"
    (default 60). While friendly names are on it raises how far away nameplates show, so friendly
    names appear from further away (this also applies to enemy plates). The game has its own maximum;
    the note under the slider shows the distance the game is really using. Your own range is put back
    when private mode is turned off. /aimbot diag shows it on the "friendly names" line.

NEW IN 2.8.17
  - Privacy "Show friendly players' names above heads" now actually turns on. This client uses the
    newer names for the friendly nameplate settings (nameplateShowFriendlyPlayers,
    nameplateShowOnlyNameForFriendlyPlayerUnits...), and 2.8.14 only set the older names, which the
    game ignored. Both sets are now listed and whichever exists is used. While it is on, friendly
    pet, guardian, minion and totem plates are also off so only players get a name; everything is put
    back when private mode is turned off. /aimbot diag shows the real values of these settings.
  - Side menu a little wider again so "Double Press (Wannabe AHK)" fits without "...".

NEW IN 2.8.16
  - Renamed "Button Sparkle" to "Button Flash". Your settings carry over. /sparkle still works, and
    "/aimbot flash" now opens its tab too.
  - Renamed "Double Press" to "Double Press (Wannabe AHK)". The side menu is a little wider, and a
    "(...)" note at the end of a name is drawn smaller and grey so the full name fits.

NEW IN 2.8.15
  - Fixed the "AddOn 'AimbotUI' tried to call the protected function 'UNKNOWN()'" error from Double
    Press. The invisible key watcher (used to flash Button Sparkle on your doubled keys) re-set a
    keyboard setting on every key press, and the game blocks that call in combat. It is now set once,
    out of combat, and the key presses themselves no longer touch it. The "never double" key picker
    got the same guard.

NEW IN 2.8.14
  - Privacy: new option "Show friendly players' names above heads (as their Privacy name)". While
    private mode is on it turns on the game's friendly nameplates in names-only mode (no health bar)
    and swaps each friendly player's name for your Privacy name (class, "Player" or nothing), so you
    can still see who is on your side. Friendly NPC plates stay off and your own name is not shown.
    Your nameplate settings are put back when private mode is turned off. In dungeons and raids the
    game locks friendly nameplates (an addon can't change their text), so they stay off there and come
    back when you leave. Nameplate settings can't change in combat, so a change waits until combat ends.

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
  Button Flash   jButtonFlash-style flash on your action buttons. Defaults match
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
  Queue Timer    Countdown bar, sound and taskbar flash when a queue pops.
  Nameplate Icons  Friendly class icons above heads, healer icons, enemy PvP racials.
  Combat Indicator Swords / Zzz next to target and focus: are they in combat?
  Interrupt Ready  Your interrupt next to enemy cast bars, green when ready.
  Diminish       DR icons on target, focus, enemy nameplates and you (green 50%, yellow 25%, red immune).
  Spell Trainer  WhatsTraining-style list. Open your class trainer once per
                 class to fill it, then it is remembered.

  Double Press (Wannabe AHK)   (category QoL) RougeUI's "Wannabe AutoHotKey": every action bar key
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
