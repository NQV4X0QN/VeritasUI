# VeritasUI

A World of Warcraft addon suite for **Midnight** (patch 12.1.0) that makes the default interface cleaner and more convenient, especially for solo play.

VeritasUI doesn't replace Blizzard's interface. It works inside it: its settings live in the normal **Options → AddOns** panel, its windows look and behave like Blizzard's own, and anything WoW already does well is left to WoW. If you didn't know VeritasUI was installed, most of it should just feel like the game.

The suite is split into modules. Each one does one job and has its own settings, and almost everything can be switched off individually.

## What's included

### Clean Solo — a quieter screen
Hides or fades the parts of the interface you don't need most of the time.

- Chat tabs and the chat background fade away when you're not using chat, and come back on mouseover
- The micro menu, chosen action bars (2–8) and your player frame fade out when idle and reappear on mouseover, in combat, or when you take damage
- **Fade Delay**: keep the micro menu, action bars and player frame up for 0 to 5 seconds after the mouse leaves, before they fade (the chat window keeps Blizzard's own timing)
- Optionally hides the social button, the chat menu and voice buttons, the bag bar, and macro names on action buttons
- Optionally hides the **talking head** story popup and, separately, **mutes its voice**, so you can keep either one
- Optionally hides the **top banners**: the zone name when you travel, event banners such as level up and scenario stages, and the boss kill and loot banner
- Optionally **hides profession gear**: keeps your own outfit on while you craft, gather or fish, instead of the profession outfit the game puts on you. If one still shows, `/cs gear` lists what you're wearing
- Hides red error text — all of it, or only the kinds you pick (combat, spells and cooldowns, items and bags, mail/vendors/bank, looting, mounts and flight paths), so "Internal mail database error." can go while "You are too far away!" stays

Settings: **Options → AddOns → Clean Solo**, or `/cs`, grouped under **Fade** and **Hide**. Changes apply after a `/reload`, except Fade Delay, which applies at once.

### Quality of Life — small conveniences
- **Item levels** on gear in your bags, bank, warband bank, character panel and at merchants
- **Auto sell junk** and **auto repair** at merchants, with a choice of paying repairs from guild funds or your own gold
- **`/way` waypoints** in the format most guides use, e.g. `/way #2351 45.2 56.3`, placing WoW's own map pin and arrow (if TomTom is installed, it keeps `/way`)
- **AFK screen**: a slow camera orbit with your name, level, item level and zone while you're away, which also helps against screen burn-in
- **Delve counts** shown right on the Delve objective icon instead of only in its tooltip: the Nemesis count, and in a Labyrinth the Treasure Room chambers completed, with a checkmark at 9
- **Map notes**: `/note <text>` leaves a note on the map where you're standing. Click a note to change its icon or remove it; `/note clear` removes the notes on your current map. Notes left inside a Labyrinth or other instance are removed when you leave it
- **Track latest reputation** (off until you turn it on): the reputation bar switches to whichever faction you most recently earned reputation with
- **Renown level on the reputation bar** (off until you turn it on): your renown level beside the faction's name, such as [18/20], and past the top the levels earned beyond it, such as [21/20]
- **Great Vault button by the minimap** (off until you turn it on): the Great Vault button sits under the minimap's mail icon whenever your vault holds something, including last week's rewards; click it to open the vault
- **Fill In DELETE** (off until you turn it on): when you delete a valuable item, DELETE is typed in for you, so Enter or Yes confirms
- **Skip Cinematics** (off until you turn it on): Escape skips a cinematic or movie straight away instead of asking first
- **NPC shortcuts** (each off until you turn it on): pick an NPC's only dialogue option, **auto accept** quests, and **auto turn in** completed quests — separate options, and holding Shift while you talk to the NPC pauses them. Reward choices and quests that cost gold are always left to you
- **Train All** button at trainers (off until you turn it on): learns everything available that you can afford in one click
- **Tooltip lines** (each off until you turn it on): who a player or NPC is targeting, green when it's you, and the mount a player is riding, with a check or red X for whether you own it. Left out where the game hides this from addons
- **Timestamp every message** (off until you turn it on): Blizzard's chat timestamp on system, loot, money, achievement, experience and reputation lines and VeritasUI's own messages, not just player chat. Uses the format from Options → Social → Chat Timestamps
- **Character sheet** (each off until you turn it on): a green check beside each slot whose enchant and gems are all there, or a red X on Epic and Legendary gear when one is missing, with a tooltip naming what's there and what's missing (optionally with the labels in your class colour); durability on each slot below 100%; and your Mythic+ rating under your item level
- **Journeys**: adds the "Show as Experience Bar" checkbox to Delves and Prey cards, and lets you click the reputation or honor bar to open that faction's page or the PvP window

For map and minimap coordinates, use WoW's own options in **Options → Interface**.

Settings: **Options → AddOns → Quality of Life**, or `/qol`.

### Auction House — prices and faster selling
- A **Scan** button records current prices across the whole auction house
- **Tooltip prices** on items and battle pets, anywhere in the game, styled like Blizzard's "Sell Price" line
- A **sell strip** on the Sell tab lists your sellable bag items: right-click one to load it, then left-click it again to post (Shift-click hides an item from the strip). Your bags need to be open.
- **Reagents value** on the Place Crafting Order form, so you can weigh a commission against the cost of materials

Settings: **Options → AddOns → Auction House**, or `/ah`.

### Zone Quests — a tidy quest tracker
Shows only quests for the zone you're in, updating as you travel. Campaign, important, legendary, meta and daily/weekly quests can be kept visible everywhere, and the quest you're navigating to always stays. Turning it off puts back the tracking you had chosen before.

Settings: **Options → AddOns → Zone Quests**, or `/zq`.

### Priority Rotation — one-button play
An accessibility tool: press one key, or hold it with your keyboard or mouse software's key repeat, to step through a list of spells, macros and trinkets that **you** choose. You decide how often each ability comes up, which ones follow others, and which only fire in combat. Each specialization keeps its own list, and starter lists are included for many specs.

To set it up, open `/pr`, click **Create / Update Macro**, drag the `Attack` macro onto any action bar (1–8), bind a key to it, and click **Scan & Bind**.

To switch specialization quickly, hover **VeritasUI — Priority Rotation** in the AddOns menu by the minimap and pick a spec from the list that opens.

Settings: `/pr` (the rotation editor), and an on/off switch under **Options → AddOns → Priority Rotation**.

### Advanced Options — WoW's hidden settings
WoW has many settings (CVars) that its Options panel doesn't show. The **Featured** tab gathers useful ones (camera distance, nameplates, combat text, soft targeting, graphics and more) as ordinary checkboxes, sliders and dropdowns, each with a reset button. The **All CVars** tab lets you search and edit every setting your client has, and star favourites.

Open it with `/ao`. It has its own window rather than an Options panel.

Stopped using ElvUI? ElvUI changes a number of these settings (nameplates for every NPC among them) and they stay changed after it is turned off. Type `/ao elvui`, or tick **Changed by ElvUI** on the All CVars tab, to see the ones that differ from Blizzard's defaults and reset them, one at a time or all at once. VeritasUI mentions it once, on your first login without ElvUI.

Tried another addon and something odd stayed behind? Type `/ao changed`, or tick **Changed** on the All CVars tab, to list every setting that differs from Blizzard's default, whoever changed it. Right-click a row to reset it. With nothing searched, **Reset Everything** puts every game setting back to Blizzard's default, the same as typing `/console cvar_default` (keybindings, Edit Mode layouts and addon settings are not touched). Search first (for example `nameplate`) and the button becomes **Reset All to Default**, which resets only the rows listed.

### VeritasUI Lib — shared core
Required by every other module. It also provides:

- `/vui`, which lists every module's command
- **Copy settings** from another of your characters (`/vui copy`, or the **Copy From…** button on VeritasUI's Options panels)
- A **Reload UI** button on those panels

### VeritasUI ElvUI — for ElvUI users
Optional, and loads only when ElvUI is installed. VeritasUI keeps looking like the game's own interface; with ElvUI, it looks like ElvUI's version of it:

- VeritasUI's windows, buttons, sell strip, scan bar and rotation editor take ElvUI's look, and follow ElvUI's Blizzard skin switch
- Clean Solo options that ElvUI handles itself (its fades and button hides) are greyed out; your choices come back if you turn ElvUI off
- If you turn on ElvUI's own Auto Repair or Vendor Grays, Quality of Life's matching option is greyed so the two don't both act
- Clicking ElvUI's reputation bar opens the faction's page, as it does with Blizzard's bar

## Settings across characters

Most settings are shared by all your characters, so you set them up once. A few are naturally per-character: which action bars fade, the player frame fade, how repairs are paid, map notes, and Priority Rotation lists, which are per character and per specialization.

Most modules are also listed in the minimap's addon menu (the addon compartment) for quick access to their settings.

## Installation

1. Download the latest `VeritasUI-vX.Y.Z.zip` from the [Releases page](https://github.com/NQV4X0QN/VeritasUI/releases/latest).
2. Extract it and copy all eight `VeritasUI_*` folders into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Keep the folder names exactly as they are.
4. Restart the game, or type `/reload` if it's already running.

Install all eight folders together. They share one version number, and every module needs `VeritasUI_Lib`. `VeritasUI_ElvUI` only loads when ElvUI is installed; without ElvUI the AddOns list shows it as missing a dependency, which is expected. Don't want a module? Disable it in the AddOns list on the character screen.

## Requirements

- World of Warcraft: Midnight, patch 12.1.0
- No other addons or libraries needed (ElvUI is optional)

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
