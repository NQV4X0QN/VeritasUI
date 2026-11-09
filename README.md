# VeritasUI

A World of Warcraft addon suite for **Midnight** (patch 12.1.5) that makes the default interface cleaner and more convenient, especially for solo play. It also loads in **WoW Forever**; support there is early, and anything Forever doesn't have is left out there.

VeritasUI doesn't replace Blizzard's interface. It works inside it: its settings live in the normal **Options → AddOns** panel, all under one **VeritasUI** entry, its windows look and behave like Blizzard's own, and anything WoW already does well is left to WoW. If you didn't know VeritasUI was installed, most of it should just feel like the game.

The suite is split into modules. Each one does one job and has its own settings, and almost everything can be switched off individually.

## What's included

### Interface — a cleaner screen, solo or in a raid
Hides or fades the parts of the interface you don't need most of the time. On a new install every fade and hide starts off, so the screen looks exactly as it did; turn on the ones you want in **Options → AddOns → VeritasUI → Interface**.

- The **chat window** fades when you're not using chat and comes back on mouseover: its background, its tabs and the chat buttons you haven't hidden (with Chat Style set to IM, the box you type in too). The messages stay readable
- The micro menu, the bag bar, chosen action bars (2–8, the pet bar and the stance bar) and your player frame fade out when idle and reappear on mouseover, in combat, or when you take damage. Tick **Show Resource Changes** (on by default) to keep your player frame up while your mana, energy, rage, fury or other main resource is still filling or draining out of combat, through the end of a fight, until mana is full or rage is empty. In WoW Forever, **Show While Your Pet Isn't Happy** (on by default) keeps your player frame and your pet's frame up while your pet isn't happy
- **Action Bar 1** fades out unless you're in combat or mousing over it, and is shown in full while it holds vehicle or quest controls; tick **Show While Flying** (on by default; not in WoW Forever, which has no flying) to keep it up in flight
- Your **buffs and debuffs** by the minimap fade out unless you're in combat or mousing over them. Tick **Show Expiring Buffs** (on by default) and a buff with 30 seconds or less left comes back on its own while the rest stay faded, so you see it run out. In WoW Forever, **Show Campfire Buff** (on by default) does the same for the buff you get near a campfire, for as long as you have it
- The **minimap alerts** (mail and crafting order icons, and Quality of Life's Great Vault button) fade out until you mouse over them
- **Fade Minimap Buttons**: pick which pieces around the minimap fade out: zone name, clock, calendar, tracking, addon compartment, expansion summary button and instance difficulty. Mouse over the minimap or any of them and they all come back; a faded one can still be clicked. Its own slider sets how much still shows. Applies at once
- The **damage meter** fades out unless you're in combat or mousing over it
- The **objective tracker** (All Objectives) fades out until you mouse over it, each section (quests, world quests, campaign, scenario and the rest) to its own opacity. A section at 0% folds away so the ones below move up; your focused quest stays at full opacity at the top of its section, under its header, and so do quests ready to turn in (**Show Quests Ready to Turn In**, on by default) and quests in your zone that have an item to use (**Show Quests With Items**, on by default). Optionally hidden in raids, or only during raid boss fights
- The **reputation, experience and honor bars** fade out until you mouse over them; tick **Show on Gains** to have them appear for 3 seconds whenever you gain reputation, experience or honor
- **Faded opacity**: a slider beside each Fade option sets how much still shows while faded, from 0% (hidden) to 100%; Action Bar 1 and the bars picked in Fade Action Bars each have their own
- **All Faded Opacity**: one slider that sets every Faded Opacity slider to the same value at once, as a starting point; each one can still be changed on its own afterwards. The objective tracker's Scenario, Event Objectives and Bonus Objectives sections are left as they are
- **Fade Delay**: keep the micro menu, action bars and player frame up for 0 to 5 seconds after the mouse leaves, before they fade (the chat window keeps Blizzard's own timing)
- **Fade Together**: pick fades that come in together, such as Action Bar 1, the micro menu, the bag bar and the reputation and experience bars along the bottom of the screen. Mouse over any of them and all the ones you picked come in, then fade out together when the mouse leaves them all. Only the mouse links them; combat and the other reasons still bring in just the one. Tick **Show in Combat** (on by default) and every linked fade is also shown while you're in combat, so a bar made of linked pieces stays whole in a fight. The chat window can't be linked
- Optionally hides the social button, the chat menu and voice buttons (left shown, they fade with the chat window), and macro names on action buttons
- Optionally hides the **talking head** story popup and, separately, **mutes its voice**, so you can keep either one
- **Mute Spell Fizzle** (off until you turn it on) silences the fizzle sound a spell makes when it fails to cast
- Optionally hides the **top banners**, picked by kind from a dropdown: zone names, boss kills and loot, level up, scenario and Delve stages, Delve and event messages (such as Nemesis Strongbox Upgraded), weekly rewards, renown, and everything else
- **Hide Transforms**: takes costumes and transformations off you as soon as they land, picked by group: profession gear (so your own outfit stays while you craft, gather or fish), holiday costumes, toys and consumables. Not in combat; they come off when it ends. If one still shows, `/interface gear` lists what you're wearing
- Hides red error text — all of it, or only the kinds you pick (combat, spells and cooldowns, items and bags, mail/vendors/bank, looting, mounts and flight paths), so "Internal mail database error." can go while "You are too far away!" stays

Settings: **Options → AddOns → VeritasUI → Interface**, or `/interface`, grouped by where things sit on screen: **All Fades**, **Action Bars**, **Micro Menu and Bags**, **Player**, **Chat**, **Minimap**, **Trackers and Meters** and **Messages and Popups**. Every dropdown of choices has **None** and **All** at the top. Changes apply after a `/reload`, except Fade Delay, the opacity sliders, Hide Transforms, Fade Minimap Buttons, Fade Action Bars and the Action Bar 1, buffs and debuffs, minimap alerts, damage meter, objective tracker and reputation bar fades, which apply at once.

### Quality of Life — small conveniences
- **Item levels** on gear in your bags, bank, warband bank, character panel and at merchants
- **Auto equip upgrades** (off until you turn it on): puts on gear from your bags that beats what you're wearing (at least as much of every stat and more of one; otherwise higher item level, then better quality, then more armor), or fills an empty slot, out of combat, naming each swap in chat. Choose which qualities count: grey and white by default, green, blue, purple and orange if you tick them. Only gear you can use, never gear that would bind when equipped; gear with a main stat that isn't yours replaces what you wear only when that has none of yours, or when it is at least 5 item levels or 25% higher (whichever is more) and still wins the comparison; trinkets are left alone and weapons only replace one of the same kind. `/qol equipcheck` lists what it would do with each piece in your bags
- **Auto sell junk** and **auto repair** at merchants, with a choice of paying repairs from guild funds or your own gold. A bag you've set to ignore junk selling in its bag menu is left alone. **Junk Lists** (`/qol junk`, or the Open button under Auto Sell Junk): drag items from your bags onto **Never Sell** to keep a grey, or **Always Sell** to sell something that isn't grey (never while it can still be refunded or traded to your group); right-click one to take it off. **Keep Unbound Grey Gear** (off until you turn it on) keeps grey weapons and armor that aren't bound, for the Auction House
- **`/way` waypoints** (on unless you turn it off) in the format most guides use, e.g. `/way #2351 45.2 56.3`, placing WoW's own map pin and arrow (if TomTom is installed, it keeps `/way`)
- **AFK screen** (off until you turn it on): a slow camera orbit with your name, level, item level and zone while you're away (in WoW Forever your guild rank and guild instead of item level), which also helps against screen burn-in. Windows you open while away (bags, character sheet, chat) show up, tooltips included, and so do tooltips for players, NPCs and objects you mouse over in the world
- **Delve counts** shown right on the Delve objective icon instead of only in its tooltip: the Nemesis count, and in a Labyrinth the Treasure Room chambers completed, with a checkmark at 9
- **Map notes** (on unless you turn it off): `/note <text>` leaves a note on the map where you're standing. Click a note to change its icon or remove it; `/note clear` removes the notes on your current map. Notes left inside a Labyrinth or other instance are removed when you leave it
- **Track latest reputation** (off until you turn it on): the reputation bar switches to whichever faction you most recently earned reputation with
- **Renown level on the reputation bar**: your renown level at the end of the bar's text, such as [18/20], and past the top the levels earned beyond it, such as [21/20]
- **Great Vault button by the minimap**: the Great Vault button sits under the minimap's mail icon whenever your vault holds something, including last week's rewards; click it to open the vault
- **Fill In DELETE** (off until you turn it on): when you delete a valuable item, DELETE is typed in for you, so Enter or Yes confirms
- **Skip Cinematics** (off until you turn it on): Escape skips a cinematic or movie straight away instead of asking first
- **NPC shortcuts** (each off until you turn it on): picks an NPC's only dialogue option, **auto accepts** quests and **auto turns in** completed quests — separate options, and holding Shift while you talk to the NPC pauses them (pick another key under **Hold Key**: Ctrl, Alt, or Command on a Mac). Reward choices and quests that cost gold are always left to you, and so is a hand-in that would spend currency or an account-bound item, or crafting reagents on a repeatable quest (such as reputation turn-ins)
- **Untrack World Quests When Unfocused** (off until you turn it on): a world quest you clicked on the map leaves the tracker when you click it again; ones you tracked yourself stay
- **Quest Options**: rules for the NPC shortcuts — skip older-expansion quests at max level, no auto accept when an NPC offers several, use them only while holding the Hold Key, or turn them off in dungeons and raids
- **Auto accept resurrection** (on unless you turn it off; in combat too if you choose), **auto unwrap** new mounts, pets and toys, and any mount or pet still wrapped when you log in (off until you turn it on), and **auto open containers** (off until you turn it on), which leaves warbound containers and locked lockboxes for you and never opens anything in combat or at a vendor, bank or mailbox
- **Train All** button at trainers: learns everything available that you can afford in one click
- **Trainer button** (WoW Forever; on unless you turn it off): your class icon under the minimap's tracking button whenever your class trainer has a skill you can learn at your level. Hover it for the skills; click it for your trainer's list, saved at your last visit, in a window like the trainer's own, with the trainer's tooltip on each skill. Visit a pet trainer and a **Pet Trainer** tab appears beside it with your pet's skills. **Always Show Trainer Button** keeps it there, dimmed, when there's nothing to learn yet, its tooltip naming the next level's skills. `/qol trainer` opens the list any time
- **Tooltips**: who a player or NPC is targeting, green when it's you; the mount a player is riding, with a check or red X for whether you own it; players' names in their class color; and their faction, Horde or Alliance, in the game's own faction red or blue. It also fixes Blizzard's max-renown reputation tooltip, whose long line ran off the edge. Each is its own option, and each is left out where the game hides it from addons
- **Guild and friends**: a player's guild rank on their tooltip's guild line, and your own guild's name there in your guild chat colour; hover the Guild & Communities button or the Social button by the chat window to see who in your guild, or which friends, are online (click a name to whisper, Shift-click to invite; **Show Guild Notes** adds each member's public note); **Accept Group Invites From** (none until you pick): accepts group invites from your friends, your guild or both, never when accepting would take you out of a queue; and **Decline From Strangers** (none until you pick): declines duels, group invites, requests to join your group, Battle.net friend requests and shared quests from anyone who isn't your friend, Battle.net friend or guild member. Quick Join requests are left to the game's own setting in Options → Social
- **Chat**: hover a link in chat to see its tooltip; your group's names in their class colour wherever they appear in a message; and a choice of **whisper sound** (Blizzard's, None, or one of the game's other alert sounds); a **copy chat** button beside the chat window that shows the tab's text ready to copy; **remember chat history**, so each window's last 100 lines come back after a reload or relog, in grey, with guild, whisper, party, instance and raid lines in a soft version of their own colour so past conversations stand out (officer chat is protected by the game and isn't remembered); and **remember typed history**, so the last 5 lines you typed in the chat box, commands included, stay in its history (both saved for each character on your computer, whispers included — turn one off and what it saved is deleted)
- **Timestamp every message** (off until you turn it on): Blizzard's chat timestamp on system, loot, money, achievement, experience and reputation lines and VeritasUI's own messages, not just player chat. Uses the format from Options → Social → Chat Timestamps
- **Abbreviate Channel Names** (off until you turn it on): [G] for [Guild], [P] for [Party], [2] for [2. Trade] and so on; clicking the short name still opens that channel
- **Hide AddOn Messages** (off until you turn it on): hides what other players' AddOns post in chat on their own, if you don't use those AddOns — Questie's quest progress, Astral Keys' keystones, Details! death announcements, Nova World Buffs' timers. An AddOn you have installed isn't listed: its own settings decide what you see. What people type, boss mod warnings and anything an AddOn shows only to you are left alone
- **Character sheet**: a green check beside each slot whose enchant and gems are all there, or a red X on Epic and Legendary gear when one is missing, with a tooltip naming what's there and what's missing; durability on each slot below 100%; your Mythic+ rating under your item level; in the stat tooltips, the rating lost to diminishing returns and the rating left before the next penalty (Retail only: WoW Forever's ratings have none); and, when you hover a stat, attributes such as Stamina included, the gear that has it lit up
- **Journeys shortcuts** (on unless you turn it off): adds the "Show as Experience Bar" checkbox to Delves and Prey cards, and lets you click the reputation or honor bar to open that faction's page or the PvP window, or the experience bar to open Character Info

For map and minimap coordinates, use WoW's own options in **Options → Interface**.

Settings: **Options → AddOns → VeritasUI → Quality of Life**, or `/qol`.

### Auction House — prices and faster selling
- A **Scan** button records current prices across the whole auction house
- **Tooltip prices** on items and battle pets, anywhere in the game, styled like Blizzard's "Sell Price" line; soulbound and other bound items show none, since they can't be auctioned
- A **sell strip** on the Sell tab lists your sellable bag items: right-click one to load it, then left-click it again to post (Shift-click hides an item from the strip). Your bags need to be open.
- **Reagents value** on the Place Crafting Order form, so you can weigh a commission against the cost of materials

Settings: **Options → AddOns → VeritasUI → Auction House**, or `/ah`.

### Zone Quests — a tidy quest tracker
Shows only quests for the zone you're in, updating as you travel. In a dungeon or raid, the quests your quest log lists under that instance's name show too, even ones with no marker on the map (such as a collect-and-turn-in quest whose quest giver is outside). Campaign, important, legendary, meta and daily/weekly quests can be kept visible everywhere, and the quest you're navigating to always stays. Turning it off puts back the tracking you had chosen before. It's turned on or off for each character on its own, and starts off on a new install.

Settings: **Options → AddOns → VeritasUI → Zone Quests**, or `/zq`.

### Priority Rotation — one-button play
An accessibility tool: press one key, or hold it with your keyboard or mouse software's key repeat, to step through a list of spells, macros and trinkets that **you** choose. You decide how often each ability comes up, which ones wait for a channelled spell such as Eye Beam (cast right after it, or held for it and never cast on their own), and which only fire in combat. Each specialization keeps its own list. A new list starts with Blizzard's **Single-Button Assistant**, so one key plays a full rotation from the start, with channelled spells such as Eye Beam no longer cut short by the next press; add, remove or reorder abilities whenever you like.

To set it up, open `/pr`, click **Create / Update Macro**, drag the `Attack` macro onto any action bar (1–8), bind a key to it, and click **Scan & Bind** at the bottom of the Settings tab. On the Rotation tab, drag a slot up or down to change the order, and hover a column's heading to see what it does.

To switch specialization quickly, hover **VeritasUI — Priority Rotation** in the AddOns menu by the minimap and pick a spec from the list that opens.

Settings: `/pr` (the rotation editor), or **Options → AddOns → VeritasUI → Priority Rotation**, which has an on/off switch and an **Open** button for the editor.

### Advanced Options — WoW's hidden settings
WoW has many settings (CVars) that its Options panel doesn't show. The **Featured** tab gathers useful ones (camera distance, nameplates, combat text, soft targeting, graphics and more) as ordinary checkboxes, sliders and dropdowns, each with a reset button, in sections you can fold away one at a time or all at once with **Collapse All** / **Expand All**. Settings marked with an orange **!** need a reload; change one and a **Reload UI** button appears beside Collapse All. Among them: **Sharpen at Full Resolution**, **Show Help Tips**, and a dropdown beside **Enable Floating Combat Text** to choose what scrolls over your character (dodges, auras, power gains, reputation and more). The **All CVars** tab lets you search and edit every setting your client has, and star favourites.

Open it with `/ao`, or from **Options → AddOns → VeritasUI → Advanced Options**, whose **Open** buttons go straight to the window or to either tab. Its settings live in that window rather than an Options panel. In WoW Forever its tabs, like Priority Rotation's, are icon tabs down the right edge, matching Forever's own windows.

Stopped using ElvUI? ElvUI changes a number of these settings (nameplates for every NPC among them) and they stay changed after it is turned off. Type `/ao elvui`, or tick **Changed by ElvUI** on the All CVars tab, to see the ones that differ from Blizzard's defaults and reset them, one at a time or all at once. VeritasUI mentions it once, on your first login without ElvUI.

Tried another addon and something odd stayed behind? Type `/ao changed`, or tick **Changed** on the All CVars tab, to list every setting that differs from Blizzard's default, whoever changed it. Right-click a row to reset it. With nothing searched, **Reset Everything** puts every game setting back to Blizzard's default, the same as typing `/console cvar_default` (keybindings, Edit Mode layouts and addon settings are not touched). Search first (for example `nameplate`) and the button becomes **Reset All to Default**, which resets only the rows listed.

### VeritasUI Lib — shared core
Required by every other module. It also provides:

- `/vui`, which lists every module's command
- **Copy settings** from another of your characters (`/vui copy`, or the **Copy From…** button on VeritasUI's Options panels)
- A **Reload UI** button on those panels
- **Steps aside for other AddOns**: when another AddOn already does what one of VeritasUI's options does (and that option of theirs is on), VeritasUI's option is greyed out with the reason in its tooltip and doesn't run, and your setting comes back as it was once it stops. In a list of choices, only the overlapping choice is greyed

## Settings across characters

Most settings are shared by all your characters, so you set them up once. A few are naturally per-character: which action bars fade, the player frame fade, how repairs are paid, map notes, and Priority Rotation lists, which are per character and per specialization.

Most modules are also listed in the minimap's addon menu (the addon compartment) for quick access to their settings.

## Installation

**With CurseForge:** install VeritasUI from CurseForge, in the CurseForge app or on the website. It updates from there like any other addon.

**By hand:**

1. Download the latest `VeritasUI-vX.Y.Z.zip` from the [Releases page](https://github.com/NQV4X0QN/VeritasUI/releases/latest).
2. Extract it and copy all seven `VeritasUI_*` folders into the AddOns folder of the game you play:
   ```
   World of Warcraft/_retail_/Interface/AddOns/      (Retail)
   World of Warcraft/_forever_/Interface/AddOns/     (WoW Forever)
   ```
3. Keep the folder names exactly as they are.
4. Restart the game, or type `/reload` if it's already running.

Install all seven folders together. They share one version number, and every module needs `VeritasUI_Lib`. If you installed `VeritasUI_ElvUI` from an earlier version, delete that folder: it has been retired. Don't want a module? Disable it in the AddOns list on the character screen.

## Requirements

- World of Warcraft: Midnight, patch 12.1.5, or WoW Forever 1.60.1. One download works in both
- No other addons or libraries needed

## Design principles

- **Native first.** If WoW has a built-in way to do something, VeritasUI uses it rather than building its own.
- **Looks like the game.** Fonts, spacing, windows and settings panels match the default interface.
- **Out of the way.** One line in chat at login. Nothing changes your game settings without telling you.
- **Honest about limits.** If a feature has a cost or limitation, it says so.

## Known limitations

- **Quest reward item levels** aren't shown, because the game doesn't reliably provide the final item level before you choose a reward.
- **Player frame fade** reacts to damage events rather than reading your health directly, because Midnight hides health values from addons.
- **Sell strip loading** goes through Blizzard's bag window. With a bag addon that replaces Blizzard's bags, load items from that addon instead.

## Changes and support

See [CHANGELOG.md](CHANGELOG.md) for what changed in each version. Problems can be reported on the [Issues page](https://github.com/NQV4X0QN/VeritasUI/issues).

## For developers

[PROBE_LIBRARY_AND_REFERENCE.md](PROBE_LIBRARY_AND_REFERENCE.md) is a development notebook of in-game measurement scripts and Blizzard values. Players don't need it.

## License

GNU General Public License v2.0. See [LICENSE](LICENSE).
