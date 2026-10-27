# VeritasUI

A World of Warcraft addon suite for **Midnight** (patch 12.1.0) that makes the default interface cleaner and more convenient, especially for solo play.

VeritasUI doesn't replace Blizzard's interface. It works inside it: its settings live in the normal **Options → AddOns** panel, its windows look and behave like Blizzard's own, and anything WoW already does well is left to WoW. If you didn't know VeritasUI was installed, most of it should just feel like the game.

The suite is split into modules. Each one does one job and has its own settings, and almost everything can be switched off individually.

## What's included

### Clean Solo — a quieter screen
Hides or fades the parts of the interface you don't need most of the time.

- Chat tabs and the chat background fade away when you're not using chat, and come back on mouseover
- The micro menu, chosen action bars (2–8) and your player frame fade out when idle and reappear on mouseover, in combat, or when you take damage
- Optionally hides the social button, the chat menu and voice buttons, the bag bar, and macro names on action buttons
- Hides red error text — all of it, or only the kinds you pick (combat, spells and cooldowns, items and bags, mail/vendors/bank, looting, mounts and flight paths), so "Internal mail database error." can go while "You are too far away!" stays

Settings: **Options → AddOns → Clean Solo**, or `/cs`. Changes apply after a `/reload`.

### Quality of Life — small conveniences
- **Item levels** on gear in your bags, bank, warband bank, character panel and at merchants
- **Auto sell junk** and **auto repair** at merchants, with a choice of paying repairs from guild funds or your own gold
- **`/way` waypoints** in the format most guides use, e.g. `/way #2351 45.2 56.3`, placing WoW's own map pin and arrow (if TomTom is installed, it keeps `/way`)
- **AFK screen**: a slow camera orbit with your name, level, item level and zone while you're away, which also helps against screen burn-in
- **Delve counts** shown right on the Delve objective icon instead of only in its tooltip: the Nemesis count, and in a Labyrinth the Treasure Room chambers completed, with a checkmark at 9
- **Map notes**: `/note <text>` leaves a note on the map where you're standing. Click a note to change its icon or remove it; `/note clear` removes the notes on your current map. Notes left inside a Labyrinth or other instance are removed when you leave it
- **Track latest reputation** (off until you turn it on): the reputation bar switches to whichever faction you most recently earned reputation with
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

Install all seven folders together. They share one version number, and every module needs `VeritasUI_Lib`. Don't want a module? Disable it in the AddOns list on the character screen.

## Requirements

- World of Warcraft: Midnight, patch 12.1.0
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
