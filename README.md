# VeritasUI

A World of Warcraft addon suite for **Midnight** (patch 12.1.5) that makes the default interface cleaner and more convenient, especially for solo play.

VeritasUI doesn't replace Blizzard's interface. It works inside it: its settings live in the normal **Options → AddOns** panel, all under one **VeritasUI** entry, its windows look and behave like Blizzard's own, and anything WoW already does well is left to WoW. If you didn't know VeritasUI was installed, most of it should just feel like the game.

The suite is split into modules. Each one does one job and has its own settings, and almost everything can be switched off individually.

## What's included

### Clean Solo — a quieter screen
Hides or fades the parts of the interface you don't need most of the time.

- The **chat window** fades when you're not using chat and comes back on mouseover: its background, its tabs and the chat buttons you haven't hidden (with Chat Style set to IM, the box you type in too). The messages stay readable
- The micro menu, chosen action bars (2–8) and your player frame fade out when idle and reappear on mouseover, in combat, or when you take damage
- **Action Bar 1** fades out unless you're in combat or mousing over it, and is shown in full while it holds vehicle or quest controls; tick **Show While Flying** (on by default) to keep it up in flight
- Your **buffs and debuffs** by the minimap fade out unless you're in combat or mousing over them
- The **minimap alerts** (mail and crafting order icons, and Quality of Life's Great Vault button) fade out until you mouse over them
- The **damage meter** fades out unless you're in combat or mousing over it
- The **objective tracker** (All Objectives) fades out until you mouse over it
- The **reputation, experience and honor bars** fade out until you mouse over them; tick **Show on Gains** to have them appear for 3 seconds whenever you gain reputation, experience or honor
- **Faded opacity**: a slider beside each Fade option sets how much still shows while faded, from 0% (hidden) to 100%; the one beside Fade Main Action Bar covers every faded action bar
- **Fade Delay**: keep the micro menu, action bars and player frame up for 0 to 5 seconds after the mouse leaves, before they fade (the chat window keeps Blizzard's own timing)
- Optionally hides the social button, the chat menu and voice buttons (left shown, they fade with the chat window), the bag bar, and macro names on action buttons
- Optionally hides the **talking head** story popup and, separately, **mutes its voice**, so you can keep either one
- Optionally hides the **top banners**: the zone name when you travel, event banners such as level up and scenario stages, and the boss kill and loot banner
- **Hides profession gear**: keeps your own outfit on while you craft, gather or fish, instead of the profession outfit the game puts on you. If one still shows, `/cs gear` lists what you're wearing
- Hides red error text — all of it, or only the kinds you pick (combat, spells and cooldowns, items and bags, mail/vendors/bank, looting, mounts and flight paths), so "Internal mail database error." can go while "You are too far away!" stays

Settings: **Options → AddOns → VeritasUI → Clean Solo**, or `/cs`, grouped under **Fade** and **Hide**. Changes apply after a `/reload`, except Fade Delay, the opacity sliders, Hide Profession Gear and the Action Bar 1, buffs and debuffs, minimap alerts, damage meter, objective tracker and reputation bar fades, which apply at once.

### Quality of Life — small conveniences
- **Item levels** on gear in your bags, bank, warband bank, character panel and at merchants
- **Auto sell junk** and **auto repair** at merchants, with a choice of paying repairs from guild funds or your own gold
- **`/way` waypoints** (on unless you turn it off) in the format most guides use, e.g. `/way #2351 45.2 56.3`, placing WoW's own map pin and arrow (if TomTom is installed, it keeps `/way`)
- **AFK screen**: a slow camera orbit with your name, level, item level and zone while you're away, which also helps against screen burn-in. Windows you open while away (bags, character sheet, chat) show up, tooltips included
- **Delve counts** shown right on the Delve objective icon instead of only in its tooltip: the Nemesis count, and in a Labyrinth the Treasure Room chambers completed, with a checkmark at 9
- **Map notes** (on unless you turn it off): `/note <text>` leaves a note on the map where you're standing. Click a note to change its icon or remove it; `/note clear` removes the notes on your current map. Notes left inside a Labyrinth or other instance are removed when you leave it
- **Track latest reputation** (off until you turn it on): the reputation bar switches to whichever faction you most recently earned reputation with
- **Renown level on the reputation bar**: your renown level at the end of the bar's text, such as [18/20], and past the top the levels earned beyond it, such as [21/20]
- **Great Vault button by the minimap**: the Great Vault button sits under the minimap's mail icon whenever your vault holds something, including last week's rewards; click it to open the vault
- **Fill In DELETE** (off until you turn it on): when you delete a valuable item, DELETE is typed in for you, so Enter or Yes confirms
- **Skip Cinematics** (off until you turn it on): Escape skips a cinematic or movie straight away instead of asking first
- **NPC shortcuts**: picks an NPC's only dialogue option, and, if you turn them on, **auto accept** quests and **auto turn in** completed quests — separate options, and holding Shift while you talk to the NPC pauses them. Reward choices and quests that cost gold are always left to you
- **Train All** button at trainers: learns everything available that you can afford in one click
- **Tooltips**: who a player or NPC is targeting, green when it's you; the mount a player is riding, with a check or red X for whether you own it; players' names in their class color; and their faction, Horde or Alliance, in the game's own faction red or blue. It also fixes Blizzard's max-renown reputation tooltip, whose long line ran off the edge. Each is its own option, and each is left out where the game hides it from addons
- **Timestamp every message**: Blizzard's chat timestamp on system, loot, money, achievement, experience and reputation lines and VeritasUI's own messages, not just player chat. Uses the format from Options → Social → Chat Timestamps
- **Character sheet**: a green check beside each slot whose enchant and gems are all there, or a red X on Epic and Legendary gear when one is missing, with a tooltip naming what's there and what's missing (optionally with the labels in your class colour); durability on each slot below 100%; and your Mythic+ rating under your item level
- **Journeys shortcuts** (on unless you turn it off): adds the "Show as Experience Bar" checkbox to Delves and Prey cards, and lets you click the reputation or honor bar to open that faction's page or the PvP window

For map and minimap coordinates, use WoW's own options in **Options → Interface**.

Settings: **Options → AddOns → VeritasUI → Quality of Life**, or `/qol`.

### Auction House — prices and faster selling
- A **Scan** button records current prices across the whole auction house
- **Tooltip prices** on items and battle pets, anywhere in the game, styled like Blizzard's "Sell Price" line
- A **sell strip** on the Sell tab lists your sellable bag items: right-click one to load it, then left-click it again to post (Shift-click hides an item from the strip). Your bags need to be open.
- **Reagents value** on the Place Crafting Order form, so you can weigh a commission against the cost of materials

Settings: **Options → AddOns → VeritasUI → Auction House**, or `/ah`.

### Zone Quests — a tidy quest tracker
Shows only quests for the zone you're in, updating as you travel. Campaign, important, legendary, meta and daily/weekly quests can be kept visible everywhere, and the quest you're navigating to always stays. Turning it off puts back the tracking you had chosen before. It's turned on or off for each character on its own.

Settings: **Options → AddOns → VeritasUI → Zone Quests**, or `/zq`.

### Priority Rotation — one-button play
An accessibility tool: press one key, or hold it with your keyboard or mouse software's key repeat, to step through a list of spells, macros and trinkets that **you** choose. You decide how often each ability comes up, which ones wait for a channelled spell such as Eye Beam (cast right after it, or held for it and never cast on their own), and which only fire in combat. Each specialization keeps its own list. A new list starts with Blizzard's **Single-Button Assistant**, so one key plays a full rotation from the start, with channelled spells such as Eye Beam no longer cut short by the next press; add, remove or reorder abilities whenever you like.

To set it up, open `/pr`, click **Create / Update Macro**, drag the `Attack` macro onto any action bar (1–8), bind a key to it, and click **Scan & Bind** at the bottom of the Settings tab. On the Rotation tab, drag a slot up or down to change the order, and hover a column's heading to see what it does.

To switch specialization quickly, hover **VeritasUI — Priority Rotation** in the AddOns menu by the minimap and pick a spec from the list that opens.

Settings: `/pr` (the rotation editor), and an on/off switch under **Options → AddOns → VeritasUI → Priority Rotation**.

### Advanced Options — WoW's hidden settings
WoW has many settings (CVars) that its Options panel doesn't show. The **Featured** tab gathers useful ones (camera distance, nameplates, combat text, soft targeting, graphics and more) as ordinary checkboxes, sliders and dropdowns, each with a reset button, in sections you can fold away one at a time or all at once with **Collapse All** / **Expand All**. The **All CVars** tab lets you search and edit every setting your client has, and star favourites.

Open it with `/ao`. It has its own window rather than an Options panel.

Stopped using ElvUI? ElvUI changes a number of these settings (nameplates for every NPC among them) and they stay changed after it is turned off. Type `/ao elvui`, or tick **Changed by ElvUI** on the All CVars tab, to see the ones that differ from Blizzard's defaults and reset them, one at a time or all at once. VeritasUI mentions it once, on your first login without ElvUI.

Tried another addon and something odd stayed behind? Type `/ao changed`, or tick **Changed** on the All CVars tab, to list every setting that differs from Blizzard's default, whoever changed it. Right-click a row to reset it. With nothing searched, **Reset Everything** puts every game setting back to Blizzard's default, the same as typing `/console cvar_default` (keybindings, Edit Mode layouts and addon settings are not touched). Search first (for example `nameplate`) and the button becomes **Reset All to Default**, which resets only the rows listed.

### VeritasUI Lib — shared core
Required by every other module. It also provides:

- `/vui`, which lists every module's command
- **Copy settings** from another of your characters (`/vui copy`, or the **Copy From…** button on VeritasUI's Options panels)
- A **Reload UI** button on those panels

## Settings across characters

Most settings are shared by all your characters, so you set them up once. A few are naturally per-character: which action bars fade, the player frame fade, how repairs are paid, map notes, and Priority Rotation lists, which are per character and per specialization.

Most modules are also listed in the minimap's addon menu (the addon compartment) for quick access to their settings.

## Installation

1. Download the latest `VeritasUI-vX.Y.Z.zip` from the [Releases page](https://github.com/NQV4X0QN/VeritasUI/releases/latest).
2. Extract it and copy all seven `VeritasUI_*` folders into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Keep the folder names exactly as they are.
4. Restart the game, or type `/reload` if it's already running.

Install all seven folders together. They share one version number, and every module needs `VeritasUI_Lib`. If you installed `VeritasUI_ElvUI` from an earlier version, delete that folder: it has been retired. Don't want a module? Disable it in the AddOns list on the character screen.

## Requirements

- World of Warcraft: Midnight, patch 12.1.5
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
