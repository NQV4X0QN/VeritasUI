# Changelog

## [1.27.0] - 2026-10-29

### Added

- `VeritasUI_CleanSolo` — **Hide Profession Gear: keep your own outfit while you work.** A new option in the Hide group removes the profession outfit the game puts on you when you craft, gather or fish, for all eleven crafting and gathering professions plus Cooking's Chef's Hat. The fishing outfit goes when you stop fishing. Never during combat: an outfit put on in a fight is removed when the fight ends. Applies at once, off by default. Confirmed in game for Herbalism, Mining and Fishing; if a crafting outfit still shows, `/cs gear` lists what you're wearing so it can be added (`CleanSolo.lua`, `README.md`)


## [1.26.0] - 2026-10-29

### Added

- `VeritasUI_CleanSolo` — **Hide Talking Head and Mute Talking Head Voice.** Two separate options in the Hide group: one hides the NPC portrait that pops up with story dialogue, the other silences its voice line, so you can keep the voice without the popup or the popup without the voice. The portrait still shows in Edit Mode so you can place it. Both off by default (`CleanSolo.lua`, `README.md`)
- `VeritasUI_CleanSolo` — **Hide Top Banners.** Stops the big messages at the top of the screen: the zone name when you travel, event banners such as level up, scenario stages and weekly rewards, and the boss kill and loot banner. They are stopped before they start rather than hidden part-way, so later banners never get stuck waiting. Off by default (`CleanSolo.lua`, `README.md`)


## [1.25.0] - 2026-10-29

### Added

- `VeritasUI_CleanSolo` — **Fade Delay: faded elements wait before fading.** A slider from 0 to 5 seconds sets how long the micro menu, faded action bars and player frame stay visible after you move the mouse away. It applies at once, with no `/reload`, and moving back during the delay keeps them up. At 0 they fade exactly as before. The chat window and its tabs keep Blizzard's own timing, so the tabs never float over an empty chat window (`CleanSolo.lua`, `Lib.lua`, `README.md`)

### Changed

- `VeritasUI_CleanSolo` — **Options grouped under Fade and Hide.** The settings page now lists every fade under a **Fade** header and every hide under a **Hide** header, the way Blizzard's own Options pages are laid out, instead of mixing the two. Your settings are unchanged (`CleanSolo.lua`)
- `VeritasUI_ElvUI` — **Fade Delay is greyed out with ElvUI,** along with the other Clean Solo fades (`Behaviour.lua`)


## [1.24.0] - 2026-10-29

### Added

- `VeritasUI_AdvancedOptions` — **Reset Everything: every game setting back to Blizzard's defaults in one click.** With **Changed** ticked and nothing in the search box, the button is **Reset Everything**: after a warning it runs the game's own `cvar_default`, exactly as typing `/console cvar_default` does, then says in chat whether anything still differs. Keybindings, Edit Mode layouts and addon settings are not touched, and it won't run during combat. Type a search and the button becomes **Reset All to Default**, which resets only the rows listed, so only one reset is ever offered (`Browser.lua`, `README.md`)


## [1.23.0] - 2026-10-29

### Added

- `VeritasUI_AdvancedOptions` — **Changed: put back settings any addon left behind.** Tick **Changed** on the All CVars tab, or type `/ao changed`, to list every setting that differs from Blizzard's default, whoever changed it. Right-click a row to reset it, or use **Reset All to Default**, which resets only the rows listed, so searching first (for example `nameplate`) leaves the rest alone. A red line warns while ElvUI or EllesmereUI is still running, since they set some of these again when they load (`Browser.lua`, `Core.lua`, `README.md`)
- `VeritasUI_AdvancedOptions` — **EllesmereUI's settings are listed.** The All CVars tab now includes the settings EllesmereUI changes, such as friendly nameplates, the camera distance and spell IDs on aura tooltips, so the Changed list can find what it left behind (`EllesmereUIChanges.lua`, new)


## [1.22.2] - 2026-10-29

### Added

- `VeritasUI_AdvancedOptions` — **Changed by ElvUI: put back the settings ElvUI changed.** ElvUI changes a number of WoW settings on its own, among them nameplates for every NPC, cast on key down and the camera distance, and they stay changed after ElvUI is turned off. Tick **Changed by ElvUI** on the All CVars tab, or type `/ao elvui`, to list the ones that differ from Blizzard's defaults; right-click a row to reset it or use **Reset All to Default**. On the first login without ElvUI, one chat line says how many there are. Chat windows are reset with Blizzard's own Chat Defaults, and the panel shows where to find it (`ElvUIChanges.lua`, new; `Browser.lua`, `Core.lua`, `README.md`)


## [1.22.1] - 2026-10-29

### Fixed

- `VeritasUI_PriorityRotation` — **Spells cast from a spellbook opened by Priority Rotation are no longer blocked.** Opening the spellbook from an empty rotation slot or the Spellbook button made WoW refuse spells clicked in it ("VeritasUI_PriorityRotation has been blocked from an action only available to the Blizzard UI"). Priority Rotation now passes your click to the menu bar's spellbook button, so Blizzard opens it exactly as the menu bar does, on the Spellbook tab while Priority Rotation is open. Shift-click for Macros and dropping spells onto slots work as before (`SpellbookOpener.lua`, new; `Editor.lua`, `Settings.lua`)
- `VeritasUI_PriorityRotation`, `VeritasUI_AdvancedOptions` — **Their windows close in combat.** The close button gave "Interface action failed because of an AddOn" during a fight; it now closes at once, and the window reopens normally afterwards (`Lib.lua`, `Settings.lua`)


## [1.22.0] - 2026-10-28

### Added

- `VeritasUI_ElvUI` — **New optional module: VeritasUI matches ElvUI.** Loads only when ElvUI is installed; without ElvUI it shows as missing a dependency in the AddOns list and nothing changes. VeritasUI's windows, tabs, buttons, checkboxes, sliders, dropdowns, search boxes and scroll bars take ElvUI's look, using ElvUI's own skin functions, and follow ElvUI's Blizzard skin switch (`Core.lua`, `Standard.lua`, new)
- `VeritasUI_ElvUI` — **VeritasUI's own widgets restyled to match.** Sell strip card and item icons (quality-coloured border), Scan button and a flat scan progress bar, Priority Rotation's rotation rows, arrows, icon slots and Compiled Sequence box, and Advanced Options' section arrows, each styled the way ElvUI styles the nearest Blizzard equivalent (`Custom.lua`, new)
- `VeritasUI_ElvUI` — **Clean Solo options ElvUI handles are greyed out.** With ElvUI loaded, Clean Solo's fades (chat tabs, chat background, micro menu, player frame, action bars) and hides (social, chat and voice buttons, bag buttons, macro names) are skipped and greyed, with "Not available with ElvUI (handled by ElvUI)." in the tooltip. Your saved choices are kept for when ElvUI is off (`Behaviour.lua`, new)
- `VeritasUI_ElvUI` — **Quality of Life defers to ElvUI's own repair and junk selling.** When ElvUI's Auto Repair or Vendor Grays is switched on, Quality of Life's Auto Repair (and Repair Funding) or Auto Sell Junk is greyed so both don't act at the same merchant. With ElvUI's left off, its default, Quality of Life's keep working (`Behaviour.lua`)
- `VeritasUI_ElvUI` — **Clicking ElvUI's reputation bar opens the faction's page,** as Blizzard's bar does with Quality of Life. Other buttons and clicks in combat still do what ElvUI does (`Behaviour.lua`)

### Changed

- `VeritasUI_Lib` — **Optional modules can restyle frames and set options aside.** `VUI.AnnounceFrame`/`VUI.OnFrameBuilt` hand built frames to a restyling module; `VUI.SetOptionUnavailable`/`VUI.OptionUnavailable` let one mark another module's option as unavailable. Nothing changes without such a module (`Lib.lua`)
- `VeritasUI_AuctionHouse`, `VeritasUI_PriorityRotation`, `VeritasUI_AdvancedOptions`, `VeritasUI_QualityOfLife`, `VeritasUI_CleanSolo` — **Hooks for the ElvUI module.** Each announces the frames it builds and honours unavailable options; the scan progress bar gains a plain-texture mode. No change without ElvUI (`ScanButton.lua`, `ScanProgress.lua`, `SellStrip.lua`, `Settings.lua`, `Editor.lua`, `Featured.lua`, `Journeys.lua`, `QualityOfLife.lua`, `CleanSolo.lua`)


## [1.21.1] - 2026-10-27

### Fixed

- `VeritasUI_QualityOfLife` — **Jumping dismisses the AFK screen as fast as walking.** A jump in place left the screen up for the 1–2 seconds the server takes to clear AFK; it now drops the moment you leave the ground (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **The AFK screen no longer comes back right after you dismiss it.** The 5-second backup check could land before the server had cleared AFK and bring the screen straight back after you walked or jumped; it now waits for the server to confirm you are back (`QualityOfLife.lua`)


## [1.21.0] - 2026-10-26

### Added

- `VeritasUI_CleanSolo` — **Hide Error Text by kind.** Hide Error Text is now a tick-box dropdown: **All**, or any of Combat: Range, Facing & Targets; Spells & Cooldowns; Items & Bags; Mail, Vendors & Bank; Looting & Objects; Mounts & Flight Paths. Hide the mailbox's "Internal mail database error." and keep "You are too far away!" and "You are facing the wrong way!" in combat. Uses Blizzard's own per-message-type switch, so the spoken line is hidden with the text. If your old Hide Error Text checkbox was on, it carries over as All (`CleanSolo.lua`, `README.md`)

### Changed

- `VeritasUI_CleanSolo` — **Fade Action Bars uses Blizzard's tick-box dropdown.** Both Clean Solo dropdowns now look and work like the Nameplates "Cast Bar Information" option: a tick box on each row, a None row, and the ticked names in the bar. Your chosen bars carry over (`CleanSolo.lua`)

### Removed

- `VeritasUI_CleanSolo` — **The separate Hide Error Text checkbox.** Its job is the dropdown's All row (`CleanSolo.lua`)


## [1.20.0] - 2026-10-25

### Added

- `VeritasUI_QualityOfLife` — **Labyrinth Treasure Room count on the Delve objective icon.** In a Labyrinth the icon shows the chambers completed, counting up from 0, with Blizzard's checkmark once all 9 are done. The setting is now called **Show Delve Counts** and covers both this and the Nemesis count (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **Map notes.** `/note <text>` (or `/mapnote`) leaves a note on the World Map where you're standing, drawn like one of Blizzard's own map icons. Click a note to change its icon (map pin, doors, treasure, quest, dungeon, Delve, vendor, flight point, quest hub) or remove it; `/note clear` removes the notes on your current map. Notes are per character, and notes left inside a Labyrinth or other instance are removed when you leave it (`QualityOfLife.lua`, `MapNotes.xml`, new)


## [1.19.2] - 2026-10-24

### Fixed

- `VeritasUI_PriorityRotation` — **Clicking Priority Rotation in the minimap AddOns menu closes the menu again.** Since the spec list was added in 1.19.0, the menu stayed open after the click opened Priority Rotation; it now closes like every other entry. Hovering still opens the spec list (`Core.lua`)


## [1.19.1] - 2026-10-24

### Changed

- **Shorter setting descriptions.** The tooltips in Options → AddOns now say what each setting does in a sentence or two, without the technical detail — Quality of Life, Auction House, Clean Solo and Zone Quests (`VeritasUI_QualityOfLife/QualityOfLife.lua`, `VeritasUI_AuctionHouse/Settings.lua`, `VeritasUI_CleanSolo/CleanSolo.lua`, `VeritasUI_ZoneQuests/ZoneQuests.lua`)


## [1.19.0] - 2026-10-24

### Added

- `VeritasUI_PriorityRotation` — **Switch specialization from the minimap AddOns menu.** Hover **VeritasUI — Priority Rotation** in the AddOns menu by the minimap and a list of your specializations opens beside it, with the current one marked; click one to switch. Two steps, against three through Talents and Spellbook. Clicking the entry itself still opens Priority Rotation. As with the Settings tab's spec dropdown, switching is refused in combat (`Core.lua`, `Settings.lua`, `README.md`)


## [1.18.1] - 2026-10-24

### Changed

- `VeritasUI_AuctionHouse` — **No tooltip on the stack loaded in the Create Auction slot.** Its tooltip rose over Deposit and Total Price while you hovered it to post. Every other sell-strip icon keeps its tooltip, and the loaded item's tooltip is still on Blizzard's own sell-slot icon (`UI/SellStrip.lua`)

### Fixed

- `VeritasUI_AuctionHouse` — **Removing an item from the Create Auction slot puts its sell-strip icon back in colour.** Right-clicking the item out of the slot left its strip icon greyed out, as if still loaded; it now returns to colour and shows its tooltip again (`UI/SellStrip.lua`)


## [1.18.0] - 2026-10-24

### Added

- `VeritasUI_QualityOfLife` — **Track Latest Reputation.** The reputation bar switches to whichever faction you most recently earned reputation with — earn Hara'ti reputation and the bar shows Hara'ti, then earn reputation with The Singularity in Voidstorm and it shows The Singularity. Works for factions at max renown that still earn paragon reputation. During combat the switch waits until combat ends, then shows the last faction you earned with. A faction you pick by hand stays shown only until your next reputation gain. Off by default; turn it on in Options → AddOns → Quality of Life (`QualityOfLife.lua`, `README.md`)


## [1.17.19] - 2026-10-14

### Removed

- `VeritasUI_QualityOfLife` — **Minimap coordinates, now built into WoW.** Patch 12.1.5 added its own coordinates under the minimap (Options → Interface, map coordinates section), reading the same position at the same rate ours did. If you had ours on, WoW's is turned on for you once at your next login; if you had it off, nothing changes. WoW's "coordinates by tenths" option in the same section controls whether decimals are shown (`QualityOfLife.lua`, `VeritasUI_QualityOfLife.toc`, `README.md`)


## [1.17.18] - 2026-10-14

### Changed

- **Interface bumped to `120105` for WoW patch 12.1.5.** All seven module TOCs updated so the suite is not flagged out of date on the 12.1.5 client — no code changes (all `.toc` files)

### Internal

- **The 12.1.0 and 12.1.5 UI source trees were diffed to bound the patch's impact.** None of the 15 Lua functions, 1 global, 34 mixin methods or 13 API-documentation names that 12.1.5 removed are referenced by the suite; the API changes touching namespaces we call (`C_ActionBar`, `C_ClassColor`, `C_LFGInfo`, `C_Timer`) are additions only. This does not cover changed behaviour of surviving functions, which only surfaces in play


## [1.17.17] - 2026-10-11

### Changed

- **Clearer descriptions.** The README is rewritten as a plain-language overview of what each module does and how to get started, and the descriptions shown in the in-game AddOns list now say what each module is for (`README.md`, every `.toc`)
- The developer probe reference is labelled as a dated notebook that players don't need (`PROBE_LIBRARY_AND_REFERENCE.md`)


## [1.17.16] - 2026-10-11

### Fixed

- `VeritasUI_AuctionHouse` — **Sell-strip icons respond to clicks again.** With WoW's "cast on key down" setting on, every strip right-click (load) and left-click (post) did nothing: Blizzard's secure buttons act on the press when that setting is on, and the strip only listens for the release. Priority Rotation used to force that setting off for everyone, which hid the problem; v1.17.10 stopped doing that and put the setting back to WoW's default, which exposed it. The strip's buttons now act on release by themselves, whatever the setting is (`UI/SellStrip.lua`)
- `VeritasUI_AuctionHouse` — `/ah stripdiag` also reports the key-down setting and the button's own choice (`UI/SellStrip.lua`)


## [1.17.15] - 2026-10-11

### Added

- `VeritasUI_AuctionHouse` — **`/ah stripdiag`, for a sell strip that stops loading items.** Hover a strip icon that won't load on right-click and run it: it reports what is under the cursor, which bag button the icon forwards to and whether that is still the right one, and whether Blizzard is refusing the forwarded click, then re-wires the strip so you can try again. Diagnostic only; it changes nothing else (`UI/SellStrip.lua`, `Core.lua`)


## [1.17.14] - 2026-10-11

### Fixed

- `VeritasUI_Lib` — **Hidden buttons stay hidden.** Buttons VeritasUI hides (for example the voice/channels, mute and deafen buttons) could be brought back by Blizzard through a route VeritasUI wasn't watching, returning invisible but still clickable — so a click on empty space beside chat could open voice channels or mute you. Both routes are now caught (`Lib.lua`)

### Changed

- **One login line instead of six.** Each module printed its own "loaded" line at every login and `/reload`; VeritasUI now prints a single line, "VeritasUI vX loaded — /vui for commands", and `/vui` lists every installed module's command. Warnings and one-time notices are unchanged (`Lib.lua` and every module)
- `VeritasUI_Lib` — **`/vui debug` turns debug output on or off for every module.** It used to exist only as `/ah debug`, which disappears if Auction House is turned off; `/ah debug` still works (`Lib.lua`, `VeritasUI_PriorityRotation/Core.lua`)
- `VeritasUI_QualityOfLife` — **Minimap coordinates are white**, in the same font as WoW's own World Map coordinates (`QualityOfLife.lua`, `README.md`)


## [1.17.13] - 2026-10-11

### Fixed

- `VeritasUI_AdvancedOptions` — **Soft Target choices now say what they do.** The Soft Target Enemy, Friendly and Interact dropdowns offered "Enabled (Icon)", "Enabled (Icon + Nameplate)" and "Enabled (Full)", but the setting really chooses who gets soft targeting — so "Enabled (Icon)" meant controller only and turned it off for keyboard and mouse players. The choices are now Off, Controller only, Keyboard & mouse only and Always (`Featured.lua`)
- `VeritasUI_AdvancedOptions` — **Colorblind Mode applies the filter you pick.** In WoW 12.1 colorblind mode is on/off and the filter is a separate setting; picking a filter in the old dropdown only switched the mode on. It is now a Colorblind Mode checkbox plus a Colorblind Filter dropdown, using Blizzard's own names, matching WoW's own colorblind settings (`Featured.lua`)


## [1.17.12] - 2026-10-11

### Fixed

- `VeritasUI_ZoneQuests` — **Turning zone filtering off puts your own quest tracking back.** The module believed WoW had removed any way to ask which quests you track, so two seconds after every login it noted every quest in your log, and turning filtering off tracked that list and untracked everything else: quests you had untracked came back, and quests picked up since you logged in vanished from the tracker. WoW does still report it (`C_QuestLog.GetQuestWatchType`). Now, when you turn filtering on, Zone Quests remembers which quests you had chosen not to track; turning it off untracks just those and tracks everything else, including quests picked up in between. If filtering was already on before this version there is no record yet, so the first time you turn it off every quest is tracked. The setting's description is corrected (`ZoneQuests.lua`)


## [1.17.11] - 2026-10-11

### Fixed

- `VeritasUI_CleanSolo` — **"Hide Voice Chat Button" now hides the voice buttons.** It targeted two frames that WoW 12.1 no longer has, so it did nothing; the voice/channels button only looked hidden because "Hide Chat Buttons" was hiding it. "Hide Voice Chat Button" now hides the voice/channels button and the mute/deafen buttons shown while you're in a voice channel, and "Hide Chat Buttons" hides the chat menu button. With both on (the default) chat looks the same as before, except mute/deafen also stay hidden in voice (`CleanSolo.lua`, `README.md`)
- `VeritasUI_CleanSolo` — **Three setting descriptions corrected.** "Transparent Chat Background" no longer claims your background won't come back (it does, after `/reload`); "Hide Chat Buttons" names the button it actually hides; "Hide Error Text" mentions that it also silences the spoken error lines, as WoW's own `/uierrorsoff` does (`CleanSolo.lua`, `README.md`)


## [1.17.10] - 2026-10-11

### Fixed

- `VeritasUI_PriorityRotation` — **The `Attack` macro is no longer created or overwritten behind your back.** Two seconds after every login the rotation wrote a macro named `Attack`: it created one for every VeritasUI player whether or not they used the rotation, brought it back after it was deleted, and replaced the text of any macro of the player's own that was already called `Attack` — then took over that macro's key. Now the macro is created only when you click **Create / Update Macro** (or `/pr macro`). At login only the rotation's own macro has its icon refreshed. A different macro using the name is left alone and never bound, and chat says so (`Core.lua`, `README.md`)
- `VeritasUI_PriorityRotation` — **WoW's "cast on key down" setting is yours again.** To make its hidden button act on key release, the rotation switched WoW's account-wide setting off at every login — changing every action bar for every VeritasUI player — and back on when it was disabled. The rotation's button now chooses key release for itself (Blizzard's per-button setting), and the account-wide setting is never changed. Because it had been overwritten for everyone, it is put back to WoW's default once, with a line in chat; set it however you like afterwards (`Core.lua`, `Settings.lua`, `README.md`)
- `VeritasUI_PriorityRotation` — **The Attack macro works from Action Bars 6, 7 and 8, and form/stealth bars no longer take over another key.** Those three bars were never searched, and the slots the rotation thought were Bars 6–8 are really the pages WoW swaps in for druid forms and stealth, so a macro placed there bound the rotation to an unrelated Bar 6–8 key. `/pr scan` now finds all eight bars and says when a form or stealth page can't be bound (`Core.lua`)
- `VeritasUI_PriorityRotation` — **The Compiled Sequence preview updates straight away** instead of showing the sequence from before your last change (`Core.lua`)


## [1.17.9] - 2026-10-11

### Changed

- `VeritasUI_QualityOfLife` — **World Map coordinates now come from WoW itself.** WoW 12.1 added its own player and cursor coordinates to the World Map (Options > Interface). VeritasUI's readout duplicated it and was less correct: its "Player" numbers came from the zone you were standing in even while the map showed another zone, and it hid the map's quest-log toggle until `/reload`. It has been removed. If you had it turned on, WoW's two map coordinate options are switched on for you once, at your next login (after combat, if you log in fighting). The quest-log toggle is back. Minimap coordinates are unchanged (`QualityOfLife.lua`, `README.md`)

### Fixed

- `VeritasUI_QualityOfLife` — **`/way` no longer announces a waypoint that was not placed.** On a map that does not allow pins it printed "Waypoint set" and nothing appeared. It now makes the same two checks as Blizzard's own `/mappin` and shows Blizzard's error message instead (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **The AFK screen clock follows your 24-hour setting** and writes the time the way Blizzard's clock does ("7:30 PM", not "07:30 PM"). The "Level" and "Item Level" labels use the game's translated words (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **`/qol delveone <n>` confirms the change as a nudge relative to the other digits**, matching what `/qol delveone` reports, and no longer errors on a bare `-` (`QualityOfLife.lua`)


## [1.17.8] - 2026-10-10

### Fixed

- `VeritasUI_AuctionHouse` — **The price database now forgets items that have left the auction house.** Nothing ever removed a record: the per-day history prune only ran for an item being recorded again, so every item ever seen kept its last price forever (one account held 30,027 records in a 5 MB file, 8,103 unseen for over 60 days). A successful scan now removes items not seen for 30 days before that scan. It is measured from the scan, so logging in after months away removes nothing, and dry runs and failed scans never prune (`Database.lua`, `Browse.lua`, `Replicate.lua`)
- `VeritasUI_AuctionHouse` — **Sell-strip right-click works however your bags were when you opened the Sell tab.** Loading forwards your click to the item's button in Blizzard's bag window, which exists only while that bag is open, and nothing redrew the strip when bags opened or closed — so closing your bags first left every right-click dead. The strip now re-wires on Blizzard's own bag open/close notifications, and the tooltip says "Open your bags to load this item" when there is nothing to forward to. With a bag addon that replaces Blizzard's bags, load items from that addon (`UI/SellStrip.lua`, `README.md`)
- `VeritasUI_AuctionHouse` — **Closing the auction house during `/ah compare` or `/ah browseprobe` no longer leaves a stray report** after the next scan (`Core.lua`)

### Changed

- `VeritasUI_AuctionHouse` — **Auction prices are written by Blizzard's own money formatter.** The "Auction:" tooltip line and the crafting-order "Reagents Value:" line now use the same formatter as Blizzard's "Sell Price:" line, so gold shows thousands separators (`12,345`) and Colorblind Mode shows letters, exactly as Blizzard's line above. Coin size and alignment are unchanged (`Tooltip.lua`)
- `VeritasUI_AuctionHouse` — **Sell-strip quality markers come from Blizzard.** Each icon's profession-quality marker is now the one Blizzard reports for that item, drawn the way your bag buttons draw it, so crafted items get their marker too (`UI/SellStrip.lua`)


## [1.17.7] - 2026-10-10

### Fixed

- `VeritasUI_Lib` — **WoW's taint debugging log is no longer switched on at every login.** Lib forced the `taintLog` CVar to 1 at each login while the `UseContainerItem()` FORBIDDEN was being investigated; the code was marked temporary and that investigation closed in v1.17.4. Removed the arming, the `/vui taint arm` / `/vui taint disarm` commands and their help line, and the leftover `taintLogArm` saved key. The CVar resets itself on logout, so nothing needs undoing. The blocked-action recorder (`/vui taint`) is unchanged (`Lib.lua`)
- `VeritasUI_Lib` — **The blocked-action recorder only records VeritasUI's own problems.** `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` name whichever addon Blizzard blames, and every one was recorded — so the login notice announced other addons' blocked actions, and their entries could push genuine VeritasUI ones out of the 25-entry log (`Lib.lua`)

### Changed

- `VeritasUI_Lib` — **Settings-panel Reload UI and Copy From buttons use Blizzard's own hooks.** They now anchor to Blizzard's Defaults button directly (`SettingsPanel:GetSettingsList().Header.DefaultsButton`) instead of searching for a button labelled `DEFAULTS` — Blizzard labels it `SETTINGS_DEFAULTS`, so on clients where those differ the buttons fell back to a fixed position. They show and hide on Blizzard's `Settings.CategoryChanged` event instead of a four-times-a-second check, and the Reload button uses Blizzard's translated `RELOADUI` text and sizes to fit it (`Lib.lua`, `.luacheckrc`)


## [1.17.6] - 2026-09-18

### Added

- `VeritasUI_QualityOfLife` — **Minimap coordinates.** Shows your current position in gold directly below the minimap, updating at 10 Hz. Display-only FontString on an insecure frame parented to `Minimap`, so it inherits the map’s show/hide and adds no taint surface; hidden automatically wherever `C_Map.GetPlayerMapPosition` returns no position (dungeons, raids, arenas). Toggle via the new "Show Minimap Coordinates" setting (`showMinimapCoords`), on by default (`QualityOfLife.lua`)

### Fixed

- `VeritasUI_AuctionHouse` — **Sell-strip tooltip now states the correct gestures.** The two hint lines were stale after the v1.17.4 secure-click rework: the load line said "Click" (it is now Right-click) and the hide line said "Shift-Right-click" (it is now Shift-Left-click). Text only; the bindings were already correct (`UI/SellStrip.lua`)


## [1.17.5] - 2026-09-13

### Removed

- `VeritasUI_AuctionHouse` — **Sell-strip auto-advance, fully removed.** Retired and force-disabled in v1.17.4, kept one version as a fallback in case the secure two-press strip misbehaved; it did not. Gone are `ArmAutoAdvance`/`CancelAutoAdvance`/`TryAutoAdvance`, the `advanceIndex`/`advanceTries` state, the multisell retry loop, the four post-completion event registrations, the `sellAutoAdvance` setting and its options checkbox, and the `/ah autoadvance` command. `InitDB` drops the orphaned key and the v1.17.4 migration flag (`UI/SellStrip.lua`, `Core.lua`, `Settings.lua`, `Tooltip.lua`)


## [1.17.4] - 2026-09-13

### Fixed

- `VeritasUI_AuctionHouse` — **`ADDON_ACTION_FORBIDDEN` on `UseContainerItem()` when clicking a bag item.** Open since 2026-07 and firing roughly once per session. The sell strip called `AuctionHouseFrame:SetPostItem()` itself, so Blizzard stored our `ItemLocation` in its own sell frame from inside our execution. Closing the auction house made `ClearPostItem()` read that tainted value, which tainted `FRAME_THAT_OPENED_BAGS` via `CloseAllBags` (`ContainerFrame.lua:2017`); opening the bank then wrote `BankPanel.bankType` tainted and every later bag click was refused. The strip no longer loads or posts anything itself — see Changed (`UI/SellStrip.lua`)
- `VeritasUI_Lib` — **`/vui taint disarm` never persisted.** The opt-out was stored as `nil` instead of `false`, so the `== false` guard could never fire and `taintLog` was silently re-armed to level 1 at every login, clobbering any manually-set level (`Lib.lua`)

### Changed

- `VeritasUI_AuctionHouse` — **Sell-strip items now use two real clicks, both handled by Blizzard.** Right-click loads the item into the sell form by forwarding a genuine click to that item's own bag button, so Blizzard's `ContainerFrameItemButton_OnClick` runs it in secure execution; left-click posts it by forwarding to the native Create Auction button. Right-click for loading matches Blizzard's own bag gesture — a left-click there picks the item up. Neither press leaves the icon, so the tooltip is never between you and the button (`UI/SellStrip.lua`)
- `VeritasUI_AuctionHouse` — **Blocklist moved from Shift+Right-click to Shift+Left-click**, now that right-click is Blizzard's load gesture (`UI/SellStrip.lua`)

### Removed

- `VeritasUI_AuctionHouse` — **Sell-strip auto-advance.** It loaded the next item from a post-completion event, which has no hardware press behind it, so the load tainted by construction and was the origin of the bug above. Two presses on one icon replace it with no mouse travel and no taint. Force-disabled on upgrade rather than defaulted off, since defaults only fill absent keys; `/ah autoadvance on` remains for one version (`Core.lua`, `Tooltip.lua`, `UI/SellStrip.lua`)


## [1.17.3] - 2026-08-30

### Added

- `VeritasUI_Lib` — **the addon now arms WoW's own taint log at login, because the CVar does not survive a logout.** `taintLog` is a Debug-category CVar with no account or character scope, so it is never synchronised to `config-cache.wtf` or the server. Measured 2026-08-30: the owner set `/console taintLog 1`, the `UseContainerItem` FORBIDDEN then fired at 00:15, and by the time he checked the CVar read `0` with no `taint.log` in `Logs/` at all. That is why four recorded occurrences of this bug across five weeks still have no WoW-side taint log — arming it by hand cannot survive the days of ordinary play between events, and the bug cannot be reproduced on demand. Value `1` is used, which logs blocked-action errors *and the taint events leading up to them*, i.e. the causal chain for this exact class; values 2–4 add tainted reads and writes of globals, upvalues and table fields and are far more verbose over multi-day sessions, so they are held in reserve. Skips the write when the CVar already reads `1`. ⚠ This is a temporary diagnostic tied to the open investigation and should be removed when it closes; `/vui taint disarm` opts out permanently without a code change, since forcing a debug setting on with no escape hatch is user-hostile. (`Lib.lua`)

## [1.17.2] - 2026-08-29

### Fixed
- `VeritasUI_AuctionHouse` — tooltips on recipes and patterns showed the price of the item they *teach* instead of the price of the recipe itself. Hovering `Pattern: Stretched Snakeskin Rack` rendered 10,000g 1s — the correct price of the decor item it teaches — on a pattern worth 5g. The tooltip data pipeline's `hyperlink` points at the taught item while its `id` stays correct, and the tooltip preferred the link. It now resolves via `TooltipUtil.GetDisplayedItem` (which resolves GUID-first, per `TooltipUtil.lua:9-21`) and cross-checks the result against `data.id`, discarding any link that disagrees (`Tooltip.lua`)
- `VeritasUI_AuctionHouse` — an item whose link and id disagree and which is equippable now renders no price line at all, rather than resolving to the ilvl-agnostic bare `i:<itemID>` gear key the key design forbids (`Tooltip.lua`)

### Added
- `VeritasUI_AuctionHouse` — `/ah ttprobe` reports what the tooltip actually priced: the link, itemID, derived key, price, and all three candidate item identities side by side. With no argument it reports the last render rather than a reconstruction (`Core.lua`, `Tooltip.lua`)

### Requires
- No action — affects display only; no stored prices were wrong

## [1.17.1] - 2026-08-29

### Fixed
- `VeritasUI_AuctionHouse` — non-commodity prices from a live search were divided by the number of competing auctions. `ItemSearchResultInfo.quantity` is how many auctions are grouped at that price, not a stack size, so v1.16.0's `floor(buyoutAmount / quantity)` stored a fraction of one auction's own price — measured on item 275334 as `floor(50000 / 3)` = 16666, showing 1g 66s 66c against a real cheapest listing of 5g. `buyoutAmount` is now stored as-is, matching `Blizzard_AuctionHouseItemSellFrame.lua:325`, which sets its own price input from that field with no division (`LiveSearch.lua`)

### Changed
- `VeritasUI_AuctionHouse` — quantity is still summed across the ladder for availability, which was never the broken part

### Requires
- No action — affected prices correct themselves the next time you open the item. Commodities were never affected; only non-commodity items with more than one auction at the cheapest price

## [1.17.0] - 2026-08-29

### Added
- `VeritasUI_AuctionHouse` — the sell strip now loads the next item into the sell form after you create an auction, so posting a run of items is just `Create Auction` repeatedly (`UI/SellStrip.lua`)
- `VeritasUI_AuctionHouse` — `/ah autoadvance` toggles that behaviour (`on` | `off`), alongside an "Auto-Load Next Item After Posting" checkbox, default on, key `sellAutoAdvance` (`Core.lua`, `Settings.lua`, `Tooltip.lua`)

### Changed
- `VeritasUI_AuctionHouse` — auto-advance populates only; nothing on that path calls a posting API, and quantity and price are left to Blizzard's own loader so the form matches a hand-clicked strip icon exactly

### Requires
- No action — on by default; `/ah autoadvance off` disables it

## [1.16.0] - 2026-08-29

### Added
- `VeritasUI_AuctionHouse` — live-search price correction: opening an item on the Buy or Sell tab now records its real listing price into the price database, overwriting whatever the scan stored (`LiveSearch.lua`, new)
- `VeritasUI_AuctionHouse` — `/ah live` reports what the correction layer has changed, and toggles it (`on` | `off`); the counters also appear in `/ah diag` (`Core.lua`)
- `VeritasUI_AuctionHouse` — "Correct Prices from Live Searches" checkbox, default on, key `liveSearchPrices` (`Settings.lua`, `Tooltip.lua`)

### Fixed
- `VeritasUI_AuctionHouse` — tooltip prices no longer read far below the cheapest listing on items you handle. The browse engine's `minPrice` can sit below every existing auction — measured item 237365 at 204900 against a cheapest listing of 352200, a 41.8% error with the market provably still — and `BrowseResultInfo` exposes only that one price field, so the value is corrected downstream from the auction house's own per-item search instead (`LiveSearch.lua`, `Browse.lua`)
- `VeritasUI_AuctionHouse` — a dry run (`/ah compare`, `/ah browseprobe`) no longer prints `Scan complete — 0 items priced` directly beneath its own honest result line, which read like a failed scan (`Browse.lua`, `Core.lua`)

### Changed
- `VeritasUI_AuctionHouse` — corrected the claim, asserted in two files since v1.12.12, that the price error attributable to browse is bounded at ~7.7%. That was a single sample presented as a ceiling; the measured error is 41.8% on an item whose market had not moved (`Browse.lua`, `Tooltip.lua`)

### Requires
- No action — the correction is on by default and needs no rescan; prices update as you open items

## [1.15.4] - 2026-08-24

Hardening pass over the day's changes. No behaviour change in any working path — owner-verified across all seven checks (AH Quantity row, checkbox label, checked-state across pooled cards, reputation bar click, Honor bar click, reload with the Adventure Guide open, Edit Mode entry).

### Fixed

- `VeritasUI_AuctionHouse` — **our bookkeeping no longer gets written onto Blizzard's Auction House sell frames.** v1.14.20 marked hooked forms with a `form._vuiQuantityPinned` field; that is an addon write onto a Blizzard frame whose `SetItem` → `CanPostItem` path reaches `C_AuctionHouse.PostCommodity`, and this module's landmines record a historical crash inside Blizzard's own commodity-post code on the native Create Auction click. It is the same family of mistake as the Edit Mode taint fixed in v1.15.2. Nothing but us reads the flag, so it now lives in a module-local table keyed by the form. The `QuantityInput` reference inside the post-hook is also re-checked for nil, since it is re-read on every call but was only guarded at install time — without it, a removed widget would throw from inside the hook on every sell-form load. (`UI/SellStrip.lua`)
- `VeritasUI_QualityOfLife` — **removed a shipped scaffolding marker and closed five latent error paths in the Journeys code.** An orphaned `<<< END ISOLATION STEP >>>` comment shipped in v1.15.3 after its opening block was removed; that marker is the string `PROBE_LIBRARY_AND_REFERENCE.md` tells future sessions to grep for when hunting scaffolding that must never ship, so a live marker with no block is actively misleading. `C_Reputation` was the file's only Blizzard namespace read unguarded — `pcall(C_Reputation.Foo)` evaluates the index before pcall runs, so pcall was protecting the call but not the lookup; all seven sites now resolve through an accessor, and every name string was verified against Blizzard's generated API documentation. The checkbox's `factionID` is now re-derived unconditionally rather than only when Blizzard's pcall'd `OnShow` left it zero, because journey cards are pooled and reused across factions and a gated refresh could have left the previous card's faction in place. The `ADDON_LOADED` listener now unregisters on the already-loaded path instead of string-comparing every addon load for the session, the status-bar overlay attach retries a bounded number of times instead of once (a single next-frame retry meant late containers left clicks silently dead for the whole session), and the `SHOW_FACTION_ON_MAINSCREEN` global is checked before being passed to `SetText`. (`Journeys.lua`)

## [1.15.3] - 2026-08-24

### Changed

- `VeritasUI_QualityOfLife` — **status-bar click navigation is back, rebuilt so it writes to nothing of Blizzard's.** v1.15.2 disabled it because `HookScript` on the reputation and honor bars tainted Edit Mode. Clicks are now taken by our own frame parented to `UIParent` and merely *anchored* to the bar — `SetPoint` writes to our frame and only reads theirs, so the Edit Mode subtree is never modified and never inherits our taint; anchoring also makes the overlay follow the bar when it is dragged in Edit Mode. `SetPropagateMouseMotion` keeps Blizzard's own hover text reveal working, and `SetPropagateMouseClicks` means we observe clicks rather than consume them, so a stale overlay can never starve a frame beneath of input. Visibility is polled at 0.2s instead of hooked (matching `HookHoverFade` and `AFK_ScanPanels` elsewhere in the suite), the click handler re-checks `IsVisible()` so a stale poll cannot fire on an off-screen bar, and overlays hide entirely while `EditModeManagerFrame:IsEditModeActive()` so they cannot interfere with dragging. Owner-verified: reputation click, honor click, Edit Mode entry, and bar hover text all correct with no Lua errors. (`Journeys.lua`)

## [1.15.2] - 2026-08-24

### Fixed

- `VeritasUI_QualityOfLife` — **entering Edit Mode no longer throws `attempt to compare a secret number value (execution tainted by 'VeritasUI_QualityOfLife')`.** The status-bar click navigation added in v1.15.0 attached its handler with `HookScript("OnMouseUp")` directly to Blizzard's reputation and honor bars — but those bars sit inside Edit Mode system frames (their containers inherit `EditModeStatusTrackingBar1/2SystemTemplate`), so hooking them taints Edit Mode's own `RefreshEncounterEvents`, which then cannot compare a Secret Value inside `secureexecuterange`. Confirmed by isolation: with the hook disabled and a fresh `/reload`, Edit Mode opens clean. The click navigation is temporarily disabled behind a flag while it is rebuilt with our own click-catcher frame that never writes to a Blizzard frame; the Journeys "Show as Experience Bar" checkbox is unaffected and still works. ⚠ This suite's landmine list already warned that `HookScript` on a secure Blizzard frame is a taint source — the mistake was treating a narrower precedent ("parent bar frames are safe to hook", measured on action bars against `ACTIONBAR_UPDATE_COOLDOWN`) as a general licence. (`Journeys.lua`)

## [1.15.1] - 2026-08-24

### Added

- `VeritasUI_QualityOfLife` — **left-clicking the Honor bar now opens and closes the PvP UI**, matching what v1.15.0 gave the reputation bar. The implementation is a single `TogglePVPUI()` call, because Blizzard's own toggle already has the narrow-close behaviour written by hand for the reputation path: `PVEFrame_ToggleFrame` closes only when the PvP panel is the one currently showing, and otherwise navigates to it, so clicking while the Group Finder sits on Dungeons switches rather than closing. It also owns the load-on-demand and the group-finder availability guard, so wrapping it in an `IsShown` check or a `LoadUI` call would only fight logic that is already correct. The bar hooks are now a dispatch table keyed by `StatusTrackingBarInfo.BarsEnum` rather than special-casing reputation, so wiring another bar is one entry. Experience, Artifact, Azerite and House Favor are deliberately left unwired — no window was requested for them, and a click that opens something unexpected is worse than one that does nothing. (`Journeys.lua`)

## [1.15.0] - 2026-08-24

### Added

- `VeritasUI_QualityOfLife` — **"Show as Experience Bar" now appears on the Journeys "Encounters" cards (Delves and Prey), which Blizzard ships without it.** The capability was always there; only the widget was missing. `JourneyCardButtonMixin` is `CreateFromMixins(RenownCardButtonMixin)`, so the encounter cards already inherit the `OnEnter`/`OnLeave` that reveal and hide the toggle — those were no-ops purely because the guard is `if self.WatchedFactionToggleFrame` and only `RenownCardButtonTemplate` declares that child. Creating it is the whole fix, after which Blizzard's own logic drives it, and the checkbox is `Mixin`'d with Blizzard's global `WatchedFactionToggleFrameMixin` so `OnClick` is theirs verbatim. Only `OnShow` is overridden: it derives its checked state from `C_Reputation.GetFactionDataByID`, which returns nil for every journey faction, so it would always draw unchecked — ours reads `GetWatchedFactionData().factionID` instead. Verified end to end in game: watching Delves: Season 2 produces a real bar reading `Delves: Season 2 (Warband) 2750 / 4200`, and the bar swaps cleanly between Delves and Prey. Placement is anchored to `JourneyCardLevel` rather than to a tuned offset, so Blizzard owns the row's position, and the horizontal inset is derived from their own `RIGHT x=30` spec so it matches the Renown cards exactly. (`Journeys.lua`, new)
- `VeritasUI_QualityOfLife` — **left-clicking the reputation status bar opens that faction's own page, and clicking again closes it.** Major factions — which is what Delves, Prey and every Renown track are — go to the Journeys page via the exact four-call sequence Blizzard's own renown NPC uses in `ShowMajorFactionRenown`; everything else opens Character → Reputation selected to that faction, walking the faction list by index because that pane addresses factions by index rather than ID. The toggle's close is deliberately narrow: it fires only when the window already shows that faction's own page, so a click while the Adventure Guide sits on Dungeons or on another faction navigates instead of discarding your place. Hooked on both status-bar containers, since Main and Secondary each build a full set of bars and Edit Mode decides which is on screen. (`Journeys.lua`)

## [1.14.20] - 2026-08-24

### Changed

- `VeritasUI_AuctionHouse` — **the Quantity row now stays visible on the Sell tab even when you only have one of the item, so "Create Auction" never moves.** Blizzard hides that row whenever you can post at most one — `AuctionHouseSellFrameMixin:SetItem` does `self.QuantityInput:SetShown(self:GetMaxQuantity() > 1)` — and because the sell form is a `VerticalLayoutFrame` whose children are ordered by `layoutIndex`, a hidden row is dropped from the layout entirely and every row beneath it (Unit Price, Duration, Deposit, Total Price, Create Auction) slides up one row height. Clicking a single-count icon in the sell strip therefore put the button at a different screen position than clicking a stack, which defeats click muscle memory. The row is now pinned shown on both sell forms via a post-hook on each form's `SetItem` — the sole place in the AH source that touches its visibility — after which Blizzard's own `MarkDirty`, `UpdateFocusTabbing` and `UpdatePostState` are re-run, since `SetItem` had already called them while the row was still hidden: without them the layout pass would miss the row, Tab from Unit Price would skip the now-visible box, and "Max" would be left enabled at 1 of 1. Blizzard's documented `SetCursorPosition(0)` workaround is re-applied too, because showing the box in the same frame its text was set is exactly the condition that hack exists for. Applied to the gear form as well, where the row reads 1 with "Max" greyed, so the button sits at one fixed height for every sale. Over-max typing remains clamped by Blizzard's own input callback, so an always-editable box cannot post more than you own. (`UI/SellStrip.lua`)

## [1.14.19] - 2026-08-24

### Fixed

- `VeritasUI_AuctionHouse` — **the Scan button no longer flashes "Retry Scan" at the start of every scan.** The label's pre-data state — scanning has begun but no progress exists yet — was calibrated for the replicate engine, where that window is a ~30 second snapshot wait that can stretch indefinitely if the server silently drops the request, and where clicking again genuinely re-fires it. On the browse engine (the default since v1.12.12) the same window is one throttled send plus a server round trip, so the state appeared for a fraction of a second on every scan and advertised a recovery browse cannot perform — `Browse.Start` refuses outright while a scan is already running. The state is now offered only where the engine can honour it: each engine declares `SupportsRetry`, and the button asks through `AH.Scan.SupportsRetry()` rather than testing engine names, preserving its contract as a pure view over the scan API. An engine that declares nothing defaults to NO retry, because a disabled "Scanning…" is never wrong whereas a false affordance is. ⚠ v1.14.17 removed this button's TOOLTIP for precisely this reason but kept the label state, leaving the misleading affordance without its explanation; this is the other half of that fix. (`UI/ScanButton.lua`, `Browse.lua`, `Replicate.lua`, `Core.lua`)

### Internal

- `VeritasUI_AuctionHouse` — **first test coverage for `UI/ScanButton.lua`.** No suite loaded the file, so its label state machine — the part visible during a scan — was entirely unverified, and a green run said nothing about it. 19 checks over all four states plus the engine-capability gate. Mutation-validated four ways: restoring the unconditional "Retry Scan", flipping browse's declaration, defaulting the facade to true, and removing replicate's capability each fail. ⚠ The suite's first version drove the button against a FAKED facade and so covered the consumer but never the producers — flipping browse's declaration still passed. It now asserts the real engine declarations and the real facade resolution before installing the fake.

## [1.14.18] - 2026-08-24

### Changed

- `VeritasUI_AuctionHouse` — **the scan progress bar is now Blizzard's Delve-card bar: no grey surround, rounded ends, and no text.** It previously sat inside the `auctionhouse-itemheaderframe` atlas — a grey squared-off card — with a squared health-bar fill and a "Scanning… N%" label crammed into 18px. It is now the three-piece build Blizzard uses on the Journeys delve card (`ui-journeys-renown-progressbar-BG` / `-fill` / `-frame`, sourced from `JourneyCardButtonTemplate` in `Blizzard_Journeys.xml`), three-sliced so the rounded caps keep their native pixel width instead of compressing 2:1 into our narrower band. The fill is left untinted for the green phases because Blizzard never tints it either (verified: `Blizzard_Journeys.lua` calls only `SetShown`/`SetMinMaxValues`/`SetValue`), and the amber/red phases desaturate first so a tint reads true rather than muddying to brown. (`UI/ScanProgress.lua`)
- `VeritasUI_AuctionHouse` — **the percentage label is off by default.** A bar and a number stating the same progress are redundant, and both terminal states already report to chat — `Core.lua` prints "Scan complete — N items priced." and "Scan failed — Prices were not updated". Removing it also freed the height the glyphs needed, which is what lets the caps read as round. ⚠ What this costs, deliberately: the indeterminate wait no longer shows its elapsed-seconds counter, so a long pre-progress wait reads as "working" (the sweep) but not "for how long" — that mattered once, when the server silently dropped requests for ~12 minutes. Recoverable with `/ah bartune label in|above`; the label code is kept, not deleted. (`UI/ScanProgress.lua`)

### Fixed

- `VeritasUI_AuctionHouse` — **a scan no longer re-sorts the Buy tab's Favorites list.** The scan re-issues the favorites search on completion so the server's result set matches the screen, but it passed an EMPTY sorts table — which means server-default (name) order. The list came back alphabetical while the column header still read "Price", presenting as a shuffle. The cause was a wrong claim in the code's own comment, that Blizzard's sort list was "a file-local and unreadable from here": `g_auctionHouseSortsBySearchContext` is declared without `local` at `Blizzard_AuctionHouseFrame.lua:2` and `AuctionHouseSearchContext` is a global `tInvert` table, and Blizzard reads that same table for this same purpose one line before its own `SearchForFavorites` call. The player's real sort order is now passed. Read-only and per-entry copied, so Blizzard's saved variable is never written or aliased — preserving the rule that this file calls no Blizzard method and writes no Blizzard table. (`Browse.lua`)
- `VeritasUI_AuctionHouse` — **the label no longer has its glyphs sheared top and bottom.** It was parented to the StatusBar, which sets `SetClipsChildren(true)` for the indeterminate sweep, so ascenders and descenders were clipped against the 18px rect. Clipping is wanted for the sweep and unwanted for the text, so the label now lives on its own unclipped host frame and shrinks by a delta derived from its own font object rather than a hardcoded point size. (`UI/ScanProgress.lua`)
- `VeritasUI_AuctionHouse` — **`/ah floor` and `/ah bartune` could throw a visible Lua error.** Both write saved settings and neither checked the database existed first, while `/ah engine` three branches away had always checked — reachable whenever the module disables itself on `AUCTION_HOUSE_DISABLED` or database init fails, with slash commands still registered. Both now guard and print "Settings not loaded." Found by a pre-release audit of the module. (`Core.lua`)

### Added

- `VeritasUI_AuctionHouse` — **`/ah floor` sets or disables the scan cooldown.** `off` allows back-to-back scans, `on` restores the 15-minute default, or pass a number of seconds. Added because verifying a cosmetic change to the scan bar otherwise cost a 15-minute wait per look. ⚠ This removes only our floor, not Blizzard's: on the replicate engine a repeat request may still be refused, while on the browse engine (the default) repeat scans genuinely work. Reported in `/ah diag`, since an overridden cooldown persists. (`Replicate.lua`, `Core.lua`)
- `VeritasUI_AuctionHouse` — **`/ah bardemo` parks the scan bar in one state so its appearance can be inspected without running a scan.** `run <pct>`, `wait`, `done`, `fail`, `off`. The headless suite cannot see the bar at all, so this is how a cosmetic change gets looked at. (`UI/ScanProgress.lua`, `Core.lua`)
- `VeritasUI_AuctionHouse` — **`/ah bartune` adjusts the bar's rounded-cap slice margin, height, label position and label font.** These are settled by eye, as the Delve-count constants were; the cap radius baked into a 335×18 atlas is not something Blizzard's source states. (`UI/ScanProgress.lua`, `Core.lua`)
- `VeritasUI_AuctionHouse` — **`/ah baratlas` draws the bar's atlases over a magenta plate so transparency is visible.** Three attempts at rounding the bar rested on one unverified assumption — that the art was pill-shaped with transparent corners — inferred from a screenshot and never measured. This probe settles that class of question in one look, and it is what identified the real cause. (`UI/ScanProgress.lua`, `Core.lua`)
- `VeritasUI_AuctionHouse` — **`/ah diag` reports the bar's art, shape, label and height state.** Native atlas sizes against the live rect, whether slicing took on each texture, and whether the label or height has been pinned away from its default. The native-versus-rect ratio is the one fact Blizzard's source cannot supply, and pinned settings are otherwise invisible. (`Core.lua`, `UI/ScanProgress.lua`)

## [1.14.17] - 2026-08-23

### Changed

- `VeritasUI_AuctionHouse` — **the Scan button no longer shows a tooltip.** Blizzard's own AH buttons carry none, the label already says what a click does, and the tooltip's main content had gone stale twice over: it explained a "Retry Scan" recovery flow that belongs to the *replicate* engine, while on the default browse engine (since v1.12.12) `Browse.Start` refuses to start while a scan is already running — so the advice ("click to re-fire, recovers a stuck scan") was not just clutter but wrong for the engine actually in use. The "Retry Scan" *label state* itself remains: it is still correct for anyone switched back to the replicate engine, where the click-to-recover path is real. (`UI/ScanButton.lua`)

## [1.14.16] - 2026-08-23

### Fixed

- `VeritasUI_AuctionHouse` — **the sell strip now shows every bag item the auction house will actually accept, not just items a vendor would also buy.** The strip's predicate was a heuristic from its construction — unbound + vendor sell price > 0, "matched 31/31 observed sellables" — which was measurement-complete for the bags it was probed against but wrong as a *definition*: auctionable items with no vendor value (caged battle pets are the canonical case; various BoEs and reagents too) read `sellPrice` 0/nil and were silently hidden — the owner-reported gap. The predicate is now `C_AuctionHouse.IsSellItemValid(loc, false)` — the exact check `AuctionHouseFrameMixin:SetPostItem` itself gates on before loading the sell form (verified against wow-ui-source live), so the strip shows precisely the set of items the native loader will accept when clicked, by construction. ⚠ `displayError=false` matters: the parameter *defaults to true*, which would pop a UI error for every non-sellable slot on every refresh. The unbound pre-filter stays (nothing bound is auctionable; skips the API call for most of the bag), the old vendor-price heuristic survives only as the fallback if `IsSellItemValid` is absent or errors, the warband-until-equip rejection stays as belt-and-braces (whether the API rejects warband gear itself is unmeasured, and the check only ever removes a definitively-unpostable item), and the cold-cache retry now covers *any* excluded item whose `GetItemInfo` is still nil — including a verdict delivered against cold data — not just the fallback path. (`UI/SellStrip.lua`)

## [1.14.15] - 2026-08-23

### Fixed

- `VeritasUI_AuctionHouse` — **running a scan no longer replaces the Buy tab's Favorites view with the entire auction house.** The browse engine's empty `SendBrowseQuery` (the default scan since v1.12.12) is not private: the server REPLACES the shared browse result set, and Blizzard's `AuctionHouseBrowseResultsFrame` — which renders the Buy tab's list, *including* the Favorites view, favorites being just a browse search (`C_AuctionHouse.SearchForFavorites`) — re-reads that set on `AUCTION_HOUSE_BROWSE_RESULTS_UPDATED/ADDED` (its `OnEvent` → `UpdateBrowseResults` → `GetBrowseResults`, verified against wow-ui-source live). So every scan visibly streamed ~20k items into whatever browse view the player had up. The scan now unregisters those events on Blizzard's frame for its duration — the frame's Lua-side copy of the list is simply never repainted — and re-registers them on every exit path (complete, failure, AH close; the close path re-registers without re-querying so the frame is never left deaf for the next session). If the Favorites view was up at scan start, `C_AuctionHouse.SearchForFavorites` is re-issued through the scan's existing throttle queue at completion, so the C-side result set matches the screen again. No Blizzard frame method is called and no Blizzard table is written — event-registration flips and one raw `C_AuctionHouse` call only (the `StaticPopupDialogs` taint lesson, v1.12.5). Known tradeoff: if category/search results were up instead of Favorites, they now stay on screen stale-but-intact rather than being replaced by the full AH; they are not re-queried, because that search's parameters live in Blizzard file-locals. (`Browse.lua`)

## [1.14.14] - 2026-08-16

### Fixed

- `VeritasUI_QualityOfLife` — **the digit-1 correction is now a DELTA off the global inset instead of replacing it, and defaults to 0 (no correction).** It used to assign the override outright, which made an inherently *relative* adjustment ("this glyph needs a pixel more inset than the others") behave as an absolute position. That had two costs. Setting `/qol delvenudge 0 0` in v1.14.13 silently changed the digit-1 correction from +2 to +3 with nothing touching it; and a `0` default would have been actively unsafe under the old semantics, because it matched the global only while the global was also `0` — the first `/qol delvenudge` would have torn the digit `1` away from every other digit by exactly the nudge. As a delta, `0` means "no correction" permanently and the two commands stay consistent with each other. ⚠ **Behaviour-preserving for existing accounts:** a stored value read as an absolute gave the same result as read as a delta off the shipped `0` global, so nothing moves and no migration is needed. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **`/qol delveone`'s report described the old absolute model.** It said the digit sat "N px in from the icon's right edge"; it now reports the delta, the resulting absolute, and what the other digits use, because a stale help string teaches the wrong mental model. (`QualityOfLife.lua`)

### Changed

- **The per-glyph override MECHANISM is kept, not removed, despite now being inert by default.** Deleting it has been tried once: v1.13.0 removed the equivalent override on the confident claim that corner anchoring made "every digit land identically by construction", and the owner falsified that on sight one version later — the `1` still read further right. Corner anchoring removed the width division and its per-digit rounding; it cannot move where a glyph's ink sits inside its own advance box, and no API exposes that. The typeface has also just changed to ARIALN, whose per-glyph metrics are unmeasured, so "no correction is needed" is currently an assumption rather than an observation. An inert knob costs one table entry; being wrong again costs a release. (`QualityOfLife.lua`)
- **Two more test assertions encoded the absolute semantics** and are now expressed as "the digit 1 differs from the other digits by exactly the stored delta", which is immune to a retune of either value. Mutation-validated: dropping the correction, reverting to absolute, and applying the delta to every digit fail 2, 2 and 5 assertions against a green identity control. (`qol_delve_test.lua`)

## [1.14.13] - 2026-08-15

### Changed

- `VeritasUI_QualityOfLife` — **the Delve count now ships matching Blizzard's own number: ARIALN typeface, `OUTLINE` weight, sitting on the icon's bottom-right corner, at 11px.** These are the values the owner settled on in game after measuring Blizzard's count on the Delve entrance placard, which draws `ARIALN.TTF` at size 14 with flags `"OUTLINE"` in white, anchored `BOTTOMRIGHT -2,+2` on a 36×36 icon. New defaults: `delveCountFace = "blizzard"`, `delveCountOutline = "OUTLINE"`, `delveFontDelta = -3`, `delveCountInsetX/Y = 0`. Existing installs are unaffected — the defaults table only seeds keys that are absent, so anyone who has tuned these keeps their values. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **the size is deliberately NOT Blizzard's exact proportion.** Blizzard's 14px on a 36×36 icon is a ratio of 0.389; the in-Delve icon measures 24×24, so the proportionally exact size would be 9.33px. The owner judged that too small to read and settled on 11px (ratio 0.458). The ratio arithmetic located the right neighbourhood; it was not the answer — matching Blizzard's proportion and being legible on the smaller icon turned out to be different goals. Recorded in the code so nobody "corrects" it back. (`QualityOfLife.lua`)

### Fixed

- **Nine test assertions froze cosmetic tuning values as if they were invariants, and failed on correct code the moment the defaults changed.** They asserted literal `FRIZQT__.TTF`, `THICKOUTLINE`, `14` and `-1/-1` — the tuning of one particular hour — which is the exact trap already documented as "do not freeze a cosmetic constant in a test", four of them introduced in v1.14.11. All nine now assert the **invariant**: the face follows `delveCountFace`, the size is StackCount's captured base plus the stored delta, the outline is the stored flag, and the applied offsets track the stored insets with the documented sign convention. Two of the typeface-fallback rungs also relied on `"plaque"` being the default, so they silently tested the wrong branch once it changed; they now set the precondition explicitly and restore it. Mutation-validated: hardcoding the delta, the outline, or the insets fails 7, 6 and 10 assertions respectively, against a green identity control. (`qol_delve_test.lua`)

## [1.14.12] - 2026-08-15

### Fixed

- `VeritasUI_QualityOfLife` — **`/qol delveplacard` now finds the entrance placard, which v1.14.11 could not.** It reported `found 0 spell widget(s)` against a placard plainly on screen, because it matched frames carrying a `SpellContainer` — and that parentKey belongs to the `ScenarioHeaderDelves` template alone (`Blizzard_UIWidgetTemplateScenarioHeaderDelves.xml:40`), i.e. the *in-delve* plaque. The entrance placard's "Map Properties" icons are registered into a generic `UIWidgetContainerTemplate` (`Blizzard_DelvesDifficultyPicker.xml:136`, registered at `.lua:651`) as `UIWidgetTemplateSpellDisplay` frames, which hold the spell frame one level down under parentKey `Spell` (`Blizzard_UIWidgetTemplateSpellDisplay.xml:8`) — so the old signature missed it twice over: wrong wrapper, and one level too shallow. The probe now looks the container up **by name** from source (`DelvesDifficultyPickerFrame.DelveModifiersWidgetContainer`) and walks `widgetFrames`, which cannot be defeated by a wrong signature or a depth cap. ⚠ The lesson is the one already recorded — a probe only covers the question it was built for — hit while writing a probe specifically to avoid it: the signature was generalised from the one surface already known, so it could only re-find that surface. Matching on `StackCount`, the thing actually being measured, is signature-by-goal rather than signature-by-example. (`QualityOfLife.lua`)

### Changed

- `VeritasUI_QualityOfLife` — **the shape sweep is retained as a backstop, widened, and now reports its depth.** It matches `StackCount`, `SpellContainer` or `widgetFrames`, names which signature matched each hit, and warns when the depth cap was actually reached — v1.14.11 could not distinguish "nothing there" from "stopped too early". Kept alongside the named lookup because it is the only thing that would notice Blizzard moving the count elsewhere. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **removed the probe's wrong conclusion.** On finding nothing it asserted "it is not a UIWidget spell frame — that is the finding", which was false: the placard's icons *are* UIWidgets, reached by a path the probe did not look down. A probe that prints a confident wrong conclusion is worse than one that prints nothing. (`QualityOfLife.lua`)

## [1.14.11] - 2026-08-15

### Added

- `VeritasUI_QualityOfLife` — **`/qol delveplacard`, a probe that measures the number Blizzard draws on the placard at a Delve entrance.** The existing `/qol delve` starts from `ScenarioObjectiveTracker` and is structurally blind to that surface, because the placard appears *before* the scenario tracker holds anything. This one discovers by SHAPE from `UIParent` — any frame carrying a `SpellContainer` whose children have `spellInfo` — and reports the sweep result so a miss is diagnosable rather than silent. For every spell widget found it dumps `stackDisplay`, the icon size, whether the `AmountBorder` is shown (which decides whether Blizzard centres the count or corner-anchors it), and the font file, size, flags, colour and anchor points of Blizzard's `StackCount`, the plaque's own `Text` and our count, side by side. Every widget call is `pcall`'d and the walk is depth-capped, because a sweep from `UIParent` meets forbidden objects — that is the v1.14.10 bug, not a hypothetical. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **`/qol delveface` and `/qol delveoutline` switch the count's typeface and outline weight live.** These are the two variables that differ between our count and Blizzard's own, and the only two that had no in-game knob — position, size, the digit `1` and the checkmark already had one. `delveface blizzard` uses the face Blizzard draws its count in (`ARIALN`, via `NumberFontNormal` → `NumberFont_Outline_Med`); `delveface plaque` uses the plaque's own Friz Quadrata. `delveoutline thick|normal|none` sets the weight, where `normal` is what Blizzard's own font object declares. **Both defaults are deliberately unchanged**, so nothing moves until asked. (`QualityOfLife.lua`)

### Fixed

- `VeritasUI_QualityOfLife` — **the count's font cache key now covers every input `SetFont` consumes, not just the size delta.** `DelveApplyFont` early-outs on a cached key; that key was the delta alone, which was correct only while the typeface and outline were compile-time constants. With both now adjustable, a delta-only key would have made `/qol delveface` and `/qol delveoutline` silently do nothing until the size happened to change — the same class of bug the anchor helper's key already documents. Found by mutation-testing rather than in game: reverting the key to its previous shape fails three assertions. (`QualityOfLife.lua`)

### Changed

- `VeritasUI_QualityOfLife` — **corrected the reasoning recorded for where the count's typeface comes from.** The comment said the template "declares it inherits `GameFontNormal`, so reading its file gives us exactly the plaque's face". Reading the live fontstring is right, but the justification was not: `Setup` calls `self.Text:Setup(text, self.spellInfo.textFontType, self.spellInfo.textSizeType, ...)` (`Blizzard_UIWidgetTemplateBase.lua:531`), so the live face is chosen by server-supplied font-type fields rather than fixed by the template's inherit. The note now says why reading the live object is the only correct approach, so nobody "simplifies" it to a hardcoded lookup. (`QualityOfLife.lua`)

## [1.14.10] - 2026-08-15

### Fixed

- `VeritasUI_Lib` — **hovering a House Editor room plaque no longer throws a repeating taint error from the player-frame fade.** The hover test walked the parent chain of whatever sat under the cursor with an unguarded `focus:GetParent()`. In the House Editor that object is a `HousingLayoutPin` button, which is a *forbidden* object — reading `focus.GetParent` as a table field succeeds, but calling it raises `Attempt to access forbidden object from code tainted by an AddOn`. Because the check runs from a 10 Hz ticker, the error's `Count` climbed by ten a second for as long as the pointer rested on the plaque, and each throw aborted the fade evaluation part-way. Every widget call in the walk is now wrapped in `pcall` and the walk is depth-capped, making it identical to the equivalent walk in `VUI.HookHoverFade` — which has had both guards since it was written. `VUI.HookPlayerFrameFade` was the inconsistency, not the pattern. An unreadable parent chain is treated as "not hovering", so the player frame fades normally while the cursor is on House Editor furniture. (`Lib.lua`)

## [1.14.9] - 2026-08-11

### Changed

- `VeritasUI_QualityOfLife` — **the "Cursor:" label now hides with its numbers when the pointer leaves the map, instead of lingering as `Cursor: —`.** Both parts of the readout appear together only while the pointer is over the map canvas, matching the behaviour of the native 12.1 map coordinates. `Player: …` owns the left edge, so it neither shifts nor jitters as the cursor half comes and goes. The label is still shown as `Cursor: —` in the narrower case where the pointer *is* over the canvas but no position can be read — that is a distinct state from being off the map and collapsing both to blank would have concealed it. (`QualityOfLife.lua`)

### Fixed

- `VeritasUI_QualityOfLife` — **the readout's invisible drag target no longer reserves the 12px inter-column gap while the cursor half is empty.** Left as-is, unlocking the readout to reposition it would leave a dead strip to the right of `Player: …` for the whole time the pointer was off the map. (`QualityOfLife.lua`)

## [1.14.8] - 2026-08-11

### Fixed

- `VeritasUI_CleanSolo` — **the chat-tab fade threw a Lua error on 12.1 and left the tabs stuck visible.** Patch 12.1.0 deleted the global `MouseIsOver()`, which the module captured at load, so the hide-countdown timer called a `nil` value about a second after the mouse left a chat frame or tab — aborting the fade block before any tab faded. Now calls the `:IsMouseOver()` widget method directly, which is what the deleted global was a one-line wrapper around (`Blizzard_UIParent/Shared/UIParent.lua:530` in 12.0.7) and what Blizzard's own 12.1 code uses. `Lib.lua`, `QualityOfLife.lua` and `SellStrip.lua` already used the widget method; CleanSolo was the only holdout. (`CleanSolo.lua`)

### Internal

- **Both the 12.0.7 and 12.1.0 UI source trees were diffed to bound the patch's impact.** Of the 133 Lua globals 12.1 removed, `MouseIsOver` is the only one this suite referenced, and none of the 86 names dropped from the generated C API documentation appear among the 60 `C_*` calls the modules make. This does not cover changed signatures of surviving functions or renamed Blizzard frame globals, which only surface in play.

## [1.14.7] - 2026-08-11

### Changed

- **Interface bumped to `120100` for WoW patch 12.1.0 (Curse of Ula'tek).** All seven module TOCs updated so the suite is not flagged out of date on the 12.1 client — no code changes. The interface number follows Blizzard's `MMmmpp` scheme, confirmed against this machine's `12.0.7` → `120007`. (all `.toc` files)

## [1.14.6] - 2026-08-08

### Fixed

- **Four comments that the settings-scope work had made false.** Two ZoneQuests settings registrations were still labelled as targeting per-character storage when they now correctly target the account-wide table; AdvancedOptions' login comment described the old binder copying account values into a character's slot, which is the behaviour the refactor removed; and two library comments presented the legacy binder's fallback as the current pattern. Each would have sent a future change down a wrong path. (`ZoneQuests.lua`, `AdvancedOptions/Core.lua`, `Lib.lua`)

### Removed

- `VeritasUI_ZoneQuests` — **a defaults table whose purpose no longer existed.** It merged both scopes for the sake of the old account-wide seeding pass, which is gone; its only remaining use was supplying defaults to settings registrations that are all account-wide. Those read the account-wide table directly now, so adding a per-character key to that loop fails loudly instead of silently registering it at the wrong scope. (`ZoneQuests.lua`)

### Internal

- **Copy Settings verified end to end against the four real modules.** Now that only per-character keys are copyable, the new suite asserts per module that the copy registry carries no account-wide key — the quiet failure being that registering the wrong set would make `/vui copy` write shared values into one character's slot. Then a full copy: the per-character value moves, the account-wide value is untouched, no shared key is written into the destination, and undo restores without reaching account scope.
- **The legacy binder is retained rather than deleted, deliberately.** It has no callers left, but removing it is tidiness with no defect attached — which this project's own audit discipline default-rejects — and the entire cost would land in test code, rewriting three working suites. Its header now records that it is legacy, why it remains, and names both behaviours that caused the defects this refactor removed, so it cannot be mistaken for the current pattern.

## [1.14.5] - 2026-08-08

### Changed

- `VeritasUI_QualityOfLife` — **the Delve count's placement, the item-level and map-coordinate toggles, auto-sell, auto-repair and the AFK screen are now shared by every character; repair funding stays per-character.** Twelve settings move to account scope, including all five Delve tuning values and the map readout's dragged position. Repair funding remains per character because guild membership differs and whether guild funds should be spent on repairs is a decision you may want to make differently on an alt. (`QualityOfLife.lua`)

### Fixed

- **A setting tuned on one character now actually reaches the others.** Previously every Quality of Life setting was stored per character, so a value confirmed on your main never applied anywhere else — and worse, once a character held its own copy, a later change to the shipped default could never reach it. That is why the digit-`1` position corrected in v1.13.4 only ever took effect on the one character it was tuned on. Verified across two characters: both now report identical insets, including a hand-nudged value that had previously existed on only one of them. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **the map coordinate readout's dragged position is carried across rather than lost.** It is the one account-wide setting with no default — an unset value means "use the default anchor" — so it could not simply be added to the defaults table, and a migration derived from that table would have discarded it silently. (`QualityOfLife.lua`)

### Internal

- **A precedence bug introduced during this conversion was caught by the existing vendor suite before release.** Guarding the guild-repair check produced `cdb and X or false` above an existing `and IsInGuild() and …` chain; because `and` binds tighter than `or`, that parses as `(cdb and X) or (false and …)`, short-circuiting the guild-membership checks away entirely — guild repair would have fired with no guild at all. The trap is now documented at the site.
- **Three existing suites asserted the previous storage location and were updated deliberately rather than silenced.** One had been writing both tables "for clarity", which would have passed whichever the module read. Another's "a fresh character inherits this value" assertions were inverted, since that inheritance was the defect. Several of its value assertions had become contaminated — the nudge cases far above now write the same account table those assertions read, and one passed only because an earlier case happened to reset the value. Replaced with structural assertions no earlier write can fake, leaving shipped values verified from source

## [1.14.4] - 2026-08-08

### Changed

- `VeritasUI_CleanSolo` — **chrome and chat settings are now shared by every character, while action-bar fading and player-frame fading stay per-character.** This is the module that prompted per-character storage in the first place: alts inheriting a main's bar-fade choices was the original complaint, and the fix at the time made *everything* per-character, including nine settings that are really about the interface itself. The nine — chat tab fading, transparent chat background, the four button-hiding toggles, micro-menu fading, macro names and error text — are now set once for the account. Action-bar fading, its display label and player-frame fading remain per character. (`CleanSolo.lua`)

### Internal

- **The settings panel builds all ten checkboxes from a single loop, and one of the ten is per-character.** Both the table handed to Blizzard's Settings framework and the table each default is read from are now resolved per key. This is the failure mode that would have been quietest: Blizzard captures the table by reference, so passing one table for all ten would have stored player-frame fading at account scope while the runtime code read the character's — invisible until a value failed to persist or leaked between characters. The test now asserts the exact nine-account/two-character split rather than trusting it.
- **The action-bar fade dropdown registers under a paired key** (`fadeActionBarsLabel`, the composite "Bars 2, 5" string recomputed from the bar list), which must share its partner's scope or the panel would describe a different character's bars.
- **Table defaults are deep-copied.** `fadeActionBars` is table-typed, and the hand-rolled loop this replaces used a shallow copy whose own comment warned it would alias a nested default into saved storage.
- **A comment asserting a now-false invariant was rewritten.** It read "every read below and every Settings control must see the same table", which was true only while the whole module was per-character; the invariant now holds per key, and leaving the sentence would have misled the next change

## [1.14.3] - 2026-08-08

### Fixed

- `VeritasUI_AdvancedOptions` — **collapsing a category on the Featured tab hid the category below it.** Expanding again left several checkboxes missing until a different category was collapsed, which then broke the one after that. Controls and headers are created once and cached, then reparented into whichever scroll-list frame the layout assigns; the record of "this frame is showing that control" was written only on the incoming frame, with nothing mapping a control back to the frame currently displaying it. A collapse rebuilds the list and reassigns elements, leaving the old frame holding a stale pointer — and the next time that frame was reused for anything, it hid a control a different frame was legitimately showing. Ownership is now recorded on the control itself and only the owning frame may release it. Headers were affected identically, which is why a whole category title could vanish rather than just its contents. (`Featured.lua`)
- `VeritasUI_AdvancedOptions` — **collapsing or expanding anything near the bottom of the Featured tab jumped the view back to the top**, so you had to scroll all the way down again to expand what you had just collapsed. Rebuilding the list scrolls to the beginning unless it is explicitly told to retain position. Safe when the list shrinks: Blizzard's scroll box captures the offset before recalculating and corrects it afterwards, precisely so that contents are not displaced by additions or removals. (`Featured.lua`)

### Internal

- **`Featured.lua` now has coverage — 674 lines that had none.** `ao_featured_test` captures the real element initializer from the view and drives it through the frame-reuse sequence a collapse produces. 28 assertions; three failed before the fix. Mutation-verified against six: removing the ownership guard, dropping either ownership write, the tempting "never detach" over-fix, and dropping the scroll-retention flag.
- **Two mutations initially survived, and one was instructive.** Deleting the *header* ownership write made the header case pass by accident — with ownership never recorded the guard can never fire, so nothing is hidden and the test looks satisfied, while the real cost would have been headers never released at all. Found only by mutating each write separately rather than the fix as a whole. A mock defect surfaced too: parent was stored under a name the mock's catch-all metatable turns into a stub function, so an "is it unparented?" assertion could never be true

## [1.14.2] - 2026-08-08

### Changed

- `VeritasUI_AdvancedOptions` — **starred CVars, collapsed sections and the last active tab are now shared by every character; the CVar value cache stays per-character.** Those three are preferences about the browser itself, so keeping a separate copy per alt served no purpose. The cache stays per-character because WoW's own CVars are a mix of account- and character-scoped, making one character's last-known-good value unsafe to apply to another. (`Core.lua`)

### Fixed

- `VeritasUI_AdvancedOptions` — **the per-character CVar cache was being written into account-wide storage at load time.** `AO:InitDB()` runs twice, at `ADDON_LOADED` and again at `PLAYER_LOGIN`, and the old binder returned the account-wide table as a stand-in on the first call — so the cache was seeded and version-stamped account-wide before the addon knew which character it was. All per-character work now waits for the second call. (`Core.lua`)
- `VeritasUI_AdvancedOptions` — **`cacheVersion` was an undeclared saved key.** It records which addon version the CVar cache was built for, and it had never appeared in a defaults table — which is how it escaped the first pass of the scope audit. It is now declared, and pinned to the same scope as the cache it invalidates: split across scopes, the first character to log in after an upgrade would stamp the new version and every other character's stale cache would never be cleared again. (`Core.lua`)

### Internal

- **Table defaults are now deep-copied rather than shallow-copied.** The loop this replaces carried a comment warning that a nested default would be aliased into saved storage; the shared binder copies recursively, so that hazard is gone rather than documented.
- **Two mutations survived the test suite before it was strengthened, and both gaps were in the tests rather than the code.** The suite modelled only a *fresh* account, where the pinning and pairing defects cannot exist — a legacy-data scenario now pre-populates both scopes in the account table and in two character slots, as a pre-refactor account actually looks. And event-handler errors were being discarded by `pcall`, hiding the crash caused by removing the "no identity yet" guard; they are now collected and asserted. Fixture values are unique empty tables compared by identity, after a sentinel string broke a module whose real value is genuinely a table.
- **`scope_map_test` was scanning 2 of AdvancedOptions' 5 files.** Those three contain no saved keys today, so the gap was harmless in fact, but a new one added there would have been invisible to every assertion in the suite

## [1.14.1] - 2026-08-08

### Changed

- `VeritasUI_ZoneQuests` — **the quest filter settings are now shared by every character, while the watched-quest list stays per-character.** Previously the whole module was per-character, so each alt had its own copy of filtering choices that are really about how you want the tracker to behave. `enabled` and the five `pin*` filters moved to account scope; `manualWatched` stays per-character because it is a snapshot of one character's quest log, and sharing it would restore watch state for quests an alt has never picked up. A one-off message on first login names whatever it promoted. (`ZoneQuests.lua`)

### Added

- `VeritasUI_Lib` — **`VUI.MigrateScopedDB`, the one-way migration for a module moving to per-key scope.** It promotes the current character's stored values for newly-shared keys, clears those keys from every character's slot so a stale copy cannot resurrect, and deletes the vestigial account-wide copies of per-character keys. Its key lists are the same two tables handed to `VUI.BindScopedDB`, so the migration and the scope decision are one thing and cannot drift apart. (`Lib.lua`)

### Fixed

- `VeritasUI_ZoneQuests` — **the old title-based watch-list migration ran against the wrong table.** It executed at `ADDON_LOADED` against the account-wide root; the list now lives per-character, so the check is re-pointed there. This also covers the one case the old placement never did — a character whose slot predates the migration. (`ZoneQuests.lua`)

### Internal

- **The hand-rolled defaults-seeding loop was replaced, not supplemented.** That loop wrote every default into the account root and is the mechanism behind the pinning defect this refactor removes, so leaving it beside the new binder would have achieved nothing.
- **`module_scope_test` (new) verifies at RUNTIME that each key resolves into the table the scope map specifies.** It replaces a source-parsed version written first and then removed: that version passed against a module whose per-character table had been emptied, because pattern-extracting a Lua table literal proved too fragile to trust in either direction. Where a value actually lands after the module runs is what decides where it is stored, so that is what is asserted. `scope_map_test`'s own extractor was rewritten to be line-bounded for the same reason, and `module_charDB_test`'s "every registration targets the character slot" assertion — correct only while a module was per-character in its entirety — is now a per-module root/slot split checked against the map

## [1.14.0] - 2026-08-08

### Added

- `VeritasUI_Lib` — **`VUI.BindScopedDB(globalName, universalDefaults, perCharDefaults)`, which gives a module PER-KEY saved-variable scope instead of all-or-nothing.** Returns `accountTable, charTable`; call it at both `ADDON_LOADED` (account table only, no identity yet) and `PLAYER_LOGIN` (both). Groundwork only — **no module uses it yet and nothing changes in game.** `VUI.BindCharDB` is untouched and the four modules currently on it keep working unchanged. (`Lib.lua`)

### Requires

- Nothing. This release is additive: 77 lines added, none changed or removed, and the new function has no callers.

### Internal

- **Two of the new binder's contracts are deliberately the opposite of `BindCharDB`'s, because `BindCharDB`'s behaviour is what produced the defect this refactor exists to fix.** It returns `nil` rather than the account root when the character identity is unavailable — falling back would write per-character keys into account-wide storage at load time. And it never copies account-wide keys into a new character's slot — that copy is what pins a shipped default per character, which is audit finding D8. It also errors if a key appears in both scopes, rather than silently choosing one and hiding a scope-map violation for as long as the two happen to agree.
- **New `scoped_db_test`, 22 assertions, mutation-verified against five.** Reinstating either inverted contract, registering the wrong defaults with the copy feature, removing the double-scope check, or shallow-copying table defaults each fails a distinct assertion. The suite also asserts `BindCharDB` still behaves as before, since the four modules migrate off it one at a time over the following phases

## [1.13.8] - 2026-08-08

### Fixed

- **Four comments that asserted things which are not true.** No behaviour changes — verified mechanically by filtering the diff for any changed line that is not a comment or blank, of which there were none. Each of these would have sent a future change down a wrong path:
  - `VeritasUI_AuctionHouse` — `UI/ScanProgress.lua` and `UI/ScanButton.lua` both described a live "persistent 60s retry chain". **There is no automatic retry.** `DoFire` has exactly one caller, inside `Start`, and `Replicate.lua:247-250` says so explicitly: since v1.9.14 the attempt counter records user-initiated fires only. The `ScanButton` wording was the more harmful of the two, claiming a dropped request "recovers with zero clicks" — the opposite of the truth, since clicking the button is the *only* recovery. (`UI/ScanProgress.lua`, `UI/ScanButton.lua`)
  - `VeritasUI_AuctionHouse` — `Replicate.lua` said the Scan button calls `AH.Replicate.StartManual()`. It calls `AH.Scan.StartManual`, the facade, and has since v1.12.9; the `Replicate` alias has **zero callers** anywhere in the suite. Kept as a back-compat surface, now marked as not live. (`Replicate.lua`)
  - `VeritasUI_Lib` — the `GetMouseFocus` shim's rationale stated a 5 Hz poll and reasoned "would error five times a second" from that figure. `PLAYER_FRAME_HOVER_POLL_RATE` is `0.10`, i.e. **10 Hz**, as a note 300 lines below already said. It understated the blast radius of the exact hazard the block exists to describe, by half — and that ticker keeps no handle, so the error flood cannot be cancelled short of a reload. (`Lib.lua`)
  - `VeritasUI_Lib` — the PlayerFrame policy block claimed hooking that frame was "the one place in this suite that hooked a secure Blizzard frame's mouse scripts". `HookHoverFade` still does exactly that on `MicroMenu` and up to seven `MultiBar*` containers. That hooking is deliberate and documented — parent containers yes, child action buttons never — but the "one place" claim was false, and it is what someone would trust when the next `ADDON_ACTION_FORBIDDEN` names the library. What is genuinely unique about PlayerFrame is that it is where hooking was *abandoned* in favour of polling. (`Lib.lua`)

## [1.13.7] - 2026-08-08

### Fixed

- `VeritasUI_AuctionHouse` — **the scan progress bar did nothing on the default scan engine.** `UI/ScanProgress.lua` read `AH.Replicate.*` directly at every site, but browse has been the default engine since v1.12.12 and `Replicate.IsScanning()` reports only replicate's own state — so the ticker's first line returned immediately and stayed that way for the whole scan. The result was an unanimated bar frozen on "Connecting…" that snapped straight to "Scan complete", with the three-phase readout the file exists to provide inert on the engine that actually runs. The ticker gate, the progress read and the requested-phase relabel now use the `AH.Scan` facade, which reports either engine and dispatches to whichever is live. Cause was the v1.12.9 facade migration, which moved `UI/ScanButton.lua` across and missed this file. (`UI/ScanProgress.lua`)

### Changed

- `VeritasUI_AuctionHouse` — **a browse scan now shows two phases rather than three, which is the honest count.** Browse fires `AH_SCAN_START`, `AH_SCAN_REQUESTED`, `AH_SCAN_COMPLETE` and `AH_SCAN_FAILED`, but never `AH_SCAN_FINALIZING` — it has no cold-cache gear-residue phase (`Browse.lua:33`). The finalizing handler is therefore left gated on `AH.Replicate` deliberately, since routing it through the facade would display "Finalizing gear… N/M" from counts that do not exist for that engine. Browse's progress curve is unchanged: it reaches roughly 57% on the first page and approaches completion asymptotically, by design, because Blizzard exposes no total. (`UI/ScanProgress.lua`)

### Internal

- **`UI/ScanProgress.lua` now has coverage** — 408 lines that had none. `ah_scanprogress_test` drives the real file against a fake namespace holding two independent engines, so "replicate idle, browse scanning" — the production default — is reachable at all. Seven cases, two failing before the fix, with a replicate control proving the harness. All four mutations are caught, including the one that routes finalizing through the facade, so the deliberate non-change is enforced rather than merely commented

## [1.13.6] - 2026-08-08

### Fixed

- `VeritasUI_QualityOfLife` — **unticking Show Item Levels left every painted number on screen, and recycled bag slots then showed the wrong item's level.** The `SetItemButtonQuality` hook returned on `not db.showItemLevels` before any `HideOverlay`, and the setting's callback was enable-only, so switching the feature off did nothing until `/reload`. Because bag and bank buttons are reused across items, those stale numbers persisted over whatever item later occupied the slot — a wrong item level displayed against an unrelated item. The setting now applies live in both directions, mirroring Show Map Coordinates directly above it. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **the merchant scanner ignored the setting.** `UpdateMerchantItems` gated on the merchant window being shown and on the selected tab, but never on `showItemLevels`, so vendor item levels kept being repainted after the feature was switched off. It now carries the same gate every other consumer of the feature already had. (`QualityOfLife.lua`)

### Internal

- **Item-level overlays are tracked in a weak-keyed registry** so they can be swept without a reload, with the sweep forward-declared because the options panel is built before the overlay system exists. The hook additionally hides on a disabled button rather than returning, which covers anything Blizzard repaints after the sweep — the two mechanisms handle different moments and mutation testing confirms neither is redundant.
- **The item-level paths had no disable coverage at all.** Four assertions added across three cases, all failing before the fix. Two pre-existing test defects were found while writing them: the texture mock's `Show`/`Hide` were no-ops, so every assertion about the gradient backdrop passed without testing anything, and the test toggled the account-wide root while the module reads its per-character slot, so the disable never took effect. The suite now asserts up front that it resolved the table the module actually reads

## [1.13.5] - 2026-08-08

### Fixed

- `VeritasUI_QualityOfLife` — **`/qol delve` reported a stale default for the digit `1`.** The probe printed `[default -1/-1, digit 1 at 1]` as a hardcoded literal, while the shipped digit-1 inset became `3` in v1.13.4 — so the one tool whose purpose is answering "what is this set to" from the client stated a default that was no longer true. The annotation is now formatted from `DELVE_COUNT_INSET_Y`, `DELVE_COUNT_INSET_X` and `DELVE_COUNT_INSET_X_BY_COUNT[1]`, so it cannot drift from the values it describes. Also drops an inline comment that named the old value in prose. (`QualityOfLife.lua`)

### Internal

- **The digit-1 drift check now covers all three copies of the value, not two.** v1.13.4 added a test asserting the `defaults` entry and the render constant agree — and it passed green while a third copy, the probe's literal, was stale. It now also asserts the probe formats its defaults rather than stating them, that no numeric literal default survives in code (comments excluded, since the fix's own comment quotes the old string as documentation), and that the format arguments are passed in `Y, X, digit-1` order. That last assertion is source-level on purpose: both inset constants are `-1`, so a swapped pair would print identically forever and reveal itself only when one is retuned. Mutation-verified against all three failures

## [1.13.4] - 2026-08-08

### Changed

- `VeritasUI_QualityOfLife` — **the Delve count `1` now defaults to 3px in from the icon's right edge, matching every other digit's optical position.** Owner-dialled in game with `/qol delveone 3`; the previous default of `1` still read slightly right of the others. Updated in both places that hold the value — the `defaults` table (what a fresh character inherits, since these settings are per-character) and the `DELVE_COUNT_INSET_X_BY_COUNT` fallback used when the saved key is absent. (`QualityOfLife.lua`)

### Fixed

- `VeritasUI_QualityOfLife` — **`/qol delveone` is now discoverable from inside the game.** The Delve Nemesis Count setting's description listed `/qol delvenudge` and `/qol delvecheck` but never mentioned the per-digit command, so the only way to learn it existed was reading the v1.13.1 changelog. (`QualityOfLife.lua`)

### Internal

- **`qol_delve_test` no longer freezes the digit-1 inset as a literal.** The assertion read `== 1`, so retuning a purely cosmetic pixel value broke a test that had no business caring what the number is — the "do not freeze a cosmetic constant in a test" trap, in the file that documents it. It now parses both value sources from the shipped Lua and asserts they AGREE, plus that a fresh character inherits whatever is currently tuned. Mutation-verified: leaving the constant behind while changing the default fails the suite

## [1.13.3] - 2026-08-07

### Changed

- `VeritasUI_QualityOfLife` — **Auto Repair and Auto Sell Junk now size their coin icons through Blizzard's own `GetMoneyString` instead of a hardcoded pixel size.** `GetMoneyString` emits each coin as `|T...:0:0|t`, and height 0 + width 0 means "size = the font's text height" — the same mechanism Blizzard's own `You gained:` line uses, rather than a number of ours that reproduces its result. Both approaches render identically today; this one inherits any future change Blizzard makes to coin sizing or coin art instead of silently desyncing until the constant is re-tuned by eye. It also handles colorblind mode explicitly, swapping coins for `GOLD`/`SILVER`/`COPPER_AMOUNT_SYMBOL`. The v1.13.2 `GetCoinTextureString(copper, 12)` path is retained as a fallback. (`QualityOfLife.lua`)

## [1.13.2] - 2026-08-07

### Fixed

- `VeritasUI_QualityOfLife` — **Auto Repair and Auto Sell Junk drew their coin icons larger than Blizzard's.** Both money lines rendered coins one notch bigger than the coins on Blizzard's own `You gained:` line directly beneath them in chat. `GetCoinTextureString`'s icon height defaults to 14; ours now passes 12, matched by eye against Blizzard's line and confirmed in game. Routes all six money strings through a single `Coins()` helper so the size is one named constant instead of six literals. (`QualityOfLife.lua`)

### Internal

- `VeritasUI_QualityOfLife` — **recorded that an absolute coin size is the correct approach here, with the measurement that proves it.** A font-derived, self-scaling size was drafted on the reasoning that a fixed pixel value could only match at one chat font size, since Blizzard's own money strings size coins font-relatively. The sources behind that were accurate but the conclusion was not: WoW's chat font-size setting scales the entire chat frame as a unit, so an absolute coin size tracks the text on its own. Verified at chat font 14, 16 and 18. The self-scaling draft was discarded and the finding written into the code to stop it being "fixed" again. (`QualityOfLife.lua`)

## [1.13.1] - 2026-08-07

### Fixed

- `VeritasUI_QualityOfLife` — **the Delve count `1` sat further right than the other digits.** Restores a per-glyph horizontal correction for that one digit, live via `/qol delveone <left>` and defaulting to `1` against the global `-1`. v1.13.0 removed the equivalent correction on the claim that corner-anchoring made it unnecessary; that was wrong. Corner-anchoring pins the advance box's right edge, which removes the width division and its per-digit pixel rounding, but it cannot move where a glyph's ink sits *inside* its own box — and that is the one cause no accessor can measure, since `GetStringWidth` and `GetUnboundedStringWidth` both report the advance. The correction is horizontal only: digits share a baseline and none has a descender, so the vertical never differs. (`QualityOfLife.lua`)

## [1.13.0] - 2026-08-07

### Changed

- `VeritasUI_QualityOfLife` — **the Delve Nemesis count now sits in the icon's lower-right corner instead of being centred on it.** Centring could not be made exact: three rounds of by-eye offsets each fixed one digit and left another visibly off, because the API centres a string's metrics box while no accessor exposes glyph ink bounds, and halving the icon's width lands on fractional pixels that round per digit. The count is now anchored by a single `BOTTOMRIGHT` point — the same construction Blizzard uses for `StackCount` on this exact widget template — so every digit lands identically with no width division. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **the Delve count is drawn white at every value.** `HIGHLIGHT_FONT_COLOR`, which is what `NumberFontNormal` declares and therefore the colour Blizzard's own stack counts render in. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **`/qol delvenudge` now takes insets from the icon's bottom-right corner** rather than offsets from its centre — pixels in from the right edge and up from the bottom, negatives moving outside the icon. Argument order is unchanged, vertical first. Shipped default is `-1 -1`. (`QualityOfLife.lua`)

### Removed

- `VeritasUI_QualityOfLife` — **the dark circular scrim behind the Delve count.** It existed to keep a centred digit readable over icon art; in Blizzard's corner their own count has no backing texture, and the number's `THICKOUTLINE` and drop shadow carry the contrast instead. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **the four-step count colour ramp** (4 red, 3 orange, 2 yellow, 1 green). A stack badge that changes colour by value is not something the default UI does. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **`/qol delvetint` and the per-glyph `/qol delveone`**, along with the saved keys `delveCountCenterX`, `delveCountCenterY`, `delveCountCenterX1` and `delveTintAlpha`, which are cleared at login rather than reinterpreted — a stored offset from the icon's centre is a different position read as a corner inset. (`QualityOfLife.lua`)

### Fixed

- `VeritasUI_QualityOfLife` — **the Delve completion checkmark was slightly too large.** It extended 2px past the icon on every side; it is now flush with the icon's bounds, and tunable with `/qol delvecheck`. (`QualityOfLife.lua`)

All notable changes to VeritasUI are documented here. Dates reflect the conversation sessions where changes were developed and tested.

## [1.12.20] - 2026-08-05

Corrects the Delve count's typeface, which was the only number on that plaque not in Friz Quadrata. Also records an attempt at removing the vertical offset that failed in game, so it is not retried by someone reading the code and thinking it looks unfinished.

### Changed

- `VeritasUI_QualityOfLife` — **the Nemesis count is now in Friz Quadrata, matching every other number on the Delve plaque.** It had been inheriting its font wholesale from Blizzard's `StackCount`, which is `NumberFontNormal` — that is ARIALN, a condensed stack-badge face, and it left the count as the only number on the panel in a different typeface. The face is now read from the widget's **own `Text` fontstring**, which the template declares `inherits="GameFontNormal"`, so it is the plaque's actual face rather than a pinned path and it follows Blizzard if they ever restyle the standard UI font. The fallback chain is `Text` → `GameFontNormal` → a literal `FRIZQT__`, none of which can land back on ARIALN. **Only the face changed:** the size still comes from `StackCount`, which is the scale Blizzard chose for a number sitting inside this icon, so switching typeface moved one variable and not two. (`QualityOfLife.lua`)

### Added

- `VeritasUI_QualityOfLife` — **`/qol delve` now reports the count's justify values, its own rect, the icon's rect and its string height.** Horizontal centring is structural and digit-independent, but vertical centring still relies on the `/qol delvenudge` offset, because a fontstring with no height ignores `justifyV`. Anchoring the string on all four sides to give it a height — which should have made `justifyV` meaningful — instead pushed the number into the icon's upper-left corner, meaning *both* justifications stopped applying, and that is not explained by the reasoning behind the change. The attempt is reverted and documented in place with a regression guard in the test suite; these measurements are what a future attempt should start from rather than another hypothesis. (`QualityOfLife.lua`)

## [1.12.19] - 2026-08-05

Reworks the Delve Nemesis readout from a bare number under the icon into a tinted number on it, replaced by a checkmark once the delve is cleared. Two of the three defects fixed along the way were caused by asserting a mechanism instead of reading Blizzard's source.

### Changed

- `VeritasUI_QualityOfLife` — **the Nemesis groups-remaining count now sits on the icon over a dark circular scrim, instead of hanging below the plaque.** The scrim is masked to the icon's own circle and draws beneath the gold border ring, so it darkens the art without dimming the ring. Darkness is a live setting (`/qol delvetint`, default 60%). (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **the count is centred structurally rather than by a tuned offset, so it stays centred on every digit.** The fontstring spans the icon's full width and is centre-justified, which centres the glyph regardless of its advance width. Centre-anchoring a width-less fontstring instead centres its bounding *box*, so an offset dialled in against "4" could be visibly wrong for "1" — a latent defect the owner spotted before it shipped. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **the number is bolder.** WoW's `SetFont` has no weight flag, so the outline is thickened to `THICKOUTLINE`, which is what Blizzard uses on nameplate and floating-damage numbers. The font file and size are still copied from Blizzard's `StackCount`, so both track a future restyle; only the weight is ours. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **the count renders at Blizzard's own font size.** The previous one-point reduction existed because the number sat *below* the icon, where `StackCount`'s size read a shade large against the plaque's other text. It sits *on* the icon now, which is precisely the placement `StackCount` is sized for, so that rationale was void by its own terms. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **the colour progression is now one colour per step: 4 red, 3 orange, 2 yellow, 1 green.** Previously 3 and 2 were both orange and green was reserved for 0; now that 0 is drawn as a checkmark rather than a digit, green belongs on the last live number. 0 remains green because it is still reachable if the checkmark atlas is unavailable, and counts above 4 still fall through to red so a larger delve reads "plenty left" rather than losing its colour. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **`/qol delvenudge` takes both axes: `/qol delvenudge <down> [right]`.** A single argument still changes only the vertical offset. Both default to 1, the values settled against the live plaque; the vertical pixel is not arbitrary, as a fontstring's box height is the line height and digits do not occupy the descent, so centring the box leaves the ink sitting high. (`QualityOfLife.lua`)

### Added

- `VeritasUI_QualityOfLife` — **a green checkmark replaces the number once every Nemesis group is defeated.** It uses `common-icon-checkmark`, the same atlas Blizzard's own `EarnedCheck` uses on this widget, drawn over the whole icon rather than in the corner. It is a texture of ours rather than Blizzard's `EarnedCheck`, because their `Setup` calls `SetShown(spellInfo.showAsEarned)` on every widget update — driving theirs would be a fight lost on the next update, and owning ours leaves their native path intact if the server ever sets that field. The scrim and number both hide, so the checkmark reads against the plain icon, and it clears again when a new delve reports groups remaining. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **`/qol delvetint <0-100>` and `/qol delvesize <n>`**, live and persisted, for the scrim darkness and the font size relative to Blizzard's. Both are by-eye values, and dialling one through screenshot round-trips is slow and imprecise since captures arrive at different crops and scales. Out-of-range values are clamped rather than ignored, so an obvious intent is not silently discarded. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **`/qol delve` now reports which mask is shown, the live digit widths, and the resolved font.** Each answers a question that came up during this work and would otherwise be argued rather than measured: which mask is active decides whether an overlay clips circular or square, equal digit widths decide whether one horizontal offset suits every digit, and the resolved font answers what size the number actually is. (`QualityOfLife.lua`)

### Fixed

- `VeritasUI_QualityOfLife` — **the scrim rendered as a square protruding past the round icon.** Blizzard's `Setup` shows exactly one of two masks per widget — `IconMask` when `iconDisplayType` is not `Circular`, `CircleMask` when it is — and hides the other. Delve icons are circular, so the mask attached to was the one Blizzard had just switched off, and a hidden `MaskTexture` does not mask. The scrim now attaches to **both**, exactly as Blizzard's own XML lists the Icon under both, which hands the arbitration back to them and keeps working if a widget ever flips that field. An earlier revision of this fix attributed the square to `SetColorTexture` and said so in a code comment; that was asserted without verification and is corrected in place. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **a fresh character would have started with the count off-centre.** Settings are per-character since v1.11.0, so the hand-tuned offsets lived only on the character they were tuned on and every alt would have begun at zero. The settled values are now the shipped defaults. (`QualityOfLife.lua`)

### Removed

- `VeritasUI_QualityOfLife` — **the superseded `delveCountOffsetY` setting is dropped at login rather than reinterpreted.** It measured from the icon's bottom edge; the count now measures from the icon's centre, so a stored value is expressed in an origin that no longer exists. Carrying it across would have been a silent one-pixel lie. (`QualityOfLife.lua`)

## [1.12.18] - 2026-08-04

Removes the last place in the suite that hooked a secure Blizzard frame's scripts. Surfaced by a blocked-action report that named the module and the function.

### Fixed

- `VeritasUI_AuctionHouse` — **using an item from your bags could be refused outright until you reloaded, and the auction price tooltip was the cause.** The recorder captured `ADDON_ACTION_FORBIDDEN`, addon `VeritasUI_AuctionHouse`, `func = UseContainerItem()` while clicking a quest-reward crafting-knowledge item; the click failed and only a `/reload` restored it. Nothing in the module calls `UseContainerItem` — suite-wide it appears once, in QualityOfLife's vendor sell path, which was not running — so this was taint propagation, the same shape as the `ClearTarget` capture in v1.12.3. This is the second occurrence of the signature on a bag-item action; the first was sending a housing decor item to the vault (2026-07-28), which had been open since. The module's owned coin fontstring was hidden by `tooltip:HookScript("OnTooltipCleared", …)` on `GameTooltip`, which injects a tainted closure directly into a secure frame's script dispatch — precisely the pattern removed from `PlayerFrame` in v1.12.3. It survived that sweep only because the claim was written as "the last place hooking a secure frame's **mouse** scripts", and `OnTooltipCleared` is not a mouse script. (`Tooltip.lua`)
- `VeritasUI_AuctionHouse` — **the file header asserted "read-only so it carries no taint risk", which is false and was contradicted by this report.** Reading the price database is harmless, but the file also mutates a shared secure Blizzard frame. The claim is replaced with a description of what it actually does, and a note not to reinstate a blanket no-taint statement. (`Tooltip.lua`)

### Changed

- `VeritasUI_AuctionHouse` — **the coin line is now hidden by two mechanisms that never touch Blizzard's frame**, reproducing the removed hook's behaviour exactly. An `AllTypes` tooltip post-call handles every tooltip built through Blizzard's tooltip data system; Blizzard insulates those deliberately, wrapping an insecure registrant in `forceinsecure()` and dispatching each through `securecallfunction`, which a script hook receives none of. Ordering was verified in Blizzard's source rather than assumed: `ProcessInsecureCalls` walks the `AllTypes` list before the type-specific list, so the hide always precedes the price render in the same synchronous rebuild and there is no flicker. A second driver, a poll alive only while the coins are on screen, covers tooltips built the legacy way with no data pipeline and therefore no post-call of any type — our own Scan button tooltip, and the AdvancedOptions, PriorityRotation and QualityOfLife text tooltips. Without that backstop this change would have traded a functional bug for a cosmetic one. No visual change: font, coin markup and the live-measured coin column are untouched. (`Tooltip.lua`)

### Notes

- **This is not proven to be the cause, and is not claimed as such.** The same lazily-created block also adds the coin fontstring onto `GameTooltip`, the other way this file mutates a secure frame, and the two arm together on the first priced-item hover — so no observation can separate them. The hook was removed because it was already a banned pattern here, which justifies the change independently of whether it was this defect. Moving the fontstring was deliberately not attempted in the same release: that is the visually risky half, with a falsified prior attempt behind it. If the signature recurs, the fontstring is the sole remaining suspect in this file.
- Verified in game before release across the tooltip render, the item-to-unit transition, a legacy tooltip following a priced hover, an unpriced item, a caged pet, and inside a Delve — that last one because this file has a real crash history in instanced content. The bag-item action itself was also exercised cleanly, but that is a single sample against a signature seen twice in five weeks, so it is recorded as encouraging rather than as evidence.

## [1.12.17] - 2026-08-04

Makes the Delve Nemesis count actually work. It did not function in v1.12.15 or v1.12.16 — both of those shipped on an unverified assumption about where Blizzard keeps the number.

### Fixed

- `VeritasUI_QualityOfLife` — **the Delve Nemesis count never appeared, for a reason neither previous release identified.** The count is read from the **spell description**, not from the widget's tooltip string. Measured on a live Delve: `spellInfo.tooltip` and `spellInfo.text` are both empty on all three icons, so v1.12.15 had nothing to parse. Blizzard's own `UIWidgetBaseSpellTemplateMixin:OnEnter` explains it — when the widget string is empty it falls back to `EmbeddedItemTooltip:SetSpellByID`, so the "Enemy groups remaining: N / M" line is the spell's description, filled in by the server. Now read via `C_Spell.GetSpellDescription`, with the widget string still preferred if Blizzard ever supplies it, and a data-load request when the description is not yet cached.
- `VeritasUI_QualityOfLife` — **v1.12.16's diagnosis was wrong and its fix addressed a non-bug.** The probe showed `StageBlock ... hasSpellContainer=YES`, so the original container path was correct all along. The search-by-shape discovery introduced there is kept because it is genuinely more robust to Blizzard moving the widget, but it was not the defect and should not have been released as a fix.

### Added

- `VeritasUI_QualityOfLife` — **the count is coloured by how many groups remain**, so the plaque reads at a glance without reading the digit: 4 red, 3–2 orange, 1 yellow, 0 green. Uses Blizzard's own `RED_FONT_COLOR` / `ORANGE_FONT_COLOR` / `YELLOW_FONT_COLOR` / `GREEN_FONT_COLOR` objects rather than invented RGB, so it matches the client and follows any restyle. A count above the observed maximum of four clamps to red rather than losing its colour, since that total is a single observation.
- `VeritasUI_QualityOfLife` — **`/qol delvenudge <n>`**, a live, persisted vertical offset for the count. Larger is lower, negative overlaps up into the icon, and it applies within half a second with no reload. Added because dialling a cosmetic offset through screenshot round-trips is slow and cannot be measured — captures arrive at different crops and scales, so each adjustment was guesswork. The shipped default of `-1` is the value settled on in game, not a calculation.

### Changed

- `VeritasUI_QualityOfLife` — the count's font is now one point below Blizzard's `StackCount`, read back through `GetFont` so the font file and its `OUTLINE` flag are preserved rather than re-specified by hand.

### Internal

- Process correction: v1.12.15 and v1.12.16 were both tagged and released before any in-game verification, against live UI behaviour that had never been read. The established loop — sync to the live AddOns folder, confirm in game, *then* commit and release — was followed for this release, and every change in it is confirmed working.
- The suite's stub previously modelled the table *path* the production code assumed, and later failed to model fonts at all, so both the wrong-source and the font-resize code were silent no-ops under test while passing. It now models a real frame tree, spell descriptions, fonts and colours. 74 checks, failing against v1.12.16.
- Removed a test that froze a cosmetic offset as an invariant; it failed on correct code the moment the offset was tuned. Replaced with the real invariants — the anchor point, and that the offset tracks the stored setting.

## [1.12.16] - 2026-08-04

Fixes the Delve Nemesis count not appearing: it was being looked for in the wrong one of Blizzard's three widget containers.

### Fixed

- `VeritasUI_QualityOfLife` — **the Delve Nemesis count never appeared.** v1.12.15 looked for the plaque in `ScenarioObjectiveTracker.StageBlock.WidgetContainer`, but Blizzard's XML declares **three** sibling widget containers — `StageBlock`, `TopWidgetContainerBlock` and `BottomWidgetContainerBlock` — and the Delve header lives in one of the others. One of three was picked by inference and shipped.
  - Fixed by **searching for the plaque's shape rather than its path**: a bounded walk of the tracker's descendants looking for a frame with a `SpellContainer` whose children carry `spellInfo`. Deliberately not another hardcoded path, which would have been the same one-in-three guess. This is self-validating — the thing searched for is the thing needed — and it survives Blizzard moving the widget between containers, which is precisely what went wrong.
  - The found widget is cached, and the cache is invalidated both when the tracker goes away and when the widget reports hidden. A released widget still answers `GetChildren`, so a cache keyed only on "this validated last time" could outlive the Delve.
  - `/qol delve` now reports **all three containers by name**, with child counts and whether each holds a `SpellContainer`. Had it printed that in v1.12.15, this would have been one screenshot instead of a release.

### Internal

- The headless suite's stub modelled the *path* the production code assumed rather than a real frame tree, so it could not have caught this — a stub that mirrors the code's assumption can only confirm that assumption. It now builds `tracker → three blocks → WidgetContainer → widget → SpellContainer` with `GetChildren` at every level, takes the hosting container as a parameter, and asserts the count appears for **all three** placements. 42 checks, failing against v1.12.15.
- Renamed a recursive walk's parameter that shadowed the module's event `frame` upvalue.

## [1.12.15] - 2026-08-04

Shows the Delve Nemesis groups-remaining count under the plaque icon, instead of only revealing it on hover.

### Added

- `VeritasUI_QualityOfLife` — **Show Delve Nemesis Count.** The Delve plaque's middle circular icon holds the number of Nemesis enemy groups you still have to clear, but only inside its tooltip, so checking it mid-run means stopping to hover. The count is now painted permanently just below that icon as a bare countdown (4, 3, 2, 1, 0). On by default; toggle in Quality of Life settings.
  - Structure verified from Blizzard's own source rather than guessed: the plaque is a **single** `ScenarioHeaderDelves` widget under `ScenarioObjectiveTracker.StageBlock.WidgetContainer`, and the three icons are its `spells` table driving a pool of `UIWidgetBaseSpellTemplate` frames under `SpellContainer`, each carrying its own `spellInfo`.
  - The count is parsed from the tooltip because **no numeric field carries it**. `spellInfo.stackDisplay` would be the obvious source, but Blizzard's spell template draws its `StackCount` fontstring unconditionally whenever `stackDisplay > 0` — and no number is drawn on any of the three icons, so all three are zero. If Blizzard ever populates that field, the overlay hides itself and defers to the native one.
  - The icon is identified by **which tooltip contains an "N / M" pair**, not by being second in the row. Position rests on a single observation and Blizzard owns the ordering, whereas the pattern that identifies the icon is the number itself — so the wrong icon can never be labelled with a real count.
  - Uses its own fontstring with the font copied live off Blizzard's `StackCount`, so it matches the client's number styling without fighting Blizzard's show/hide logic on every widget rebuild.
  - Driven by a 0.5s poll rather than a hook: frames built from a mixin get the methods copied onto them, so hooking the mixin table afterwards would miss every existing frame. The poll body early-outs unless a Delve plaque is on screen.
- `VeritasUI_QualityOfLife` — **`/qol delve`**, a permanent diagnostic dumping the live plaque's icons with each one's `spellID`, `stackDisplay`, `text`, tooltip and what the parser extracted. Kept shipped for the same reason as `/ah check` and `/qol ilvl`: the whole design rests on where Blizzard keeps this number, and that is only knowable by reading the live widget.

## [1.12.14] - 2026-08-04

Stops the scan-completion line from reporting an auction count the browse engine never had.

### Fixed

- `VeritasUI_AuctionHouse` — **the scan-completion line claimed an auction count that browse does not measure.** The wording was hardcoded to "N items priced from M auctions" for both engines, which is true of replicate — it walks individual auction rows, so M is genuinely informative (15,828 priced from 272,220). Browse returns one summary per item and never sees an auction count, so M was just the item count restated: the first browse scan after v1.12.13 printed "22702 items priced from 22702 auctions", repeating one number under two labels while understating the real auction count by orders of magnitude. The source noun is now supplied by the firing engine, so browse omits the clause instead of inventing a figure, and replicate keeps it. Passed in rather than derived from the engine name at the print site, so `Core.lua` keeps owning the user-facing wording while staying engine-agnostic. (`Core.lua`, `Replicate.lua`)

### Internal

- The headless suite now asserts, by source, that every `AH_SCAN_COMPLETE` fire site agrees with the handler's contract — a site that forgets the noun would otherwise degrade silently to the shorter sentence. It also covers the login-notice guard across four simulated logins, confirming the one-time scan-engine reset notice is once-ever rather than once-per-login.

## [1.12.13] - 2026-08-04

Fixes the reason the v1.12.12 browse trial never actually ran, and makes which scan engine is active visible in the three places that should already have said so.

### Fixed

- `VeritasUI_AuctionHouse` — **the scan-engine default was unreachable, so v1.12.12's browse trial silently ran on replicate for its entire duration.** `scanEngine` was seeded into saved variables like an ordinary toggle, which writes a concrete engine name on the first login of any release. From that moment on, changing the default in `Tooltip.lua` could not change behaviour for anyone who had already logged in. The default moved browse to replicate to browse across v1.12.9, v1.12.11 and v1.12.12 and **every one of those flips was inert**; the owner's saved variables read `["scanEngine"] = "replicate"` while v1.12.12 shipped announcing browse as the default. A setting whose default is under active evaluation is now exempt from seeding, so absence means "follow the default" and the default is live. A previously-seeded value is cleared once, announced at login, because a seeded value and a deliberate pin are indistinguishable in the stored data — there was never a flag recording which wrote it. (`Tooltip.lua`, `Core.lua`)
- `VeritasUI_AuctionHouse` — **`/ah help` never listed `engine`, `compare` or `browseprobe`.** All three shipped as working branches in v1.12.9 and were advertised nowhere, so for four releases the only way to find the command that selects the scan engine was to read the source. The `Surface:` comment above the slash handler already warned a reader to keep the branch list, that comment and `PrintHelp` in step by hand — and it did not survive one feature. The headless suite now asserts the three agree, scoped to `PrintHelp`'s body, because that is the only form of this rule that cannot be forgotten. (`Core.lua`)
- `VeritasUI_AuctionHouse` — **a browse pin fell back to replicate silently when `Browse.lua` was absent.** Falling back is right, since a scan beats no scan, but doing it without a word is not: the user asked for one engine and would get the other engine's failure modes with no explanation. Warned once per session. (`Core.lua`)
- `VeritasUI_AuctionHouse` — corrected the comment on the engine resolver, which claimed a nil setting meant replicate. It does not; an absent key reads as the current default. The `or "replicate"` beside it is a load-order guard, not a policy, and read as deliberate intent while the real policy lived in `SETTING_DEFAULTS`. (`Core.lua`)

### Added

- `VeritasUI_AuctionHouse` — **the active scan engine is now named in three places: the scan-start line, `/ah diag`, and `/ah engine`.** The module has shipped two engines with materially different failure modes since v1.12.9 and named neither. The only reason the wrong engine was ever noticed is that replicate's 60-second "request was lost" message happens to be engine-specific — the system was diagnosed by luck, not by observability. `/ah diag` and `/ah engine` also distinguish a deliberate pin from the default. (`Core.lua`)
- `VeritasUI_AuctionHouse` — **`/ah engine default`**, which clears a pin and returns to following the default. Without it, pinning was a one-way door that could only be undone by editing saved variables. (`Core.lua`)

## [1.12.12] - 2026-08-04

Makes the browse engine the default again, for a trial period, after decomposing the numbers that prompted the previous release to revert it.

The revert in 1.12.11 was an over-correction. The price discrepancy that triggered it was real but smaller than it appeared, because two different problems were being added together. A stored price of 2 gold 11 silver was compared against a market price of 2 gold 98 silver, a gap of 29%. Almost all of that was simply the market moving — that commodity climbed 41% over the course of a few minutes — and any engine's stored price goes stale the moment the market moves. Measured at a single instant, against the game's own cheapest listing, the browse engine reads about 8% low. That is the part actually attributable to the engine.

An 8% understatement on fast-moving commodities is a genuine defect and it is documented rather than dismissed. But it is not worse than an engine that fails the first scan of most days, which is the problem this whole line of work set out to solve and which remains unsolved after five falsified explanations. The browse engine completed in ten to fifteen seconds on every attempt, priced 22,540 items where the older engine managed 15,828 in nearly a minute, and does not abandon gear — the older engine dropped between 38% and 67% of all gear rows on two measured scans, freezing both the price and the recorded age of those items.

So this ships as the default on the basis that a scan that works and reads slightly low is more useful than an exact one that cannot be relied upon to run. It is a trial: if prices feel wrong in daily use, `/ah engine replicate` switches back, and `/ah browseprobe` will show what the game returned for any single item at the moment of asking.

### Changed

- `VeritasUI_AuctionHouse` — **Default scan engine is browse again.** The reasoning, and the arithmetic separating the engine's ~8% lag from ordinary scan staleness, is recorded in full beside the setting so a future change has to engage with it rather than repeat the same conflation. This is the third time the default has moved; the note says so. (`Tooltip.lua`, `Browse.lua`)

### Notes

- A minutes-granularity price-age line was proposed as a way to make staleness visible, and **declined**: the age line exists to answer "should I rescan", and per-minute detail on every tooltip is noise rather than signal. Price age stays day-grained, and a test now guards that decision so it is not quietly "improved" later.
- Neither engine is clean. Browse reports prices below the market minimum, which nothing discloses. Replicate abandons gear rows and serves stale gear prices, which the age line does disclose. Both defects are documented where a reader will meet them.

## [1.12.11] - 2026-08-04

Reverts the default scan engine to replicate. The browse engine introduced two releases ago reports prices that are not the lowest price available, and it should not have been made the default.

The evidence is a single reading that admits no other interpretation. For one commodity, at one moment: the game's own sell listing, sorted cheapest first, showed the lowest available price as 2 gold 98 silver. The browse engine reported 2 gold 75 silver. A lowest price cannot be below the cheapest thing on sale. The same reading showed the quantity matching the game's figure almost exactly, so the engine is looking at the right set of auctions and only its price is wrong.

The practical effect was that a tooltip advertised 2 gold 11 silver for an item selling at 2 gold 98 silver. Anyone pricing against that number loses money, which makes it unfit as a default regardless of the engine's other merits.

The likeliest explanation is that the figure is a cached summary that lags behind the live market, which would match on items whose price is steady and read low on items whose price is climbing. That is consistent with the comparison run before the switch, which showed near-total agreement on most items alongside a two-to-one bias toward reading low on the rest — a bias that was noticed at the time and wrongly dismissed as ordinary market movement. It has not been confirmed, and the revert does not depend on confirming it.

Browse remains selectable and is still the faster engine with better coverage — 22,540 items in fifteen seconds against 15,828 in fifty-six, and it never abandons gear the way replicate does. It is not deprecated. But it will not be the default again until the price discrepancy is understood rather than averaged away.

### Changed

- `VeritasUI_AuctionHouse` — **Default scan engine reverted to replicate.** Browse's reported minimum price was measured below the cheapest existing listing for the same item at the same moment, so it cannot be used as a price source. The revert deliberately does not wait on an explanation: a confidently wrong price is worse than replicate's known problem, which produces stale prices that the tooltip's age line discloses. (`Tooltip.lua`, `Browse.lua`)

### Added

- `VeritasUI_AuctionHouse` — **`/ah browseprobe`, now permanent.** Shift-click an item at the auction house and it runs a browse scan that writes nothing, then reports exactly what the game returned for that item: price, quantity, item level, derived key, and whether the result was used or skipped. Compare the reported price against the sell tab's cheapest listing at the same moment. This is the tool that found the discrepancy, and it is the tool that would have to clear browse before it could be default again, so it is kept rather than removed. (`Browse.lua`, `Core.lua`)

### Notes

- Both engines now have a documented, distinct defect, and neither is a clean baseline. Replicate abandons gear rows and therefore serves stale gear prices, which the age line at least discloses. Browse reports prices below the market minimum, which nothing discloses. The second is worse, which is the whole reason for the revert.
- The comparison tool's own headline figure — 98.2% agreement on commodities — is an average over a population dominated by items whose price had not moved, and it concealed the failure on the items that had. It should not be used on its own to justify promoting an engine again.

## [1.12.10] - 2026-08-04

Retracts a cause stated in the previous release that turned out to be invented, and adds the measurement that should have come first.

Version 1.12.9 introduced the browse scan engine and made it the default. It also claimed, in this changelog and in the source, that the older replicate engine loses gear because it waits passively for item data instead of asking for it. That was written without reading the code it described. Replicate does ask, both when a row is first set aside and again on every subsequent attempt. The claim was wrong, and it was the second wrong explanation offered for the same problem — the first being that the retry deadline was too short, which a later scan disproved by stopping well before that deadline.

The cause is therefore unknown, and this release says so rather than offering a third guess. What is known is that the machinery worked on one scan and stopped early on the next, and the difference is unexplained. Three candidates are recorded and none of them is asserted.

The more serious omission was on the new engine. Browse discards a result in three situations and, as shipped, reported none of them. That replaced a loss the old engine printed in plain view with a loss nothing recorded at all. Two of those situations are legitimate — a listing with nothing available, and a listing with no buyout price, both of which the old engine also skips. The third is not: a result that cannot be identified is lost data, and it is now counted, reported prominently, and accompanied by examples so the next step is a lookup rather than an inference.

### Fixed

- `VeritasUI_AuctionHouse` — **Browse no longer discards results silently.** Every skipped result is counted by reason and reported at the end of a scan; results that could not be keyed are called out separately with example item IDs, because those are real data loss rather than a legitimate skip. A scan with nothing skipped stays quiet. This is the evidence that the default scan engine is not losing items, and it is deliberately not hidden behind a debug flag. (`Browse.lua`)
- `VeritasUI_AuctionHouse` — **Retracted the invented explanation for replicate's gear loss.** The source, and the previous release notes, asserted a cause that reading the code disproves. The comment now records what is actually known, names the three unmeasured candidates, and instructs against filling the gap with another guess. (`Replicate.lua`)

### Added

- `VeritasUI_AuctionHouse` — **Replicate now reports why its retry phase ended.** When gear rows are abandoned it prints the count, whether it ran out of time or concluded the data stream had dried up, how many attempts it made, and how many rows could never have been retried because their item identity was never established. Those three numbers separate the candidate causes. Always printed when rows are lost — an unexplained loss visible only under a debug flag is one nobody will explain. (`Replicate.lua`)

### Notes

- The quiescence check that ends the retry phase does so after a **single** attempt that resolves nothing. With attempts three seconds apart and item data arriving asynchronously, one empty window is thin evidence the stream has stopped, and this is one of the three candidates. It is counted but deliberately **not** changed: after two wrong guesses, that is a change to make on evidence.
- Browse remains the default and has no deferred rows, so none of this affects the normal path. Replicate is kept as the fallback, and a fallback with an unexplained data loss is not a fallback — hence finishing the measurement rather than moving on.

## [1.12.9] - 2026-08-04

Adds a second Auction House scan engine and makes it the default, because the one this addon was built on has never worked reliably and the alternative measurably does.

The scan asks the server for every auction and folds the results into a price database. That request — replicate — fails the first scan of most days, and months of work established only what the cause is not: not taint, not the way the request is fired, not readiness, not pacing, not an account rate limit. Each was investigated and ruled out.

The answer turned out to be that there was a second way to do the job. Auctionator, which scans the same account reliably, does not use replicate at all in its default configuration; it sends an empty search and pages through the results, and ships the replicate path switched off behind an advanced option. That is a different server endpoint, and on a live test it completed in fifteen seconds at the exact moment ours had just failed.

Both engines are now present and either can be selected. Browse is the default. Comparing the two on a live realm found near-total agreement where agreement was expected — 98.2% of commodities and 100% of pets priced identically to the copper — which settled the one open question about the new engine, namely whether its prices might reflect bids rather than buyouts. They do not.

Gear is the exception, and it is the old engine at fault. Replicate cannot identify a piece of gear without loading its full item data, and when that data does not arrive in time it abandons the row. On two measured scans it abandoned 38% and then 67% of all gear. An abandoned row updates neither its price nor its date, so gear prices could be days old immediately after a successful scan, and scanning again dropped them again. The new engine receives the item level as part of each result, so there is nothing to load, nothing to defer, and nothing to drop. It also found 1,388 gear items the database did not have at all.

### Added

- `VeritasUI_AuctionHouse` — **Browse-summary scan engine.** An empty `C_AuctionHouse.SendBrowseQuery` paginated via `RequestMoreBrowseResults` until `HasFullBrowseResults`, folding per-item summaries the same way the replicate path folds rows: minimum unit price and summed quantity. Restores the throttled-message send queue the design specified in Phase 1 and v1.7.0 removed — browse queries, unlike replicate, genuinely run inside that system. No timeout, matching the replicate rule: delivery time is unbounded and a watchdog can only kill a slow success. (`Browse.lua`, new)
- `VeritasUI_AuctionHouse` — **`AH.DB.MakeKeyFromItemKey`.** Derives a price key from a browse result's `itemKey`, taking gear item level and battle-pet species directly from the result rather than from a loaded link. Produces keys byte-identical to `MakeKey`, so both engines write the same records and can be compared item for item. Third copy of this file's gear predicate; all three are now cross-referenced. (`Database.lua`)
- `VeritasUI_AuctionHouse` — **`AH.Scan` engine façade, `/ah engine`, and `/ah compare`.** The façade dispatches to either engine so callers stay engine-agnostic; `UI/ScanButton.lua` no longer references either engine directly, preserving its stated role as a pure view over a public API. `/ah compare` runs a browse scan in dry-run mode, writing nothing and consuming no cooldown, and diffs its prices against the stored database by item class with median ratios and a freshness-scoped coverage split. (`Core.lua`, `UI/ScanButton.lua`)

### Changed

- `VeritasUI_AuctionHouse` — **Default scan engine is now browse.** Replicate remains fully selectable via `/ah engine replicate` and is not deprecated: it is the only engine that sees per-auction detail, and the fallback if a realm ever refuses browse. Its gear coverage is unreliable, and `Replicate.lua` now says so where a reader will find it. (`Tooltip.lua`)
- `VeritasUI_AuctionHouse` — **Gear-retry budget raised from 45 to 120 seconds.** This was a stop-gap for the abandoned-gear problem and it did not work: the next scan exited after four passes on its quiescence check, nowhere near the cap, with more gear unresolved than before. Kept because it bounds the case where the cap genuinely binds, and annotated with what actually happened so the next reader does not repeat the reasoning. The likely root cause is recorded and deliberately not fixed — the retry loop polls for item data rather than requesting it, and the browse engine makes that path unnecessary. (`Replicate.lua`)

### Notes

- **Known, unresolved:** the comparison found 209 items from the most recent replicate scan that browse did not return — 0.9%, including a few commodities. Most plausibly auctions that sold or expired in the minute between the two scans, but that is an explanation and not a measurement. Net coverage still favours browse decisively: 1,388 items found against 209 missed, versus 10,609 gear rows abandoned by replicate on the same scan. To settle it, run `/ah compare` twice in succession — churn gives a different set each time, a structural gap gives the same one.
- The file header claiming replicate is the only sanctioned whole-AH scan was corrected in v1.12.7. It conflated `SendSearchQuery`, which is genuinely rate-capped and unsuitable, with `SendBrowseQuery`, which is neither. That conflation is why this module stayed on one endpoint for months.

## [1.12.8] - 2026-08-03

Adds a Reagents Value line to Blizzard's Place Crafting Order window, showing what a recipe's reagents are worth at your last-scanned auction prices.

The line sits under the reagent list, where the form already leaves a gap. Reagents you have allocated are priced at the quality you actually chose; slots you have not filled are priced at their cheapest quality for the amount still required, which is why a recipe with everything at 0/N still shows a figure. Optional and finishing slots cost nothing until you allocate them.

It reads only the stored price database, so it works away from an auction house and never sends a query. There is a checkbox for it in the Auction House settings, on by default.

Two deliberate differences from how Auctionator does the same job. It prices each reagent at the vendor price when one exists, falling back to the auction price; this uses auction prices only, which is the question being answered — what these are worth on the auction house — but it means the figure is a sale value and not the cheapest way to source the materials. And where Auctionator silently counts a reagent it has no price for as costing nothing, making a partly-unknown recipe look cheap rather than unknown, this appends the number of unpriced reagents instead, or says so outright when nothing is known.

### Added

- `VeritasUI_AuctionHouse` — **"Reagents Value:" line on the Place Crafting Order form.** Totals the recipe's reagents from the stored price database, mounted on `ProfessionsCustomerOrdersFrame.Form` when the crafting-order interaction opens. Allocated reagents priced at the chosen quality via the form's transaction allocations; unallocated basic slots at their cheapest quality for the remaining quantity; optional and finishing slots excluded until allocated. Unpriced reagents are counted and reported rather than treated as free. Every profession API call is `pcall`-guarded, so a Blizzard restructure costs the line rather than throwing. New "Show Reagents Value on Crafting Orders" checkbox, default on. (`UI/CraftingOrder.lua`, new; `Settings.lua`, `Core.lua`)

### Changed

- `VeritasUI_AuctionHouse` — **`TT_DEFAULTS` renamed to `SETTING_DEFAULTS`, and `AH.Setting` added as the canonical accessor.** The table is no longer tooltip-only, and `Settings.lua` already documents `SeedDefaults` as the single seeding authority — a crafting toggle living in a table named for tooltips would mislead the next reader, and a second defaults table would drift from the settings panel. `AH.Tooltip.Setting` is kept so existing call sites are untouched. (`Tooltip.lua`)

### Notes

- The reagent cost model was reimplemented from Auctionator's `Source_Mainline/CraftingInfo`, not guessed. Cross-checked on one recipe: 3,136g 88s against Auctionator's 3,266g 24s on the same recipe from a different scan — the same ballpark, which is evidence the model matches rather than merely being self-consistent.
- The amount renders in white through the same probe-verified coin-atlas builder the tooltip price uses, so the two agree and the atlas constants exist in one place. The label stays in Blizzard's gold label font. Inline texture markup is not tinted by a colour code, which is what allows a single fontstring to carry both.
- Two facts were recorded during development and are worth knowing beyond this feature: `OnUpdate` does not fire on a hidden frame, so a frame whose own `OnUpdate` reveals it must never start hidden; and the verified frame path for this window, including its sibling keys, so a future Blizzard rename is detectable rather than a guessing exercise.

## [1.12.7] - 2026-08-03

Reverts the fifteen-minute lockout added three days ago, because the comparison that justified it turned out to have tested a different part of the auction house API — and that mistake led to the most useful finding so far.

Version 1.12.6 made a failed scan start the fifteen-minute cooldown, so a scan that produced nothing locked the button for a quarter of an hour. The reasoning was that Auctionator, which scans reliably on the same account, records every attempt rather than every success, and that our willingness to retry immediately was aggravating the server.

Testing that on a real failure showed something different. Our scan failed as usual, Auctionator's full scan succeeded moments later — but its own chat line said "summary mode", and that is a separate implementation which never calls the function ours depends on. It sends an empty browse search and pages through the results instead. Auctionator ships with the function we use switched off; the single Full Scan button chooses between the two based on a checkbox in its Advanced settings that is off by default.

So the lockout was copied from the half of Auctionator that its own users do not run, and there is no evidence it protected anything. It has been removed. A failed scan leaves no cooldown, exactly as before 1.12.6, and you can press Scan again immediately.

The finding that matters is that the browse-search path completed successfully at the moment ours was dead, on the same character and realm, seconds apart. That is a working alternative rather than another theory, and adding it is the next piece of work. The cause of the original failure is still unknown and is no longer the thing being chased.

### Changed

- `VeritasUI_AuctionHouse` — **A failed scan no longer starts the 15-minute floor.** The v1.12.6 attempt-stamp is removed and the floor is success-only again, as it was from v1.6.47 to v1.12.5. Pressing Scan after a loss re-fires immediately. (`Replicate.lua`)
- `VeritasUI_AuctionHouse` — **The lost-request message no longer quotes a cooldown.** It states that the request was lost, that Scan can be pressed again, and that reopening the Auction House and `/reload` make no difference — and stops asking for a diagnostic line now known to be blank on this code path. (`Replicate.lua`)

### Fixed

- `VeritasUI_AuctionHouse` — **The file header claimed `ReplicateItems` is the only sanctioned whole-AH scan.** It conflated two different APIs: `SendSearchQuery`, an item-specific search that is rate-capped and correctly rejected for scanning, and `SendBrowseQuery`, which is neither the same call nor subject to the same cap and enumerates the whole auction house as per-item summaries when paginated. That single conflation is what kept this module tied to one endpoint for months, so the header now records both APIs, Auctionator's default, and the measurement. (`Replicate.lua`)

### Notes

- **Measured:** with our replicate scan freshly failed (zero event pulses, no data), Auctionator's browse scan returned 20,056 items seconds later on the same character, realm and session — comparable to our usual 19,000-25,000. The failure is an endpoint difference, not a timing, taint, readiness, fire-context or rate-limit difference; all five of those were investigated and falsified.
- **The throttled-message instrumentation added in v1.12.6 is retained and now has a purpose.** It is inert for replicate, which was measured, but browse queries do run inside the throttled-message system — Auctionator routes every one through a queue for that reason — so it becomes load-bearing when the browse path lands.
- **Next:** add the browse-summary scan. It carries a real trade to settle first, namely that browse returns a minimum price and total quantity per item rather than the per-auction distribution this database currently records.

## [1.12.6] - 2026-07-31

The Auction House scan failed the first time each day and then refused to recover, and the message it printed sent you round a loop that could not work.

The scan asks the server for a full snapshot of the auction house. That request sometimes produces nothing at all: no data, no error. Until now, a request that produced nothing cost the addon nothing either, so the addon would happily let you ask again straight away, over and over, at whatever pace you clicked. Auctionator — which does the same job reliably on the same account — behaves differently in exactly one respect: it records the time of every attempt, successful or not, and refuses to ask again for fifteen minutes. It has no path that skips this, and reloading or reopening the auction house does not clear it.

This release adopts that rule. A scan attempt now starts the fifteen-minute cooldown at the moment it is sent, rather than only when data comes back. The practical effect is that a failed scan now locks the button for fifteen minutes instead of letting you retry immediately. That is deliberate: the evidence is that asking again quickly is at best useless and may be prolonging the problem.

The advice the addon printed on failure — close the auction house, reopen it, and scan again, because "it works straight away; there is no need to wait" — was wrong, and has been removed. Reopening does not recover it, and neither does reloading. Only elapsed time does. The message now tells you when the next attempt is allowed and asks for a diagnostic line instead of prescribing a fix nobody has verified.

The underlying reason the first request of the day goes missing is still unknown, and this release does not claim to fix it. What it does is stop the addon making the situation worse and stop it giving confident advice that does not hold.

### Changed

- `VeritasUI_AuctionHouse` — **The 15-minute scan floor now starts on the attempt, not on success.** `SetLastScanTime` is called immediately before `C_AuctionHouse.ReplicateItems()`, matching Auctionator's `FullScan/Mixins/Frame.lua` exactly. Previously both stamp sites sat downstream of data arriving, so a lost request left no cooldown and `SecondsUntilReady()` returned 0 — the addon permitted unlimited back-to-back requests precisely when the server was least willing to answer. The two success-path stamps are deliberately unchanged: they fire later and only push the floor further out, so the success path is bit-for-bit identical and this stamp is load-bearing solely when no data ever arrives. (`Replicate.lua`)
- `VeritasUI_AuctionHouse` — **The lost-request message no longer prescribes a recovery that does not work.** It now reports when the next attempt is allowed, states plainly that reopening the Auction House and `/reload` do not reset it, and asks for the `/ah diag` throttle line. (`Replicate.lua`)

### Removed

- `VeritasUI_AuctionHouse` — **`sessionRequestLost` and its `Start()` refusal.** It marked an AH session unscannable and directed the user to close and reopen, which forced a fresh request per cycle and re-armed the problem by hand. With a real cooldown in place the floor does the refusing, and the refusal now reads "Next scan available in 14:32" instead of an instruction that fails. (`Replicate.lua`)

### Added

- `VeritasUI_AuctionHouse` — **Throttled-message instrumentation in `/ah diag`.** Records any of Blizzard's six `AUCTION_HOUSE_THROTTLED_*` / `AUCTION_HOUSE_BROWSE_FAILURE` events that fire while a scan request is outstanding, with offsets from the fire, on a new `throttle:` line. Always on, never prints on the event, capped at 40 entries with overflow counted, and each name registered under its own `pcall` so a rename reports itself rather than reading as a meaningful silence. (`Replicate.lua`, `Core.lua`)

### Fixed

- `VeritasUI_AuctionHouse` — **Two source comments taught falsified theories as settled fact.** `ArmStallDetector`'s header asserted that re-asking is futile at any duration and that closing and reopening recovers the scan; the first came from a single measurement contradicted twice elsewhere in the record, and the second concluded that waiting was irrelevant from a recovery procedure beginning "wait 60s". Both are now recorded as errors with the evidence against them, so the reasoning is visible rather than the conclusion. (`Replicate.lua`)

### Notes

- **The throttled-message events do not fire for `ReplicateItems`.** Measured on a fully successful scan: 275,455 rows, first data 32.8s after the request, 106,926 pulses, and not one throttled-message event in the entire request-to-data window. The instrumentation above therefore cannot distinguish a dropped request from a refused one, which was its original purpose; it is kept only because the null baseline is now established, so a non-blank line during a failure becomes meaningful where before it was ambiguous. This also corrects an assumption made while investigating: `Throttle.lua`, deleted at v1.12.5's ancestor v1.7.0, governed browse queries and never covered the replicate path, so its removal cost the scan nothing.
- **Root cause of the initial failure remains unknown.** The next step is a side-by-side against Auctionator on the same account and realm at the moment of a failure, which is the only remaining way to establish whether the server is refusing the account or whether something about this addon's request differs.

## [1.12.5] - 2026-07-29

A blocked-action error naming VeritasUI_Lib appeared when learning a pet, and the cause was a single line added the day before.

Yesterday's copy-settings feature opened with a defensive line that created Blizzard's shared dialog table if it happened to be missing. Assigning one of the game's own global variables from an addon is the classic way to contaminate it: from that moment on, every time the game reads that variable it treats whatever it is doing as coming from the addon rather than from itself. The game reaches every one of its confirmation dialogs through exactly that variable.

The visible result was that any dialog which then needed to do something only the game is permitted to do was refused. Learning a caged pet that is still tradeable raises such a dialog, so clicking Accept did nothing except produce the error. Nothing was damaged, but the pet was not learned.

The defensive line was worthless on top of being harmful: the game builds that table unconditionally, long before any addon is allowed to load, so it can never have been missing. Only the three entries the addon adds remain, which is both safe and ordinary — the game looks entries up individually and never walks the table, so the addon's entries cannot affect the game's own.

Two things in the project's own tooling had hidden this. The linter that exists to catch precisely this mistake had been told the table was ours to write, and a second setting was suppressing the warning for any line of this shape anywhere in the suite. That setting had been carrying an explanation of what it did that was simply incorrect. Both are corrected, and reintroducing the mistake is now reported rather than passed over.

**Still outstanding.** A separate error appeared minutes earlier, while mounting after leaving the Auction House, pointing at the game's casting bar and also naming VeritasUI_Lib. That one is not explained, and this release does not claim to fix it. It occurred before the dialog was ever clicked, so it is not a consequence of that click. Contamination does spread from one place to another, so it may share this cause and stop here — or it may not, in which case it is a separate fault and the next occurrence is the evidence needed. Please report either error recurring.

### Fixed

- `VeritasUI_Lib` — **the copy-settings feature no longer assigns Blizzard's global dialog table**, which was contaminating it and causing the game to refuse permitted actions in unrelated confirmation dialogs. Observed in game as a blocked-action error for `EndBoundTradeable()` when learning a still-tradeable caged pet. Only the three dialog entries the addon owns are written now. (`Lib.lua`)

### Changed

- **The linter now reports this mistake instead of allowing it.** Blizzard's dialog table is declared read-only with the addon's own three entries listed individually, so both assigning the table and adding an undeclared fourth entry are flagged. (`.luacheckrc`)
- **Removed a linter setting that was silently suppressing the warning class** for every file in the suite. Its stated purpose was unrelated to what it actually did. Removing it was measured to change nothing else: identical output before and after, because every global the suite defines is already declared by name. (`.luacheckrc`)

### Notes

- The stale warning in the copy-settings header, which told a future reader the control must never be a dropdown, is corrected. It has been a dropdown since v1.12.1, and the rule it was reaching for is narrower: the control must never store its selection.
- Fourteen new checks covering both the code and the tooling, since a safeguard that can be switched off without anyone noticing is not a safeguard. Run against the previous version first, where seven fail — including naming both settings that had disabled the linter.
- Eight existing test suites broke the moment the offending line was removed, because the test harness had never supplied that table itself and had been relying on the addon's own defect to create it. The harness now models the game instead. A test setup that leans on a bug cannot report that bug.
- `ao_removal_test`, written for v1.12.2, was never listed in the test runner and so had never executed once. It is wired in and passing. A test that never runs is worse than no test, because it reads as coverage.

## [1.12.4] - 2026-07-29

Item levels no longer appear on World Quest rewards. A fishing World Quest offering a trinket showed 26 on the reward icon while the tooltip beside it read 151.

Neither number was recoverable from the other. A World Quest reward is scaled by the quest, not by the item, so asking the item what level it is returns a meaningless template value. There is no better source to reach for — which is precisely why quest reward item levels were removed outright back in v1.1.0, the stated reason being that base-versus-actual mismatch made them impossible to display reliably.

That removal worked by naming two specific frames. World Quest rewards live in a different frame entirely, inside the map tooltip, so they matched neither — and the check also gave up immediately on any unnamed element, which those are.

Rather than add a third name to that list, the addon now decides the other way round: it only draws on something it can identify as an actual inventory slot — a bag, bank, warband bank or equipped slot. Anything else gets nothing. A list of names can only exclude the surfaces someone already thought of, which is exactly how this was missed; this excludes everything that isn't a real item slot, including places that don't exist yet.

Bags, bank, warband bank, character panel and vendor windows are unaffected, and there are now automated checks holding each of those in place, since a rule like this fails by being too strict rather than too loose.

### Fixed

- `VeritasUI_QualityOfLife` — **item levels no longer appear on World Quest rewards**, or on any other element that isn't a real inventory slot. The number shown there could never have been right, because those rewards are scaled by the quest rather than by the item. (`QualityOfLife.lua`)

### Changed

- `VeritasUI_QualityOfLife` — **the exclusion is now based on what a button actually is**, rather than on a list of frame names. The old name-based check is kept as a backstop and is marked as such, so it is neither removed as redundant nor mistaken for the real safeguard. (`QualityOfLife.lua`)

### Notes

- Slightly more work is done per item button, since identifying the slot now happens even when the game already supplied enough information to skip it. Around two milliseconds across a full bank opening, once. Caching it would have been faster but adds state for a saving that does not matter.
- Five new checks: two that the bad surfaces get nothing, three that bags, bank and the character panel still do. Run against the previous version first, where the World Quest case fails and the rest pass — so the check is known to detect this specific thing, and the surfaces that already worked are known not to have been broken.

## [1.12.3] - 2026-07-28

A blocked-action warning naming this addon's shared library appeared during ordinary mounted travel, with nothing being interacted with. The recorded detail — the first time that detail has been available, and the reason the recorder was added — named the blocked call as the game's own clear-target function.

This addon does not call that function anywhere. So the game's own code was reached while carrying this addon's taint, rather than this addon calling something it may not. Of every game frame the shared library touches, exactly one has its own code that does targeting: the player's unit frame, which the fading-player-frame feature attaches to. Everything else it touches — bag bar, micro menu, action bars, chat buttons, the options window — has no targeting behaviour at all.

That frame was also the one remaining place in this addon that attached mouse handlers to one of the game's secure frames. The action bar fading deliberately does not do that, and has not since 2026-05, because attaching to a secure frame's mouse handlers makes the game's own code on that frame run tainted — which is exactly the shape of what was observed. The player frame was the inconsistency, on the single most targeting-sensitive frame in the game.

So those two handlers are gone, and hover is detected the same way the action bars already detect it. **This is not a proven fix.** The connection is reasoning from elimination plus a rule this addon already follows everywhere else, on a fault seen exactly once. It is worth doing regardless — it removes an inconsistency and the only plausible route — but it should not be treated as settled until a good while passes without recurrence.

Practical impact of the original warning was nil: the call that was blocked was the game clearing your target, so a target did not clear, once.

### Changed

- `VeritasUI_Lib` — **the fading player frame no longer attaches mouse handlers to the player's unit frame.** Hover is detected by the same polling the action bars use. Behaviour is unchanged: it still appears on hover, in combat, and while your health is not full, and still fades when idle. (`Lib.lua`)

### Added

- `VeritasUI_Lib` — **the blocked-action log now also records what the cursor was over and whether you had a target.** The datum missing this time was which frame's code was running; if this recurs and names a unit frame there, it is close to conclusive. (`Lib.lua`)

### Notes

- The removed handlers were load-bearing, not redundant: the old hover poll only ran while the frame was already visible, and the handler was what woke it. The poll is now always running, at the same rate the action bars use, so hover response is unchanged.
- Two pieces of code left dead by the change — an unused timer handle and a routine that became empty — were removed rather than left as no-ops.
- Six checks cover the player frame's fading, including an explicit assertion that no handlers are attached to it. Run against the previous version first, where that assertion fails and names the two handlers, so the check is known to detect the thing it is about.

## [1.12.2] - 2026-07-28

Advanced Options no longer appears in Options → AddOns. Its entry there was empty, and had been from the start: the code registered a category with no controls in it purely so the module could be found in that list. A blank panel reads as something broken rather than as a way to discover a feature, so it is gone. Every setting the module has is in its own window, opened with `/ao` or from the AddOn button menu, and nothing has moved.

`/ao settings` no longer has anything to open, so it now opens the window instead of doing nothing, and it is no longer listed in `/ao help`.

Five modules still appear in Options → AddOns, so the Copy From… control added in the last two releases is reachable in the same places it was before.

### Removed

- `VeritasUI_AdvancedOptions` — **the empty Options → AddOns entry.** It contained no settings and existed only to be listed. (`Settings.lua`, `Core.lua`)

### Changed

- `VeritasUI_AdvancedOptions` — **`/ao settings` opens the window** rather than an options page that no longer exists, and is dropped from the help text. (`Core.lua`)

### Notes

- The AddOn button menu was already opening the window rather than the options page, so it is unaffected.
- If an entry there is ever wanted again, it should have real content — at minimum a button that opens the window — rather than an empty category. That is written into the file so the stub is not simply reinstated.
- Priority Rotation keeps its entry: sparse, but it holds a working Enable toggle, so it is not blank. Left untouched deliberately — that module carries outsized regression risk and there was no defect to fix.

## [1.12.1] - 2026-07-28

The character list for copying settings now opens in the same place every time, directly beneath the control, instead of appearing wherever you happened to click. The previous version used a right-click style menu, and those anchor to the mouse pointer by design, so clicking the left of the button opened it further left.

Copy From… is now a dropdown rather than a plain button. That is what fixes it: a dropdown's list is attached to the control itself, so its position cannot drift. The same widget is already used elsewhere in this addon, so the placement is guaranteed by how the widget works rather than by a setting that could behave differently on another version of the game.

To be clear about an apparent contradiction: the previous release deliberately avoided a dropdown here. That concern was specifically about a dropdown tied to a *saved* setting, because the game re-applies saved dropdown choices whenever the interface loads — which would have re-copied your main over the destination character on every reload. This dropdown saves nothing; its entries are actions, and the copy is still confirmed before anything is overwritten. There is no saved choice to be re-applied.

If the dropdown widget is ever unavailable, it silently falls back to the previous button and cursor-anchored menu — worse placement, same functionality.

### Fixed

- `VeritasUI_Lib` — **the copy-settings character list opens in a fixed position** under the Copy From… control rather than following the mouse. (`Lib.lua`)

### Changed

- `VeritasUI_Lib` — **Copy From… is a dropdown**, sharing one menu definition with the fallback path so the two cannot drift apart. Its label stays fixed rather than showing the last character clicked, since the entries are actions and not a saved selection. (`Lib.lua`)

### Notes

- The probe of this client's menu system showed each cursor-anchored menu function paired with a non-cursor counterpart, which implies the plain variants attach to the control. That is an inference from a naming pattern rather than something measured, and it is deliberately not what this fix depends on — the dropdown route was chosen because it is already proven in this addon.

## [1.12.0] - 2026-07-28

You can now copy one character's settings onto another, which completes the per-character work started in the previous release. Open the options window on the character you want to change, pick any VeritasUI section, and a **Copy From…** button appears beside the existing Reload UI button. It lists your other characters; choose one, confirm, and that character's settings are applied to the one you are on.

It can be undone. The current settings are saved before anything is overwritten, and an **Undo copy** entry appears in the same menu afterwards, so a copy onto the wrong character costs one click to reverse rather than reconfiguring by hand. The saved state belongs to the character it was taken from, so it will not offer to undo somebody else's copy.

Two things are copied only if the source character actually has them: a module the source has never touched is left alone rather than reset, and any individual setting the source never expressed is filled from the normal default rather than left blank.

Priority Rotation and Auction House are not included. Rotations are stored per specialization as well as per character, so they cannot meaningfully transfer between characters of different classes, and the Auction House holds shared price data rather than per-character preferences.

The trigger is a button rather than a dropdown, deliberately. Blizzard's settings framework re-applies a saved dropdown choice every time the interface loads, which this addon has been bitten by before — a dropdown here would silently re-copy the source character over the destination on every reload and quietly destroy exactly the independence the last release added.

### Added

- `VeritasUI_Lib` — **Copy From… button** in the options window, beside Reload UI and visible on the same terms. Lists your other characters, confirms before overwriting, and offers a reload afterwards, since some settings only take effect after one. (`Lib.lua`)
- `VeritasUI_Lib` — **undo for the last copy.** The destination's settings are captured before being overwritten, and an Undo entry appears in the same menu. Scoped to the character the copy was made on. (`Lib.lua`)
- `VeritasUI_Lib` — **`/vui copy` and `/vui undocopy`** as text equivalents. These exist because the button is positioned by locating a Blizzard button by its label, which has a fallback but is not guaranteed; without them a failure there would leave the feature unreachable. (`Lib.lua`)

### Notes

- Which modules take part is determined by the modules themselves rather than by a list, so a module added to per-character storage in future is included automatically and cannot be forgotten. Priority Rotation and Auction House are excluded by not taking part at all, rather than by being named.
- Settings tables are rewritten in place rather than replaced. Each module and Blizzard's settings framework both hold those tables by reference, so replacing them would leave both reading something nobody writes to — the options window would appear to work while editing a discarded copy.
- Forty-one automated checks cover this: the copy itself, the undo, isolation between characters, that a copy cannot be triggered without confirming, that accepting offers a reload, that the undo entry only appears when there is something to undo and only on the right character, and that the feature degrades to a message rather than an error if the menu system is unavailable.

## [1.11.0] - 2026-07-28

Settings are now per character. Fade Action Bars, Repair Funding and everything else in CleanSolo, Quality of Life, Zone Quests and Advanced Options are stored separately for each character, so a caster and a melee character no longer have to share one configuration, and a character who is not in a guild no longer inherits guild repair settings.

Nothing resets. Each character, on its first login after updating, inherits whatever account-wide configuration was in effect, so the change is invisible until you deliberately set something differently on one character. The old account-wide values are kept rather than deleted, because they are the starting point for any character you have not logged into yet — without that, those characters would silently drop to defaults the next time you played them.

Two modules were left alone on purpose. Priority Rotation has always been per character *and* per specialization through its profile keys, so converting it would change nothing and risk stranding rotations. The Auction House saved file is 3.6 MB of scanned price data — market information rather than a preference — and making that per character would either duplicate it for every character or force each one to run its own full scan.

This is the first half of the work. The second half is a way to copy one character's settings onto another, which is why the storage is account-wide-keyed rather than using the game's per-character files: those are only loaded for the character you are playing, so no character could ever read another's settings and copying would be impossible. That half comes next, once this is confirmed working.

One visible timing change: the four modules' options panels are now created a moment later in the login sequence, at the same point the Auction House module has always created its own. This is required — Blizzard's settings framework holds a direct reference to whichever table it is given, so it has to be handed the character's own settings rather than the shared ones, and the character's identity is not reliably known any earlier.

### Changed

- `VeritasUI_CleanSolo` / `VeritasUI_QualityOfLife` / `VeritasUI_ZoneQuests` / `VeritasUI_AdvancedOptions` — **settings are stored per character.** Each character reads and writes its own set; changing one no longer changes the others. (`CleanSolo.lua`, `QualityOfLife.lua`, `ZoneQuests.lua`, `Core.lua`)
- `VeritasUI_Lib` — **new shared storage helper** used by all four, so they cannot drift apart in how they resolve, migrate or seed a character's settings. (`Lib.lua`)

### Notes

- `VeritasUI_PriorityRotation` and `VeritasUI_AuctionHouse` are deliberately unchanged, for the reasons above.
- The three modules that use Blizzard's settings framework now register their panels after the character's settings exist, and hand it those settings. Registering earlier, against the shared table, would have let every checkbox write to the shared copy — the feature would have appeared to work while doing nothing. All twenty-three registrations across those modules are checked automatically for this.
- Verified by eighteen checks on the storage itself and eleven driving the real modules through a login, covering inheritance on first login, independence between characters, repeated binding, and that a character's changes never leak into another's or into the built-in defaults.

## [1.10.1] - 2026-07-28

Fading action bars no longer vanish while you are using a flyout. Buttons that open a set of sub-abilities — Pet Utility, mage teleports, profession tools, warlock demons — put those sub-abilities in a panel that opens above the bar. Moving the cursor off the button and into that panel counted as leaving the bar entirely, so the bar faded a fraction of a second later and took the sub-abilities with it, leaving a tooltip floating over nothing.

The visibility check only ever looked at the bar itself and the buttons directly on it. It now also recognises anything belonging to the bar however deeply nested, and separately recognises an open flyout by name. Both are included on purpose rather than picking one: which of them applies depends on how the game attaches a flyout to the button that opened it, and that was not established before shipping, so neither is depended on alone. If both somehow miss, a new command reports the actual structure under the cursor so the gap can be closed by measurement instead of another guess.

The extra checks only run while a bar is already visible. A flyout cannot be opened without first hovering the bar, so on the idle path — which is most of the time — the cost is unchanged.

### Fixed

- `VeritasUI_Lib` / `VeritasUI_CleanSolo` — **a fading action bar stays visible while the cursor is inside one of its flyouts.** Previously the bar faded mid-interaction because the flyout is not one of the bar's own buttons, hiding the sub-abilities the player was reaching for. Applies to every fading bar and to every kind of flyout. (`Lib.lua`)

### Added

- `VeritasUI_Lib` — **`/vui hover`** reports the element under the cursor and its full chain of parents, plus whether a flyout is currently open. Sampling is delayed five seconds, because running a command necessarily puts the cursor in the chat box; move onto the element and hold still. Added so that "the bar still faded on this thing" is one measurement rather than a guessing exercise. (`Lib.lua`)

### Notes

- Two internal flags had to be declared earlier in the file than before, because the visibility check now reads one of them. A local declared after a function that references it is silently treated as a missing global, which is the same trap that broke the waypoint command once before; it is called out in place so it is not undone.
- Eight automated checks cover this, including the case where the flyout is attached to the button and the case where it is not, and a check that the idle path still does not consult the cursor. They were run against the previous release first, where the three flyout checks fail with the bar fully faded — the reported behaviour — while the unrelated fade-in and fade-out checks pass on both, so the change is known not to trade one fault for another.

## [1.10.0] - 2026-07-28

The AFK screen is no longer all-or-nothing. Open your character sheet, your bags, the map, the Escape menu or anything else and it appears over the AFK screen; close it and the screen is clean again. Press Enter and the chat window comes up with the typing box so you can read and answer; send the message, or press Escape, and both disappear.

Nothing new is captured from the keyboard, and that is the point. The AFK screen hides the interface by making it transparent rather than by closing it, so every panel was already opening and closing correctly the whole time — pressing C really did open the character sheet, it was simply invisible. This release makes what you open visible, using the same mechanism the AFK screen already uses to keep itself visible over everything else. An earlier version of this feature did capture keystrokes and was removed a while back for breaking movement when a mob attacked you; none of that comes back here, because the screen only watches which windows are open and never touches input.

The chat window is deliberately tied to the typing box rather than to itself. Chat windows are always technically open, so following their own state would have left the conversation on screen for the entire AFK session. Following the typing box instead means the conversation appears exactly when you start typing and leaves when you stop, which is what was asked for.

Windows are found by asking the game for its own list of registered panels, so every standard window is covered without maintaining a list, including this addon's own Priority Rotation and Advanced Options windows. Bags, the chat box and the Escape menu are named explicitly because they are not on that list.

One thing to watch on first use: opening windows does not clear your away status, but *sending* a chat message may well do, and if it does the AFK screen will dismiss itself the moment you send, because it follows your real away status. Reading and typing without sending should be unaffected. That is a guess about the game's behaviour rather than something measured, so treat the first message you send as the test.

### Added

- `VeritasUI_QualityOfLife` — **windows you open during the AFK screen are now visible.** Character sheet, bags, map, Escape menu, collections, spellbook and everything else registered as a panel, plus this addon's own windows. Opening reveals, closing hides, with no new setting — if you open nothing the screen looks exactly as it did. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **press Enter during the AFK screen to read and reply to chat.** The chat window and the typing box appear together and both disappear when the typing box closes, whether you send the message or cancel it. (`QualityOfLife.lua`)

### Notes

- No keyboard capture was added. The panels were always functional under the AFK screen because it hides the interface with transparency rather than by closing anything; this only changes what is drawn. The removed keyboard-capture approach stays removed.
- Open windows are detected by polling while the AFK screen is up, roughly five times a second, rather than by hooking each window. Hooking would need separate handling for panels, bags, chat and the Escape menu and would still miss anything new. The poll runs only while the screen is up and only acts when something actually changes.
- While a window is open the AFK screen drops behind it, and returns to the front when the last one closes. Lowering the screen is deliberate rather than raising the window: window layering is owned by the game's panel manager, and fighting it causes drift and flicker. Nothing is lost by the screen sitting behind the rest of the interface, because the rest of the interface is transparent.
- Leaving the AFK screen reverts every visibility override, in that order. An override left behind would make that window ignore transparency for the rest of the session, which would break the next AFK screen and CleanSolo's fading.
- Covered by nineteen automated checks driving the real file. One of them initially failed on the layering behaviour; the code turned out to be correct and the test harness was at fault — it made every unset internal flag read as set, which defeated exactly the kind of guard being tested. Fixed in the harness, and worth knowing because it would have silently weakened other checks too.

## [1.9.17] - 2026-07-28

Item levels shown on icons now match the tooltip on scaling gear. A Timewalking crossbow whose tooltip read 78 was showing 522 on its icon; three items in the same bag were similarly inflated. The cause was the API the overlay has always used, `GetDetailedItemLevelInfo`, which on a level-scaling item returns the scaling **ceiling** rather than the item's level as it stands. `GetItemInfo`'s item level field returns the same number the tooltip does, so that is now the source.

This was changed on measurement, not on reasoning. Both candidate sources were dumped side by side for two items: the scaling crossbow, where the old source returned 522 against a tooltip of 78, and — the case that actually mattered — an upgrade-track epic on a max-level character with a base level of 44 and an effective level of 276. The specific risk of this change was that the new source would report base levels and quietly wreck every upgraded piece on a geared character. It reads 276 there, matching both the tooltip and the old source, so it is upgrade-aware and that risk is disproven. The old source is only wrong in the scaling case.

Reading the tooltip's own data was also measured and rejected. It returns the correct answer, but costs between 11 and 22 ms across a full bank depending on the item — more than a whole frame at 60 fps — and would require parsing translated text. There is no reason to pay that for a number a plain numeric call already gets right.

This is very likely the same problem that removed quest reward item levels back in v1.1.0, whose stated reason was a base-versus-effective item level mismatch. Restoring them is now plausible, but is not attempted here and would need its own testing.

Unrelated and still unverified: the bank and warband bank fixes shipped in v1.9.16 have not yet been confirmed in game. A screenshot taken as confirmation turned out to show backpack bags, a surface that never had the problem, and that reading was withdrawn.

### Fixed

- `VeritasUI_QualityOfLife` — **item levels on the icon now match the tooltip for level-scaling gear** such as Timewalking rewards, heirlooms and other scaled loot. The overlay read the scaling ceiling instead of the item's current level, so a crossbow whose tooltip said 78 displayed 522. It now reads the same field the tooltip does. Verified against an upgrade-track epic as well, where the previous source was already correct, so geared characters are unaffected. (`QualityOfLife.lua`)

### Changed

- `VeritasUI_QualityOfLife` — **`/qol ilvl` is now a permanent diagnostic** rather than a temporary one. It was added to decide this fix and has done so, but "this number looks wrong" recurs in this feature by nature — the correct source is only knowable by comparing against the tooltip — and the suite already keeps equivalent permanent probes for the Auction House. It reads state and changes nothing. Its labels now point at the source actually in use. (`QualityOfLife.lua`)

### Notes

- Deliberately not done: `GetDetailedItemLevelInfo` was **not** kept as a fallback for when the new source returns nothing. Nothing returned means the item's record is not cached yet, which the existing retry already handles, whereas a fallback would put the wrong number back on precisely the items this fixes. The reasoning and the measured values are recorded in the code and in the project's probe reference.
- Two regression tests were added for this, and checked against both previous releases first, where they reproduce the reported value exactly. A second test covers the upgraded case that was already working, so the change is known not to trade one fault for another.

## [1.9.16] - 2026-07-28

Four item-level display faults turned out to be one defect. Numbers appearing over empty bank slots, numbers rendering white instead of the item's rarity colour, item levels on grey junk that was supposed to be excluded, and — separately — a meaningless `1` on cosmetic gear at vendors. The first three all trace to the cold-cache retry added in v1.8.0 to make bank overlays appear on the first open of a session, which predates the recent audit and matches where this was first noticed.

That retry waits for an item's record to load and then paints the overlay. It guarded against the button being reused in the meantime with a token, but the token was only cleared deep inside the paint routine, and the three early exits above it — no item, grey item, quest-reward button — all returned before reaching it. So a bank button that had been emptied or reassigned kept its retry armed, and when the record finally arrived it stamped an item level onto a slot that was now empty. The cancel now lives in the one routine every one of those exits already calls, which retires the whole class rather than the three known instances, and the retry additionally re-checks what the button is holding before it paints, because whether the game always notifies us about a slot it empties is not something that could be established by reading the code.

The white numbers and the junk numbers were the same retry replaying a *quality* of nil. On a cold cache the game passes no quality, and nil silently defeated both consumers: the grey-item filter is written as "not nil and equal to zero", so nil skipped it entirely, and the colour lookup falls back to Common — which is white. Quality is no longer captured and replayed; it is re-read from the item at paint time, by which point the record is loaded by definition. The existing grey filter then starts working for the first time on that path.

The cosmetic `1` is unrelated and simpler: cosmetic gear genuinely has an item level of 1, and the filter only rejects zero and below. Deliberately not fixed by raising that cutoff — a real low-level character's gear legitimately sits in single digits, so a threshold would have hidden numbers that are correct. It now tests whether the item is cosmetic.

Vendor item levels are unchanged and stay. A recollection that they had been removed turned out to be crossed wires: it was *quest reward* item levels that were removed, back in v1.1.0, and the stated reason was a base-versus-effective item level mismatch — which is exactly the remaining open symptom below.

Still open, deliberately: item levels that disagree with the tooltip in scaled content, such as a Timewalking item whose tooltip reads 120 while the icon reads 78. A plausible cause was identified and then **falsified by testing** — the theory that the retry path loses the item link and falls back to a base-only value does not reproduce, because the button resolves its own link successfully. Rather than ship a second guess, this release adds a diagnostic that measures where the number comes from. The two are different questions: the API in use reports what an item's level *is*, while the tooltip reports what it is *for you, right now*, and those coincide for ordinary current-content gear, which is why those numbers have always looked right.

### Fixed

- `VeritasUI_QualityOfLife` — **item levels no longer appear over empty bank and warband bank slots.** The cold-cache retry's reuse token was only cleared inside the paint routine, which the three early exits above it never reach; it is now cleared in the shared hide routine that all of them call, so a stale retry is unreachable from every path at once instead of from three patched ones. The retry also verifies the button still holds the same item before painting, and distinguishes "this slot is now empty" from "I cannot identify this button", so merchant buttons — whose link is supplied rather than derived — keep working. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **item levels render in the item's rarity colour instead of white.** The retry captured the quality argument and replayed it, but the game supplies no quality while an item's record is cold, and the colour lookup treats a missing quality as Common, which is white. Quality is now re-read from the item when the overlay is painted. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **grey junk no longer shows an item level.** It was always meant to be excluded, but the filter reads "quality is not nil and quality is zero", so the nil quality described above skipped it silently. Re-reading quality makes the existing filter effective on that path. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **cosmetic items no longer show an item level of `1`** at vendors or anywhere else. Cosmetic gear has a genuine item level of 1, which passed a filter that only rejects zero and below. Fixed with a cosmetic test rather than a higher cutoff, so a genuine low-level character's single-digit gear still shows. Conservative: only a definite yes hides the number, so a missing API or an unloaded record shows the item rather than hiding a legitimate one. (`QualityOfLife.lua`)

### Added

- `VeritasUI_QualityOfLife` — **`/qol ilvl`, then shift-click an item** — a diagnostic that reports every available item-level source for that item side by side: the value in use, the base-only value, the value the tooltip itself reports, the cosmetic flag, quality, class and subclass, and the cost of the tooltip lookup projected across a full bank. Added to settle the scaled-content mismatch by measurement instead of argument, after the leading theory was falsified by testing. Temporary, and will be removed once that decision is made. (`QualityOfLife.lua`)

### Notes

- The button link resolver used by the item-level hook was extracted so the retry can reuse it. Its fall-through order is preserved exactly: each accessor is tried only while no link has been found, because returning on the first merely-callable accessor would quietly downgrade some buttons to a bare item ID and with it to a base-only item level. That regression was introduced during this change and caught before release.
- All four fixes are covered by a regression suite that drives the real file headlessly against a simulated cold cache. It was checked against the previous version first, where it reproduces all four reported symptoms including the exact values seen in game, so the tests are known to test something.

## [1.9.15] - 2026-07-28

A blocked-action popup naming `VeritasUI_AuctionHouse` appeared while sending a housing decor item to the vault, nowhere near an auction house. The cause is not known and is not fixed here. What is fixed is that the addon was in no position to ever find out: the one datum that would identify the offending call — the function name — is handed to us exactly once, in an event that vanishes with the session, and nothing was listening. The popup was dismissed, a reload cleared it, and the evidence went with it.

So this release adds a recorder rather than a fix. It listens for both blocked-action events, writes what it learns to disk, and keeps it across reloads and logouts, so a popup dismissed days ago can still be read back with `/vui taint`. This is the same lesson the Auction House scan trace already taught: a failure that depends on session history and appears on one machine and not another cannot be summoned on demand, so it has to already be recorded when it happens. Diagnosis of the popup itself is deliberately left open — two candidate sources inside the Auction House module remain, they cannot be separated by reading the code, and the attempt to separate them by repro was abandoned as a poor use of playtime, since a negative result under different session conditions proves nothing.

Two Priority Rotation reports were investigated in the same session and closed with no code change, because both are the intended design working as specified: rotation entries built from macros deliberately get neither the Combat checkbox nor an injected `[nochanneling]`, since a macro body carries its own conditionals and rewriting it would be a correctness violation. The reported pattern of the symptoms appearing on alts rather than the main character is a macro-built profile versus a spell-built profile, not a per-character fault — confirmed against the saved profiles, where one specialization is built from spells and gets both features, and another is built from macros and gets neither.

### Added

- `VeritasUI_Lib` — **a blocked-action recorder, always on.** Listens for `ADDON_ACTION_FORBIDDEN` and `ADDON_ACTION_BLOCKED` and records the addon name, the function name, an occurrence count, first and last sighting, and a one-time context snapshot: character, zone, combat state, and whether the Auction House UI had been loaded. Read it with `/vui taint`; reset it with `/vui taint clear`. It lives in the library rather than in any one module because the popup names whichever module tainted the path, and a recorder inside the Auction House would miss one that named a different module. It is deliberately not gated behind the debug flag, for the reason above: the flag would be off exactly when it mattered. (`Lib.lua`)
- `VeritasUI_Lib` — **the log survives reloads and logouts**, via a new `VeritasUI_LibDB` saved variable — the library's first. A popup answered with "Ignore" is still readable afterwards, and a one-line notice at login reports anything recorded so it cannot sit unread indefinitely. (`Lib.lua`, `VeritasUI_Lib.toc`)
- `VeritasUI_Lib` — **`/vui` as a short alias for `/veritasui`**, matching the short-alias convention every other module already follows, and the bare command now lists its subcommands instead of only printing the version. (`Lib.lua`)

### Notes

- The recorder never prints on the event, only on request. `ADDON_ACTION_BLOCKED` can fire hundreds of times on a single zone entry, so printing would bury the user in the symptom; entries are instead deduplicated on event, addon and function, which turns a flood into a counter increment rather than table growth, and timestamps are stored as integers and formatted only when dumped so no date formatting runs on that path.
- The log caps at 25 distinct signatures, and a forbidden-action event arriving at a full log evicts the least-seen blocked-action entry rather than being discarded. A plain first-come cap would have let routine blocked-action noise fill the log and drop the rare event the recorder exists to capture — found by testing the recorder against a simulated flood, not by reading it.
- Deliberately not done: no `IsForbidden` guards were added. The suite has none, which is a real gap worth closing on its own merits, but it is very unlikely to be this defect — the tooltip handler already returns early on anything that is not the shared game or item-reference tooltip, so it is not calling methods on forbidden frames, and if Blizzard's own code is running tainted then such guards would change nothing. Shipping them here would have implied a fix that has not been demonstrated.

## [1.9.14] - 2026-07-25

A hung Auction House scan used to cost minutes or hours; it now costs about seventy seconds. The addon no longer retries a lost scan request, because retrying cannot work: a hung scan was left re-firing every sixty seconds for four hours on the owner's Windows client and not one of those requests was ever answered. Once a request goes missing, that Auction House session is spent, and the only thing that recovers it is closing the window and reopening it — immediately, with no waiting, which also rules out any time-based server cooldown. The old persistent retry was therefore pure cost: it produced activity that looked like progress, and every one of its notices was hidden behind the debug flag, so in normal play the addon simply went silent for minutes. That is what drove four-hundred-second waits, repeated close/reopen cycles and full reloads.

So the sixty-second timer stays, but it now detects rather than retries. On silence it says so in plain sight, debug or not, and names the one recovery that works. The session is marked spent, so pressing Scan again without reopening refuses instantly instead of burning another silent minute. Deliberately not done: the scan is *not* aborted — `scanning` stays set and the event handler stays live, so a late snapshot is still processed, honouring the module's standing no-timeout rule. Also deliberately not done: failed attempts are still *not* recorded against the fifteen-minute scan floor. Recording them was in the original plan and would have been actively harmful, because it would have blocked the immediate reopen-and-rescan that is the actual fix.

The underlying cause — why the first request of a session goes missing at all, on one machine and not the other — is still unknown and is not addressed here. Five hypotheses were raised and falsified in the course of diagnosis (server-side drop with timed recovery, auction-house subsystem readiness, teardown-versus-time, a self-resetting server cooldown, and a competing addon). What is now measured: [FIRE STATE] is byte-identical between a failing fire and the succeeding one, ordinary search/buy/sell work perfectly during a hang, and event pulses are zero, so the snapshot is never begun and no client-side signal distinguishes a doomed request from a good one. The v1.9.5 rationale claiming a re-fire once succeeded twelve minutes in could not be reproduced and is no longer trusted.

### Changed

- The Auction House scan no longer re-fires a lost request. `ArmRetry` (persistent, unbounded, sixty-second re-fire chain, v1.9.5) is replaced by `ArmStallDetector`, which fires once, does not re-request, and does not abort the scan.
- The lost-request notice is no longer debug-gated. It is always visible and states the recovery: close the Auction House and reopen it, then press Scan again.
- `AH.Replicate.Start()` refuses a fire in an Auction House session where a request was already lost, returning the reopen instruction immediately instead of issuing a request that cannot be answered.

### Fixed

- A hung scan left to retry no longer wastes unbounded time. The four-hour measurement of 2026-07-24 established that in-session re-firing never succeeds at any duration.
- The addon no longer appears frozen during a hung scan. Previously the only indication anything was happening was a debug-gated message, so a normal user saw "Full scan started…" followed by silence.

### Documentation

- `ArmStallDetector` carries the full evidence that retired the retry chain: the four-hour test, the immediate-reopen recovery, the identical fire-state captures across three dates, and the healthy first-event latency now confirmed at 26.0s on 2026-07-24.
- The scan-floor reasoning records why a failed attempt must *not* be timestamped, so a future reader does not "fix" the asymmetry and reintroduce the lockout.

## [1.9.13] - 2026-07-25

Phase 5 of the fourth code audit, and the last one — the leftovers, which turned out to be clusters rather than individual defects. Four of them: the suite was split down the middle on whether to guard saved-variable access, on whether to localize hot globals, on whether help text goes through the module's own print, and on whether a constant lives in one place or two. Each was settled as a single convention with a stated boundary rather than by converting every site that looked odd — module tables the load order guarantees are now explicitly *not* guarded and say why, saved-variable state is guarded at every consumer, diagnostic paths are hardened generously, hot-path globals are localized while cold ones are left alone, user-facing help is tagged while multi-line diagnostic dumps deliberately stay untagged for copy-paste. Roughly a third of the findings here resolved to no code change at all, which is the point: an apparent inconsistency that is actually a deliberate trade is worse than a real one, because the next reader will "fix" it. Those are now written down in the files.

One process failure is worth recording. A guard finding turned out to be listed inside a cluster but absent from all five phase plans, so every filed finding identifier was mechanically reconciled against the plan: of 78, fourteen were missing, seven of them genuinely unhandled and unmentioned anywhere. All seven are fixed or resolved in this release; without that check they would have shipped unfixed at the end of the cycle. The reconciliation belongs at the point the phase plan is written, not at the end of it.

The cross-cutting result of the whole cycle held for a fifth consecutive phase: every absolute line number cited by this phase's own findings had drifted before the phase could act on them — one flagship citation has now been empirically wrong four times, and one moved because of an edit made earlier in this same phase. The luacheck warning set is unchanged from the previous version, with a single honest exception: one long line in the rotation module got five characters shorter, same line and same rule, because of the very first fix below.

### Fixed
- `VeritasUI_PriorityRotation` — **`/pr clear` and `/pr reset` could error instead of running.** Both reach the file's only two unguarded saved-variable consumers, while the enabled check, the sequence compiler and `/pr settings` all guard the same startup window — and the last even prints a friendly "still loading" for it. The window is real, if short, because slash commands are registered at file scope. Guarded at the one choke point rather than at the 25 call sites that read a profile, and the profile getter keeps its "always returns something usable" contract by handing back a throwaway default, since returning nothing would turn one clean error into many. This is the finding that was listed in a cluster but missing from every phase plan. (`Profiles.lua`)
- `VeritasUI_AuctionHouse` — **`/ah check` would error on its own price lines if the money-formatting module had failed to load**, while `/ah diag` eight lines above it guards that module before using it. `/ah check` is one of the commands you run when something is *already* broken, so it is exactly the code that must not add a second error. Both price lines now route through one guarded accessor that falls back to raw copper. Hardened rather than simplified — the opposite of the tooltip decision below — because the load order here genuinely does not guarantee the module is present. Folding the missing case into the existing "never recorded" message was rejected: it would report a missing module as a missing price. Two further rows of the same finding were checked and dropped as already correct. (`Core.lua`)
- `VeritasUI_AuctionHouse` — **the sell strip kept scheduling work for minutes after you closed the Auction House.** It was the only Auction House interface file with no close subscription, so the set of items whose data had not yet arrived outlived the session and the permanently-registered item-data handler kept arming tenth-of-a-second timers during ordinary play, each resolving to a refresh that does nothing but return. The missing teardown now cancels the pending timer and drops that set, which the next session rebuilds from your bags anyway. The event registration itself was deliberately left in place, and the file now says why: the v1.7.15 behaviour of warming prices while the strip is hidden depends on that event arriving while hidden, and unregistering it would bring back the on-screen reshuffle that change removed. Self-limiting rather than an unbounded leak, since the event stops firing once each item's data is cached. (`UI/SellStrip.lua`)
- `VeritasUI_AuctionHouse` — **hiding an item from the sell strip with shift-right-click could error on a missing database**, the one saved-variable access in that file without a guard; the three read paths and the wipe path all have one. Not reachable today, since the handler needs a built strip, but saved-variable state is precisely the category where a guard can legitimately fire. (`UI/SellStrip.lua`)
- `VeritasUI_ZoneQuests` — **saving and restoring your tracked-quest list could error on a missing database.** They were the module's only two unguarded consumers while the always-tracked check, the sync pass, the event handler and all three slash paths return cleanly. Unreachable only because the database is assigned on the line before the settings callbacks are registered — an invariant invisible at the two write sites. The manual-watch table inside it was checked and needs no guard of its own. (`ZoneQuests.lua`)
- `VeritasUI_PriorityRotation` — **`/pr scan` told you to do something that cannot work** when the generated macro sits on action bar pages 2 and up, or on a stance or stealth bar. Those slots are deliberately unmapped, so the scan finds the macro but has no binding to override and lands in the same state as an unbound main-bar slot — printing "assign a key to that bar slot, then `/pr scan`". Assigning a key cannot help, so you can loop on that advice indefinitely. It now names the real problem and tells you to move the macro to a main bar. Reachable in normal play: druid form bars and the rogue stealth bar are ordinary places to keep a macro. (`Core.lua`)
- `VeritasUI_AuctionHouse` — **the price tooltip could commit an "Auction:" heading with no price under it.** Two of the coin renderer's three exits returned "I drew it" *after* adding the label row but before drawing any coins, which suppressed the caller's plain-text fallback that exists for exactly that case. Fixed by hoisting the lookup that can fail above the label, so that exit can honestly report failure with the tooltip untouched. The other early exit still reports success on purpose and now says why — the label is already committed, so reporting failure there would add a *second* "Auction:" line. Latent rather than live, since both tooltips this handler accepts satisfy the lookup; nothing changes on screen, the contract is simply no longer inverted. (`Tooltip.lua`)
- `VeritasUI_ZoneQuests` — **`/zq debug` was lying about the behaviour it exists to explain.** Rather than reporting the tracker's verdict it recomputed each quest's disposition, and that second copy had drifted three ways at once: no super-tracked case, so a quest kept solely because you were super-tracking it printed as dropped while it was in fact tracked; zone tested before pin, inverting the precedence the real code labels by, so a campaign quest in your current zone was called one thing here and the other by `/zq synctest`; and it built a fresh quest set, bypassing the cache the live tracker reads. The loop is gone and the command now points at `/zq synctest`, which already prints per-quest additions and removals with the reason tag taken from the real code, keeping only the environment block `/zq debug` uniquely provides. The missing super-tracked case was deliberately *not* added — that would have kept the second copy alive and guaranteed the next drift — and the sync pass was deliberately not given a report-only mode, which would touch the module's hottest function for a diagnostic's benefit. (`ZoneQuests.lua`)
- `VeritasUI_PriorityRotation`, `VeritasUI_AdvancedOptions` — **`/pr help` and `/ao help` printed untagged lines and neither listed itself.** In both modules the header went through the module's tagged print while the command list used bare prints, so the one block a new user reads was the one block that did not say which addon it came from; and both printed inventories were one command short of what their dispatchers actually handle. Both are now fully tagged and one-for-one with their dispatchers, the same invariant established for `/ah` earlier in this cycle. The rotation module's omission was not in the audit at all — it was noticed while fixing the options module's identical one. A further line was added to `/pr help` pointing at the suite-wide debug toggle, because the two operations the rotation module defers through the shared combat queue swallow their errors unless that separate flag is set, so `/pr debug` alone leaves "my rotation didn't recompile after combat" undiagnosable. Deliberately did not make `/pr debug` set the suite-wide flag: that would switch on every other module's output as a side effect and could silently clear a flag you had set elsewhere. (`PriorityRotation/Core.lua`, `AdvancedOptions/Core.lua`)
- `VeritasUI_AdvancedOptions` — **two settings accessors could report a stored `false` as unset.** A defect of this exact shape was fixed in v1.9.1, and it left four siblings in the same file that all read like the same bug. Each was resolved on its own evidence instead of being converted as a batch. The collapsed-category check was genuinely at risk — it is the one accessor whose stored value can really be `false` — and was correct only by the coincidence that the swallowed value equalled its fallback. The default-value reader was converted because its two immediate siblings already use the explicit form, making the file's own majority unanimous. The other two are kept as they are, with their reasons now written down: nothing anywhere writes a boolean to the value cache, and the favourite check's normalisation to `false` is deliberate because its one caller uses it purely as a yes/no. No visible behaviour changes. Absent from every phase plan. (`Core.lua`)
- `VeritasUI_PriorityRotation` — **the function that names every saved profile still used the pattern that was removed from its neighbour 36 lines below for being silently wrong.** v1.6.25 replaced it there precisely because the specialization API returns many values and the short form mishandles them; here it is correct only because a pair of parentheses truncates the call. So the file held both the condemned pattern and its replacement, and anyone tidying away those parentheses would reintroduce a fixed bug in the string that identifies every profile — stranding all of them. Converted to the explicit form with the history recorded in place. No behaviour change today; this removes the trap. Absent from every phase plan. (`Profiles.lua`)

### Changed
- Suite-wide — **five files now spell each operation one way.** Four modules declare a "localize hot globals" convention at the top and then break it: the rotation diagnostics called string joining through the global while five sibling sites used the local; the waypoint command spelled string formatting three different ways in one file, including a second alias for an upvalue already in scope; the scan progress bar read the clock as a bare global on its only per-frame path, which since v1.9.5 can legitimately run for twelve minutes and therefore tens of thousands of consecutive frames; and the replicate module had one formatting holdout against eight conforming sites plus a profiling call never localized at all despite eleven uses, three inside the per-row loops that cross a ~270,000-row snapshot. None of this is claimed as a speedup — each row already makes two or three API calls and the loop is time-capped, so the lookup is below measurement noise. The cold globals were deliberately left alone: a timer called once per scan and two one-off conversions stay as they are, because the convention is for hot paths, not for tidiness. (`PriorityRotation/Core.lua`, `QualityOfLife.lua`, `UI/ScanProgress.lua`, `Replicate.lua`)
- `VeritasUI_PriorityRotation` — **the Create / Update Macro button and `/pr macro` were two copies of one combat guard and one success message, and they had already drifted apart** — the button said the macro is "ready — drag it from `/macro` to an action bar" while the command said "ready in `/macro`". The button directly below it delegates to the slash command and inherits its guard and messaging for free, so one settings row used both strategies for the same job and the duplicated one was the one that rotted. The macro button now delegates the same way, nine lines lighter. The better of the two messages won and was promoted into `/pr macro`, so the wording improves for both entry points rather than one being silently dropped. (`Settings.lua`, `Core.lua`)
- `VeritasUI_AdvancedOptions` — **the CVar Browser's three column widths were written twice each**, once for the header labels and once for the row text, so the alignment its own header comment calls load-bearing rested on six literals nobody was keeping in sync — edit one set and the labels quietly stop sitting above their data. Collapsed to three named constants consumed at all six sites, which is the pattern this file already follows for its row height and scrollbar inset, and the same collapse v1.6.26 performed on the control heights. The shared four-pixel inter-column gap and the star anchor were deliberately left alone as a different value and outside this finding. The values agreed before the change, so the tab should look identical. (`Browser.lua`)
- `VeritasUI_AdvancedOptions` — **a row-height fallback was a second source of truth for the height v1.6.26 centralised**, so changing the shared value would have left the table and this literal silently disagreeing. The fallback now reads that table. It was kept rather than removed to fail loudly, because it runs as a scroll-list measurement callback where arithmetic on a missing value would blank the entire Featured tab instead of failing anywhere a reader would look. Correction to the finding as filed: it listed two such sites, but Phase 3's frame cleanup had already deleted one. (`Featured.lua`)
- `VeritasUI_AuctionHouse` — **the price tooltip's defensiveness ran backwards.** The primary coin path called the money module unguarded while both plain-text fallbacks guarded it, so a reader could not tell which way the dependency actually goes. The load order puts that module first, both files bail identically when the library is missing, and every call site runs at hover time, so neither guard could ever fire. Simplified rather than hardened — a guard encoding a non-existent risk teaches the next reader that the dependency is optional — and the load-order guarantee is now stated in the file so the guards are not re-added. The separate fallbacks for the formatter returning nothing were deliberately kept: that risk is real. (`Tooltip.lua`)
- `VeritasUI_PriorityRotation` — the rotation editor's icon button was the one handler in the file that argued with its own neighbours, re-entering the profile lookup to reach the same list three times in consecutive lines while the row's own right-click three lines above and three other buttons all take a local first. Hoisted, with a note on why one local stays correct across a list removal. Filed and fixed as consistency, not cost — four API calls per click on an icon would have been dropped on footprint grounds. (`Editor.lua`)

### Documentation
- `VeritasUI_ZoneQuests` — **the module was split exactly down the middle on its own output convention**, 18 bare prints against 18 tagged ones, which reads as drift with no way for a reader to tell. It is not drift: all 17 candidates are multi-line diagnostic dumps behind `synctest`, `dumpquest` and `debug`, with their own inline colouring, where a per-line module tag would be noise in output meant to be copy-pasted. Recorded as policy instead of converted, so the split is now deliberate rather than accidental. No print call was changed, and the header print that fires before the library exists is named as permanently exempt — in this module and in the options module, where the same line exists. (`ZoneQuests.lua`)
- `VeritasUI_ZoneQuests` — **this is the one module with no hot-global block, which reads as the outlier a future editor would "correct"** by adding thirty lines of aliases to match the other five — and this release's localization work above makes that reading more likely, not less. The trade is now recorded in the file: those blocks exist for genuinely hot paths, an auction row loop crossing hundreds of thousands of rows and a progress bar running every frame, while this module's heaviest loop is debounced and walks 25 to 50 quest log entries. No code change. The sweep that produced the note found no orphaned aliases and no forward references anywhere in the suite — the ninth consecutive clean sweep for the bug class that caused two real crashes in this project's history. This finding existed only as a forward reference from a heading, with no entry of its own and no place in any phase plan. (`ZoneQuests.lua`)
- `VeritasUI_AuctionHouse` — **the gear test that decides how an item is priced exists twice in one file, byte-identical, with nothing marking the two as a pair** — and the functions holding them do opposite things with the answer: one appends the item level to the key, the other refuses gear so the caller defers the row. Loosening one without the other lets gear through the cold path under the item-level-agnostic key the pricing rules forbid by name, after a rare piece was once priced at roughly 500g against a 10,000g market — and it would fail silently, with prices merely averaged across variants. Both sites now cross-reference each other by name and state that they must agree, and returning nothing for gear is recorded as by design. Deliberately did *not* extract a shared helper: both sites sit in the per-row path that runs hundreds of thousands of times per scan, and more to the point extraction addresses the duplication that does not matter while leaving the opposite-polarity handling just as easy to break. Comment-only; scan counts unchanged. (`Database.lua`)
- `VeritasUI_AuctionHouse` — **the scan bar's terminal-message handler lacks the guard its two neighbours carry, and that is correct.** Those two say the guard exists so a stray event cannot resurrect the bar after a close — which reads as an invitation to add a third and, in doing so, suppress the one message that must land precisely *because* the scan has just stopped. Resolved with no code change and the reasoning written down instead, after settling both cross-file questions the finding was filed to answer: the close handler aborts by clearing the scan coroutine and hiding its driver and emits no terminal event, so completion and failure cannot arrive after a close; and reopening within the bar's hold window is separately unreachable, because closing hides the frame and cancels the hide timer while reopening only rebuilds. The one live path in the second question — a stuck-flag guard dropping the scanning flag when the close event was never delivered, leaving the ticker's per-frame handler returning immediately for the rest of the session — was left alone: self-hiding there saves one empty call per frame in a rare case and costs the ticker the self-arming property it depends on. Absent from every phase plan. (`UI/ScanProgress.lua`)
- `VeritasUI_AuctionHouse` — the Scan button's label poll understated its own rate by half, claiming one update per second where the accumulator gates at two, and that parenthetical "cheap" is the justification a future reader would rely on when deciding whether the poll is acceptable. The comment was corrected, not the interval, which is the rate the label needs to track a scan's state changes. Absent from every phase plan despite being the same comment-accuracy class Phase 4 shipped. (`UI/ScanButton.lua`)
- Suite-wide — **the only two hardcoded-English sites are now marked won't-fix in place**, so a future audit reads a decision instead of rediscovering them as two separate localization defects. The price tooltip builds its measured prefix from Blizzard's localized "sell price" string but appends its own separator, so a locale that spaces its colon differently measures one space short and shifts the first coin digit a few pixels off the native column; the library's reload-button search tests the localized defaults string first and falls back to the English literal, which can only ever help on an English client. Both are cosmetic on non-English clients and neither is ever a fault, and this is a single-user addon on an English client, so both were declined as one decision rather than two. Deleting the redundant literal was also declined: the localized string already covers the only client this runs on, so removing it changes nothing and loses the belt-and-braces. (`Tooltip.lua`, `Lib.lua`)
- `VeritasUI_Lib` — **the mouse-focus compatibility shim is not redundant, and the half a reader would keep is the dead one.** It tries the legacy global first and falls back to the modern plural call, which reads like belt-and-braces around an API rename that has already settled. An in-game probe settled it the other way: on this client the legacy global does not exist at all — asking its type returns nothing and calling it raises an error — so the fallback is the only path that has ever run here. That matters because collapsing the shim to the legacy call, which is what "the rename is done, drop the fallback" would produce, puts a call to a missing function inside the player frame's hover test, and that runs from a five-times-a-second ticker whenever the frame is faded in, in normal play. The shim is kept in its existing direction — the load-time test costs nothing and keeps working if the global ever returns — and the probe result is now written above it so the reasoning does not have to be rediscovered. This closes the last open probe the audit was owed. (`Lib.lua`)
- `VeritasUI_AuctionHouse` — one finding resolved as already correct with nothing to change: `/ah help`'s stated fifteen-minute scan cooldown matches the constant that enforces it. Absent from every phase plan. (`Core.lua`)

## [1.9.12] - 2026-07-25

Phase 4 of the fourth code audit — the stale-comment class, handled as one policy pass rather than as twenty unrelated typos. Almost nothing here changes what the addon does; what changes is whether its own comments can be trusted, which matters because every audit in this project starts by reading them. The findings sort into three kinds. Some are wrong pointers — a comment citing a line number that has since drifted onto something unrelated — and the flagship case had drifted three separate times, including once immediately after a maintenance pass whose stated purpose was to fix it, which is about as conclusive a demonstration as one could ask for that absolute line numbers cannot be maintained in a codebase this active. Every one of them was replaced by naming the thing being pointed at instead of counting lines to it, and that is now the standing convention. Some are wrong descriptions — comments documenting buttons that were deleted three versions ago, a two-phase progress bar that has had three phases for months, a name-matching fallback that never existed. Those are the dangerous ones, because they read as instructions. And two were worse than stale: they taught a theory of a bug as settled fact after the project's own live repro had disproved it, and they sat exactly where the next person to hit that bug would look. One measurable defect surfaced along the way and is listed separately. Deliberately excluded: no logic was rewritten to match a comment; where comment and code disagreed, the code was assumed right until read, and it always was.

### Fixed
- `VeritasUI_AuctionHouse` — **the scan progress bar's moving highlight was a pixel taller than the bar it slides inside**, overhanging it at both top and bottom. Invisible until now only because the bar clips its children, which is to say the addon was drawing an oversized texture and then hiding the evidence. The cause was three places independently recomputing the bar's interior from the frame's outer size, and getting the vertical answer wrong because the interior is asymmetric — one pixel of inset above, four below. Those insets are now named once and the backing, the fill and the highlight all read them, which is the actual root cause rather than the audit's suggested fix of anchoring the highlight to both edges; that would have over-constrained it vertically, since the animation re-anchors it horizontally every frame. The backing and fill come out to arithmetically identical coordinates — only the highlight changed. (`UI/ScanProgress.lua`)

### Documentation
- `VeritasUI_AuctionHouse` — **the Scan button no longer teaches a disproved explanation of the first-scan hang.** Three places stated that firing the scan synchronously from a real mouse click is what prevents it, following the theory v1.8.0 was built on. Version 1.9.5 caught the hang live and classified it: the server silently ignores every request for around twelve minutes after a long-idle login and then starts answering again on its own, no matter how the request was made. The comments now record that the theory was held, tested and falsified, and that the call stays synchronous only because nothing needs to wait — not because deferring is known to break it. Two side effects of the same theory were corrected: the file called the removed automatic scan "the locus" of the hang when it was merely unattended, and described the stall as lasting "forever" when the measured window is finite and clears itself. Nothing was rewired. (`UI/ScanButton.lua`)
- `VeritasUI_AuctionHouse` — **the replicate module's description of how it aggregates quantity was backwards**, calling it a maximum where the code sums. Both halves are deliberate and neither duplicates the other: within one scan the listings for an item are added up, because each row is a separate auction; across repeated scans in a day the largest of those daily totals is kept. The comments invited a future session to "correct" the sum to a maximum, which would have quietly reported the biggest single stack as the whole market's availability. Now spelled out as the two-level pipeline it is, with the trap named. (`Replicate.lua`)
- `VeritasUI_AuctionHouse` — **`/ah find` advertised a fallback that has never existed.** Its documentation said rows with unresolved links are matched by exact item name; they are in fact matched by item identifier read from a position the scanner calibrates live, and no name comparison exists anywhere in the sweep. A reader chasing a mispriced item would have gone looking for it, or added it — which is precisely the fuzzy matching the pricing rules forbid after it once cost real gold. The unused parameter left over from that removed design, and the caller's now-pointless work to supply it, are gone with it. (`Replicate.lua`, `Core.lua`)
- `VeritasUI_AuctionHouse` — **the scan bar's design contract described two phases and quoted a status message that does not exist.** The bar has had three phases since the gear-pricing pass was added, and the contract's own closing instruction not to collapse them into a single percentage would have been read by a future session as covering two. Rewritten against the shipped labels, each verified present in the code, with the third phase and the reason for keeping it separate stated explicitly. (`UI/ScanProgress.lua`)
- `VeritasUI_AuctionHouse` — **the documented list of `/ah` commands listed six of the nine that actually work**, in two separate places, which had the effect of hiding the ones with no help text. Both now match what the command handler dispatches, in the order the in-game help prints them, and say that they must stay one-for-one. (`Core.lua`)
- `VeritasUI_AuctionHouse` — the sell strip's paging section promised scroll-arrow handling the file has never contained (paging is mouse-wheel only, as its own header says); the price tooltip's documentation gave a coin size that a comment thirty lines below it explicitly called wrong; the scan button quoted a neighbouring module's spacing constant as 100 where it is 108, contradicting a correct comment two lines further down; and the item-key builder still asserted the fixed data position that the 1.8.1 scanner rewrite exists to abolish, now stating outright that Blizzard's documented position is wrong on this client and that the real one is discovered per scan. (`UI/SellStrip.lua`, `Tooltip.lua`, `UI/ScanButton.lua`, `Database.lua`)
- `VeritasUI_AdvancedOptions` — **the CVar list's policy note has pointed at three different unrelated lines across three versions.** This is the clearest evidence in the project for dropping line numbers altogether: it was written as one number in 1.6.41, deliberately corrected in 1.7.13, wrong again by 1.9.8, and moved once more when this cycle restructured the file. It now names the loop it means, and records that the omission is on purpose so nobody helpfully restores a number. The policy itself — keep every known setting name, never prune — is untouched; it was only ever the pointer that was wrong. (`Browser.lua`)
- `VeritasUI_AdvancedOptions` — **the CVar browser's header documented a UI that was deleted in 1.6.23/24**: click a row to expand it, with Set and Reset buttons. There are no such buttons, rows do not expand, and that design is on the do-not-reintroduce list — so the file's own introduction read as documentation that a rejected pattern still shipped. Replaced with what actually happens: left-click edits in place over the value column, Enter applies, Escape cancels, right-click resets. The comment justifying the fixed row height carried the same deleted vocabulary and was corrected with it, since that is the one place a reader checks before changing row heights. (`Browser.lua`)
- `VeritasUI_AdvancedOptions` — **a comment promised a deep copy of saved-settings defaults where the code copies one level.** Harmless today because every default that is a table is empty, but it sits exactly where the first nested default will be added, and it would have read as though the hazard were already handled — reintroducing the shared-reference bug that the copy was added to prevent in the first place. The comment now says what the loop does, why one level is enough for now, and what the next person will have to write instead. The code was left alone deliberately: making it genuinely recursive would add a fourth copy of the same helper for a guarantee nothing currently needs. (`Core.lua`)
- Suite-wide — **audit finding identifiers no longer appear in shipped comments.** Four comments cited tags like "F-2" and "F-5", but that namespace restarts with every audit cycle, so those tags now resolve to entirely different findings than the ones intended — a citation that gets more wrong over time rather than merely going stale. All four now cite the version that made the change, which is the one form of reference in this codebase that has never drifted, or simply name the mechanism. (`Replicate.lua`, `PriorityRotation/Core.lua`)
- Suite-wide — **the remaining line-number citations were replaced with names.** A debug-flag note pointing at a blank line; two rotation-module comments pointing 60 and 15 lines off; three separate comments sending readers to a quality-of-life function 130 lines from where it lives; a shared-helper note citing what is now a block of event registrations in another module; five comments citing line numbers in the project's own notes file, which is not even version-controlled and drifted mid-session while being edited. Also filled in a gap rather than a drift: the rotation module's taint rules read as though the module violated its own prohibition, because the two kinds of button involved — its own, safe to write to, and Blizzard's, never — had never been named in the block that assumed the distinction. (`Lib.lua`, `PriorityRotation/Core.lua`, `CleanSolo.lua`, `QualityOfLife.lua`, `Editor.lua`, `UI/ScanProgress.lua`, `UI/ScanButton.lua`)

### Skill maintenance (outside repo)
- **The auction-house design document's section on cold item data was actively misleading and has been rewritten.** It described the problem as unhandled, told the reader not to fix it, and recommended waiting synchronously for each unknown item's data to arrive — the approach a competitor uses. All three are wrong now: version 1.8.1 solved it, and following that recommendation today would break the requirement stated in the same document three paragraphs above, that the scan must never stall the client. Replaced with what actually ships, verified against the code rather than recalled: unknown rows are keyed from an identifier read at a position recalibrated on every scan because the documented one is wrong on this client, anything still unkeyable is retried in the background without blocking, and the measured effect was priced coverage rising from 7,977 items to 21,612.

## [1.9.11] - 2026-07-24

Phase 3 of the fourth code audit — footprint. Where Phases 1 and 2 fixed things that misbehaved, this phase removes work the addon was doing for no result: frames created and thrown away, handlers rebuilt on every scroll step, code kept alive after the question it was written to answer had been answered. Nothing here is meant to change what you see, with two exceptions noted below. The bar for inclusion was deliberately high — six of the seven modules yielded nothing worth removing, and every reduction had to say why the current form existed before it counted, so a temp diagnostic was retired only after its findings were written down somewhere permanent, and an orphaned handle was kept rather than deleted once it turned out this cycle had given it a real reader. Three of the audit's own recommendations were improved on rather than followed, and one was taken only in part; all four are recorded below. Net 75 lines lighter despite a good deal of added explanation, with the luacheck warning set identical to the previous version's.

### Changed
- `VeritasUI_AdvancedOptions` — **the CVar Browser stopped rebuilding every visible row's click and tooltip handlers each time you scroll.** Five wirings — the favourite star's click, the row's click registration, its click, hover and unhover handlers — sat in the section that runs on every data bind rather than the one-time setup section, so each of the ~24 visible rows re-registered its clicks and allocated four fresh closures on every scroll step, roughly 96 closures per full list refresh. This is restoration rather than a new idea: the v1.6.7 release notes state the intended design outright — handlers wired once when a row frame is created, reading the row's data through a stable reference that still exists and is still used by the hover handler — and no release since records moving them, so this was undocumented drift, most likely from the v1.6.18 initializer rewrite. Two of the five captured the row's data at wiring time and now read it at click time instead; getting that wrong would have welded a row to whichever CVar happened to occupy it first, and the symptom — the star favouriting the wrong CVar — only appears after the list has scrolled far enough to recycle frames, so it is worth verifying deliberately. (`Browser.lua`)
- `VeritasUI_AdvancedOptions` — **the Featured tab no longer leaves 40 empty frames behind the first time it is built.** Every control was created inside a throwaway frame that existed only so the factory could read a width, then hidden — and frames cannot be destroyed in this client, so all 40 persisted for the session. The width was discarded anyway: the row is re-anchored to both edges of its list frame immediately afterwards, which overrides it. The real container is now passed instead, so the count goes to zero rather than to one, which is what the two options the audit offered would each have left. Also made a silent failure audible: a control with an unrecognised type used to render an empty row and re-enter the same code on every layout pass — formerly an unbounded frame leak — and now says so once. (`Featured.lua`)
- `VeritasUI_AdvancedOptions` — **the three control factories no longer keep three copies of the same row scaffolding.** All of the checkbox, slider and dropdown builders opened by creating the same frame with the same width fallback and closed with the same 25 lines of trailing furniture: reset button, restart warning icon, whole-row tooltip, refresh handle. The three copies were byte-identical, and they are now one shared pair of helpers — 84 lines deleted for 57 added. Presented by the audit as a judgment call that three previous audits had declined; taken this time because a defect fixed earlier in this same cycle, the reset button painting the wrong colour, *was* these copies drifting apart, so collapsing them removes the whole class rather than the one instance. The dropdown's fallback path, used only if the modern dropdown template is unavailable, deliberately keeps its own minimal version. (`Controls.lua`)
- `VeritasUI_AdvancedOptions` — **the restart-warning icon's dead guards are gone.** It was guarded three times over: the caller tested whether the CVar needs a reload, passed a literal yes, and then tested the result for nothing. Sequenced immediately after the de-duplication above on purpose — that collapsed three identical call sites into one, turning what would have been a three-place edit into a four-line one. Offered as a reduction and not as the correction of a known mistake: the release history records the decision behind this icon's appearance but is silent on the guards, so no reason for them could be dated. (`Controls.lua`)
- `VeritasUI_AdvancedOptions` — **four fields that were written and never read anywhere are gone**, each commented as being "for external callers" that do not exist. The one apparent reader turned out to be reading a similarly-named field on the configuration tables, not on the rows. Taken in part rather than whole: the audit listed a fifth, the per-control refresh handle, which was genuinely orphaned when the audit was written and is not any more — Phase 1 of this same cycle gave it a live reader when it made the Featured tab re-read its values on becoming visible — so it stays. One of the four was residue from that Phase 1 work. (`Controls.lua`, `Featured.lua`, `Browser.lua`)
- `VeritasUI_AuctionHouse` — **`/ah find` stopped leaving a dead frame behind on every use.** Each invocation created a fresh frame to drive its chunked sweep and only stopped the sweep when finished; since frames cannot be destroyed, the frame and everything its handler had captured stayed alive for the session. The scan path already gets this right, creating its driver once and re-showing it, and the search now does the same. Improved on the audit's fix rather than following it: hoisting the sweep's counters alongside the frame, as suggested, is exactly what would let a second search corrupt the first one's counts mid-sweep, so the counters were left where they are and only the frame is shared — the hazard disappears instead of being guarded. Two consequences handled: a second search now politely refuses while one is running, rather than silently abandoning it without printing a summary, and the frame is explicitly shown when armed rather than relying on a fresh frame's default state. (`Replicate.lua`)
- `VeritasUI_AuctionHouse` — **opening the Auction House directly onto the Sell tab no longer scans your bags twice.** The open handler refreshed the sell strip unconditionally, and the tab-change hook that fires moments later refreshed it again; on any other tab the first refresh is the one that matters, so it now runs only when the Auction House did not open into Sell. (`SellStrip.lua`)
- `VeritasUI_PriorityRotation` — **the rotation editor stopped recomputing your current specialization key once per row on every repaint.** The row painter asked for it, then each row's lookup asked for it again, around 40 redundant API calls and 10 table allocations per repaint of a full profile. The lookup now accepts the value the caller already has. Chosen over the audit's alternative of caching the key, which had a trap: the cache would not notice a specialization change, and the whole point of the key is that it changes with your spec. (`Editor.lua`)

### Removed
- `VeritasUI_AuctionHouse` — **the `/ah btnprobe` diagnostic**, an undocumented temporary command written to work out why disabled buttons lose their artwork. Its own comments said to delete it once the question was answered, and the module's practice is to probe and then remove. Removed only after its findings — the mechanism, the fix that shipped, and the four approaches that were tried and rejected — were transcribed into the project's permanent probe reference, so the knowledge outlives the code. The pre-warm fix it led to is untouched; only the investigation tooling is gone. (`ScanButton.lua`, `Core.lua`)
- `VeritasUI_AuctionHouse` — **an orphaned market-price helper** with no callers anywhere in the addon. (`Database.lua`)

## [1.9.10] - 2026-07-24

Phase 2 of the fourth code audit — the remaining correctness defects, all of them low-severity edge cases rather than broken features. Same discipline as Phase 1: every fix is scoped to one misbehaviour with a cause traced through the module's own history, footprint reduction and comment drift stay deferred to later phases, and no intentional design decision is altered. Two of the audit's own conclusions were corrected during this phase rather than followed, and one plan formed earlier in the cycle was reversed on evidence; all three are recorded below rather than quietly dropped. One question the audit left open — whether the price database contains item-level-agnostic gear records — was settled by reading the live saved-variables file instead of guessing.

### Fixed
- `VeritasUI_PriorityRotation` — **the rotation cycle pressed the same ability twice in a row at the wrap point.** The compiler removes adjacent duplicates with a linear scan, but the sequence is *cyclic* — the secure snippet advances with `step % #macros + 1` — so the last and first steps are neighbours at runtime and were never compared against each other. Hand-traced: a two-ability profile weighted 3:1 compiles to `[A, B, A]` and therefore plays `A, B, A, A, B, A`, one dead press every cycle. This is the exact clumping the v1.9.6 redesign was written to eliminate, and it triggers whenever the highest-weighted ability also wins the final slot, which is the normal case. Dropping the trailing step is safe precisely because it is only done when its text is identical to the first step's, so an ability emitted for "After" adjacency still has the wrap land on a step with the same macro text; and exactly one drop can ever be needed, because the existing pass already forbids consecutive matches. (`Core.lua`)
- `VeritasUI_PriorityRotation` — **the Frequency help text promised a literal attempt count the compiler never delivers.** Both places it was explained — the Settings info tab and the Editor's column header tooltip — described it as attempts per cycle, "1 = once per cycle". Because adjacent duplicates are collapsed *after* weighting, a frequency of N never yields N steps, so anyone who set 5, counted 4 in the preview, and checked the help was told by the addon itself that the feature was broken. The copy now describes what the setting actually controls: how densely that ability is spread through the cycle relative to the others. Written after the wrap-around fix above deliberately, since that fix collapses one more duplicate per sequence. (`Settings.lua`, `Editor.lua`)
- `VeritasUI_PriorityRotation` — **a failed spec switch reported "Spec switch failed: nil".** The error variable is only ever assigned by a protected call, so on a client that has neither the modern spec API nor the legacy global, no call runs, nothing is assigned, and the message degenerates into the exact diagnostic dead end the surrounding comment says the block exists to prevent. It now names the real reason. Low reachability, but that class of client is already in scope here — the dropdown construction a few lines earlier is protected for the same reason. (`Settings.lua`)
- `VeritasUI_CleanSolo` — **the micro menu stayed fully visible after leaving Edit Mode.** The hover-fade helper hands back two control handles, and this call site discarded both, so unlike the action bars nothing re-asserted the faded state once layout editing ended — Blizzard forces Edit-Mode-movable frames visible, and no mouse-leave event fires afterwards to undo it — and the cached list of child buttons was never rebuilt even though the micro menu's button set changes. Both handles were added to the shared library for the action-bar feature *after* this line was written, and it was never migrated; it now mirrors the action-bar wiring exactly. This also corrects the previous audit, which filed the same symptom as a library defect on the premise that the cache-rebuild handle is never called by anything — it is, from the action bars, so the library itself was left untouched. (`CleanSolo.lua`)
- `VeritasUI_QualityOfLife` — **turning Show Map Coordinates off and on before ever opening the world map leaked a frame each time.** The setup function had no re-entry guard of its own, unlike its item-level counterpart which guards on its first line; its only guard sits one level deeper and is not set until the map frame actually exists. While Blizzard's world map module is still unloaded, the function creates a loader frame waiting on an addon-load event and returns — leaving the settings toggle to re-enter on exactly the condition that was still unmet, adding another loader and another event registration on every cycle. Frames are never reclaimed in this client, so each one persisted for the session. Invisible in play, because once the map finally loaded every loader ran the same initializer and all but the first returned immediately, which is why it went unnoticed for so long. A separate flag was added rather than reusing the existing one, which means something different and is what both branches of the toggle depend on. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **logging in un-hid the minimap even when another addon or an Edit Mode layout had deliberately hidden it.** The AFK screen's crash-recovery block restored the interface on every login, justified by a comment claiming its calls are harmless no-ops when already at their defaults. That is true of resetting the interface alpha but false of showing the minimap cluster, so any deliberate hide elsewhere was overridden, subject only to load order — the very behaviour the AFK code goes out of its way to avoid, since it records the minimap's visibility before hiding it and restores it only if it was shown. The recovery intent is kept and now gated on evidence that the AFK screen itself left the interface hidden: a flag set when it takes over and cleared when it hands back, persisted so a crash or disconnect while the AFK screen is up is still recovered at the next login. Chosen over merely correcting the comment, because the comment was the only thing making the override look intentional. (`QualityOfLife.lua`)
- `VeritasUI_AuctionHouse` — **the gear-residue retry pass at the end of a scan stopped early and its progress label could never reach its own total.** The test for "this pass accomplished nothing" counted rows folded into the price aggregate, but a row leaves the pending pile as soon as its link resolves, whether or not it was folded — bid-only, zero-count and unpriceable rows are legitimately skipped. A pass that resolved only skip-worthy rows therefore looked like a dry stream and abandoned the rest of the pile, which is ordinary for a small bid-only tail at the end of a scan. The same mistake skewed the "Finalizing gear N/M" readout, counting folds against a denominator of pending rows so the numerator could never catch up. Now tracked as two separate counts. Deliberately not collapsed into one: doing so would remove the early-exit entirely and burn the full 45-second budget on every scan that ends with a bid-only tail. (`Replicate.lua`)
- `VeritasUI_AuctionHouse` — **gear whose item level had not loaded yet was priced under a key that ignores item level.** Key derivation appends the item level for equippable gear but fell through to a bare item-ID key when the detailed item data was not yet available — the one key shape the design forbids outright, because it collapses every item-level variant of a piece of gear into a single price record. It is reachable on a cold cache: a loaded item link does not imply loaded detailed item data, which is the entire premise of the cold-cache work in v1.8.1. It now declines to produce a key, deferring the row into the retry machinery that already exists for exactly this case, and matching the behaviour of the equivalent function written eight months later. Deliberately *not* fixed by teaching the reader to fall back to the bare key — that is the change the design most explicitly forbids, having been decided after a real gold loss. No cleanup of existing records was needed: of 13,045 price keys in the live database, 9,750 bare and 3,295 carrying an item level across 2,332 gear items, exactly zero items appear both ways, which is the signature a polluted record would leave. (`Database.lua`)
- `VeritasUI_AuctionHouse` — **`/ah wipe` and `/ah blocked` printed nothing at all if their module was missing.** Both were wrapped in a bare module check with no alternative branch, while the other five subcommands all report a reason. `/ah blocked` was the worse of the two, because its normal output is printed from inside the listing function, making a missing sell strip indistinguishable from an empty blocklist. Latent rather than live — both modules load after the command handler and a real load failure raises an error first — so this is a consistency fix. (`Core.lua`)
- `VeritasUI_AuctionHouse` — **the price database's schema-version field could not do what it documented.** It was annotated "bump on layout change", but the database initializer seeds keys only when they are absent, so an existing saved-variables file keeps its stored value forever and a bump would leave every existing database reporting the old number; nothing anywhere compared the two. The two schema changes that have actually shipped were done as unconditional cleanup assignments instead. The comment now describes what the field really is — a diagnostic reported by `/ah diag` — and names the cleanup pattern as the real mechanism. This reverses a plan formed earlier in this audit cycle to implement the missing version check: it was to be the facility a gear-record cleanup would hang on, and the database probe above found nothing to clean, so the mechanism would have been machinery with no consumer. (`Core.lua`)
- `VeritasUI_AdvancedOptions` — **right-clicking a CVar in the Browser to reset it claimed success even when the reset had not happened.** After re-reading the live value, the handler painted the "this is the default" colour unconditionally, so a reset deferred by combat or rejected outright left the old, still-modified value on screen wearing the colour that means it matches the default. The two other places that repaint that column in place both compare value against default correctly; only the reset copy had drifted. The duplication dates to the v1.6.22–v1.6.24 work that replaced rebuilding the list on every edit with updating rows in place — a deliberate trade, but the copies diverged. All three now share one painter, so the de-duplication *is* the fix rather than a bundled tidy-up. Deliberately not fixed by rebuilding the list from the handler, which would undo that trade and rebuild the data source from inside a bound row's own click. (`Browser.lua`)
- `VeritasUI_AdvancedOptions` — **typing a CVar value in the Browser during combat threw the typed value away without explanation.** The handler ignored whether the write had actually landed and immediately re-read the live value, which in combat is still the old one, so the row snapped back and the pending value the write path had deliberately cached was never shown. It now keeps the typed value on screen when a write is deferred, mirroring the dropdown fix from Phase 1, and colours it against the default. This also corrects the audit, which filed the defect as entirely silent: the write path already announces both the deferred and the failed case, so no message was added and the one recommended would have duplicated it. Deliberately not extended to the right-click reset alongside it, even though they share a root cause — showing a pending default there would repaint the row grey in combat, which is precisely the false signal the fix above exists to stop. (`Browser.lua`)
- `VeritasUI_AdvancedOptions` — **the CVar Browser's "alternating" row shading was random mottling.** The shade came from the parity of the CVar name's character sum, which is a property of the name and not of the row's position, so roughly half of all adjacent pairs shared a shade. The comment's premise was true but beside the point: the scroll list genuinely cannot be asked for a row index, but the index never had to come from it — the refresh already walks the filtered list in order, so it stamps the visible position there. Stamped at that point deliberately, and not where CVars are first enumerated, since the list is rebuilt and reordered by every search and favourite toggle and an enumeration-time index would follow the unfiltered alphabetical order instead of the view. Also removes a loop over every character of every visible row's name on each scroll pass. (`Browser.lua`)
- `VeritasUI_Lib` — **the Reload UI button would have been permanently absent had the Settings panel not existed yet at load.** The initializer returned early without recording that it had run, and the apparent retry mechanism — all seven modules calling the same registration function — is illusory, because they all register within the same load phase, so seven retries at one instant amount to one. A single retry at player login was added, which is the only point strictly later than addon load and therefore the only one that adds a genuinely new opportunity. Pre-emptive rather than corrective: the panel is created by a non-load-on-demand Blizzard addon and is present at load in current retail, so this is unreachable today. (`Lib.lua`)

## [1.9.9] - 2026-07-24

Phase 1 of the fourth code audit — every correctness defect it found, and nothing else. The audit read all 22 files against each module's own history, so each fix below is scoped to a specific misbehaviour with a known cause rather than a general tidy-up; footprint reduction and comment/documentation drift are deliberately deferred to later phases so that any regression here is attributable to a single change. Nothing in this release alters an intentional design decision, and the four "policy" blocks the audit re-confirmed (`KNOWN_CVARS` breadth, the removed overlay editor, ZoneQuests' strict ascent-level rejection, the AH exact-match price rule) are untouched.

### Fixed
- `VeritasUI_CleanSolo` — **chat tabs snapped out of view instead of fading whenever you moved the mouse off chat and back on.** The 2-second fade-out ends with a timer that flips each tab to a hard-hidden state, but that timer was armed with no handle and so could never be cancelled — and it runs for 2.05s while the hide countdown is only 1.0s, so an ordinary hover out → in → out cycle leaves the first cycle's timer pending. Hand-traced against live defaults: leave at t=0, re-enter at t=1.5, leave again at t=2.0, and the stale timer lands at t=3.05 — 0.05s into a fresh 2-second fade — marking the tabs hidden mid-fade, at which point the alpha hook that enforces the hidden state slams every remaining fade frame to zero. A ~1.05s window of every hover cycle could trigger it, needing no user action beyond moving the mouse. The fade-completion timer is now a cancellable handle, cancelled anywhere the hide countdown is; the two `IsOverAnyChatElement` / `FADING_OUT` guards are deliberately left as the second line of defence. (`CleanSolo.lua`)
- `VeritasUI_AdvancedOptions` — **controls on the Advanced Options tab showed stale values and could write the wrong one back.** Each control reads its CVar exactly once, when it is first created, and the list initializer only reparents cached controls into scroll-pool frames — so nothing ever re-read the value. There was no refresh path at all: a search for any `Refresh()` call across the module returned nothing, the control cache was never invalidated, and the internal refresh handle was assigned but never called by anything. Reachable in normal use, because most of these CVars are also editable from Blizzard's own Options panel and from this addon's own Browser tab — after changing one elsewhere, the stale checkbox would report the old state and the next click would send the wrong value. Values are now re-read every time the tab becomes visible, mirroring the Browser tab's existing wiring so both tabs behave the same. Values only, deliberately: rebuilding the list would reset the scroll position on every show. Skipped while in combat, so a write deferred to the end of combat keeps showing the pending value instead of snapping back. (`Featured.lua`)
- `VeritasUI_AdvancedOptions` — **choosing a dropdown option during combat silently reverted it.** `AO:SetCVar` defers writes made in combat and optimistically caches the pending value so the UI can show it — but the dropdown immediately re-read the *live* CVar afterwards, which is still the old value while deferred, so the label snapped back and the cached pending value was overwritten in the same breath. The checkbox and slider factories never re-read and so were never affected; the dropdown was the odd one out. It now shows the chosen option when a write is deferred and re-reads the authoritative value otherwise. Deferred and genuinely-failed writes are distinguished at the call site rather than by changing `AO:SetCVar`'s return contract, which would have touched every caller. The label-painting branch is also now in one place instead of two. (`Controls.lua`)
- `VeritasUI_AdvancedOptions` — **every slider on the Advanced Options tab rendered Blizzard's stock "Low"/"High" labels under it.** The code that hides them looked the fontstrings up by frame name, but the slider is deliberately created unnamed, so the lookup always returned nothing and the whole block was dead — the labels the template ships with default text simply stayed visible. It now uses the template's direct child references, keeping the name-based lookup as a fallback, with both treated as optional so a future template change leaves the labels alone rather than erroring. (`Controls.lua`)
- `VeritasUI_QualityOfLife` — **auto-repair against a guild bank could under-repair and still report full success.** The personal-gold path has had a pre-check since v1.6.36, but the guild path called guild repair then personal repair and printed "Repaired for X" unconditionally — and `RepairAllItems` silently no-ops when the funds aren't there. So with a daily withdrawal limit below the repair bill and not enough personal gold for the remainder, gear stayed damaged while the addon claimed otherwise; the comment above the function asserted the opposite ("we never silently under-repair"). The split is now computed *before* anything is repaired, from the daily withdrawal limit (`-1` = unlimited), and if personal gold can't cover the remainder the repair is declined with a message naming both the bill and the guild's share — the same shape as the personal path. `GetRepairAllCost()` is deliberately not re-read after the guild repair (that stale-cache race was removed in v1.3.21), and `GetGuildBankMoney()` is deliberately not consulted: it is unreliable until the bank frame has been opened, and trusting a stale zero would refuse repairs that would actually succeed. That residual case is now documented in the comment instead of being papered over. (`QualityOfLife.lua`)
- `VeritasUI_PriorityRotation` — **the "After" button stopped cycling once a profile held the same ability in two slots.** Links are stored as identity keys, but the candidate list was built per *slot*, so a duplicated ability put the same key in the list twice and the forward search for the current link always matched the first copy. The cycle then oscillated between two entries forever: "none" and every candidate past the duplicate became unreachable, and only right-click could clear the link. Candidates are now de-duplicated by key while preserving profile order — two slots holding the same ability are one candidate, which is what the stored key already meant. (`Editor.lua`)

## [1.9.8] - 2026-07-19

### Fixed
- `VeritasUI_ZoneQuests` — **normal quests were pinned as "Important" and stayed in the tracker across zones; quest-type detection now trusts `questClassification` only.** Found in-game (Harandar, alt character): "Stalkers of the Stars" and "Veterans of the Great Dark" — Silvermoon City quests with normal-quest icons — survived zone filtering, and unchecking "Always Show: Important Quests" removed them, proving they were misclassified. A `/zq dumpquest` probe showed why: Blizzard's tag layer and classification layer disagree — quest 96049 carries tagID 282 / tagName "Important Quest" while `questClassification = 7` (Normal), and it renders with the classification's normal icons. The pin logic's tagName substring matching (`"important"`, `"campaign"`, `"legendary"`, `"meta"`) trusted the wrong layer; all of it is removed. Every pin category now checks `Enum.QuestClassification` (Campaign / Important / Legendary / Meta / Recurring) — the same field that drives the pink-! and campaign-shield visuals the player actually sees — with the legacy structured fields (`isCampaign`, `campaignID`, `frequency`, …) kept as harmless backup. Dailies/weeklies additionally match the Recurring classification. (`ZoneQuests.lua`)

## [1.9.7] - 2026-07-11

### Changed
- `VeritasUI_PriorityRotation` — **editor column layout rebuilt on exact geometry.** "Freq" is now "Frequency"; the Frequency / After / Combat columns sit on a grid computed from the panel's real content width (420 → 390-px rows) with identical visible gaps between the spinner's arrow art, the After icon, the Combat checkbox, and the right border (25/25/26 px); headers center on their elements' true centers, and the frequency spinner narrowed from 70 to 56 px so its arrows tuck in beside the number instead of floating. The header divider line now spans exactly the row width (the old panel-inset anchor fell a few px short on the right). The Settings info tab's stale "Freq 3+/1" section (pre-v1.9.6 semantics) is rewritten to teach the current Frequency / After / Combat model. (`Editor.lua`, `Settings.lua`)

### Added
- `VeritasUI_PriorityRotation` — **per-ability "Cbt" (combat-only) checkbox — hand-built macros are no longer needed for anything.** The last remaining reason to wrap spells in macros before importing them into PR was adding `[combat, nochanneling]` by hand (`[nochanneling]` has been compiled in since v1.9.6). Each spell/trinket row now has a Combat checkbox: checked compiles the step as `/cast [combat, nochanneling] <spell>` so it only fires in combat; unchecked keeps it castable anytime — leave exactly your opener unchecked so a key press out of combat starts the fight. Macro entries deliberately have no checkbox (their bodies and conditionals stay user-owned), and existing profiles are unaffected (the gate defaults off). Verify any profile's compiled conditionals with `/pr debug` + `/pr test`. (`Core.lua`, `Editor.lua`)

## [1.9.6] - 2026-07-11

The PriorityRotation compiler redesign, from the 2026-07-11 design session. PR is a blind stepper — the secure snippet legally cannot see cooldowns, procs, or cast history (the same wall that stops every addon short of Blizzard's engine-side Assisted Combat) — so the only lever for "cast X reliably when it comes off cooldown" is how often, and how evenly, the sequence *attempts* X. Attempt economics are lopsided: a not-ready attempt costs one press (~100ms at hardware-repeat rates; the GCD throttles real throughput, not presses), while a ready ability waiting for its next step costs seconds of uptime. Both features below are pure compile-time placement of the same single-`/cast` steps PR has always fired — no new secure surface, and no reliance on the approaches falsified by in-game testing (castsequence, multi-line `/cast` fallback, press-and-hold-driven SBR).

### Changed
- `VeritasUI_PriorityRotation` — **priority (Freq) now means evenly-spaced attempt density, fixing the clumping that made off-cooldown usage unreliable.** The old compiler appended each ability's copies in consecutive blocks (freq 4 → four back-to-back steps of the same spell — up to three guaranteed dead presses in a row, then no attempt at all for the rest of the cycle). The new compiler places steps by smooth weighted round-robin (the nginx algorithm): each slot, every ability accumulates its weight, the highest total wins the slot and pays back the cycle total. Deterministic, profile-order-stable on ties, and gaps come out as even as arithmetic allows — e.g. Blade Dance 3 / Eye Beam 4 / Chaos Strike 1 / Immolation Aura 2 now compiles to `EB, BD, IA, EB, BD, CS, EB, IA, BD, EB` instead of `CS, BD, BD, BD, EB, EB, EB, EB, IA, IA`. Same mental model for every class: freq 5 = attempted constantly, freq 1 = once per cycle. (`Core.lua`)

### Fixed
- `VeritasUI_PriorityRotation` — **half of every compiled sequence was silently discarded — a latent parity bug present since PR's inception, exposed by the new compiler and fixed.** The keybind path (`SetOverrideBindingClick`) delivers two clicks per physical press — key-down and key-up — and the secure OnClick wrap advanced the step on both, while the cast fires only on the up edge (`ActionButtonUseKeyDown=0`, which PR itself enforces). Two advances, one cast: every other step never executed. The old clumping compiler masked it — consecutive duplicate steps put every ability in both parity classes — but the smooth-weave cycle's even length locked execution to one fixed parity, hard-starving any ability living only on the other (found in-game during v1.9.6 validation: Immolation Aura silent for 40s, Eye Beam and Blade Dance seconds late). The wrap now gates on the snippet's standard `down` argument: exactly one step consumed per physical press, on the same edge that casts. This also makes the "After" guarantee literal — the follower step is the next *executed* step — and effectively doubles attempt throughput for every profile, since no step is ever discarded. (`Core.lua`)

### Added
- `VeritasUI_PriorityRotation` — **spell and trinket steps are now compiled with `[nochanneling]` channel protection.** A press landing mid-channel clips the channel tail the moment the GCD opens (~75% through) — found in-game when one hand-built macro missing the conditional cost every Eye Beam its full-channel haste buff and empowered Blade Dance (~4-6k DPS). Profiles built from hand-written macros only worked because the user added `[combat, nochanneling]` themselves; raw spell entries had no protection at all. The compiler now emits `/cast [nochanneling] <spell>` (and `/use [nochanneling] <trinket>`), so a press during your own channel is a harmless no-op and the channel always completes. Macro entries are deliberately untouched — their bodies and conditionals belong to the user. Conditional verified working in Midnight (in daily use in the user's own macros). (`Core.lua`)
- `VeritasUI_PriorityRotation` — **`/pr test` now dumps each step's actual compiled macrotext when `/pr debug` is on**, so compiled conditionals (`[nochanneling]`, reacquire lines) are verifiable in-game instead of inferred from combat behavior. (`Core.lua`)
- `VeritasUI_PriorityRotation` — **"After" column: guarantee an ability is attempted on the very next press after another one casts** — the class-agnostic form of "Blade Dance must land inside the 6-second window after Eye Beam." Each rotation row gains a fourth column showing the icon of the ability it follows (left-click cycles through the other entries and back to none; right-click clears; tooltip explains the link). A linked ability keeps its own weighted placement *and* is inserted immediately after every occurrence of its target; adjacent duplicate steps are collapsed (identical macrotext back-to-back adds nothing), chains (A after B after C) cascade with a visited guard so hand-edited cycles terminate, and a link whose target is removed goes inert rather than breaking — re-adding the same ability reactivates it. Links are stored as stable identity keys (`spell:ID` / `macro:name` / `item:ID`), so they survive list reordering. (`Core.lua`, `Editor.lua`)

## [1.9.5] - 2026-07-11

The first-scan hang, finally classified from a live repro (first login after 6 idle days, debug trace captured in-game): **the server silently drops every `ReplicateItems()` request for an extended window after a long-idle login (~12 minutes measured), then recovers on its own** — `numReplicate=0` at each later fire proved no snapshot was ever assembled, and the eventual accepted request delivered a textbook-healthy scan (first pulse 23.9s, 255,990 rows in 75.6s). Two prior hypotheses are falsified by the same repro: the hardware-click fire path does *not* prevent the hang (v1.8.0's premise), and closing/reopening the AH is *not* required to recover — a later fire in the same AH session succeeded. Client-side gating remains impossible (`throttleReady`/`hasFullBrowse` read `true` at failing and working fires alike, 2026-07-02 and 2026-07-11). The only working strategy is to keep asking until the server says yes — which the addon now does.

### Fixed
- `VeritasUI_AuctionHouse` — **a scan now recovers from the long-idle-login server drop window by itself; no more indefinite "Requesting auctions…" hang.** The 60s no-event auto-retry was one-shot: it re-fired once and then gave up forever, so during the measured 12-minute drop window the addon fired at ~0s and ~60s and then sat silent while the user's manual Retry clicks did its job. The retry chain is now persistent — it re-fires and re-arms every 60s (above the ~24–40s healthy first-event latency band, so it never duplicates a healthy scan) until data arrives or the AH closes. Every re-fire re-checks AH-open/scanning/no-coroutine, `AH_CLOSED` cancels the chain, and duplicate fires are proven safe (the v1.7.9 10s timer duplicated on every healthy scan for weeks without harm; the 2026-07-11 success came 4 minutes after a dropped fire). Deliberately unbounded, same reasoning as the established no-timeout rule: any cap just recreates "gave up N seconds before the server recovered" at a different N. Today's hang would have self-recovered with zero clicks. (`Replicate.lua`)

### Added
- `VeritasUI_AuctionHouse` — **always-on scan trace, so the next rare repro is never dark.** The purpose-built hang diagnostics were debug-gated prints, and `VUI.debug` was off during the 2026-07-11 repro — the classification only happened because the hang lasted long enough to enable debug mid-hang. Every scan now records an attempt-chain trace regardless of the debug flag: attempts fired (auto re-fires *and* manual Retry clicks continue the same chain), event pulses seen, first-event latency and which attempt it followed, outcome (`requesting`/`processing`/`complete`/`failed`/`aborted`), and committed/rows/total-time on completion. `/ah diag` dumps it — during a hang ("requesting — attempt 5, no data for 43s / first data: never arrived") and after the fact. Exposed as `AH.Replicate.LastTrace()`. (`Replicate.lua`, `Core.lua`)
- `VeritasUI_AuctionHouse` — **`/ah debug` toggles the suite-wide debug gate** — `/run VeritasUI.debug = true` proved to be an incantation nobody remembers during a live repro. Listed in `/ah` help; prints the new state. (`Core.lua`, comment touch-up in `Lib.lua`)
- `VeritasUI_AuctionHouse` — **the scan progress bar shows the retry chain working**: from the second attempt on, the wait label reads "Requesting auctions… (43s, try 3)" so a long wait is visibly the addon retrying, not hung. (`UI/ScanProgress.lua`)

## [1.9.4] - 2026-07-04

### Fixed
- `VeritasUI_QualityOfLife` — **the AFK screen now dismisses the instant you move, instead of sometimes taking several seconds.** Dismissal previously depended entirely on `UnitIsAFK("player")` clearing server-side: `PLAYER_FLAGS_CHANGED` when the server sent it promptly, or the v1.6.21 5-second fallback poll when it didn't — so how fast the overlay disappeared varied with network round-trip time rather than with when you actually moved. A new `PLAYER_STARTED_MOVING` handler drops the overlay the moment the client itself detects movement, with no server confirmation needed. This is a plain event registration, not keyboard capture — it doesn't touch the combat-protected `EnableKeyboard`/`SetPropagateKeyboardInput` path removed in v1.9.2. `PLAYER_FLAGS_CHANGED` and the fallback poll are unchanged and still catch every other AFK-clearing input. (`QualityOfLife.lua`)

## [1.9.3] - 2026-07-04

The high-severity finding from the full-suite code audit — the final batch of the three-release remediation (lows v1.9.1, mediums v1.9.2).

### Fixed
- `VeritasUI_ZoneQuests` — **newly accepted quests are no longer silently un-tracked until the next zone change.** `SyncTracking` reuses a cached zone quest set that was only invalidated on `ZONE_CHANGED*`. The v1.7.14 rewrite changed what that cache holds: the old cache (v1.6.3 lineage) held the zone *name set* — stable within a zone, so the v1.6.27 removal of the `QUEST_ACCEPTED` handler was sound at the time — but the new cache holds the zone *quest-ID set*, which changes on every acceptance. Accepting a quest fired `QUEST_LOG_UPDATE` → the debounced sync judged the new quest against the stale set → not in it, not pinned → `RemoveQuestWatch`, actively undoing Blizzard's auto-watch until a zone boundary rebuilt the cache (and even `/zq refresh` used the stale set, so the manual escape hatch couldn't rescue it; pinned categories masked the bug for Campaign/Important/etc.). Fix, scoped deliberately: `QUEST_ACCEPTED` is re-registered and does exactly two things — invalidate the cache and route through the existing cancellable 0.3s debounce (NOT the stacked per-event `C_Timer.After` the v1.6.27 hardening removed, and NOT blanket invalidation on `QUEST_LOG_UPDATE`, which fires on every objective tick and would rebuild the map query per kill-credit burst — the exact cost the cache exists to avoid). One rebuild per acceptance burst; `/zq refresh` now also rebuilds fresh. Zone-transition behavior, pins, super-track preservation, and the strict sub-zone semantics re-confirmed in v1.9.2 are all untouched. (`ZoneQuests.lua`)

## [1.9.2] - 2026-07-04

Medium-severity batch from the full-suite code audit (3 findings shipped of 4 — one was falsified during in-game validation and reverted, see Internal; the low batch shipped as v1.9.1, the high finding ships as v1.9.3). Each fix was validated against the git history of the code it touches.

### Fixed
- `VeritasUI_QualityOfLife` — **the AFK screen no longer captures the keyboard, eliminating a combat-blocked protected call and a swallowed wake-up keypress.** The overlay's only keyboard code was an `OnKeyDown` handler calling `SetPropagateKeyboardInput(true)` — combat-protected for insecure frames since 10.1.5. A mob attacking the AFK player puts them in combat; the wake-up keypress then fired a blocked-action error on every key, and if it was the session's first overlay keypress the key was swallowed outright (propagation still at its default `false`) — the player couldn't move to clear AFK. Dismissal has never depended on keystrokes (it's `PLAYER_FLAGS_CHANGED` + the v1.6.21 poll), so `EnableKeyboard` and the handler are simply removed: every key now reaches the game directly, in or out of combat. (`QualityOfLife.lua`)
- `VeritasUI_PriorityRotation` — **`/pr diag` no longer flips `ActionButtonUseKeyDown` to "0" as a side effect.** The diagnostic's write-permission probe had hardcoded `SetCVar(..., "0")` since its introduction in v1.3.26 and never restored the value — with PR disabled (where `EnsureActionBarCVar` deliberately keeps the CVar at "1" for Press-and-Hold Casting), running a diagnostic silently broke the user's casting mode until the next login. The probe now writes back the CVar's *current* value — a same-value `SetCVar` still exercises write lockdown, which is all the probe exists to test. (`Core.lua`)
- `VeritasUI_Lib` / `VeritasUI_QualityOfLife` / `VeritasUI_AuctionHouse` — **settings that apply immediately no longer tell you to /reload.** `VUI.PrintOnOff`'s "— /reload to apply." suffix dates to v1.2.0 when every setting genuinely required one; v1.6.28 made QoL live-apply (and AH's tooltip toggles always were) without revisiting the message — nine toggles across two modules printed a false instruction. New `VUI.PrintOnOffLive` variant (same wording, no suffix) now used by all QoL and AH checkboxes; CleanSolo keeps `PrintOnOff` unchanged (its hook-based features genuinely require /reload, per its file-top POLICY block). Also closed the one real live-apply gap behind that message: `MERCHANT_SHOW`/`MERCHANT_CLOSED` were registered at login only if Auto Sell or Auto Repair was already enabled, so with both off at login, enabling one mid-session did nothing until /reload — the toggle callbacks now register the events (idempotent; disable needs no unregister since the handler gates on the db flags). (`Lib.lua`, `QualityOfLife.lua`, `Settings.lua`)

### Internal
- `VeritasUI_ZoneQuests` — **audit finding "map-walk ascent path empties the tracker" is FALSIFIED and the drafted fix reverted; ascent-level rejection is policy, not a bug.** The draft extended the accept set with each walked ancestor level + its descendants so quests found at the ancestor would pass the per-POI mapID filter. In-game validation immediately disproved the premise: standing in Silvermoon City, the tracker surfaced Eversong's Windrunner Spire quest — parent-zone quests bleeding into a sub-zone the filter had (correctly) kept them out of since v1.7.14. The strict semantics are intended: a map with no quests of its own shows only pinned quests, and the walk exists solely to catch quests filed at an ancestor level whose POI mapID points back INTO the best map or its sub-areas (the v1.7.14 "Stalkers of the Stars" case). A POLICY comment now fences the walk so future audits treat the rejection as deliberate. No behavior change vs v1.9.1. (`ZoneQuests.lua`)

## [1.9.1] - 2026-07-04

Low-severity hardening batch from the full-suite code audit (8 findings; the audit's medium and high findings ship separately as v1.9.2 / v1.9.3). Every fix was validated against the git history of the code it touches so no hard-won behavior regresses.

### Fixed
- `VeritasUI_QualityOfLife` — **Auto Repair no longer claims "Repaired for X" when personal gold can't cover the bill.** `RepairAllItems` silently no-ops when unaffordable, but the success line printed unconditionally. The personal-funding path now pre-checks `GetMoney() >= cost` (synchronous read-once — no delta math, no `PLAYER_MONEY` listener, preserving the v1.6.36 constraints) and prints an honest "Can't repair — costs X and you don't have enough gold." instead. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **Auto Sell Junk now recovers from a fully cold item cache.** If every grey's `GetItemInfo` was uncached at merchant open (fresh client start straight to a vendor), `ScanJunk` summed 0 and the sale never armed — nothing sold that visit, silently. Cold greys are now requested via `C_Item.RequestLoadItemDataByID` and tracked in a pending set; `GET_ITEM_INFO_RECEIVED` (registered only while a merchant is open — it is far too chatty to listen to globally) re-runs the junk scan once records land, debounced 0.1s and **gated on no sale being in progress** (re-entering `AutoSellJunk` mid-sale would reset the accounting and corrupt the report). Mirrors the proven SellStrip pending/request pattern. (`QualityOfLife.lua`)
- `VeritasUI_QualityOfLife` — **Map Coordinates now keep tracking the map frame after being repositioned.** `StartMoving()` silently re-anchors the frame to screen coordinates; the old code saved the container-relative position but left the live frame screen-anchored, so moving or rescaling the windowed map made the coords float until the next login. `SavePosition` now immediately re-anchors to the container with the just-saved offsets — the exact restore path already used at login, applied live. (`QualityOfLife.lua`)
- `VeritasUI_CleanSolo` / `VeritasUI_QualityOfLife` — **`/cs` and `/qol` (and their Addon Compartment entries) no longer call `Settings.OpenToCategory(nil)` if options registration hasn't run or failed.** Both now use the same nil-guard + "Settings are still loading — try again in a moment." pattern the other four modules already had. (`CleanSolo.lua`, `QualityOfLife.lua`)
- `VeritasUI_AdvancedOptions` — **`AO:GetCVarBool` no longer collapses a legitimate `false` into `nil`.** The `ok and val or nil` idiom made "off" indistinguishable from "unreadable", silently breaking the function's documented true/false-or-nil contract for any future caller that distinguishes them (the sole current caller happened to treat both alike). (`Core.lua`)
- `VeritasUI_AdvancedOptions` — **slider reset can no longer be silently overwritten by a stale drag write.** The 0.15s debounced `SetCVar` from a drag could land *after* a Reset-to-default click, re-applying the dragged value while the UI showed the default. `Refresh` now cancels any pending debounced write (the `pendingWrite` handle was hoisted above `Refresh` so the closure can actually see it). (`Controls.lua`)
- `VeritasUI_AuctionHouse` — **the Scan button keeps Blizzard's genuine disabled state (silver backdrop, grey text — pixel-identical to Cancel Auction) and no longer blanks for ~1s on the session's first disable: the disabled art is now pre-warmed at build time.** The blank resurfaced during v1.9.1 validation on a cold client start (v1.9.1 had not touched the button — verified by file hash and git history). A new **`/ah btnprobe`** diagnostic (dumps the live art state of disabled native AH buttons) drove the root-cause: **(1)** this template is a **three-slice build with no `GetNormalTexture`/`GetDisabledTexture` objects** — so v1.8.1's disabled-slot copy (and a retry-hardened variant tried this session) were *silent no-ops from day one*; the v1.8.1 "verified" pass was a warm-cache coincidence. **(2)** Probed live, a disabled native button's three BACKGROUND slices hold **file 130824 — the silver disabled art** (the highlight slice at 130826 pins the Disabled/Down/Highlight/Up family) — with text in `GameFontDisable` (0.5 grey); the blank was that silver file streaming from disk on the session's first state swap. (Three interim emulations — desaturation+dim, a disabled-atlas overlay, and grey-text-on-normal-art from misreading 130824 as the normal art — each failed a side-by-side screenshot against Cancel Auction and are all removed.) Final fix: the button uses the **real `Disable()`/`Enable()`** — fully native art and text, per the suite's native-first philosophy — and at build time it flips Disable→read→Enable synchronously (no frame renders in between), records the file(s) the template swaps into its slices, and parks 1px 5%-alpha textures on them so the disabled art renders — and therefore streams — from AH open onward, seconds before any real disable can occur. Sole residual: opening the AH mid-cooldown on a cold client can show the silver fading in once at open; a mid-interaction flip can no longer blank. Verified in-game (cold client restart): the greyed button is now pixel-identical to Cancel Auction with no blank. `/ah btnprobe` is retained as a permanent diagnostic alongside `/ah find` and `/ah check`. (`UI/ScanButton.lua`, `Core.lua`)
- `VeritasUI_AuctionHouse` — **a scan failure during the gear-residue finalize phase no longer reports "Scan failed — Prices were not updated".** Since v1.8.1 the main results are committed (and the 15-minute floor started) *before* the finalize phase, so that message was false on both counts for a post-commit error — and the floor blocked the "try again shortly" it suggested. The driver now records the phase-1 commit (`mainCommit`) and, on a post-commit coroutine error, reports the scan as complete with the committed counts (only late gear residue is lost); a pre-commit error still reports the genuine failure. Finalize counters are also cleared on the error path. (`Replicate.lua`)

### Documentation
- `README.md` — **two stale feature descriptions corrected:** Zone Quests now describes the v1.7.14 per-POI `mapID` location filter (the "directional prefix stripping, bidirectional substring matching" machinery it named was removed in v1.7.14), and the Auction House sell strip now says **Shift**-Right-click to hide (changed in v1.9.0; a bare right-click is deliberately ignored).
- `VeritasUI_AuctionHouse` — **two contradictory/stale comment blocks corrected before they cause a wrong "fix":** `Tooltip.lua`'s header still claimed the coin fontstring is parented to UIParent ("never the tooltip") while the code — correctly, per the v1.7.7 fix — parents it to the tooltip; `ScanProgress.lua` still described its "connect" phase as waiting on `AUCTION_HOUSE_THROTTLED_SYSTEM_READY`, a gate removed in v1.8.0 (the phase is zero-length under the synchronous fire path and is kept only as a defensive default). Comment-only; no behavior change.

## [1.9.0] - 2026-07-03

### Added
- `VeritasUI_PriorityRotation` — **"Auto-target next enemy on death" — a per-spec toggle in the rotation Settings tab.** When enabled, holding the rotation key keeps attacking into the next mob the instant your current target dies, instead of stalling until you manually tab. It works by baking a reacquire prefix into each spell step at compile time — `/cleartarget [dead]` drops the corpse and `/targetenemy [noexists]` grabs the nearest enemy, but **only** when you have no target. A live target you picked yourself satisfies neither condition, so it is never overridden: the sole triggers are a target's death or your own tab/click. This is why it can't be replicated with a hand-made macro — the keybind is override-bound straight to the secure button and bypasses the Attack macro's body, so the targeting has to live in the injected step. The toggle is **off by default and stored per spec**, so you enable it only on the characters/specs you want it on. Macro and trinket steps are deliberately left untouched (a macro may carry its own `@mouseover`/`@focus` targeting; trinkets need no target). The added lines are ordinary secure macro commands run through the existing `macrotext` path — no new taint surface. (`Core.lua`, `Profiles.lua`, `Settings.lua`)

### Changed
- `VeritasUI_AuctionHouse` — **hiding an item from the Sell Strip now requires Shift-Right-click instead of a bare right-click.** The strip sits over the bag/sell area where right-clicks are frequent, and a stray click could blocklist the wrong item (recoverable only via `/ah blocked`). Requiring Shift makes hiding a deliberate act; a plain right-click on the strip is now ignored. The tooltip hint updates to match. (`UI/SellStrip.lua`)

## [1.8.1] - 2026-07-02

### Fixed
- `VeritasUI_AuctionHouse` — **the price scan now covers the entire auction house instead of silently discarding over half of it.** Diagnosed live via the new `/ah find` snapshot sweep: ~50% of replicate rows (138k–145k of ~270k) have uncached item links at scan time, and the old per-row logic skipped every one of them — which is why a months-old item (Elixir of Greater Water Breathing) could show a day-old tooltip price while 352 units sat on the AH. Three-part fix: **(1)** cold rows are now keyed directly from the row's own itemID — the field's return position is **auto-calibrated live each scan** (measured at return #17 on Midnight; the documented #15 is wrong) by cross-checking the first 20 link-resolved rows, so a future Blizzard reshuffle can't break it; **(2)** gear rows (whose key needs the loaded link for item level) queue record loads and are re-read in **budget/quiescence-guarded retry passes** matched to the measured ~1k records/3s streaming rate — verified draining 14,809 of 14,809 deferred rows with **0 dropped**; **(3)** a chunk-tail guard re-checks the snapshot row count while draining so late-streamed chunks are never dropped. Result on a live realm: **21,612 items priced from 272,220 rows, up from 7,977** — 2.7× coverage. (`Replicate.lua`, `Database.lua`)
- `VeritasUI_AuctionHouse` — **a scan's main results are now committed (and the 15-minute floor started) the moment row processing finishes**, before the gear-residue retry phase. Closing the AH mid-finalize no longer discards the whole scan; late gear resolutions commit incrementally per retry pass. (`Replicate.lua`)
- `VeritasUI_AuctionHouse` — **the Scan button no longer loses its backdrop for a second on the session's first press.** The template's separate disabled-state texture streams from disk on first render; the disabled state now reuses the already-streamed normal art, desaturated and dimmed, so the swap can never outrun the texture streamer. (`UI/ScanButton.lua`)

### Added
- `VeritasUI_AuctionHouse` — **"Finalizing gear… N/M" live counter phase on the scan progress bar.** After the 1→100% row drain, scans with cold gear residue enter a finalize phase (up to ~45s); the bar shows honest resolved/total counts ticking up instead of freezing at 100% (or inventing a percentage with no denominator — the phase can end early on quiescence, so counts are the truthful display). (`UI/ScanProgress.lua`, `Replicate.lua`)
- `VeritasUI_AuctionHouse` — **`/ah find <shift-clicked item>` diagnostic**: sweeps the last replicate snapshot still in client memory for that item and reports each matching row's count, buyout, link state, and derived key, plus the snapshot-wide nil-link total — the tool that discriminated "absent from server data" vs "present but skipped" and cracked this whole class of bug. (`Replicate.lua`, `Core.lua`)

### Internal
- `VeritasUI_AuctionHouse` — Scan button centered between the money frame and the scan bar (equal 14px gaps).
- `PROBE_LIBRARY_AND_REFERENCE.md` — recorded the five hard-won replicate facts (itemID at return #17, ~50% nil-link rate, ~1k/3s record streaming, links self-loading on request, snapshot buffer surviving until `/reload`).

## [1.8.0] - 2026-07-02

### Added
- `VeritasUI_AuctionHouse` — **a "Scan" button on the Auction House frame, now THE way to run a price scan.** It sits in the bottom band right of the money frame (present on the Buy, Sell, and Auctions tabs alike), height-matched and aligned to the native Cancel Auction button. It shows a live state: **"Scan"** when ready, a **mm:ss countdown** during the 15-minute cooldown, **"Retry Scan" (enabled)** during the pre-data wait, and **"Scanning…" (disabled)** only while rows actually drain. The OnClick fires `C_AuctionHouse.ReplicateItems()` **synchronously inside the hardware-event execution context** — Auctionator's model, whose click-fired scan never exhibited the first-open hang our event-fired auto-scan did. The button doubles as hung-scan recovery: clicking "Retry Scan" clears a fired-but-never-arrived request and re-fires; a scan actively processing rows is never interrupted. (`UI/ScanButton.lua`, new; `Replicate.lua` `StartManual`)

### Removed
- `VeritasUI_AuctionHouse` — **auto-scan on Auction House open is removed.** It fired the replicate request from the `AH_OPEN` event path, which is where the first-open-of-session scan hang lived (the request goes out, `REPLICATE_ITEM_LIST_UPDATE` never arrives, and only closing/reopening the AH recovers — three weeks of falsified candidate fixes: throttle-ready gate v1.7.9, cold-edge settle delay, one-shot and bounded retries). All scans are now user-initiated via the Scan button or `/ah scan`. The `autoScan` settings checkbox is removed and the orphaned saved-vars key is dropped on next login. Tooltip prices persist across sessions in the price database, so day-to-day tooltip use is unchanged between scans.
- `VeritasUI_AuctionHouse` — **the experimental pre-fire gates are stripped** (`FireWhenReady` throttle-readiness gate, `FireAfterSettle` cold-edge delay, `FireWhenBrowseReady` browse-readiness gate). Live captures falsified their premises: `[FIRE STATE]` showed `throttleReady=true` and `hasFullBrowse=true` at the fire moment of a fresh login's first open, and the AH is fully usable (browse/buy/sell) during a scan hang, so no client-side readiness signal distinguishes a doomed request from a good one. `Start()` and the button's `StartManual()` are now the same direct, synchronous fire path. (`Replicate.lua`)

### Fixed
- `VeritasUI_QualityOfLife` — **item-level overlays now appear on all bank/Warband Bank items on the first open of a session.** Previously the first open showed ilvls on only a few items (the ones already in the client's item-data cache); flipping tabs "fixed" it because the redraw re-queried after the server had streamed the records in. The overlay code asked `GetDetailedItemLevelInfo()` once at button-draw time and permanently hid the overlay on a nil answer. A nil on equippable gear now queues a one-shot `ItemMixin:ContinueOnItemLoad` retry that re-processes that specific button the moment its item record arrives, with a reuse token so a button reassigned to a different item ignores the stale callback. (`QualityOfLife.lua`)

### Internal
- `VeritasUI_AuctionHouse` — replicate retry threshold raised **10s → 60s** (`REPLICATE_RETRY_DELAY`), above the measured healthy first-event latency of ~28–40s (re-confirmed 26.5s in a live capture this session). At 10s the "request was dropped; retrying" line fired inside the normal response window on every healthy scan — a misdiagnosis that muddied three weeks of traces. At 60s, a retry means a real drop. (`Replicate.lua`)
- `VeritasUI_AuctionHouse` — the debug-gated `[FIRE STATE]` snapshot (throttle-ready / full-browse / replicate-count / owned-count at the exact `ReplicateItems()` moment) is retained for diagnosing any future first-open hang under `/run VeritasUI.debug = true`; the invalid `GetNumBrowseResults` probe field was dropped.

## [1.7.17] - 2026-06-27

### Fixed
- `VeritasUI_AuctionHouse` — **auction-price tooltip coin column now aligns pixel-perfectly across operating systems.** The first coin digit of the `Auction:` line sits directly under the first digit of the native `Sell Price:` line on both macOS and Windows. Previously the column position was a hardcoded constant (`COIN_COLUMN_X = 59`) — the rendered px width of the native `"Sell Price: "` prefix, measured once on macOS. macOS and Windows rasterize the same FRIZQT__/12 glyphs to slightly different pixel widths, so the baked constant drifted: sub-pixel on macOS (where it was measured), ~1px on Windows. The column is now **measured live at render time** via `GetStringWidth()` of the native prefix string in the actual tooltip line font, so each OS self-corrects — the same principle already used to copy the live label font (rather than trusting a stored value). `COIN_COLUMN_FALLBACK = 59` is retained for the measure-failed path; `COIN_COLUMN_NUDGE = 0` added as an optional manual fine-tune. Confirmed pixel-perfect on Mac and PC. (`Tooltip.lua`)

### Internal
- Verified during this session that **healthy first-event scan latency is ~28–40s+**, not the ~2–5s the v1.7.16 changelog note speculated. Captured trace from a live scan: `time-to-first-event=27.8s`, `total=32.1s` for 268,154 auctions → 8,163 items, with the first request dropped and rescued by the v1.7.9 10s retry. This means the **10s retry threshold fires inside the normal response window** — it is not detecting a drop, it re-fires while the first request is still legitimately in flight. The planned bounded-retry fix must therefore also **raise the threshold well above ~40s**, gated on `co == nil`, before it is correct. Still deferred pending a captured day-boundary *hang* trace (the healthy baseline is now in hand).

## [1.7.16] - 2026-06-27

### Internal
- `VeritasUI_AuctionHouse` — **the debug-gated replicate trace now logs one line per scan instead of one per event pulse, and reports scan timing.** Blizzard streams the auction snapshot in chunks and fires `REPLICATE_ITEM_LIST_UPDATE` once per chunk; the existing trace printed on every pulse (it sits before the `co`-guard), so a real scan flooded chat with `(scanning=true, co=true)` lines and buried the first arrival — the one line that matters for diagnosing the first-scan-of-session hang. A per-scan `firstEventLogged` guard now collapses the trace to a single line on the first pulse, reporting `time-to-first-event = GetTime() - fireTime` (the request→first-pulse latency; a healthy arrival is ~2–5s, which is the figure that should set any retry threshold). A companion line at scan completion reports `total=<fire→drain-complete>s` plus committed/row counts, so a slow *start* (server/readiness) is distinguishable from a slow *drain* (dataset size). `fireTime` is stamped in `DoFire()` at the actual `ReplicateItems()` moment and `firstEventLogged` is re-armed there per attempt. Logging only — no change to scan, retry, or guard behavior. Enable with `/run VeritasUI.debug = true`. (`Replicate.lua`)

### Known issues
- The **first-scan-of-session hang** (request issued, no `REPLICATE_ITEM_LIST_UPDATE` ever arrives; a `/reload` clears it) is **not fixed in this release** — only made cleanly measurable. The v1.7.9 mitigation (FireWhenReady + a single 10s retry) arms exactly **one** retry, fired directly rather than through `DoFire()`, so it never re-arms; a double-dropped request defeats it and the scan waits indefinitely with no failure path (the v1.7.6 watchdog removal left nothing to escalate to). The planned fix — a bounded-repeating retry gated on `co == nil`, capped at N attempts, then `AH_SCAN_FAILED` — is deferred pending a captured `time-to-first-event` measurement from this build, so the threshold is set from data rather than a guess.

## [1.7.15] - 2026-06-27

### Added
- `VeritasUI_AuctionHouse` — **a live progress indicator for the price scan, mounted in the empty band to the right of the Auction House money frame so it is visible on the Buy, Sell, and Auctions tabs alike.** Previously the auto-scan ran invisibly — you waited, with no feedback, until the "Scan complete" chat line. The scan already tracked a 0–1 `progress` value and broadcast its lifecycle on the event bus (`AH_SCAN_START` / `AH_SCAN_COMPLETE` / `AH_SCAN_FAILED`), but nothing consumed it on screen; the readout is a pure view subscribed to those existing events, so no scan logic changed. It is deliberately **two-phase** because only one phase has a knowable percentage: while waiting for the server snapshot (`REPLICATE_ITEM_LIST_UPDATE`, an unbounded wait with no progress signal by design) it shows an indeterminate animated sweep with a phase label and a live elapsed timer — "Connecting… (Ns)" before the throttle system is ready, then "Requesting auctions… (Ns)" after `ReplicateItems()` fires — and only once row-processing begins does it switch to a real determinate fill, "Scanning… N%", climbing 1→100%. A percentage is never invented for the wait. The bar uses the native player-health-bar fill atlas (`UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health`) and the `auctionhouse-itemheaderframe` frame art to match the native look, is centered against the atlas's visual cavity, and auto-hides shortly after a terminal message. Frame level is set by a relative bump off `AuctionHouseFrame`, not an absolute value (absolute `SetFrameLevel` does not stick on AH children). (`UI/ScanProgress.lua`, new)

### Fixed
- `VeritasUI_AuctionHouse` — **the sell strip no longer flickers and reshuffles when you open the Sell tab.** `Refresh()` was gated on the strip being *visible*, so item collection only began the instant you clicked Sell; the first scan then hit a cold item cache and, as `GET_ITEM_INFO_RECEIVED` events streamed in and the list re-sorted on each one, items visibly appeared, vanished, and shifted under the cursor — so a just-clicked item could disappear before it loaded. Collection is now gated on the Auction House *session* (`AH.isOpen`) instead of strip visibility, and a warm pass runs on `AH_OPEN`. Because `Render()` is safe on a hidden frame, the bag is collected and the cache-warm churn settles off-screen while you are still on the Buy tab; by the time you switch to Sell the list is already complete and stable, matching how established sellers (e.g. Auctionator) behave. Bag scanning still does not occur outside an open Auction House. (`UI/SellStrip.lua`)
- `VeritasUI_AuctionHouse` — **the tooltip "Auction:" price line now matches Blizzard's 12.0.7 tooltip styling exactly (font, coin size, and column alignment).** In 12.0.7 Blizzard moved the native "Sell Price:" line off the `MoneyFrame` widget to an inline body-font text line and restyled it; our coins were still pinned to `NumberFontNormalRight` (ArialN / 14 / outline), which no longer matched. The native line was confirmed by live introspection to be the tooltip body font (`FRIZQT__` / 12 / no-outline); our coins now copy the live font from our own label line at render time, so they track the body font per-tooltip and across any future Blizzard restyle (what the old font-object pin only claimed to do). The coin column position (`COIN_COLUMN_X`) was set to the probe-measured rendered width of the native "Sell Price: " prefix (59 px) so our first digit sits directly under the native first digit, and the inline coin markup was matched byte-for-byte to native (`|A:coin-gold:14:14:2:0|a` — the inherited "13×13" code comment was wrong; native is 14×14 with a `2:0` baseline offset). (`Tooltip.lua`)

### Internal
- `VeritasUI_AuctionHouse` — **added an additive `AH_SCAN_REQUESTED` event**, fired in `Replicate.lua` immediately after `C_AuctionHouse.ReplicateItems()` goes out, marking the transition from the throttle/connect wait to the snapshot wait. It carries the auto/manual flag and changes no scan behavior; it exists so the new progress view can distinguish its two waiting phases. (`Replicate.lua`)

## [1.7.14] - 2026-06-21

### Fixed
- `VeritasUI_ZoneQuests` — **quests are now filtered by their actual objective location instead of the quest-log section header, fixing both missing in-zone quests and bleed-in from neighbouring zones.** The previous logic matched a quest's quest-log **header** string against the current zone name. Midnight's quest log groups many quests under non-geographic activity headers (Void Assaults, Dungeon, Meta, Abundance), so quests physically in the current zone but filed under such a header were wrongly hidden — e.g. standing in Silvermoon City, "Stalkers of the Stars" (in Murder Row, filed under "Void Assaults") never appeared. The module now derives the current-zone quest set from `C_QuestLog.GetQuestsOnMap` on the player's best map (walking up to the closest map level that has quests), and keeps a quest only when its **per-POI `mapID`** belongs to the current zone or a descendant sub-area. This correctly surfaces activity-headered quests that are genuinely local while rejecting sibling-zone bleed-in (e.g. Zul'Aman quests whose POIs draw inside the Eversong Woods map carry `mapID` 2536, a sibling, and are excluded; Silvermoon City quests carry `mapID` 2393, a child of Eversong, and are kept). Verified in-game across Eversong Woods, Zul'Aman, Voidstorm, and Harandar, including correct re-filtering on every zone transition. The "Always Show" pin toggles (Campaign / Important / Legendary / Meta / Daily & Weekly) and super-track preservation are unchanged and continue to override the zone filter, so a pinned quest type still shows everywhere regardless of zone. (`ZoneQuests.lua`)

### Internal
- `VeritasUI_ZoneQuests` — removed the legacy header-string matching machinery (`BuildZoneNameSet`, `HeaderMatches`, the directional-prefix stripper, and the zone-name cache) now that location is determined purely from map IDs. `/zq debug` rewritten to report the current best map, the resulting zone quest set, and a per-quest `zone` / `pin` / `dropped` verdict. Two map-based approaches were tried and rejected before landing on the per-POI `mapID` filter: walking map descendants/ancestors of the current zone (over- or under-showed depending on direction), and `C_QuestLog.GetQuestUiMapID` / global `GetQuestUiMapID` (returns a quest's anchor/hub map, not its objective zone — observed returning Silvermoon City for Voidstorm and Eversong quests alike, so it cannot distinguish a quest's real location). (`ZoneQuests.lua`)

## [1.7.13] - 2026-06-20

### Internal
- **Audit hardening pass (static + dynamic code audit; no gameplay behavior change).** A comprehensive seven-module read produced 0 critical/high logic findings; the codebase was confirmed solid. Applied changes are cleanup and hardening only:
  - **Dead code removed:** the unreferenced `AppendSpell` function in `Editor.lua` (orphaned since the v1.5.1 drop-zone removal), plus ~15 unused localized-global upvalues across `Lib.lua`, `AdvancedOptions/*`, `AuctionHouse/Core.lua`, `AuctionHouse/Database.lua`, `AuctionHouse/UI/SellStrip.lua`, `PriorityRotation/Core.lua`, and `QualityOfLife.lua`. Behavior-neutral; verified in-game with zero Lua errors.
  - **`VeritasUI_QualityOfLife`** — **`IsAddOnLoaded` now uses the modern `C_AddOns.IsAddOnLoaded` path** with a legacy-global fallback (mirrors `AuctionHouse/UI/SellStrip.lua`), future-proofing the `/way` TomTom-conflict check against removal of the bare global. Behavior identical on 12.0.7. (`QualityOfLife.lua`)
  - **`VeritasUI_PriorityRotation`** — **`/pr diag` now reports the live patch version** via `GetBuildInfo()` instead of a hardcoded "12.0.5" string, so the diagnostic header and `/pr help` line never go stale on a patch bump. The `table.freeze()` probe line dropped its stale "(12.0.5 confirmed)" parenthetical (it reports current availability, not a version claim). (`Core.lua`)
  - **`VeritasUI_PriorityRotation`** — **`/pr test` output unified onto `VUI.Print`**, so every line carries the `[Priority Rotation]` prefix (matching the earlier `/pr diag` and `/pr status` conversions). (`Core.lua`)
  - **Stale comments corrected:** `AuctionHouse/Tooltip.lua` comments that described the removed `SetTooltipMoney` approach now match the owned-fontstring render path (guards against reintroducing the v1.7.6 Secret-Value crash); `AdvancedOptions/Browser.lua` `KNOWN_CVARS` policy line-reference corrected; `AuctionHouse/Replicate.lua` "temp" diagnostic relabeled as a permanent debug aid (its first-scan-hang bug was fixed in v1.7.9).
  - **`SELL_BATCH` confirmed at 11** (`QualityOfLife.lua`) — verified working in-game on 12.0.7; the comment was corrected to record this as intentional, superseding the conservative 9 from the v1.3.14 era. No code change to the value.
  - **Added `.luacheckrc`** — a WoW-aware luacheck config (Blizzard global set, accidental-global / unused-variable / unreachable-code detection). luacheck run: 0 errors; warnings reduced from 80 to 24, the remaining 24 being intentional long display-string lines (no real issues suppressed).

## [1.7.12] - 2026-06-20

### Fixed
- `VeritasUI_AuctionHouse` — **the sell strip now shows reagent-bag items again (the module's primary purpose), reversing the v1.7.11 exclusion.** v1.7.11 stopped scanning bag 5 (the reagent bag) in response to a `CanPostItem` crash ("attempt to compare nil with number"). New evidence reframes that fix: the captured stack trace (`Blizzard_AuctionHouseSellFrame.lua:477` → `CanPostItem` → `CommoditiesSellFrame` `StartPost`/`PostItem`) shows the crash occurred **entirely inside Blizzard's own commodity-post code, with no VeritasUI frame on the stack**, and fired on the native "Create Auction" click — not on our `SetPostItem` load as the v1.7.11 commit message stated. The crash was reachable from Blizzard's native Sell flow too (loading a reagent natively and posting), so excluding bag 5 only removed our shortcut to a Blizzard-side bug, at the cost of the feature the module exists for. The crash **no longer reproduces on the current client by any path** (native sell from reagent bag, or sell-strip post) — most likely a 12.0.7 launch-week issue (the patch landed ~2026-06-15, the crash was hit 2026-06-17) since resolved server-side, though that attribution is probable, not confirmed. `CollectItems` now scans bags 0–5 again. (`UI/SellStrip.lua`)

### Added
- `VeritasUI_AuctionHouse` — **the sell strip now hides Warband-bound-until-equipped equipment, which cannot be auctioned.** Such items read `isBound = false` (they bind on equip) and carry a vendor sell price, so the existing "unbound + sellable" predicate wrongly admitted them — the strip could show a Warband weapon that can't be posted while hiding genuinely sellable items. Items are now rejected when `C_Item.IsBoundToAccountUntilEquip` returns true. This was verified by in-game probe (item 249677 Twinthorn Wildglaive) as the only clean discriminator: Warband-until-equip gear reports `bindType = 2`, identical to ordinary sellable BoE, so `bindType` cannot distinguish them. The check is conservative — it only rejects on a definitive `true`; on any error or unresolved result the item is shown, so a legitimate sellable is never hidden on doubt. Commodities (reagents, potions, dyes), ordinary BoE gear, and transmog "junk" armor all continue to appear. (`UI/SellStrip.lua`)

## [1.7.11] - 2026-06-17

### Fixed
- `VeritasUI_AuctionHouse` — **clicking a sell-strip item no longer throws a Lua error ("attempt to compare nil with number" in `CanPostItem`).** The bag scan in `CollectItems` looped over bags 0–5; bag 5 is the reagent bag, and Blizzard's AH `CanPostItem` → `StartPost` path crashes on reagent-bag items (nil deposit cost / missing category data). This bug was latent in prior versions because reagent-bag items were silently dropped as cache misses on first Sell-tab open and never appeared in the strip. The v1.7.10 cache-fill fix correctly populated them for the first time, making them clickable and surfacing the crash. Fix: `CollectItems` now iterates bags 0–4 only; the reagent bag (5) is excluded entirely. (`UI/SellStrip.lua`)

## [1.7.10] - 2026-06-16

### Fixed
- `VeritasUI_AuctionHouse` — **sell strip now populates all sellable items on first open of the Sell tab, not just the one or two already in the item cache.** `CollectItems` calls `C_Item.GetItemInfo` to read each item's vendor sell price; on the first Sell-tab open of a session most items aren't in the client cache yet, so `GetItemInfo` returns `nil` and those items were silently excluded — only previously-hovered or recently-used items (already cached) passed through. Clicking one item loaded it into the Sell form, which triggered cache population, and a subsequent `BAG_UPDATE_DELAYED` then revealed the rest — the visible symptom. Fix: when `GetItemInfo` returns `nil` (clean cache miss, distinct from a pcall error), the itemID is added to a `state.pending` set and `C_Item.RequestLoadItemDataByID` is called to actively request the data. The loader frame now also handles `GET_ITEM_INFO_RECEIVED`; when a pending itemID's data arrives, a 0.1s debounce timer (`ScheduleRefresh`) collapses any burst of incoming cache fills into a single `Refresh()` call. The strip populates fully within a fraction of a second of first open. (`UI/SellStrip.lua`)

## [1.7.9] - 2026-06-16

### Fixed
- `VeritasUI_AuctionHouse` — **first-Auction-House-visit-of-a-session scans no longer hang.** The v1.7.8 `FireWhenReady` fix correctly deferred until `AUCTION_HOUSE_THROTTLED_SYSTEM_READY`, but the server could still silently drop the `ReplicateItems()` call even after that event — confirmed in-game on day 2 of testing: the throttle system reported ready, `ReplicateItems()` fired, but `REPLICATE_ITEM_LIST_UPDATE` never arrived and the scan sat at `0%` indefinitely. Root cause: the server needs a moment beyond throttle-system readiness to accept replicate requests on the very first AH open of a session. Fix: after each `ReplicateItems()` call, a `REPLICATE_RETRY_DELAY = 10` second timer arms. If `REPLICATE_ITEM_LIST_UPDATE` arrives within that window (the normal path), the timer is cancelled immediately — no effect. If the event has not arrived after 10 seconds, the request is confirmed dropped (a genuine arrival would appear within 2–5 seconds) and `ReplicateItems()` is called again. The retry guard checks `AH.isOpen`, `scanning`, and `co == nil` before firing, so it can only trigger when the coroutine genuinely hasn't started. Timer is also cancelled on `AH_CLOSED`. (`Replicate.lua`)

## [1.7.8] - 2026-06-15

### Changed
- **Interface bumped to `120007` for the WoW 12.0.7 patch** (all seven module TOCs).

### Fixed
- `VeritasUI_AuctionHouse` — **the tooltip "Auction:" coins no longer leak onto player/NPC and other non-item tooltips.** Our coin display is a fontstring parented to the tooltip that persists between hovers; it was only hidden in the item-tooltip post-call, which never runs for unit/spell/etc. tooltips — so after hovering a priced item the stale coins appeared on the next player tooltip (e.g. a player showing the last item's price). It's now hidden whenever the tooltip is cleared (every rebuild, all content types); priced items re-show it in the same rebuild, so there's no flicker. (`Tooltip.lua`)

### Fixed (candidate — pending in-game verification)
- `VeritasUI_AuctionHouse` — **first-Auction-House-visit-of-a-session scans should no longer hang.** Confirmed cause: on the first AH open since login, the auto-scan fired its data request before Blizzard's throttle/message system was ready; the request was silently dropped, no data event arrived, and the scan sat at 0% until a `/reload` (re-opening the AH in the same session worked). The request is now deferred until the throttle system reports ready (`AUCTION_HOUSE_THROTTLED_SYSTEM_READY`) instead of firing too early. Defensive: if the readiness API is unavailable it falls back to firing immediately (prior behavior), and it uses an event wait, not a timeout. **This fix could only be tested on a fresh login, so it ships unverified for live confirmation;** the function and event were confirmed to exist in-client beforehand. (`Replicate.lua`)

## [1.7.7] - 2026-06-14

### Fixed
- `VeritasUI_AuctionHouse` — **the tooltip "Auction:" price line no longer reverts to the wrong font and old coin art (and no longer leaves a stray gap), including inside Delves, on login, and after picking up new bag items.** The v1.7.6 fix rendered the price through a private `TooltipMoneyFrameTemplate` driven by `MoneyFrame_Update`, on the belief that feeding it our own plain-integer price made it crash-safe. That was wrong: `MoneyFrame_Update` does arithmetic on an **internal** coin-column width (`silverWidth`) that becomes a **Secret Value** in instanced content (Delves/M+/raids), so it threw (`MoneyFrame.lua:340`) regardless of our price — and the pcall fallback quietly swapped in `GetCoinTextureString` text coins, which is the "old coins / wrong font" you saw. The price is now rendered **without ever calling Blizzard's money code**: a plain "Auction:" label line (matching the native "Sell Price:" label font) plus the coins drawn in a fontstring **we create and own**, parented to the tooltip, using the modern `Coin-Gold/Silver/Copper` atlases as inline `|A|` markup and the native money number font (`NumberFontNormalRight`). Because it's pure text and an owned region, there is no Blizzard money math to hit a Secret Value — verified rendering correctly in a Delve. (`Tooltip.lua`)
- `VeritasUI_AuctionHouse` — **the "Auction:" coins now line up under the native "Sell Price:" coins.** Our owned coin fontstring is placed at a fixed column (`COIN_COLUMN_X`) from the label so the first digit sits under Sell Price's first digit, instead of being right-justified to the tooltip edge. The owned fontstring is hidden on every tooltip rebuild, so non-priced items never show stale coins from a previous hover. (`Tooltip.lua`)

### Internal
- `VeritasUI_AuctionHouse` — removed the temporary `/ah probe` diagnostic (its job — capturing the native coin atlases + money font specs — is done; those values are now baked into `Tooltip.lua`). A temporary `REPLICATE_ITEM_LIST_UPDATE` debug-trace line is intentionally **retained** in `Replicate.lua` to help diagnose a separate, still-open issue (first-Auction-House-visit-of-the-day scans can hang until a `/reload`); it only prints under `VeritasUI.debug`.

## [1.7.6] - 2026-06-13

### Fixed
- `VeritasUI_AuctionHouse` — **item tooltips no longer trigger a Lua error.** v1.7.2 switched the tooltip "Auction:" price line to the global `SetTooltipMoney` to pixel-match the native "Sell Price:" line. That function reuses Blizzard's *shared, pooled* money frame; calling it from our (insecure) addon context tainted that pool, and Blizzard's own Sell Price render then crashed doing arithmetic on a Secret Value (`MoneyFrame.lua:340`, "secret number value … tainted by VeritasUI_AuctionHouse") — item sell-price money is a Secret Value in Midnight. Once the pooled frame was tainted in a session, *every* item hover that drew a sell price threw. The price line now renders through a **private money frame we create and own** (`TooltipMoneyFrameTemplate`), driven by our plain-integer database price — so Blizzard's pool is never touched and its secure render is never disturbed. Same coins, same font as native, no crash. (`Tooltip.lua`)
- `VeritasUI_AuctionHouse` — **the tooltip "Auction:" coins now align under the native "Sell Price:" coins** across every denomination combination. The price frame is shifted so each line's leftmost visible coin lines up: matching-denomination lines (gold↔gold, silver↔silver) align coin-for-coin; mismatched lines (e.g. a silver-only Sell Price vs. a gold Auction price) align at the block's left edge and stay inside the tooltip border. This is self-correcting across any font and value width — no hand-tuned spacing. (`Tooltip.lua`)
- `VeritasUI_AuctionHouse` — **the Sell-tab sellable-items strip now draws a border on *every* item, matching Blizzard's bags.** Previously only Uncommon (green) and above showed a colored edge; Poor (junk) and Common ("general") items had bare icons. Native item buttons border every item — gray on junk and common, colored above — so the strip now does too, using Blizzard's own bag quality palette (`BAG_ITEM_QUALITY_COLORS`). (`UI/SellStrip.lua`)

## [1.7.5] - 2026-06-13

### Fixed
- `VeritasUI_AuctionHouse` — **Auction House scans no longer fail intermittently.** The price scan was failing roughly half the time with "Scan failed." Root cause: a 45-second watchdog (added in v1.7.1 as a well-intentioned safety net) was declaring failure and **discarding the snapshot** when it arrived later than 45s — which a large, queued Auction House snapshot (200k+ rows) frequently does. The watchdog has been removed entirely; the scanner now waits for the data however long it takes, matching the proven model used by established scanners. The genuine "stuck flag" risk the watchdog was meant to address is now handled correctly by resetting scan state on Auction House open/close, with no failure timer. (`Replicate.lua`)
- `VeritasUI_AuctionHouse` — **sell-strip tooltips now update while scrolling.** Previously, scrolling the sellable-items strip with the mouse held still kept showing the first item's tooltip; you had to move off and back. The tooltip now refreshes to whatever item is under the cursor on each scroll (and hides if you scroll onto an empty slot). (`UI/SellStrip.lua`)

### Removed
- `VeritasUI_AuctionHouse` — **the `/ah scan force` option.** Bypassing the 15-minute cooldown just fired a replicate request into the server's own cooldown — a silent no-op that looked like a failure. The cooldown is now always honored, matching how reliable scanners behave. `/ah scan` is unchanged.

### Added
- `VeritasUI_AuctionHouse` — **`/ah check`** diagnostic: shift-click an item after the command to see its stored price, age, and derived database key. Useful for confirming a scan recorded an item correctly.

### Internal
- `VeritasUI_AuctionHouse` — removed an unused `ADDON_NAME` local from five files (kept where actually used).

## [1.7.4] - 2026-06-12

### Fixed
- **Zone Quests login message** — its `/zq` slash command now renders in the same yellow as every other module's command. The other five modules wrap their command in the yellow color code; Zone Quests' was plain (white), an oversight from the v1.7.3 login-message standardization. Purely cosmetic — all six login lines are now visually consistent. (`VeritasUI_ZoneQuests/ZoneQuests.lua`)

## [1.7.3] - 2026-06-12

### Changed
- **Standardized every module's login message** to one consistent format: `[Module] vX.Y.Z loaded — /slash` (and `[Zone Quests] vX.Y.Z active for <zone> — /zq`). Previously some modules printed a version and a slash command while others just said "Loaded. Type /xxx to open settings." with no version. The version is pulled dynamically from `VUI.VERSION`, so these lines stay correct on every future bump. Clean Solo now advertises its short `/cs` alias. (`VeritasUI_AdvancedOptions/Core.lua`, `VeritasUI_AuctionHouse/Core.lua`, `VeritasUI_CleanSolo/CleanSolo.lua`, `VeritasUI_PriorityRotation/Core.lua`, `VeritasUI_QualityOfLife/QualityOfLife.lua`, `VeritasUI_ZoneQuests/ZoneQuests.lua`)

### Documentation / repo housekeeping
- **README brought current** — added the `VeritasUI_AuctionHouse` module (was entirely absent), corrected "six folders" → "seven" in the install steps, refreshed the Clean Solo (added Transparent Chat Background, Fade Action Bars) and Quality of Life (added AFK Screen, Repair Funding option) feature lists, corrected the Advanced Options CVar-enumeration description for Midnight (which removed `C_Console`), and removed a stale third-party-addon reference from the Priority Rotation description.
- **Removed two stale release-zip artifacts** (`VeritasUI-v1.6.32.zip`, `VeritasUI-v1.6.33.zip`) that were committed before `.gitignore` excluded `*.zip`; release zips live only on the GitHub Releases page.

## [1.7.2] - 2026-06-12

Two roadmap items for `VeritasUI_AuctionHouse`, both AH-only; no other module changed. Each verified in-game.

### Added
- `VeritasUI_AuctionHouse` — **auto-scan on Auction House open.** Opening the AH now automatically runs a price scan so tooltip prices stay fresh without typing `/ah scan`. It reuses the same 15-minute cooldown as a manual scan, so it silently does nothing if you scanned recently. A new **"Auto-scan on Auction House open"** checkbox (default on) in the AH settings panel controls it. You get a distinct "Auto-scanning prices…" start message, plus the usual success ("Scan complete — …") or failure message, so you always know whether to keep the window open and whether prices actually refreshed. (`Replicate.lua`, `Core.lua`, `Settings.lua`)

### Changed
- `VeritasUI_AuctionHouse` — **tooltip price line redesigned to match Blizzard's native "Sell Price:" line exactly.** The label is now `Auction:` (was "Auction (each)"), rendered in the same white, same font, and — crucially — using Blizzard's own embedded money frame (`SetTooltipMoney`) so the coin icons are the exact same model and size as the Sell Price coins, with the amount aligned directly beneath them. Previously the line used a right-justified text coin string, which used a different coin texture and font height. Battle-pet tooltips keep a text coin string (their custom frame has no money-frame support). (`Tooltip.lua`)
- `VeritasUI_AuctionHouse` — the scan-failure chat message is now cause-neutral: **"Scan failed — Prices were not updated; try again shortly."** (previously speculated a server cooldown, which the client cannot actually confirm). (`Replicate.lua`, `Core.lua`)

## [1.7.1] - 2026-06-12

Audit/robustness pass over the `VeritasUI_AuctionHouse` module (the v1.7.0 refocus shipped quickly; this is the follow-up quality review). All changes are AH-only; no other module touched. Each item below was verified in-game.

### Added
- `VeritasUI_AuctionHouse` — **battle-pet prices in tooltips.** Caged-pet auction prices were already recorded in the scan database (keyed by species) but never surfaced, because battle-pet tooltips do **not** flow through the item tooltip system. Added the correct hook (`BattlePetToolTip_Show`, which hands us the species id directly) so the "Auction (each)" line now appears on battle-pet tooltips in the AH, bags, and chat links. (`Tooltip.lua`)

### Fixed
- `VeritasUI_AuctionHouse` — **sell strip hardened against Midnight Secret Values.** The bag-scan that builds the sellable-items strip now wraps the bound-check, the `C_Item.GetItemInfo` call, and the vendor-price comparison in the suite's three-pcall pattern (mirroring QualityOfLife's AutoSell). A single problematic item is skipped instead of erroring the whole strip refresh. (`UI/SellStrip.lua`)
- `VeritasUI_AuctionHouse` — **price scan no longer strands on a dropped server response.** Added a watchdog: if `ReplicateItems()` is issued but `REPLICATE_ITEM_LIST_UPDATE` never arrives, the scan state resets cleanly and reports an honest message instead of leaving `/ah scan` permanently reporting "a scan is already running" until the AH is reopened. (`Replicate.lua`)
- `VeritasUI_AuctionHouse` — **a single malformed row no longer aborts an entire price scan.** The per-row read inside the scan coroutine is now pcall-isolated, so one bad row out of a 200k+ snapshot is skipped rather than discarding the whole scan. (`Replicate.lua`)
- `VeritasUI_AuctionHouse` — settings panel no longer depends on cross-frame event-dispatch order to seed its tooltip-toggle defaults (it now seeds them itself before reading them). (`Settings.lua`, `Tooltip.lua`)

### Changed
- `VeritasUI_AuctionHouse` — all `/ah` diagnostic and help output now routes through the standard `VUI.Print` formatter, so every line carries the `[Auction House]` prefix (matching the rest of the suite). (`Core.lua`, `UI/SellStrip.lua`)

### Removed
- `VeritasUI_AuctionHouse` — **dead-code sweep left over from the v1.7.0 Shopping-tab cut.** Removed the orphaned `AH.Money.SanitizePrice` helper (its only caller, the auction-posting path, was cut), a no-subscriber `AH_SCAN_PROGRESS` event broadcast, an unused local, and a global frame name on the strip buttons; scrubbed stale comments that still referenced removed files (`Throttle.lua`, `Search.lua`), a non-existent `/ah search` command, and obsolete development-phase tags. Comment-and-cleanup only — no behavioral change. (`Core.lua`, `Money.lua`, `Replicate.lua`, `Database.lua`, `Settings.lua`, `Tooltip.lua`, `UI/SellStrip.lua`)

## [1.7.0] - 2026-06-11

### Changed
- `VeritasUI_AuctionHouse` — **major refocus.** The module is no longer a "modernized Auctionator." Direct comparison against Midnight's native Auction House showed the planned Shopping/Buy/Cancelling clone duplicated functionality Blizzard now ships (category sidebar, sortable columns, Filter flyout with Required-Level/rarity/toggles, drill-down + Buy Now, Favorites-as-shopping-list). The module is refocused to do only what native does **not**: a price database feeding tooltip prices, plus the one genuinely-missing convenience — Auctionator's sellable-items bag panel, rebuilt natively on the default Sell tab.

### Added
- `VeritasUI_AuctionHouse` — **Sell strip (`UI/SellStrip.lua`)**: a horizontal strip of your sellable bag items mounted in the empty band under the native Sell tab's "Create Auction" button.
  - **Click an icon → the item loads into Blizzard's own Sell form** via `AuctionHouseFrame:SetPostItem(ItemLocation)` (the same path the native bag right-click uses). You verify, then click Blizzard's own Create Auction. **We never make a protected call — Blizzard owns the post entirely**, proven taint-clean in-game (populate-from-addon-code → native post produced no `ADDON_ACTION_BLOCKED`).
  - **Sellable predicate:** unbound items with a vendor sell price (verified to match native auctionability across the test bags). **Right-click an icon to hide it** from the strip (per-itemID blocklist; `/ah blocked` to list, `/ah blocked clear` to reset) — for dyes, saved reagents, etc.
  - **Mouse-wheel horizontal scroll** (no arrows). **Loaded-stack desaturation** mirrors Blizzard graying the bag item (hooks `SetPostItem`/`ClearPostItem`, matched by bag+slot, source-agnostic). **Native inset card** behind the icons using the `auctionhouse-itemheaderframe` atlas (the same art as the sell-slot card above). Quality-colored icon borders (`WhiteIconFrame`, no action-button glow) and correctly-sized **Midnight profession reagent-quality tier markers**.
  - The native **Buyout Mode checkbox is hidden** (it occupied the strip's space; the user always sells in buyout mode).
- `VeritasUI_AuctionHouse` — kept from earlier phases: the full-AH price scan (`/ah scan`), the native price database, and **auction prices in item tooltips** (the module's primary native-beating value).

### Removed
- `VeritasUI_AuctionHouse` — **the entire Shopping tab and its dependencies** (`Search.lua`, `Buy.lua`, `Shopping.lua`, `Throttle.lua`, `UI/TabInject.lua`, `UI/ShoppingTab.lua`, `UI/ShoppingCells.{lua,xml}`, `UI/FilterFlyout.lua` — ~4,200 lines). These cloned native Buy-tab functionality and were retired with the refocus above. The techniques (clean tab injection, taint-clean protected writes, live-client introspection) are preserved in git history and were reused where relevant. `Throttle.lua` was removed as dead code once no live AH queries remained (the price scan uses `ReplicateItems` directly). Orphaned `shopping` saved-variable data self-cleans on load.

## [1.6.52] - 2026-06-10

### Added
- `VeritasUI_AuctionHouse` — **Phase 4 Layer 4: the Shopping tab's Filter control** — a clean-room reproduction of Blizzard's native Buy-tab Filter button + filter flyout, extended with our own filters, all in one flyout (no tab-hopping). New file `UI/FilterFlyout.lua`.
  - **Reskinned Filter button** replacing the old "Search Options" stub. Built from the verified native dropdown-button atlas family (`common-dropdown-b-button` + `-hover`/`-pressed`/`-open`/`-disabled`), `GameFontNormal` label, with the native script-driven state swaps (OnEnter/OnLeave/OnMouseDown/OnMouseUp). Hover highlights in every state including while the flyout is open; the button swaps to the `-open` art while the flyout shows. Frame sits on the same grid as its Search / Add To List siblings (visible pill height is decoupled onto the background texture so alignment and height are independent).
  - **Native-faithful flyout** — `common-dropdown-bg` panel, `GameFontHighlight` section headers, texture-built checkboxes (`common-dropdown-ticksquare` + `common-dropdown-icon-checkmark-yellow`), and `common-search-border-*` numeric fields. Sections, top→bottom: **Level Range** · Uncollected/Usable/Current Expansion Only · **Equipment:** Upgrades Only · **Rarity** (7 quality checkboxes, quality-colored) · **More Filters:** Item Level, Max Buyout. Reproduced clean-room (our own frame/state); the native flyout frame is never reused.
  - **Filters split by mechanism (verified against `Enum.AuctionHouseFilter`, 14 members):** Level Range → `query.minLevel/maxLevel`; the four toggles (`UncollectedOnly=1`, `UsableOnly=2`, `CurrentExpansionOnly=3`, `UpgradesOnly=4`), `ExactMatch=5`, and the seven qualities (6–12) are all **server-side** `filters[]` members passed to `SendBrowseQuery`. Item Level + Max Buyout are **client-side** post-filters on the result rows (no native query field exists for them).
  - **Dynamic, like Blizzard's:** changing any server-side control re-runs the current search (single term or whole-list) with the new filters, debounced 0.3s so toggling several boxes collapses into one query; client-side controls re-filter the shown rows instantly with no re-query. Clicking outside the flyout closes it (via `GLOBAL_MOUSE_DOWN`, non-intercepting — your click still lands).
  - **Result-row tooltips** — hovering a results row now shows the item tooltip (prefers a true item hyperlink, falls back to `SetItemByID`), so items can be inspected without drilling in.

### Removed
- `VeritasUI_AuctionHouse` — **Import / Export / Export Results buttons** (were honest stubs). For a single-user, ~1-character account they serve no purpose: same-account characters already share shopping lists via the account-wide saved variable, the `WTF/.../SavedVariables/VeritasUI_AuctionHouse.lua` file already serves as the backup/transfer artifact, and a clean VeritasUI-native export blob would only round-trip into another VeritasUI install (a cross-account/sharing case that does not apply). The results panel reclaims the freed space; the New List button remains the sole bottom-left control.

## [1.6.51] - 2026-06-07

### Added
- `VeritasUI_AuctionHouse` — **Phase 4 Layer 3: Shopping Lists persistence, Recent Searches, and whole-list multi-term search.** The Shopping tab's left panel is now fully functional (previously stubbed).
  - **`Shopping.lua` — new persistence layer (UI-agnostic, mirrors `Search.lua`'s separation).** `AH.Lists` (create / delete / rename / add-item / remove-item) and `AH.Recent` (move-to-top, deduped, capped at 20), both over a new account-wide `AH.db.shopping = { lists, recent }` container. Terms are stored normalized (plain item name via `AH.Search.NormalizeSearchTerm`) so a shift-clicked link and a typed name dedupe identically. No `dbVersion` bump — this is UI state, not price-DB layout, so `InitDB`'s nil-seed upgrades any pre-Layer-3 saved var transparently with no migration.
  - **Shopping Lists left panel** — a `WowScrollBoxList` rendering saved lists as expandable headers (item count shown) with their search terms indented beneath. Any number of lists may be expanded at once. Expansion is signaled the native AH Buy-tab way — a gold selection band on the expanded header (`auctionhouse-ui-row-select`) plus the indented child rows — with no arrow glyph.
  - **Recent Searches left panel** — every search (button, Enter, shift-click, list-item click) is recorded newest-first and persists across `/reload` and relog.
  - **Whole-list multi-term search (`AH.Search.SearchList`).** Clicking a list header runs every term in the list sequentially through the existing throttle-queued browse engine (in a new `silent` mode that suppresses single-search events), accumulating results deduped by itemKey-string and keeping the lowest price seen per item. Progress is surfaced via a new `AH_LISTSEARCH_*` event family; results fill the same native results table.
  - **New List / Add To List wiring.** New List opens a native `StaticPopup` (Enter-to-create now works, routed through `StaticPopup_OnClick`). Add To List adds the current search term to the selected list. Left-row left-click searches; right-click removes (list deletion via a confirm popup).
  - **Right-click a results row → add that specific item to a list.** A native `MenuUtil.CreateContextMenu` lists each Shopping List (checkbox: checked = already present, click toggles add/remove) plus **New List…** (creates a list and adds the item in one step). Adds the exact item you clicked without retyping its name.

### Fixed
- `VeritasUI_AuctionHouse` — the Add To List button targeted a stale internal field after the multi-expand refactor and would always report "select a list first"; it now correctly targets the selected list.

## [1.6.50] - 2026-06-07

### Added
- `VeritasUI_AuctionHouse` — **Phase 4 Layer 2: the Shopping-tab drill-down + buying.** Clicking a results row now opens an individual-auction detail view modeled pixel-faithfully on Blizzard's native commodity/item buy display, wired to the proven `AH.Buy` engine.
  - **Two-pane drill-down (`UI/ShoppingTab.lua`).** A wide LEFT detail pane (item card + Quantity / Unit Price / Total Price / Buy) beside a narrower RIGHT auction list, each in its own themed inset. The item card uses the real circular icon mask + native item-border ring + quality-colored name on the `auctionhouse-background-buy-noncommodities-header` atlas, with a thin 1px tooltip-style border (not the heavy `InsetFrameTemplate` bevel).
  - **Native banded auction list (no fabricated textures).** Every row draws the verified native atlases — `auctionhouse-rowstripe-1` (full-width row band), `auctionhouse-ui-row-highlight` (hover), `auctionhouse-ui-row-select` (gold selection) — discovered by live-client introspection, not guessed. Price-left / quantity-right, headerless, matching native. Columns size so large gold values and large quantities both fit without clipping.
  - **Cumulative commodity selection.** Clicking row N selects rows 1..N (cheapest through N), highlights them gold, and fills the Quantity box with their summed quantity — the native commodity-buy behavior. "Select-all" (through the last row) uses the server's authoritative `GetCommoditySearchResultsQuantity` rather than the client row-sum; manual typing clears the selection (via the native `OnTextChanged` `userInput` flag). Total Price is a blended fill across price tiers.
  - **Buy Now, both paths, through the real UI.** Commodity: two-step `StartCommodity` → quote → `ConfirmCommodity`. Item: single `PlaceBid` buyout. Both fire from the Buy button's genuine hardware event (never throttle-queued), re-querying after purchase to refresh the list.
  - **Modern quantity input** — three-slice `auctionhouse-ui-inputfield-{left,middle,right}` atlas field (verified native), replacing the legacy beveled `InputBoxTemplate`.

### Changed
- `VeritasUI_AuctionHouse` — **native sort headers on the Shopping results table.** The Price / Name / Available column headers are now interactive, driving Blizzard's own header sort-state protocol (`RegisterHeader` / `SetSortOrder` / `GetSortOrderState` / `UpdateHeaders` against the global `AuctionHouseSortOrderState`), so the genuine native sort arrow and blue hover/active highlight light up exactly as on the Buy/Sell tabs. Click toggles ascending/descending; sort is client-side and stable.

### Removed
- `VeritasUI_AuctionHouse` — retired the Layer-2 development scaffolding now that the real Buy UI supersedes it: the `/ah buytest` validation harness (the OQ#5 taint test, its job done) and the `/ah rowdump` introspection probe. The live `AH.Buy` engine (`StartCommodity` / `ConfirmCommodity` / `CancelCommodity` / `IsActive` / `BuyItem`) is unchanged.

## [1.6.49] - 2026-06-06

### Added
- `VeritasUI_AuctionHouse` — **Phase 4: the Shopping tab (first in-AH UI) + verified protected-buy foundation.** The module's vision was refined this release to **a modernized, clean-room reimplementation of Auctionator** — its feature set (Shopping / Selling / Cancelling) rebuilt on *modern* Blizzard UI (where Auctionator still uses legacy assets), indistinguishable from today's default UI. The earlier "Browse" tab was repurposed into a **Shopping** tab to match Auctionator's model (Auctionator has no Browse tab; it doesn't re-skin Blizzard's native Buy).
  - **`UI/TabInject.lua` — native tab injection.** Injects our own tab into Blizzard's `AuctionHouseFrame`, matching the Buy/Sell/Auctions strip pixel-for-pixel. Our tab button lives under our *own* root frame (the inherited `parentArray="Tabs"` would otherwise silently pollute Blizzard's tab array), inherits `AuctionHouseFrameTabTemplate`, hooks `SetDisplayMode` (guarded on `#mode > 0` so our own teardown doesn't fight our clicks), re-injects idempotently on every AH open, and guards against the TSM sub-0.5 scale corruption.
  - **`Search.lua` — the query engine.** Keyword **browse** via `SendBrowseQuery` (throttle-queued, paginated to completion) plus a **drill-down** engine for per-item detail that handles the documented `SendSearchQuery` cold-cache trap by construction (gate on `GetItemKeyInfo`, validate-and-retry on false-empties, request-token matching, bounded timeout). Includes **shift-clicked-item / pasted-link normalization** (extracts the plain item name; a raw `|Hitem:…|h` string matches nothing on the AH server) — exposed for the search box so shift-clicking an item into Shopping Just Works.
  - **`UI/ShoppingTab.lua` + `UI/ShoppingCells.{lua,xml}` — the Shopping tab UI.** Search strip (`SearchBoxTemplate` with built-in clear button, Search / Search Options / Add To List), left **Shopping Lists / Recent Searches** sub-tabs (native `PanelTopTabButtonTemplate`), and a results table built on Blizzard's native **`TableBuilder`** — tab-bordered column headers, native `MoneyDisplayFrame` coin cells, `WowScrollBoxList` + `MinimalScrollBar`, columns **Price · Name · Available** matching Auctionator and native Buy exactly. Panels use the native **`auctionhouse-background-index`** atlas (not a fabricated fill — found in the game's own assets) for an authentically modern look.
  - **Protected-buy path PROVEN taint-clean (`Buy.lua`, resolves design OQ#5 — the project's highest-risk unknown).** Verified in-game that our own hardware-event button can drive the restricted commodity-purchase flow (`StartCommoditiesPurchase` → `COMMODITY_PRICE_UPDATED` quote → `ConfirmCommoditiesPurchase` → purchase succeeded) with **zero taint / blocked-action errors**. This unblocks the entire write side of the module — buying *and* Phase-5 selling (`PostItem`/`PostCommodity`) *and* Phase-6 cancelling (`CancelAuction`) all rely on this same capability. Hard rules recorded: protected calls must originate from a genuine hardware event and must NOT be throttle-queued (deferral strips the hardware context).
  - **Tooltip/DB note:** the scanned/DB market price intentionally appears only in item tooltips (its proper home), not as a results column — exact-match-only, blank on a miss, never an estimate (a wrong price is worse than no price).

### Notes
- The Shopping tab ships with search + results fully working and native-faithful. Selling/buying UI, drill-down, and the Shopping Lists / Recent Searches content are stubbed ("coming in a later layer") and land in subsequent passes — consistent with the suite's foundation-first, ship-each-phase cadence.

## [1.6.48] - 2026-06-05

### Added
- `VeritasUI_AuctionHouse` — **Phase 3: auction prices in item tooltips (first user-visible feature).**
  - **`Tooltip.lua`** — appends the stored market price to item tooltips via the modern hook `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)` (verified 12.0.5). The callback reads the item link from `data.hyperlink` (falling back to `TooltipUtil.GetDisplayedItem`), looks it up with `AH.DB.GetMarketPriceForLink`, and adds an **"Auction (each)"** line in Blizzard coin-icon style plus an optional grey **"N seen · X days old"** annotation. Pure database read — no live AH query, works away from the Auction House, read-only (no taint). `pcall`-guarded so a malformed link can never error a tooltip; re-derives the link per tooltip rebuild so lines never stack. Items with no stored price show nothing (no empty line).
  - **`Settings.lua`** — three real, persisted checkboxes (all default on), bound to `AH.db.settings` via `Settings.RegisterAddOnSetting` → `Settings.CreateCheckbox`: *Show Auction Price in Tooltips*, *Show Quantity Seen*, *Show Price Age*.
  - **Phase 2 price accuracy confirmed:** spot-checked tooltip prices against the live Auction House in-game and they match — validating the full scan → per-unit keying → storage → readback pipeline produces correct values, not just plausible counts.

## [1.6.47] - 2026-06-05

### Added
- `VeritasUI_AuctionHouse` — **Phase 2: full-scan price database (first real data).**
  - **`Replicate.lua` — chunked full-scan driver.** `C_AuctionHouse.ReplicateItems()` → `REPLICATE_ITEM_LIST_UPDATE` → reads `GetNumReplicateItems()` rows via `GetReplicateItemInfo` + `GetReplicateItemLink`. **The row loop runs in a coroutine sliced to an ~8 ms/frame budget** so even a 50k–200k+ row snapshot never hitches the client (verified in-game on a ~278k-auction snapshot with no visible stutter). Per-row policy: skip bid-only auctions (`buyoutPrice == 0`), normalize to per-unit price (`floor(buyout / count)`), aggregate per key (min unit price + summed qty), commit once per item. Enforces a persisted **15-minute scan floor** (`/ah scan force` overrides). Fires `AH_SCAN_START` / `AH_SCAN_PROGRESS` / `AH_SCAN_COMPLETE` / `AH_SCAN_FAILED` on the module event bus; aborts cleanly if the AH closes mid-scan.
  - **`Database.lua` — native price store (no LibCBOR).** Key scheme (resolves design OQ#3): `p:<speciesID>` for battle pets, `i:<itemID>:<itemLevel>` for equippable gear (ilvl from `C_Item.GetDetailedItemLevelInfo` so variants don't collide — NOT `GetReplicateItemInfo`'s `level`, which is required *player* level), `i:<itemID>` for everything else (commodities/mats/consumables). The full 4-field `C_AuctionHouse` ItemKey is intentionally not used — `itemID[:ilvl]` is the right pricing granularity and Midnight dropped suffixes. Per-unit copper integers; per-day `{min,max,qty}` history; prune-on-write at a 14-day retention default. API: `MakeKey`, `Record`, `GetMarketPrice`, `GetMarketPriceForLink`, `GetPriceHistory`, `GetItemCount`, `GetPriceAge`, `Wipe`.
  - **`/ah scan`** (+ `scan force`) and **`/ah wipe`** commands; scan progress/complete chat reporting; `/ah diag` now shows live scan state (ready / cooldown / scanning %) and the real priced-item count.
  - Verified in-game: a scan priced **8,327 distinct items from 278,623 auctions**, persisted across `/reload`, with the scan floor enforced and no frame hitch. (Per-item price *accuracy* is spot-checkable in Phase 3 once tooltip prices render.)

## [1.6.46] - 2026-06-05

### Added
- `VeritasUI_AuctionHouse` — **Phase 1: session lifecycle + mandatory throttle queue + money helpers (foundation, no user-facing feature yet).**
  - **Session lifecycle (`Core.lua`)** — handles `AUCTION_HOUSE_SHOW` / `AUCTION_HOUSE_CLOSED` / `AUCTION_HOUSE_DISABLED`, tracks `AH.isOpen` / `AH.disabled`, and broadcasts `AH_OPEN` / `AH_CLOSED` / `AH_DISABLED` on a new in-module event bus.
  - **`AH.Events` pub/sub bus (`Core.lua`)** — a minimal `On(name, fn)` / `Fire(name, ...)` bus (pcall-isolated handlers). `VeritasUI_Lib` has no EventBus and the suite's module-independence rule forbids cross-module coupling, so the AH module owns its own. Defined before sibling files so they can subscribe at file-load time.
  - **`Throttle.lua` — mandatory AH send-queue.** Blizzard rate-limits AH traffic and gates its own SellFrame on `IsThrottledMessageSystemReady()`. This queue dispatches one send at a time only when the throttle system is ready, re-arms on `AUCTION_HOUSE_THROTTLED_SYSTEM_READY`, re-queues the in-flight send at the head on `AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED`, and clears on `AH_CLOSED`. Public API: `Enqueue(fn, label)`, `Clear()`, `PendingCount()`, `IsAwaiting()`. All later-phase AH queries (browse/search/replicate/owned) must route through this rather than calling `C_AuctionHouse` directly.
  - **`Money.lua` — copper formatting/rounding helpers.** `Format` (Blizzard coin-icon string via `C_CurrencyInfo.GetCoinTextureString`), `FormatText` ("12g 34s 56c"), `Breakdown`, and `SanitizePrice` (mirrors Blizzard's `AuctionHouseUtil.SanitizeAuctionHousePrice`: rounds up to copper, or to silver when `C_AuctionHouse.SupportsCopperValues()` is false). **Verified in-game: retail AH returns `SupportsCopperValues() == false`, so prices round up to the nearest silver** (e.g. `SanitizePrice(12345.6) == 12400`). This is a convenience/consistency layer, NOT a Secret-Value taint boundary (see design §2.1 — AH money is plain copper integers).
  - **`/ah diag` expanded** with session state (AH open / disabled), throttle state (ready / awaiting / pending), and a money-helper self-test line. New **`/ah throttletest`** enqueues a no-op send to verify the queue end-to-end (requires the AH open).

## [1.6.45] - 2026-06-05

### Added
- `VeritasUI_AuctionHouse` — **New 7th module (Phase 0 scaffolding).** Adds the foundation for an Auctionator-class Auction House module: full-scan price database, tooltip prices, search/browse, selling assistance, and owned-auction cancelling — built clean-room against the modern `C_AuctionHouse` API (Interface 120005), native-only (no LibStub/LibCBOR/Ace), and styled to be indistinguishable from Blizzard's own AH UI. **This release is scaffolding only — no AH features are active yet.** Phase 0 delivers: (a) `VeritasUI_AuctionHouse.toc` (`RequiredDeps: VeritasUI_Lib`, `SavedVariables: VeritasUI_AuctionHouseDB`); (b) `Core.lua` — seeds `VeritasUI_AuctionHouseDB = { dbVersion=1, prices={}, settings={} }` via recursive `DeepCopy` (the anti-aliasing pattern used by CleanSolo/ZoneQuests), registers `/ah` + `/auctionhouse` with `help`/`diag`/`settings` subcommands, and prints a load line on `PLAYER_LOGIN`; (c) `Settings.lua` — a discovery-only Blizzard Settings category + shared Reload-UI label. The module's main UI will be **injected tabs on Blizzard's `AuctionHouseFrame`** (matching the native Buy/Sell/Auctions tab strip) rather than a standalone window, so no `RegisterManagedPanel` is used — the one intentional divergence from the PriorityRotation/AdvancedOptions panel pattern. Full design, verified API facts, and the phased build plan live in `AUCTIONHOUSE_DESIGN.md` (skill directory). `/ah diag` reports module version, DB readiness, schema version, priced-item count, and AH-open state.

### Notes
- All 8 version strings (7 module TOCs + `Lib.lua` `VUI.VERSION`) bumped to 1.6.45 in lockstep. The suite's skill `sync-check.sh` was updated to count version-bearing files dynamically (no longer hardcoded to 6) so it stays accurate as modules are added.

## [1.6.44] - 2026-05-16

### Changed
- `VeritasUI_PriorityRotation` — **`/pr status` body now emits via `VUI.Print('Priority Rotation', ...)` matching F-38's `/pr diag` pattern.** F-38 (v1.6.42) unified the `/pr diag` output channel but was scoped to `/pr diag` only per the audit; `/pr status` retained the same header-uses-VUI.Print / body-uses-print mix that F-38 corrected. Per Observation #1 from `REMEDIATION_DELTA_AUDIT.md` (post-Phase 8 consistency cleanup, user-approved Phase 9 scope): bulk-converted 5 `print()` calls in `Core.lua:589-605` to `VUI.Print('Priority Rotation', ...)` using the same line-bounded perl regex as F-38. Multi-line prints (the `Macro:`/`On bar:`/`Keybind:` continuations) convert correctly because each trailing `)` still balances the opening `(` we replaced. All `/pr status` output now consistently prefixed.
- `VeritasUI_PriorityRotation` — **`UpdateMacroStub` now `pcall`-guards `CreateMacro` symmetrically with the F-7 `EditMacro` wrapping.** F-7 (v1.6.39) wrapped `EditMacro` at `Core.lua:318` to catch transient macro-frame state during `/reload` bursts; `CreateMacro` at `Core.lua:328` is called under the same conditions but was left unwrapped per F-7's audit-defined scope. Per Observation #4 from `REMEDIATION_DELTA_AUDIT.md` (user-approved Phase 9 scope): wrapped in `pcall`; on failure prints `|cFFFF4444Couldn't create the Attack macro|r — <err>` via `VUI.Print` and returns `false`, matching the failure-return contract used by both the EditMacro branch above and the macro-list-full branch below. Both macro-write APIs in `UpdateMacroStub` now have identical pcall-and-return-false handling.

### Documentation
- `VeritasUI_PriorityRotation` — **Stale legacy-`GetItemInfo` comment in `Editor.lua` Refresh block updated to match F-37's migrated code.** F-37 (v1.6.42) migrated the actual API call from legacy `GetItemInfo` to `C_Item.GetItemInfo` at `Editor.lua:631`, but the descriptive comment immediately above (`Editor.lua:616-618`, the "Refresh icon" doc block) still named the legacy global. Per Observation #2 from `REMEDIATION_DELTA_AUDIT.md` (user-approved Phase 9 scope): updated comment text from "refresh icon from `GetItemInfo`" to "refresh icon from `C_Item.GetItemInfo`" so the comment matches the migrated code.

### Skill maintenance (outside repo)
- `~/.agents/skills/veritasui/SKILL.md` — Added `**Policy:**` field to the CleanSolo Module Inventory entry cross-referencing the v1.6.43 file-top POLICY block at `CleanSolo.lua:4-41` (F-10 / OQ#3). Captures the `hooksecurefunc`-required-`/reload` rationale, the intentional asymmetry with QoL, and the tooltip wording policy. Per Observation #3 from `REMEDIATION_DELTA_AUDIT.md` (user-approved Phase 9 scope). Skill files are outside the repo's git history; no separate commit but logged here so the change is discoverable from changelog history.

### Deferred (per user direction in Phase 9)
- Observation #5 (CHANGELOG "Conventions" subsection as standing format) — left for the user to decide naturally as future entries accumulate.
- Observation #6 (`VUI.PrintRaw` body-text helper to suppress per-line prefixes in `/pr diag`) — left as YAGNI; `/pr diag` is a rarely-used diagnostic command and the current verbose output is acceptable.

## [1.6.43] - 2026-05-16

### Documentation
- `README.md` — **Two stale module descriptions corrected.** (1) Line 32 (AutoSell): replaced "reports earnings via gold delta" with "reports earnings by summing item sell prices, independent of any concurrent gold deductions (e.g. AutoRepair on the same merchant frame)" — v1.6.36 reverted from `GetMoney()` delta accounting to item-value summing as part of the AutoSell/AutoRepair decoupling that fixed the "Sold N for 0g" race; the README still described the pre-v1.6.36 mechanism. (2) Line 47 (PR): the bullet "Dynamic icon shows the current spell on the action bar" deleted entirely — the icon ticker was removed in v1.6.25 as part of PR architectural hardening (`Show()`/`SetTexture` on ActionButton children propagated taint causing Secret Value errors in Delves/M+/raids); the README still claimed the feature existed.
- `VeritasUI_CleanSolo` — **`/reload`-required policy formalized as file-top comment block + tooltip consistency pass.** Per audit OQ#3, CleanSolo's `hooksecurefunc`-heavy implementation cannot cleanly toggle off mid-session (hooks have no inverse), so settings cannot apply live the way `QualityOfLife`'s v1.6.28 mid-session-apply pattern does. This asymmetry is intentional but was previously undocumented in the file itself, leaving any reader (or future audit) wondering whether it was a bug or a feature. Added a 38-line POLICY block at the top of `CleanSolo.lua` (lines 4–41) documenting: (a) why the module uses `hooksecurefunc` extensively, (b) why hooks can't be removed at runtime, (c) the chosen design (db-gating at hook-installation time on `PLAYER_LOGIN`), (d) the explicit asymmetry with `QualityOfLife` and why both are correct, (e) the policy that all CS setting tooltips and on-toggle messages mention `/reload to apply`. Also updated all 11 setting tooltips (10 checkboxes in the `options` table + the Fade Action Bars dropdown) to consistently end with "Requires `/reload` to apply." — the Fade Action Bars dropdown previously said "`/reload` to apply" (slightly different wording) and the 10 checkboxes said nothing about `/reload`. All tooltips now use the same suffix wording. No Lua logic changes.

## [1.6.42] - 2026-05-16

### Added
- `VeritasUI_Lib` — **`VUI.debug` diagnostic flag (file-scope, default `false`).** Opt-in gate for prints from normally-silent paths. Currently used by `CombatQueue` (see below); future silent paths can adopt the same pattern. Flip at runtime via `/run VeritasUI.debug = true` and reproduce the issue. Off by default to keep normal play uncluttered.

### Changed
- `VeritasUI_Lib` — **`CombatQueue` now surfaces queued-closure errors when `VUI.debug` is on.** The `PLAYER_REGEN_ENABLED` drain at `Lib.lua:342-353` previously did `for _, fn in ipairs(pending) do pcall(fn) end` — errors caught (the queue must always finish draining; one bad action shouldn't strand the rest in combat-locked state) but completely silent, leaving developers and users unable to diagnose stuck-frame symptoms with no error trail. Wrapped the `pcall` to capture the error and print `|cFFFF4444[VeritasUI]|r CombatQueue error: <err>` only when `VUI.debug == true`. Behavior unchanged when the flag is off (still silent, queue still drains fully); when the flag is on, every queued-closure failure surfaces with its full Lua error message.
- `VeritasUI_PriorityRotation` — **Editor `GetItemInfo` migrated from legacy global to `C_Item.GetItemInfo` namespace.** Two sites in `Editor.lua` (`BuildEntryFromCursor` line 153; `Refresh` icon path line 631), both already pcall-wrapped by F-2 in v1.6.38. Return-value signature is identical between the legacy global and `C_Item.GetItemInfo` in 12.0.5 — both return `(name, link, quality, level, minLevel, type, subType, stack, equipLoc, texture, sellPrice, classID, ...)` so the positional captures remain correct without modification. Brings `Editor.lua` into namespace-consistency with `QualityOfLife.lua`'s `SetupItemLevels` paths, which use `C_Item.GetItemInfo` throughout. One of the last legacy-global call sites in the suite is now removed.
- `VeritasUI_PriorityRotation` — **`/pr diag` body now emits via `VUI.Print('Priority Rotation', ...)` instead of bare `print()`.** The diagnostic command had a header that already used `VUI.Print` but body lines used bare `print()`, creating a mixed-channel output where the header had the `[Priority Rotation]` prefix and 46 body lines didn't. Bulk-converted all 46 `print()` calls in `Core.lua:632-779` to `VUI.Print('Priority Rotation', ...)` via a line-bounded perl regex. Indentation and color-code formatting preserved verbatim. The single multi-line `print` (the slot-type diagnostic at line 710) converts correctly because the trailing `)` on the continuation line still balances the opening `(` we replaced. All `/pr diag` output now consistently prefixed. Tag chosen as `'Priority Rotation'` (matching the existing header) rather than the audit-suggested `'/pr diag'` to keep the prefix consistent across the entire PR module's output. The same `print()`/`VUI.Print` mix exists in `/pr status` (lines 589-604) but is out of F-38's scope and left untouched.

### Fixed
- `VeritasUI_Lib` — **`RegisterManagedPanel` now warns instead of silently returning on bad input.** `Lib.lua:418` rejected non-string `frameName` (nil, frame objects, numbers — all caller-side bugs) by returning silently. A developer registering a panel and forgetting to pass the frame's name as a string would see "panel not registered" with no error to debug. Added `VUI.Print("Lib", "RegisterManagedPanel: bad frameName (got <type>, expected string)")` before the `return` so the bug is immediately visible at file-load time. The string check itself is unchanged — non-strings still bail out and don't pollute `UIPanelWindows`.

## [1.6.41] - 2026-05-16

### Changed
- `VeritasUI_CleanSolo` — **Defaults init now uses recursive `DeepCopy` instead of inline shallow copy (preventive).** The `ADDON_LOADED` handler in `CleanSolo.lua` previously initialized table-typed defaults with a one-level inline shallow copy (`for k2, v2 in pairs(v) do db[k][k2] = v2 end`). This is correct for the only currently-existing table default (`fadeActionBars = {}`, an empty table with no nested keys), but any future nested default would silently alias the `defaults` constant under the shallow-copy idiom — mutating `db.<table>.<nested>` would mutate `defaults.<table>.<nested>` at runtime, an extremely subtle aliasing bug that only surfaces when the user's saved-vars and the constant both end up pointing at the same subtable. Replaced with the recursive `DeepCopy` pattern ported verbatim from `ZoneQuests.lua:357-362` (the audit-blessed implementation, also documented in SKILL.md Known Landmines under "Table defaults must be deep-copied on first init"). Behavior unchanged for the current single flat table default; future-proof against new nested defaults.

### Documentation
- `VeritasUI_AdvancedOptions` — **`KNOWN_CVARS` policy formalized as comment block (per audit OQ#2).** The master CVar list at `Browser.lua:49-67` includes some Midnight-removed CVar names. The audit raised this as F-12 (apparent drift); investigation confirmed it is policy: `C_CVar.GetCVarInfo` returns `nil` for removed names, and the Strategy 3 probe loop silently skips any name that returns nil. Removing entries from `KNOWN_CVARS` would risk accidentally pruning a CVar that does exist on this client (Blizzard restoring or renaming a CVar between patch cycles is not unprecedented), and the cost of keeping a dead entry is one wasted probe per `/reload` (negligible). Replaced the previous one-line "extend freely; invalid names are harmlessly skipped" comment with a full POLICY block at the same site (`Browser.lua:49-66`) explicitly: (1) calling out `C_CVar.GetCVarInfo`-nil as the silent-skip mechanism, (2) cross-referencing the Strategy 3 loop where the probe runs (line 225), (3) documenting the rationale for never pruning entries, (4) tagging the policy with its formalization version (v1.6.41) and origin (audit OQ#2). No code change. Future audit cycles should treat apparent stale entries in `KNOWN_CVARS` as policy, not drift.

### Conventions
- **`KNOWN_CVARS` is intentionally broad.** Dead names from previous patch cycles are silently skipped at runtime via `C_CVar.GetCVarInfo` returning nil. Entries are NOT pruned on Midnight removals — removing a name risks accidentally removing a CVar that does exist. See the policy comment at `VeritasUI_AdvancedOptions/Browser.lua:49-66`. This is policy, not drift.

## [1.6.40] - 2026-05-16

### Changed
- `VeritasUI_QualityOfLife` — **`[noautorepair]` guild-info parsing is now case-insensitive and tolerant of whitespace inside the brackets.** The auto-repair feature respects a longstanding guild-convention tag in `GetGuildInfoText()` — if the tag is present, the guild-bank repair branch is skipped and personal gold covers the cost. Previously the parser at `QualityOfLife.lua:264` (now line 300 after F-1's expansion) used `:find("[noautorepair]", 1, true)`, a plain literal match that only fired on the exact lowercase string `[noautorepair]`. A GM who typed `[NoAutoRepair]`, `[ noautorepair ]`, or `[NOAUTOREPAIR]` would have their suppression intent silently ignored and the user's repairs would still hit the guild bank. The user is at the mercy of whatever the GM typed; defensive parsing only ever makes the feature more reliable. Replaced with `:lower():find("%[%s*noautorepair%s*%]")` — case-insensitive (`:lower()` first), tolerant of optional whitespace immediately inside both brackets. Internal whitespace (`[no auto repair]`) is intentionally NOT matched so a GM who really did mean a different bracketed tag isn't accidentally swept up by the suppression convention. Resolves OQ#4.

### Fixed
- `VeritasUI_QualityOfLife` — **`/way` usage hint now states "coordinates must be positive 0–100"** so users who type `/way -5 50` (or any negative coordinate) understand why the command rejected their input. The current `(%d+%.?%d*)` parse pattern correctly refuses to match negative numbers (which don't exist in WoW maps — coordinates are always 0–100 within a map's UV space), but the rejected input falls through to the usage hint without explaining the constraint. The 0–100 range check at `QualityOfLife.lua:1278` does emit a friendly "Coordinates must be between 0 and 100." message, but only on a successful parse where the values exceed 100; negative coordinates fail to parse entirely and never reach that line. Updated the usage hint text inline to make the constraint discoverable on the first failed attempt. No pattern change, no behavior change for valid input — purely a clarity fix per the F-31 pre-resolved decision.

## [1.6.39] - 2026-05-16

### Added
- `VeritasUI_PriorityRotation` — **One-time per-session diagnostic warnings for missing macros and stale spellIDs in compiled rotations, with `UPDATE_MACROS` listener so the missing-macro warning surfaces immediately on external macro deletion.** Two parallel diagnostic gaps were closed in `Core.lua` `CompileSequence`. The macro branch (was lines 171–177) silently elided macro entries whose macros had been deleted or renamed since authoring — the rotation simply got shorter with no signal to the user. The spell branch (was lines 185–188) emitted `/cast <spellName>` text for stale `spellID`s without verifying the ID still resolved, so every key press surfaced an "Unknown spell: X" line in chat with no indication of which rotation slot was the culprit. Both branches now use the same warn-once-per-session pattern: file-scope `PR._missingMacroWarned = {}` and `PR._missingSpellWarned = {}` (declared with the `PR.*` constants block at line 65–66) track which names/IDs have already been reported. On a successful resolve the stored flag is cleared, so a future delete-and-recompile re-warns. On a missing macro or `C_Spell.GetSpellInfo`-nil spellID, a single `VUI.Print` "Missing macro X — entry skipped this session" or "Stale spell X (ID N) — entry skipped this session. Drag the current version of the spell back onto the slot." is emitted and the entry is elided from the compiled sequence as before. Subsequent compiles are silent until the entry resolves or `/reload` clears the table.
  - **`UPDATE_MACROS` listener (F-5 extension, Option C, approved post-Phase 3):** initial F-5 implementation matched the audit's recommendation verbatim but missed a real-world flow gap — `CompileSequence` is only called on profile change, editor edits, or specific slash commands, never on external macro deletion. A user who deleted a macro from `/macro` saw the rotation lose its compiled-cache contents only at the next manual recompile, with no warning surfacing in the meantime, and (separately, pre-existing per F-1 baseline) the rotation could appear "stuck" if the cached macro body became internally inconsistent. Registered `UPDATE_MACROS` on the existing event frame and routed it through `PR:ScheduleCompile()` (already-existing 0.3s debounce path; no new compile entry point introduced). Editor bursts — rapid save/rename/reorder during macro editing — collapse into a single recompile 0.3s after the last fire, so cadence concerns are bounded by the existing debounce. `CompileSequence`'s `if not self.db then return end` guard at line 150 makes any pre-`ADDON_LOADED` fire a no-op. Net effect: deleting a macro that's referenced by the active rotation now (a) immediately surfaces the F-5 warning, (b) recompiles the sequence excluding the missing entry so the rotation continues working with the remaining slots, and (c) restores the warning if the macro is later recreated and deleted again. The audit's optional Editor.lua red `[M]` visual indicator was deferred per minimal-change preference; rotation row icons remain unchanged.

### Changed
- `VeritasUI_PriorityRotation` — **`UpdateMacroStub` now `pcall`-guards `EditMacro` and returns false on failure.** `EditMacro(idx, name, icon, body)` at `Core.lua:273` was historically reliable but the macro frame can be in a transient state during `/reload` bursts or addon-driven `CreateMacro` pile-ups; a hard error here would surface as a vague Lua popup with no actionable recovery message. Wrapped in `pcall`; on failure prints `|cFFFF4444Couldn't update the Attack macro|r — <err>` via `VUI.Print` and returns `false`, matching the failure-return contract already used by the macro-list-full branch immediately below (line 280–283). `CreateMacro` at line 277 is intentionally not wrapped — F-7 scope is `EditMacro` only; a future audit cycle can address `CreateMacro` if its surface ever proves unreliable.

### Fixed
- `VeritasUI_PriorityRotation` — **`/pr settings` typed before Settings panel init now prints a friendly message instead of erroring on `Settings.OpenToCategory(nil)`.** `PR.settingsCategoryID` is set in `Settings.lua:512` after `category:GetID()` resolves; if the user types `/pr settings` during the brief PLAYER_LOGIN burst before that init line runs (timing-fragile, may need repeated tries to reproduce), `Core.lua:466` previously called `Settings.OpenToCategory(nil)` which depending on Blizzard's tolerance either silently no-op'd or surfaced a Lua error. Added a nil-check: if `PR.settingsCategoryID` is set, open the panel; otherwise emit `Priority Rotation is still loading — try again in a moment.` via `VUI.Print`. After PLAYER_LOGIN completes the panel opens normally as before.

## [1.6.38] - 2026-05-16

### Fixed
- `VeritasUI_PriorityRotation` — **Editor `GetItemInfo` + `equipLoc` comparison now pcall-protected against Midnight Secret Values.** Two sites in `Editor.lua` called the legacy global `GetItemInfo` and compared `equipLoc ~= "INVTYPE_TRINKET"` without protection: `BuildEntryFromCursor` (lines 145-158, the trinket drag-handler) and the icon-refresh path inside `Refresh` (line 619). Both compare values that may be Secret Values in raid encounters or other restricted-execution contexts; either could surface as a Lua error popup mid-drag (BuildEntryFromCursor) or mid-row-render (Refresh). Fixed using the per-call pcall pattern that mirrors `QualityOfLife.lua:339-350` (the `IsEquippableGear` defensive pattern, also used by F-1 in v1.6.37): `pcall(GetItemInfo, itemID)` capturing all 10 returns positionally, then `pcall(function() return equipLoc == "INVTYPE_TRINKET" end)` for the comparison. On either pcall failure, `BuildEntryFromCursor` returns the existing user-facing "Item info not loaded yet — try again in a moment." message (the Secret Value path is indistinguishable from a not-yet-cached item from the user's perspective and the same retry advice applies). The Refresh icon path is purely cosmetic — on pcall failure it silently keeps the cached `e.icon` rather than overwriting with stale data. Legacy `GetItemInfo` namespace retained for now; the F-37 migration to `C_Item.GetItemInfo` is a separate Phase 6 commit per the audit's recommendation set.
- `VeritasUI_Lib` — **`SuppressFrame` Show-hook now combat-defers the `Hide` via `VUI.CombatQueue` instead of silently no-op'ing.** The Show-hook installed at `Lib.lua:114-117` set the frame's alpha to 0 and conditionally called `self:Hide()` only when `not InCombatLockdown()`. A combat-locked Show — common during the login burst, action bar layout passes, or any Blizzard subsystem that re-asserts a suppressed frame mid-encounter — left the frame at alpha 0 but still `:IsShown()`, and the deferred Hide it was promised never fired. Layout invalidation could subsequently re-assert the frame's geometry and the user would see the suppressed element flicker back at the next frame cycle. Fixed by routing the deferred Hide through `VUI.CombatQueue.Add(function() if self:IsShown() then self:Hide() end end)`, mirroring the established pattern in `SafeHide` (line 106). The `IsShown()` guard inside the queued closure handles the case where Blizzard hid the frame itself between the Show and the queue drain at `PLAYER_REGEN_ENABLED` — without it, the queued Hide would be a redundant but harmless call; with it, the queue drain is a clean no-op.
- `VeritasUI_Lib` — **Renamed two same-named file-locals `HOVER_POLL_RATE` to disambiguate `HookHoverFade` (10 Hz) from `HookPlayerFrameFade` (5 Hz).** Two unrelated subsystems in `Lib.lua` both declared `local HOVER_POLL_RATE` at file scope with different values — `0.1` (line 136, used by `HookHoverFade` for MicroMenu / faded action bars) and `0.20` (line 233, used by `HookPlayerFrameFade` for the player frame hover poll). The second declaration shadowed the first within its lexical scope; both resolved correctly because `HookHoverFade`'s closure captured the local from line 136 before line 233 was reached, and `HookPlayerFrameFade`'s closure captured line 233 after the shadow took effect. Behaviorally correct, but reading the file from top to bottom makes the second declaration look like a mistake or a refactor halfway done. Renamed to `HOVER_FADE_POLL_RATE` (line 136 → 147) and `PLAYER_FRAME_HOVER_POLL_RATE` (line 233 → 244) so the names match their function. No behavior change; both still poll at their original rates.

## [1.6.37] - 2026-05-16

### Fixed
- `VeritasUI_QualityOfLife` — **AutoSell `C_Item.GetItemInfo` calls now pcall-protected against Midnight Secret Values.** v1.6.36's rewrite to item-value summing reinstated `C_Item.GetItemInfo` at `ScanJunk` (lines 117-133) and `SellNextBatch` (lines 159-185) without preserving the pcall protection that v1.3.18 and v1.3.22 had established for this exact API. The Item Level overlay paths in the same file (lines 339-368) remained pcall'd, confirming the inconsistency was unintentional. Realistic exposure window: a player who starts selling near a hub vendor, then is pulled into combat (trash respawn in Stormwind / Dornogal) before the sell completes, would hit a Secret-Value comparison error on the next `SellNextBatch` cycle, producing a Lua error popup with `BAG_UPDATE_DELAYED` still registered. Fixed using the per-call pcall pattern that mirrors `QualityOfLife.lua:339-350` (the `IsEquippableGear` defensive pattern): the `info.quality == 0 and not info.hasNoValue` check is wrapped in `pcall(function() ... end)`, the `C_Item.GetItemInfo` call is wrapped in `pcall(C_Item.GetItemInfo, info.itemID)` capturing the 11th return positionally, and the `price > 0` arithmetic is wrapped in a third `pcall(function() ... end)` that returns the contribution (`price * stackCount`) on success. Items that fail any of the three guards are skipped (treated as not-junk / not-sellable). `SellNextBatch` applies the same three-pcall pattern with the additional `info.isLocked` clause in the first guard. The closure-helper alternative proposed in the audit was rejected in favor of inline per-call pcalls so the fix matches the file's established defensive idiom exactly. No other AutoSell behavior modified — locked-items-as-remaining accounting, no-progress timeout, decoupled AutoRepair, MERCHANT_SHOW one-frame defer, and BAG_UPDATE_DELAYED retry are all preserved verbatim.

## [1.6.36] - 2026-05-16

### Changed
- `VeritasUI_QualityOfLife` — **AutoSell and AutoRepair rewritten in the Scrap-style decoupled architecture; AutoRepair now works at Delver's Supplies and every other repair-only vendor.** The v1.6.30 "sell-first sequencing" architecture chained `AutoRepair` off the inside of `SellNextBatch` (and later `DoReport`), meaning `AutoRepair` could only fire after `AutoSellJunk` reached one of two narrow completion paths. At Delver's Supplies crates in Delves, Blizzard disables item sales entirely while still allowing repair — `UseContainerItem` no-ops, `BAG_UPDATE_DELAYED` never resolves the sell loop, and `AutoRepair` was therefore never called. The user experienced absolutely nothing happening at Delves crates. Five releases (v1.6.31, v1.6.32, v1.6.34, v1.6.35) chased symptoms of this coupling without removing its cause.
  - **Reread Scrap's actual source** (`jaliborc/Scrap` `addons/merchant/button.lua`). Scrap's `Button:OnMerchant` calls `Sell()` and `Repair()` independently — neither chains off the other. The earlier claim that Scrap coupled them was incorrect; the coupling in VeritasUI was based on a misread.
  - **MERCHANT_SHOW handler restored to independent dispatch** (matching v1.6.27 and Scrap): `if db.autoRepair then AutoRepair() end; if db.autoSellJunk then AutoSellJunk() end`. Either function can fail, no-op, or never start without affecting the other.
  - **Gold accounting replaced with item-value summing** (matching Scrap). At sell start, `ScanJunk` walks bags once and sums `select(11, C_Item.GetItemInfo(itemID)) * stackCount` for every grey item — this is `saleTotal`. On each cycle, `ScanJunk` recomputes the remaining junk value; when remaining hits 0, the print uses `saleTotal` directly. `GetMoney()` is never used for the sell amount, so there is no race with a concurrent repair deduction — this kills the original v1.6.12-v1.6.29 "Sold N items for 0g" bug at its root, not at a symptom.
  - **Locked items are counted as "remaining"** so the completion print only fires when the server has physically removed items from bags — not when they are merely locked mid-sale. The client locks each item the instant `UseContainerItem` runs, while the server is still processing (or rejecting) the request. If `ScanJunk` excluded locked items the way Scrap's `GetReport` does, we would print "Sold N for X" immediately after the sell loop and then the items would either confirm shortly after (print was just premature) or fail to sell and reappear unlocked (print was an outright lie). Counting locked items defers the print until the bag actually empties.
  - **No-progress timeout** (`MAX_NO_PROGRESS = 5s`) ends the retry loop only when items have stopped disappearing from the bag — not on absolute elapsed time. Each cycle compares the current remaining value to `lastRemainingValue`; if it dropped, sales are confirming and the timer resets. If it has been flat for 5 seconds, the vendor is rejecting our requests (or there is some other persistent failure) and `PrintSold` reports whatever partial value did sell (`saleTotal - remaining`, `saleCount - remainingCount`). This is correct for both small piles and very large drains — a 200-item sell that legitimately takes 8 seconds keeps resetting the timer with every confirmed batch, while a stuck vendor times out cleanly. The v1.6.16 0.5s `SELL_RETRY_SEC` BAG_UPDATE_DELAYED fallback is preserved, so the historical "stops after one batch if the bag event is dropped" stall stays fixed.
  - **Repair print uses `GetRepairAllCost()` directly** — known, exact, synchronous; no delta math, no listener, no fallback timer.
  - **Removed**: the `PLAYER_MONEY` event registration, the `pendingReportFn` / `pendingReportTimer` state, the `CancelPendingReport` helper, the `DoReport` closure with its `earned ≤ 0` rebase guard, the `count == 0` chained-repair branch in `SellNextBatch`, the `local AutoRepair` forward declaration, and the `sellState` struct with deferred `startMoney` snapshot. Roughly 90 lines of coupling machinery deleted.
  - **Preserved**: the `MERCHANT_SHOW` one-frame defer (v1.6.34's fix for Blizzard's handler-order race), the `BAG_UPDATE_DELAYED` event-driven sell loop, the 0.5s `SELL_RETRY_SEC` safety fallback for dropped bag updates (v1.6.16), the `[noautorepair]` guild-info convention (v1.6.30), and the Guild + Personal / Personal Only Repair Funding dropdown (v1.6.30).

## [1.6.35] - 2026-05-15

### Fixed
- `VeritasUI_QualityOfLife` — **Repair print appeared before sell print, breaking the visible sell-first ordering.** `RepairAllItems` triggers its `"Repaired for X"` print **synchronously** the instant `AutoRepair()` runs. The sell print is **asynchronous** — `DoReport` only fires after the server's sell `PLAYER_MONEY` packet arrives (~200ms RTT). Even though the logical sequencing was sell-first (UseContainerItem requests sent to the server before RepairAllItems), the client-side message order ended up repair-then-sell because the repair print didn't wait for any network round-trip. Fixed by chaining the `AutoRepair()` call off the *inside* of `DoReport` (after the sell `VUI.Print`), rather than firing it immediately after the listener is armed. The `earned ≤ 0` rebase guard is retained as a safety net for unrelated deductions during the gap, and `CanMerchantRepair()` inside `AutoRepair` handles the rare case where the merchant closes between the sell print and the chained repair call. The `count == 0` branch (no junk to sell) still calls `AutoRepair()` directly — no sell print means no ordering issue.

## [1.6.34] - 2026-05-15

### Fixed
- `VeritasUI_QualityOfLife` — **AutoSell Junk and AutoRepair completely non-functional on merchant visit.** `MERCHANT_SHOW` fires *before* Blizzard's `MerchantFrame_OnShow` handler runs, so `MerchantFrame:IsShown()` returns `false` at the moment our handler executes. `SellNextBatch`'s safety guard (`if not MerchantFrame:IsShown() then return end`) silently aborted the sell, and because `AutoRepair` is now chained off `SellNextBatch` (v1.6.30 sell-first sequencing), repair never fired either. Net effect: clicking a merchant did absolutely nothing — no error, no message, no sell, no repair. v1.6.29 masked this race condition with a 0.25s `C_Timer.After` delay before `AutoSellJunk`, which was removed in v1.6.30 when the sell-first refactor restructured the timing model. Fixed by deferring the `MERCHANT_SHOW` body by one frame (`C_Timer.After(0, ...)`), which runs after Blizzard's handler completes and `MerchantFrame` is fully shown. The `MerchantFrame:IsShown()` safety check is preserved inside the deferred closure to handle the edge case where the merchant is closed during the one-frame gap.

## [1.6.33] - 2026-05-15

### Fixed
- `VeritasUI_QualityOfLife` — **`/way` command was non-functional for non-TomTom users.** `local function WayCommand(msg)` was declared at the bottom of the file, after `frame:SetScript("OnEvent", ...)`. Lua compiles free variables in a closure at definition time; since `WayCommand` was not yet declared when the OnEvent closure was compiled, references inside it resolved to the global `_G.WayCommand` (nil). At PLAYER_LOGIN, `SlashCmdList["VERITASUI_WAY"] = WayCommand` assigned nil, and typing `/way` silently failed. Fixed by adding a `local WayCommand` forward declaration before `frame:SetScript` and changing the definition from `local function WayCommand` to `WayCommand = function` so it populates the upvalue. TomTom users were unaffected (the registration block is skipped when TomTom is present).
- `VeritasUI_PriorityRotation` — **Removed unused `usedCharSlot` variable from `BuildEntryFromCursor` in `Editor.lua`.** The variable was declared and assigned in two branches of the macro character-slot disambiguation logic but never read anywhere in the function. Dead code removed.

## [1.6.32] - 2026-05-15

### Fixed
- `VeritasUI_PriorityRotation` — **Settings.lua crash when opening the spec switcher dropdown.** Fix #3 from v1.6.31 incorrectly migrated `GetNumSpecializations()` to `C_SpecializationInfo.GetNumSpecializations()`. That method does not exist in the `C_SpecializationInfo` namespace in Midnight 12.0.5 — only the legacy global `GetNumSpecializations()` is available. Opening the spec switcher dropdown triggered `attempt to call a nil value` at `Settings.lua:382`. Reverted that one call to the global; all other `C_SpecializationInfo` migrations from v1.6.31 are correct and preserved.

## [1.6.31] - 2026-05-15

### Fixed
- `VeritasUI_QualityOfLife` — **AutoRepair scoping fix: `SellNextBatch` now correctly calls the VUI `AutoRepair` local.** `local function AutoRepair()` was declared at line 218, after `SellNextBatch` at line 104. In Lua, a local is only visible to code declared after it, so `AutoRepair()` inside `SellNextBatch` resolved to `_G.AutoRepair` (nil in WoW) rather than the VUI local — causing a Lua error on every merchant visit with both Auto Sell and Auto Repair enabled. Fixed with a forward declaration (`local AutoRepair`) placed before `SellNextBatch`; the definition is unchanged and the sell-first sequencing architecture from v1.6.30 is fully preserved.

### Changed
- `VeritasUI_PriorityRotation` — **Settings.lua spec API calls updated to `C_SpecializationInfo` namespace.** `ApplySpecPortrait`, `CurrentSpecName`, and the spec switcher dropdown's `SetupMenu` were using the legacy global `GetSpecialization` / `GetSpecializationInfo` / `GetNumSpecializations` with defensive nil guards. These are now replaced with direct `C_SpecializationInfo.*` calls, consistent with the pattern already used throughout `Profiles.lua`. Eliminates the inconsistency and removes reliance on globals that Blizzard may eventually drop.
- `VeritasUI_PriorityRotation` — **Deduplicated Spellbook/Macro toggle logic.** `ToggleSpellBookPanel` and `ToggleMacroPanel` are defined once in `Editor.lua` and exposed on the `PR` table. `Settings.lua`'s Spellbook and Macros button handlers now call `PR.ToggleSpellBookPanel()` / `PR.ToggleMacroPanel()` instead of inlining identical logic. Any future change to the toggle behavior only needs to be made in one place.

## [1.6.30] - 2026-05-14

### Changed
- `VeritasUI_QualityOfLife` — **AutoSell and AutoRepair: sell-first sequencing, guild tag respect, and repair funding setting.**
  - **Sell-first sequencing** — AutoSell now runs before AutoRepair instead of after. The merchant-open handler kicks off `AutoSellJunk()` immediately; `AutoRepair()` is triggered from inside `SellNextBatch` when all junk has been sold (or immediately if there was nothing to sell). This eliminates the 0.25s artificial delay that existed to prevent repair deductions from corrupting the sell gold delta. Sell credits arrive from the server before repair deductions in normal network order, and the existing `earned ≤ 0` rebase guard in `DoReport` handles the rare high-latency edge case. If Auto Sell is disabled and Auto Repair is on, repair fires immediately from `MERCHANT_SHOW` as before
  - **`[noautorepair]` guild tag** — `AutoRepair` now checks whether the guild's info text contains the literal string `[noautorepair]` before attempting guild bank repair. This is an informal convention used by guild masters to prevent auto-repair addons from drawing on guild funds (common in organized raiding guilds). If the tag is present, the guild repair step is skipped and personal gold is used instead
  - **Repair Funding setting** — new dropdown in the Quality of Life settings panel (directly below the Auto Repair checkbox): `Guild + Personal` (default, existing behavior) or `Personal Only`. `Guild + Personal` tries guild bank funds first when all guild conditions are met, then covers any remainder with personal gold. `Personal Only` skips guild entirely and always uses personal gold — useful for players not in a guild or who prefer not to use guild funds

## [1.6.29] - 2026-05-14

### Fixed
- `VeritasUI_QualityOfLife` — **AutoSell Junk gold reporting still showed 0g when Auto Repair also ran using personal gold.** Root cause: `C_Timer.After(0, AutoSellJunk)` started the sell one frame (~16ms) after the repair request was sent, but the server's repair `PLAYER_MONEY` event (money deduction) typically arrives 50–200ms later. `startMoney` was therefore captured pre-repair. Once the sell completed and `pendingReportFn = DoReport` was set, the repair's `PLAYER_MONEY` arrived first and fired `DoReport` with a negative delta (repair deduction − 0) → clamped to 0 → "for 0🪙". The sell's own `PLAYER_MONEY` arrived after `pendingReportFn` was already cleared and was silently ignored.
  - **Primary fix:** sell deferred by 0.25s (up from one frame) so repair credit settles in `GetMoney()` before `startMoney` is captured. Covers typical server round-trips of 50–200ms.
  - **Secondary fix (high-latency guard):** `DoReport` now checks whether `earned ≤ 0` before reporting. If a repair deduction still arrives after `pendingReportFn` is set (connection latency > 250ms), `DoReport` rebases `capturedStart` to the current post-deduction gold and returns without reporting — keeping `pendingReportFn` active so the sell's subsequent `PLAYER_MONEY` (earned > 0) fires a correct report. The 2-second fallback timer also reads the rebased `capturedStart`, so it reports sell proceeds rather than a net sell-minus-repair delta.

## [1.6.28] - 2026-05-14

### Changed
- `VeritasUI_QualityOfLife` — **Architectural hardening: ten robustness improvements.**
  - **AutoSell gold reporting — PLAYER_MONEY event replaces fixed-frame delay** — `C_Timer.After(0, ...)` raced against the server's money-credit packet, causing sub-1g sell totals to read `GetMoney() - startMoney == 0` and report "for 0g". `PLAYER_MONEY` fires exactly when the server confirms the credit; the report now triggers in that handler. A 2-second fallback timer fires if `PLAYER_MONEY` never arrives. A stale-closure guard (`pendingReportFn ~= DoReport`) and `CancelPendingReport()` prevent double-reporting if a new sell session starts before the previous report fires
  - **Item level hook respects mid-session disable** — `hooksecurefunc("SetItemButtonQuality", ...)` cannot be unregistered once set; overlays remained visible after disabling the setting mid-session. Added `if not db or not db.showItemLevels then return end` as the first guard in the hook closure so disabling takes effect immediately without a `/reload`
  - **Map coordinates OnUpdate respects mid-session disable** — the anchor frame's 30 fps `OnUpdate` ran regardless of `db.showMapCoords`. Added a db check that hides the anchor and returns when the setting is off
  - **Settings callbacks invoke feature setup on mid-session enable** — enabling `showItemLevels` or `showMapCoords` after login (when they were disabled at login) previously did nothing because setup only ran in `PLAYER_LOGIN`. Callbacks now call `SetupItemLevels()` / `SetupMapCoordinates()` when toggled on; `SetupItemLevels` is idempotent via the new `itemLevelsSetup` guard. Map coords anchor is shown/hidden directly if already initialised
  - **AFK poll starts when AFK Screen enabled mid-session** — `AFK_StartPoll()` was only called in `PLAYER_LOGIN` if `db.afkScreen`. Enabling the feature after login left the 5-second fallback poll un-started (event-driven path still worked). The `afkScreen` settings callback now calls `AFK_StartPoll()` on enable; the function is idempotent
  - **`MinimapCluster` visibility preserved across AFK** — `AFK_Exit()` unconditionally called `MinimapCluster:Show()`, revealing it even if another addon had hidden it before AFK started. `AFK_Enter()` now snapshots `MinimapCluster:IsShown()` into `afkOverlay._minimapWasShown`; `AFK_Exit()` restores that exact state
  - **`MoveViewRightStart` / `MoveViewRightStop` pcall-wrapped** — camera movement APIs can fail in cinematics, vehicle sequences, and certain phased content. Both calls are now guarded with `pcall`
  - **`InitCoords` idempotency guard** — added `coordsInitialized` flag; `InitCoords()` is now a no-op if called a second time (e.g. edge-case LoD event re-fire), preventing duplicate anchor frames on the map
  - **Merchant scanner no longer double-fires on open** — the item-level merchant scanner's `mf` frame registered both `MERCHANT_SHOW` and `MerchantFrame:HookScript("OnShow", ...)`, causing `UpdateMerchantItems` to be called twice at +0.1s on every merchant open. Removed `MERCHANT_SHOW` from `mf`; the `OnShow` hook covers the open case
  - **`/way` defers registration to `PLAYER_LOGIN` with TomTom detection** — if TomTom is loaded, both addons register `/way` and the last to load silently wins. Registration now happens in `PLAYER_LOGIN`; if `_G.TomTom` or `IsAddOnLoaded("TomTom")` is true, `/way` is skipped and a one-time note is printed. The slash handler extracted to `local function WayCommand(msg)` for testability

## [1.6.27] - 2026-05-14

### Changed
- `VeritasUI_ZoneQuests` — **Architectural hardening: five robustness improvements.**
  - **Remove `QUEST_ACCEPTED` stacked timers** — The `QUEST_ACCEPTED` handler created a non-cancellable `C_Timer.After(0.5, ...)` per event. Accepting multiple quests from one NPC fired multiple stacked timers that all called `SyncTracking` independently. Since `QUEST_LOG_UPDATE` fires on every acceptance and already routes through the cancellable debounce, `QUEST_ACCEPTED` was redundant. Handler and event registration removed
  - **Map walk uses `Enum.UIMapType` stop sentinel** — `BuildZoneNameSet`'s C_Map hierarchy walk previously stopped at hardcoded parent map IDs 946/947 (the World and Cosmic map IDs). If Blizzard renumbers these in a future patch, the walk would climb past the world level and pollute the name set with world-level names, causing every quest header to match every zone. Now stops when `info.mapType` is `Enum.UIMapType.World` or `Enum.UIMapType.Cosmic` (with numeric fallbacks), which is ID-independent
  - **`StripDir` uses ordered array and loops until stable** — `DIRECTIONAL` changed from a hash table (non-deterministic `pairs` iteration) to an ordered array (`ipairs`). `StripDir` now loops until no further prefix is stripped, so doubly-prefixed names like `"The Upper Blackrock Spire"` fully reduce to `"Blackrock Spire"` in two passes. Previously only one prefix was stripped per call, leaving the second prefix in place and relying on the substring fallback in `HeaderMatches` — which introduced false-positive risk
  - **`HeaderMatches` guards short stripped headers** — The bidirectional substring fallback now requires `#hs > 2` before checking whether the stripped quest header appears inside a zone name in the set. Previously a very short stripped header could sweep-match across unrelated zone names. The guard on `#name > 2` already protected the forward direction; this adds the symmetric guard to the reverse direction
  - **Remove redundant `registeredCategory` variable** — `registeredCategory` and `settingsCategoryID` both tracked whether `InitializeOptions` had run. All three guard sites now use `settingsCategoryID` directly, eliminating the drift risk if the two variables were ever set independently

## [1.6.26] - 2026-05-14

### Changed
- `VeritasUI_AdvancedOptions` — **Architectural hardening: six improvements to eliminate fragility and ensure long-term robustness.**
  - **Shared height constants** — `AO.CONTROL_HEIGHTS` table defined in `Controls.lua` using `ROW_HEIGHT` as the single source; `Featured.lua`'s extent calculator now references it instead of maintaining a duplicate copy. Adding a new control type no longer requires updating two files
  - **Shared scrollbar inset** — `AO.SB_INSET = 16` defined once in `Core.lua`; both `BuildFeaturedContent` and `BuildBrowserContent` reference it. The precisely-tuned scrollbar alignment between tabs can no longer silently drift if one is changed independently
  - **Featured → Browser CVar sync** — `EnumerateCVars` now auto-supplements the browser list with every CVar from `AO.FEATURED_CATEGORIES` after the three enumeration strategies run. Adding a CVar to the Featured tab will automatically appear in the All CVars tab without a separate `KNOWN_CVARS` entry; the lists can never silently diverge
  - **Slider write debounce** — `CreateSlider`'s `OnValueChanged` now uses the `userInput` parameter to skip programmatic `SetValue` calls (e.g. from `Refresh()`), and defers the actual `SetCVar` write via a 0.15s `C_Timer` debounce that commits only after the drag settles. Eliminates spurious writes on every `Refresh` and rapid-fire writes during drag
  - **CVar cache version stamp** — `InitDB` now clears `db.cvarCache` when `db.cacheVersion` doesn't match `AO.VERSION`, evicting stale entries from CVars renamed or removed in a prior patch. Cache repopulates naturally during the session
  - **Restart indicator comment corrected** — `CreateRestartIndicator` comment updated to reflect that `"!"` text is the intentional implementation; the atlas approach was tried and abandoned due to pool-frame reparenting conflicts

## [1.6.25] - 2026-05-14

### Changed
- `VeritasUI_PriorityRotation` — **Architectural hardening: seven improvements to eliminate fragility and Secret Value taint risk.**
  - **Removed icon ticker system** — `StartIconTicker()`, `StopIconTicker()`, `UpdateIcon()`, and `iconCache` are gone. The ticker called `icon:Show()`/`Hide()` and polled action button frames on every tick, producing taint that could corrupt secure execution contexts in Delves, M+, and raids. Action bar button now keeps its static macro icon; no dynamic updates
  - **CombatQueue delegation** — `PR.needsRecompile` and `PR.needsClearOverride` boolean flags replaced by direct calls to `VUI.CombatQueue.Add()` (already implemented in Lib.lua). Combat-blocked operations now queue correctly and execute atomically via the shared processor on `PLAYER_REGEN_ENABLED`; the `PLAYER_REGEN_ENABLED` handler in Core.lua is removed (Lib.lua owns it)
  - **Single cancellable scan timer** — `PR:ScheduleScan(delay)` method with one `PR._scanTimer` handle replaces three ad-hoc `C_Timer.After()` calls that stacked without cancelling each other
  - **Idempotent CVar management** — `PR:EnsureActionBarCVar(enabled)` value-checks before writing, so toggling enable/disable mid-session doesn't dirty the CVar when the value is already correct
  - **Compile dedup guard** — `_compileQueued` flag prevents multiple combat-blocked `CompileSequence()` calls from queueing more than one deferred execution
  - **Parameter-driven scan** — `ScanAndOverrideBarButton(macroName, verbose)` is now explicit-argument instead of hardcoded, ready for future multi-rotation support without structural change
  - **Per-macro override state** — `PR.overrides[macroName]` table replaces flat `overriddenButton`/`overriddenKeys` fields, matching the parameter-driven scan signature
  - **Explicit specID extraction** — `BuildDefaultProfile` in Profiles.lua uses explicit `if specIndex then ... end` instead of relying on Lua `and`/`or` multi-return discard, which was silently wrong when `GetSpecializationInfo` returned multiple values

## [1.6.24] - 2026-05-09

### Changed
- `VeritasUI_AdvancedOptions` — **All CVars tab: redesigned CVar editor from dropdown panel to inline edit.** Clicking a CVar row now turns the Value column into an editable field in-place — no overlay panel, no Set/Reset buttons, no DataProvider re-layout. Press Enter to apply, Escape to cancel, right-click to reset to default. This eliminates the `DataProvider:SignalUpdate()` dependency that was removed in Midnight (which caused the original crash) and all the layout issues that followed from trying to replace it. The extent calculator is now fixed-height (`ROW_H`) for all rows; the `EXPAND_H` constant and the shared editor frame are removed entirely

## [1.6.23] - 2026-05-09

### Fixed
- `VeritasUI_AdvancedOptions` — **All CVars tab: inline editor overlapped the row below and left a gap above.** The row frame stayed at `ROW_H` height even when the ScrollBox's extent calculator reserved `ROW_H + EXPAND_H`, and the editor anchored to `BOTTOMLEFT`/`BOTTOMRIGHT` (the row's bottom edge) which placed it outside the row's bounds. Fixed by dynamically setting the row height to `ROW_H + EXPAND_H` when expanded and anchoring the editor to `TOPLEFT` offset by `-ROW_H` — placing it directly below the CVar data line but inside the row's own allocated space

## [1.6.22] - 2026-05-09

### Fixed
- `VeritasUI_AdvancedOptions` — **All CVars tab: clicking a row to expand/edit crashed with "attempt to call a nil value" at Browser.lua:516.** `DataProvider:SignalUpdate()` was removed in Midnight. All three call sites (row expand/collapse, Set button, Reset button) called this nil method. Replaced with `FullRefresh()` which creates a fresh `DataProvider` and calls `scrollBox:SetDataProvider()` — the same proven path used by search, favourites, and initial populate. Required a forward declaration (`local FullRefresh` before the editor callbacks, assigned after ScrollBox setup) to avoid the Lua forward-reference-local-is-nil-in-closures trap

## [1.6.21] - 2026-05-04

### Fixed
- `VeritasUI_QualityOfLife` — **AFK Screen now reliably triggers on idle timeout.** Added a 5-second fallback poll (`UnitIsAFK("player")`) that detects AFK state independently of `PLAYER_FLAGS_CHANGED` event delivery. In Midnight, the event may not fire reliably for server-originated idle AFK in all contexts — the poll guarantees detection within 5 seconds regardless. The event handler remains for instant response when it does fire
  - **Secret Value hardening:** `UnitIsAFK` is tagged `SecretInChatMessagingLockdown` in Midnight and can return opaque secret values in restricted contexts. Both the event handler and the poll now guard with `pcall` + `issecretvalue` (matching ElvUI's defensive pattern via their `oUF:NotSecretValue` wrapper). If blocked, the poll silently retries on the next tick
  - **Dual-path architecture:** event handler (instant, when it fires) + poll (guaranteed, always running). Poll starts at `PLAYER_LOGIN` when AFK Screen is enabled; cost is one `pcall` every 5s with no allocations when state is unchanged

## [1.6.20] - 2026-05-04

### Fixed
- `VeritasUI_QualityOfLife` — **AFK Screen not triggering on idle timeout.** When WoW's server-side idle timer sets the AFK flag, `PLAYER_FLAGS_CHANGED` can fire with `arg1 = nil` (server-originated event without an explicit unit payload). The previous guard `if arg1 ~= "player"` treated `nil` as "not player" and bailed early, preventing `AFK_Enter()` from executing. Manual `/afk` was unaffected because the client-originated event always passes `arg1 = "player"`. Fixed by changing the guard to `if arg1 and arg1 ~= "player"` — nil is now treated as "self" and falls through to the `UnitIsAFK("player")` state check. Note: ElvUI's AFK module has the same unguarded pattern as of their current `main` branch

## [1.6.19] - 2026-05-03

### Added
- `VeritasUI_QualityOfLife` — **AFK Screen.** New toggle (default on) that activates a cinematic overlay when the player goes AFK. Hides all standard UI and displays character name (class-coloured), level, equipped item level, current zone/subzone, and a real-world clock over a slow camera orbit — designed to minimise OLED burn-in by eliminating static UI elements and keeping the screen moving
  - **Trigger:** `PLAYER_FLAGS_CHANGED` → `UnitIsAFK("player")`; dismissed when the server clears the AFK flag on character movement (keyboard input), matching Blizzard's default behavior
  - **UI hiding:** `UIParent:SetAlpha(0)` plus explicit `MinimapCluster:Hide()` (minimap has `SetIgnoreParentAlpha` in Blizzard code and bleeds through the alpha change)
  - **Camera:** `MoveViewRightStart(0.03)` slow orbit, stopped on exit
  - **Vignette:** four edge gradients (bottom/top 25%, left/right 20%) framing the 3D scene; single `OnSizeChanged` + `OnShow` handler for robust sizing
  - **Safety:** `PLAYER_LOGIN` unconditionally restores `UIParent` alpha and `MinimapCluster` visibility (crash/disconnect recovery); `PLAYER_LOGOUT` calls `AFK_Exit()` before the client saves frame state; `PLAYER_FLAGS_CHANGED` gated on `arg1 == "player"` to ignore group member flag changes
  - **Midnight hardening:** `GetAverageItemLevel` and the subsequent `format` call both wrapped in `pcall` for Secret Value safety; zone segment omitted from info line when `GetZoneText()` returns empty (loading screen/instance transition)

## [1.6.18] - 2026-05-03

### Changed
- `VeritasUI_AdvancedOptions` — **Both tabs now use Blizzard's native `WowScrollBoxList` + `MinimalScrollBar` for scrolling.** Replaces the custom `AttachSlimScrollbar` implementation with the same scroll system used by Blizzard's Talents, Professions, Housing, and Collections panels — pixel-identical scrollbar appearance and behavior
  - **Browser tab (All CVars):** Rewrote from manual 26-row virtual pool + bare `ScrollFrame` to native `WowScrollBoxList` + `CreateScrollBoxListLinearView` + `CreateDataProvider`. Blizzard's view handles row recycling natively; ~200 fewer lines of scroll plumbing. Inline editor and expand/collapse preserved
  - **Featured tab:** Converted from bare `ScrollFrame` to `WowScrollBoxList` with a flat data model — each category header, control, and inter-category gap is a separate list element. Controls are created once by the existing factory functions (`CreateCheckbox`/`CreateSlider`/`CreateDropdown`) and cached; the element initializer reparents them into whichever pool frame the ScrollBox assigns. Collapse/expand rebuilds the DataProvider

### Removed
- `VeritasUI_Lib` — **Removed `VUI.AttachSlimScrollbar` helper** (~240 lines). All consumers now use Blizzard's native `MinimalScrollBar` directly. Tombstone comment in Lib.lua points future modules to the AO implementations as reference

## [1.6.17] - 2026-05-03

### Improved
- `VeritasUI_QualityOfLife` — **Item level overlays now have a subtle bottom-vignette gradient for readability on busy or bright item art.** A vertical gradient fades from 70% black at the icon's bottom edge to fully transparent 24px above, ensuring ilvl numbers are legible regardless of the icon artwork behind them. Uses the Warcraft Wiki-documented `WHITE8x8` + `SetGradient` pattern with `colorRGBA` alpha interpolation (`SetColorTexture` does not support gradient alpha in Midnight — discovered during development). Single texture per button, zero extra frames

## [1.6.16] - 2026-05-03

### Fixed
- `VeritasUI_QualityOfLife` — **Auto Sell Junk no longer stalls mid-sell with large junk counts.** The sell chain relied entirely on `BAG_UPDATE_DELAYED` to drive each batch. If that event was lost — server throttle, event coalesced away, or bag reorganization swallowing the signal — the chain broke silently and remaining junk was never sold. Fix: a 0.5s safety timer (`SELL_RETRY_SEC`) now self-chains after every `SellNextBatch` call. If `BAG_UPDATE_DELAYED` fires normally (the common path), it cancels and replaces the timer. If the event is lost, the timer fires and resumes selling. The timer is cancelled on merchant close and on sell completion. Normal-path behavior and timing are unchanged

## [1.6.15] - 2026-05-03

### Fixed
- `VeritasUI_Lib` — **Fix Midnight Secret Value taint errors on faded action bars.** `HookHoverFade` previously hooked `OnEnter` on every child ActionButton via `HookScript`, which tainted their execution context. When `ACTIONBAR_UPDATE_COOLDOWN` fired in Secret Value zones (Delves, M+, raids), Blizzard's `ActionButton_UpdateCooldown` ran in the tainted context and `SetCooldown` rejected the Secret Values — producing `"bad argument #1 to 'SetCooldown'"` errors (175+ per Delve entry). Fix: child ActionButton `OnEnter` hooks removed entirely; the always-on 10 Hz poll now handles both hover-start and hover-end detection. Only the parent bar frame's `OnEnter` is hooked (not an ActionButton, so no taint). Poll was previously gated on `hovered` state; now runs unconditionally. Identical user-visible behavior, zero taint surface on ActionButton frames
- `VeritasUI_PriorityRotation` — **Remove `icon:Show()` from icon ticker to prevent latent taint.** `UpdateIcon` called `Show()` on the overridden ActionButton's icon texture from addon code every 0.25s. While `SetTexture` is unprotected, `Show()` on a child of a secure ActionButton propagates taint to the button's execution context, causing the same Secret Value errors when a rotation is active. Fix: `Show()` removed — `SetTexture(iconID)` alone is sufficient since the icon is already visible on any button with an assigned action

## [1.6.14] - 2026-05-02

### Fixed
- `VeritasUI_Lib` — **Rewrote `HookHoverFade` with hybrid poll-based hover detection.** The old event-driven `OnEnter`/`OnLeave` approach failed for action bars in Edit Mode layouts (e.g., 3×4 grids) where buttons extend beyond the parent bar frame's bounds — `MouseIsOver(target)` returned false while hovering a button, and `OnLeave`/`OnEnter` races between adjacent buttons left bars stuck visible. New approach: event-driven `OnEnter` for instant fade-in, `OnUpdate` poll (10 Hz, only active while hovered) for robust fade-out that checks target AND all direct children via `IsMouseOver()`. Cached child array with `RefreshChildren` handle avoids per-tick allocation. 150ms grace period prevents flicker between adjacent buttons. Zero per-frame cost while hidden
- `VeritasUI_CleanSolo` — `SetupActionBarFading` now captures the `RefreshChildren` handle and calls it on Edit Mode exit alongside `FadeOut`, so the child cache stays current after layout changes

## [1.6.13] - 2026-05-02

### Fixed
- `VeritasUI_CleanSolo` — **Fade Action Bars now re-hide after exiting Edit Mode.** Blizzard forces bars visible during Edit Mode layout editing, but no `OnLeave` fires on exit to trigger `FadeOut`. Fix: `SetupActionBarFading` now collects `FadeOut` handles returned by `HookHoverFade` and hooks `EditModeManagerFrame:ExitEditMode` to re-evaluate fade state 200ms after exit
- `VeritasUI_Lib` — `HookHoverFade` now returns its internal `FadeOut` closure so callers can force a re-evaluation after external state changes (e.g., Edit Mode exit). Existing callers that discard the return are unaffected

## [1.6.12] - 2026-05-02

### Fixed
- `VeritasUI_QualityOfLife` — **Auto Sell Junk now reports accurate earnings when Auto Repair is also active.** The `GetMoney()` snapshot was captured at sell-init time, but the preceding `AutoRepair` deduction could land asynchronously during the sell window, making the delta negative (clamped to 0 — "Sold 17 junk items for 0🥉"). Fix: the `startMoney` snapshot is now deferred to the moment the first `UseContainerItem` call fires inside `SellNextBatch`, giving the repair deduction time to settle in `GetMoney()` before the delta window opens

## [1.6.11] - 2026-05-02

### Fixed
- `VeritasUI_CleanSolo` — **Reverted v1.6.10 Fade Action Bars changes that broke persistence.** The v1.6.10 hardening commit added an early-return guard (`if val == db.fadeActionBarsLabel then return end`) in the dropdown callback that prevented the recompute + SetValue refresh from running when the Settings framework replayed a persisted value on load. This caused bar selections to silently reset to "None" across sessions. Restored the original working callback from v1.6.9 which handled all replay scenarios correctly

## [1.6.10] - 2026-05-02

### Fixed
- `VeritasUI_CleanSolo` — **Fade Action Bars selection now persists across sessions.** Blizzard's `Settings.RegisterAddOnSetting` framework persists the raw dropdown value (e.g. `"toggle:2"`) and replays it through the `SetValueChangedCallback` on the next login, re-toggling the bar OFF and resetting the label to "None". Fix: the display label is now computed fresh from the authoritative `fadeActionBars` table on every load, force-set on the setting after registration (overriding the stale persisted string), and the callback is suppressed during initialisation so the framework's restore replay is ignored. Bar selections in saved vars were always correct — only the display/callback replay was broken
- `VeritasUI_CleanSolo` — **Early-return on composite label re-selection in Fade Action Bars callback.** Prevents a no-op toggle cycle when the user clicks the already-displayed composite label in the dropdown

## [1.6.9] - 2026-05-02

### Added
- `VeritasUI_CleanSolo` — **Fade Action Bars: hover-reveal for action bars.** Designated bars fade to transparent when idle and reappear on mouseover. Uses `VUI.HookHoverFade` with an Edit Mode guard so bars stay visible during repositioning. Bars 2–8 are supported (Bar 1 is Blizzard-protected and excluded). Per-bar selection via a native `Settings.CreateDropdown` multi-select dropdown in the Options panel — modern gold-arrow style, part of the layout system, no floating frames or deferred anchoring. Toggling a bar in the dropdown marks it green; the dropdown label shows the current selection ("Bar 2" / "Bars 2, 5" / "None"). Saved vars: `fadeActionBars` table + `fadeActionBarsLabel` display string. Deep-copy table defaults on first init to avoid the shared-reference landmine

### Fixed
- `VeritasUI_CleanSolo` — **Player frame now reliably appears when joining combat initiated by another player.** `PLAYER_REGEN_DISABLED` can fire before `InCombatLockdown()` returns true on the same frame (known WoW timing quirk). Added a zero-delay deferred re-evaluation on `PLAYER_REGEN_DISABLED` that retries on the next frame when the lockdown flag has settled

## [1.6.8] - 2026-05-02

### Fixed
- `VeritasUI_CleanSolo` — **Player frame now reliably appears when joining combat initiated by another player.** `PLAYER_REGEN_DISABLED` can fire before `InCombatLockdown()` returns true on the same frame (known WoW timing quirk). When you initiate combat yourself, a near-simultaneous `UNIT_HEALTH` event masked the race, but when joining someone else's fight without immediately taking damage, the sole `Evaluate()` call saw `InCombatLockdown() == false` and the frame stayed hidden. Fix: a zero-delay deferred re-evaluation (`C_Timer.After(0, Evaluate)`) on `PLAYER_REGEN_DISABLED` retries on the next frame when the lockdown flag has settled

## [1.6.7] - 2026-05-02

### Changed
- `VeritasUI_AdvancedOptions` — **Browser tab rewritten as a virtual scroll list.** The old implementation created one full row frame (Button + 4 fontstrings + editor Frame + EditBox + 2 UIPanelButtons) per CVar — ~1,400 frames for 197 CVars. Every scroll interaction triggered `RefreshEntry` (pcall to `C_CVar.GetCVarInfo`) on all 197 entries and re-wired `SetScript` closures on every row. The new implementation uses a fixed pool of 26 row frames that are recycled as the user scrolls, with a single shared editor that repositions to the expanded row. Only the ~24 visible rows are bound and have their CVar values read on each scroll change. Click handlers, tooltips, and star toggles are wired once at pool creation and use a stable `row._entry` reference. Eliminates the game lock-up on first scroll and makes the tab feel instant
- `VeritasUI_AdvancedOptions` — Browser search now resets scroll position to top on every filter change. Previously, filtering down to a few results while scrolled deep into the full list left the viewport past the content, showing an empty list until the user scrolled up
- `VeritasUI_AdvancedOptions` — Browser tab scrollbar right-edge alignment normalized to match the Featured tab (both now at 16px inset from the parent's right edge)
- `VeritasUI_Lib` — `VUI.AttachSlimScrollbar` now includes hover-fade behaviour: the scrollbar starts invisible, fades in (0.15s) on mousewheel, hover, track click, or thumb drag, lingers for 1.5s after the last interaction, then fades out (0.4s). Stays visible during active thumb drag. Applies to both the Featured and Browser tabs automatically
- `VeritasUI_AdvancedOptions` — removed unused `math_abs` localization from `Browser.lua` (dead import from pre-virtual-scroll `Refresh`)

## [1.6.6] - 2026-05-02

### Removed
- `VeritasUI_AdvancedOptions` — removed 7 dead CVars from the Featured tab that were removed or replaced in WoW Midnight. **Nameplates:** `nameplateMotion` (dropdown), `nameplateOverlapH`, `nameplateOverlapV`, `nameplateOtherTopInset`, `nameplateOtherBottomInset` (sliders) — nameplate stacking is now per-unit-type (Enemy/Friendly) in Blizzard's Options → Nameplates panel. **Combat Text:** `WorldTextScale` (slider), `floatingCombatTextFloatMode` (dropdown) — no longer exposed as CVars. These controls appeared functional but were reading nil from `C_CVar.GetCVar`; sliders silently showed their min value, dropdowns showed "?"

### Changed
- `VeritasUI_AdvancedOptions` — `Controls.lua` dropdown factory (`CreateDropdown`) now uses `tostring()` coercion on both sides of value comparison and `ipairs()` for deterministic option iteration. Prevents potential mismatches between CVar string formatting and option table values
- `VeritasUI_AdvancedOptions` — `Core.lua` `GetCVar` now caches last-known-good values in saved vars (`cvarCache`). If a CVar returns nil (e.g. its Blizzard subsystem hasn't loaded yet), the cache provides a fallback. `SetCVar` also updates the cache on successful writes. Defensive measure for any future edge cases with late-loading LoD subsystems
- `VeritasUI_AdvancedOptions` — removed unused `PAD_Y` variable from `Featured.lua` and unused `CONTENT_W` constant from `Settings.lua`
- `VeritasUI_AdvancedOptions` — updated `GetCVar` docblock to reference the general late-loading subsystem case rather than specific removed CVars

## [1.6.5] - 2026-05-02

### Added
- `VeritasUI_AdvancedOptions` — the Featured tab now has the same slim scrollbar as the All CVars tab, for consistency across tabs. Mousewheel still works (as before), plus the new thumb can be dragged, and clicking the track above/below the thumb page-jumps. Scrollbar auto-hides when content fits in the visible area
- `VeritasUI_Lib` — new `VUI.AttachSlimScrollbar(scrollFrame, opts)` helper that attaches a modern Blizzard-style 8px slim scrollbar on the right edge of any ScrollFrame. Encapsulates the track / thumb / drag handling / mousewheel routing / page-jump behavior that was previously open-coded in `Browser.lua`. Options: `wheelStep`, `scrollbarWidth`, `gap`, `minThumbHeight`, `parent`. Returns an `update` function callers invoke after content-size changes so the thumb recomputes its height and position

### Changed
- `VeritasUI_AdvancedOptions` — `Browser.lua` refactored to call `VUI.AttachSlimScrollbar` instead of inline scrollbar code. ~105 lines of self-contained widget logic pulled out of the module; behavior preserved exactly (same wheel step of `ROW_H * 3`, same 8px scrollbar width, same 4px gap). Lowers drift risk between the two tabs' scrollbar implementations going forward
- `VeritasUI_AdvancedOptions` — Featured tab's scroll container is now inset 16px from the right edge (scrollbar width + gap + margin). `CW` (control row width) is reduced by the same 16px so right-anchored reset buttons fit cleanly within the scrollChild bounds instead of overflowing into the scrollbar gutter. Controls are ~3% narrower on a 520px window — imperceptible but arithmetically correct
- `VeritasUI_Lib` — added `math_max` and `math_min` localizations alongside the existing `math_abs` (required by the new scrollbar helper)

## [1.6.4] - 2026-05-02

### Added
- `VeritasUI_CleanSolo` — new "Transparent Chat Background" toggle (default on). Sets every chat frame's backdrop alpha to 0 via Blizzard's `FCF_SetWindowAlpha` API so only the text is visible when idle. Blizzard's built-in hover-to-reveal behavior still works — mousing over the chat frame reveals the background naturally. The color component is untouched, so any custom tint the user set in `/chatconfig` is preserved. Third arg to `FCF_SetWindowAlpha` (`doNotSave`) keeps the write session-volatile, so toggling the feature off and `/reload`ing restores Blizzard's saved alpha rather than leaving `alpha=0` baked into the profile
- `VeritasUI_CleanSolo` — Transparent Chat Background enforces itself against Blizzard's color picker. Hooks `FCF_SetWindowColor` (re-applies alpha=0 after any color change from the tab right-click → "Background" menu) and `FCF_SetWindowAlpha` (re-applies 0 if any code path — including Blizzard's opacityFunc firing on picker open — tries to set a non-zero alpha). Hooks are db-gated so toggling the feature off + `/reload` cleanly disables enforcement. Re-entry-guarded with a per-frame flag to prevent our own 0-write from looping through the alpha hook

## [1.6.3] - 2026-05-02

### Fixed
- `VeritasUI_PriorityRotation` — `C_CVar.SetCVar("ActionButtonUseKeyDown", ...)` is now `pcall`-wrapped at all three call sites (PLAYER_LOGIN handler, Enable setting callback on, Enable setting callback off). A raw error here would previously abort the rest of the login handler and leave PR half-initialized; now surfaces an amber warning and lets the rest of init proceed
- `VeritasUI_PriorityRotation` — `ScanAndOverrideBarButton` now counts slots that `pcall(GetActionInfo)` fails on (likely Midnight Secret Values in raid / M+ zones). When the user-initiated `/pr scan` or "Scan & Bind" button fails to find the Attack macro AND unreadable slots were present, prints an actionable diagnostic telling the user to re-scan after leaving the encounter or move the macro. Automatic scans (post-compile, post-login, post-spec-change) remain silent as before
- `VeritasUI_PriorityRotation` — `UpdateMacroStub` now returns a success boolean and warns the user with a red error when the account macro list is full (120/120). Previously the function silently no-op'd and callers printed a misleading "Macro is ready" message. Both user-facing callers (`/pr macro` slash command, "Create / Update Macro" button) now gate their success message on the return value

### Changed
- `VeritasUI_Lib` — corrected the `VUI.RegisterManagedPanel` docblock to accurately document the `pushable` default (`1`, Tier B coexist-with-everything) instead of the previously-claimed `0` (Tier A exclusive). Explains both tiers and clarifies when to pass `pushable=0` explicitly
- `VeritasUI_QualityOfLife` — map-coords `OnUpdate` now tracks a `dirty` flag and only calls `ResizeAnchor()` when player or cursor text actually changed. `GetStringWidth` / `GetStringHeight` / `SetSize` no longer fire 30×/sec on unchanged coordinates
- `VeritasUI_ZoneQuests` — first `BuildZoneNameSet()` call now assigns its result to `cachedNameSet` so subsequent `QUEST_LOG_UPDATE` events in the login-to-first-zone-change window reuse the cached set instead of rebuilding the map-hierarchy walk on every fire
- `VeritasUI_AdvancedOptions` — removed 4 duplicate entries from `Browser.lua` `KNOWN_CVARS` list (`movieSubtitle`, `showTimestamps`, `speechToText`, `textToSpeech` were each listed twice). List is now clean; 197 unique CVar names
- `VeritasUI_AdvancedOptions` — removed dead `thumb:RegisterForClicks` call on the Browser scrollbar thumb. Drag is implemented via `OnMouseDown` / `OnMouseUp` / `OnUpdate`; `RegisterForClicks` was a no-op
- `VeritasUI_AdvancedOptions` — Browser `expandedRow` (numeric list index) renamed to `expandedName` and keyed by CVar name. Toggling a favourite mid-session (which re-sorts the filtered list) no longer desyncs which row's inline editor is open

## [1.6.2] - 2026-05-02

### Changed
- `VeritasUI_QualityOfLife` — redesigned Map Coordinates display. Removed the metallic tooltip-style box (BackdropTemplate with border and tinted background) and lock icon button. Coordinates now render as two bare fontstrings side-by-side on one horizontal line: `Player: 42.0, 67.1  Cursor: —` with a black drop shadow for legibility against any map background. Player coords in gold, cursor coords in light gray. Frame strata set to DIALOG so the coordinates can be positioned anywhere on the map frame including the title bar chrome. Right-click the coordinates to toggle lock/unlock (cyan tint when unlocked); left-drag to reposition when unlocked. Hover tooltip provides contextual hint in both states. Settings tooltip updated to reflect the new interaction

## [1.6.1] - 2026-05-01

### Fixed
- `VeritasUI_PriorityRotation` — fixed Midnight taint error in `ActionButton_ApplyCooldown` caused by PR calling `SetAttribute` on Blizzard ActionButtons. Calling `SetAttribute("type", "click")` and `SetAttribute("clickbutton", ...)` from addon code taints the button's execution context; when Blizzard's own cooldown update code later passes Midnight Secret Values to `SetCooldown`, the tainted context throws `"Secret values are only allowed during untainted execution"`. Strategies 1 and 2 now only track which button frame holds the Attack macro (for the icon ticker) without modifying any attributes. Strategy 3 (`SetOverrideBindingClick`) is the sole click-routing mechanism — direct mouse clicks still work via the Attack macro's `/click PRAttackButton`

## [1.6.0] - 2026-04-28

### Added
- `VeritasUI_AdvancedOptions` — new module providing curated hidden settings and a full CVar browser. Features two tabs: a Featured tab with 9 collapsible categories (Camera, Nameplates, Combat Text, Action Bars, Targeting & Mouse, Tooltips & UI, Chat, Graphics, Accessibility) containing ~45 hand-picked settings with proper native controls (checkboxes, sliders, dropdowns), and an All CVars tab with a searchable browser listing every CVar on the client via `C_CVar.GetCVarInfo` probe fallback (Midnight removed `C_Console`). Browser features: star-favourite system (persisted, sorts to top), click-to-expand inline editor with Set/Reset buttons, modified-value highlighting, mousewheel + draggable slim scrollbar. Window uses `PortraitFrameTemplate` (520×660) registered as a Tier A UIPanel (`pushable=0`), matching the PriorityRotation panel pattern. Slash: `/ao`, `/advancedoptions`
- `VeritasUI_AdvancedOptions` control factory system in `Controls.lua` — three reusable factories (`CreateCheckbox`, `CreateSlider`, `CreateDropdown`) with per-control reset-to-default (`transmog-icon-revert` atlas), restart indicators for GX-restart CVars, and tooltips. Adding a new CVar to the Featured tab is a single table entry in `Featured.lua`
- `VeritasUI_AdvancedOptions` CVar browser uses a three-strategy enumeration: `C_Console.GetAllCommands()` (guarded), legacy `ConsoleGetAllCommands()`, then a ~170-entry known-CVar probe list as fallback. Midnight ships without `C_Console`, so the probe strategy fires and indexes all valid CVars via `C_CVar.GetCVarInfo`

## [1.5.1] - 2026-04-25

### Fixed
- `VeritasUI_PriorityRotation` combat-time Lua errors in Midnight — Blizzard `ActionButton.ApplyCooldown` and `SpellBookItem.UpdateCooldown` no longer throw "Secret values are only allowed during untainted execution" when PR is open during combat. Root cause: WoWUIBugs #783 — if a tainted (addon) dropdown is the first menu opened in a session, the menu compositor assigns a tainted `nil` to the shared menu frame's `minimumWidth` field, which then propagates through secure menu operations later. Applied Meorawr's workaround (Total-RP-3 PR #1242): call `root:SetMinimumWidth(CW)` at the top of every `SetupMenu` generator so the compositor sees a clean concrete integer instead of the tainted nil landmine
- `VeritasUI_PriorityRotation` spec dropdown label now updates live when the spec changes externally (via spec panel, macro, etc.). Switched from `SetDefaultText` (which only controls the label when no radio has been clicked) to `OverrideText`, which bypasses the click-label cache so `PLAYER_SPECIALIZATION_CHANGED` refreshes the display regardless of how the change originated
- `VeritasUI_PriorityRotation` window now sits flush against the instance-info side bar in M+ / raid zones. Added `win:SetToplevel(true)` to match Blizzard's `CharacterFrame` XML declaration — the frame now raises above same-strata frames (instance bar) when shown. Removed `width` / `height` from the `UIPanelWindows` registration so the manager reads live `GetWidth`/`GetHeight` from the frame instead of stale declared values, matching `CharacterFrame`'s entry exactly and eliminating a 1-2px horizontal drift

### Changed
- `VeritasUI_PriorityRotation` removed the green "Drop a spell, macro, or trinket here" bar at the bottom of the rotation editor — empty slots themselves accept drag-and-drop, and the `Spellbook` / `Macros` buttons in the Settings tab Tools section cover the "open spellbook" affordance. The Compiled Sequence card now grows into the reclaimed vertical space
- `VeritasUI_PriorityRotation` clicking an empty rotation slot toggles the Blizzard `PlayerSpellsFrame` (open if closed, close if open — same behaviour as the Spellbook button in Tools). Shift-clicking an empty slot toggles the Macro UI. Combat-guarded with a chat message. Empty-slot tooltip updated to document the new controls

## [1.5.0] - 2026-04-25

### Added
- `VeritasUI_Lib` — three new managed-panel helpers wrapping Blizzard's `UIPanelWindows` system: `VUI.RegisterManagedPanel(name, opts)`, `VUI.OpenManagedPanel(frame)`, `VUI.CloseManagedPanel(frame)`. Combat-safe via the existing `CombatQueue` and `pcall`-wrapped end-to-end. Documented Blizzard pushable values (`CharacterFrame=3`, `CollectionsJournal=0`, `ProfessionsFrame` outside `UIPanelWindows`) in the Lib comments for future module authors.
- `VeritasUI_PriorityRotation` Tools section in the Settings tab — spec switcher dropdown using the modern `WowStyle1DropdownTemplate`, plus `Spellbook` and `Macros` toggle buttons (click to open, click again to close) styled with `MagicButtonTemplate`
- `VeritasUI_PriorityRotation` trinket support — drag a trinket from your character pane or bag onto a rotation slot and PR will compile a `/use <ItemName>` macro for it. Item-name-based binding (not slot-based) so the rotation always fires THAT specific trinket. Restricted to `INVTYPE_TRINKET`; non-trinket items politely rejected. Editor displays trinkets with a yellow `[T]` tag, item icon, and standard Blizzard item tooltip on hover

### Changed
- `VeritasUI_PriorityRotation` settings panel now anchors to the standard Blizzard left edge via the `UIPanel` manager (`area="left"`, `pushable=0`) — visually and behaviourally indistinguishable from a Tier A primary panel like `CollectionsJournal`. Holds slot 1 against `CharacterFrame` / `SpellBookFrame` (which slide to slot 2), mutually exclusive with other Tier A panels (`Achievements`, `Housing`, `Maps`, `Appearances`). Escape closes it via `UISpecialFrames` registration. Replaces the previous floating `:SetPoint("CENTER")` + draggable behaviour
- `VeritasUI_PriorityRotation` editor help text and drop zone label updated to mention trinkets alongside spells and macros

### Fixed
- `VeritasUI_PriorityRotation` spec-switch handler now tries `C_SpecializationInfo.SetSpecialization` first and falls back to the global `SetSpecialization` — Midnight refactored the spec API into the `C_SpecializationInfo` namespace and the global may be absent or shimmed differently across builds

## [1.4.3] - 2026-04-25

### Changed
- `VeritasUI_PriorityRotation` rotation editor "Compiled Sequence:" label + preview text now wrapped in a card matching the Phase 2 row card style (dark fill + 1px warm-amber border)
- Sequence preview card width now aligns with the row cards (was previously narrower)
- Card border tint refined across all editor cards (rows + sequence preview) from `(0.28, 0.23, 0.14, 0.75)` to `(0.32, 0.26, 0.15, 0.80)` for a "recessed in stone" look
- Sequence preview now scrollable via mousewheel for long rotations (e.g. 10 slots × freq 5 = 50 entries) — text no longer bleeds out of the card or frame

## [1.4.2] - 2026-04-25

### Changed
- `VeritasUI_PriorityRotation` Settings tab action buttons (Create / Update Macro, Scan & Bind, Reset to Spec Defaults, Clear All Spells) swapped from `UIPanelButtonTemplate` to `MagicButtonTemplate` to match Blizzard's modern frame chrome (same template used by the Profession Specializations "Apply Knowledge" / "Overview" buttons)

## [1.4.1] - 2026-04-25

### Changed
- `VeritasUI_PriorityRotation` rotation editor rows now render as bordered cards — dark fill with a 1px warm-amber border using `BACKGROUND`/`BORDER` draw layers
- Row gap increased from 2px to 4px for visible card separation
- Freq spinner `< >` text buttons replaced with arrow texture buttons using `SetRotation`
- Freq value label upgraded from `GameFontNormalSmall` to `GameFontNormal` white
- Drop zone replaced with a green-bordered card to distinguish it as a drop target

### Fixed
- Freq arrow vertical misalignment — both arrows now use identical rotation (`-π/2`) by pairing `Arrow-Down-Up` (dec) and `Arrow-Up-Up` (inc) so WoW's renderer produces pixel-perfect vertical alignment

## [1.4.0] - 2026-04-25

### Changed
- `VeritasUI_PriorityRotation` settings panel rebuilt on `PortraitFrameTemplate` with modern frame chrome
- Portrait slot now shows current spec icon (falls back to class atlas for unspecced characters)
- Spec/class name displayed in `GameFontNormalHuge` white, horizontally centered below the portrait
- Title bar "Priority Rotation" re-anchored to center on full frame width
- Tab navigation replaced with `PanelTabButtonTemplate` bottom tabs (Journeys-style)
- Column headers in the rotation editor now anchor to row components for pixel-accurate alignment
- Row slot numbers changed to center-justified under the `#` header
- Settings tab redesigned with gold section headers, dividers, full-width primary buttons, and side-by-side secondary buttons
- Freq guidance corrected — Freq 3+ for priority/cooldowns, Freq 1 for fillers
- Removed hardware-specific key-repeat wording from Setup instructions
- All 18 starter profiles updated: priority/cooldown spells default to Freq 3, filler spells to Freq 1

## [1.3.27] - 2026-04-24

### Fixed

- **[ZoneQuests] Deep-copy table defaults on init** — the shallow default-fill loop assigned `DEFAULTS.manualWatched` by reference into `VeritasUI_ZoneQuestsDB.manualWatched`, so subsequent `SnapshotWatched()` writes would mutate the `DEFAULTS` constant at runtime. Benign in current code paths (`DEFAULTS.manualWatched` is never re-read after init) but a latent footgun that would produce silent cross-mutation the moment any future code read `DEFAULTS.manualWatched` as an empty template. Added a local `DeepCopy` helper invoked only on table-typed defaults — matches the "table defaults must be deep-copied on first init" landmine documented in the development skill

## [1.3.26] - 2026-04-24

### Added

- **[PriorityRotation] `/pr diag` command for 12.0.5 API diagnostic** — tests `issecretvalue`, `table.freeze`, `C_ActionBar.RegisterActionUIButton`, `C_Secrets`, `C_RestrictedActions` availability; checks `SetCVar` lockdown, `newtable()` in restricted execution, `GetActionInfo` secret values across all 120 action slots, `GetAttribute` step readability, and icon resolution. Run in different contexts (open world, M+, raid, Delve) to identify platform-specific API restrictions

## [1.3.25] - 2026-04-21

### Changed

- **TOC bump to Interface 120005** — WoW patch 12.0.5 is now live; updated all module TOC files from 120001 to 120005 for full compatibility.

## [1.3.24] - 2026-04-16

### Fixed

- **TOC revert to Interface 120001** — v1.3.23 pre-bumped the interface version to 120005 for patch 12.0.5, but WoW rejects addons with a TOC version *higher* than the running client — there is no "load anyway" override for that direction. Reverted to 120001 so the addon loads correctly on live 12.0.1. The 120005 bump will be re-applied on patch day.

## [1.3.23] - 2026-04-16

### Changed

- **TOC bump to Interface 120005** — Updated all module TOC files from 120001 to 120005 for WoW patch 12.0.5 compatibility.

## [1.3.22] - 2026-04-11

### Fixed

- **[QualityOfLife] Auto Sell Junk gold reporting wildly inaccurate** — The tally used `C_Item.GetItemInfo` to look up each sold item's vendor price and multiply by stack count. In Midnight, `sellPrice` can return stale or secret values that pass the pcall arithmetic guard but contain bogus numbers, producing reported totals 20–30× the actual amount earned. Replaced with a `GetMoney()` delta approach: the player's gold is snapshotted before selling begins, and the reported amount is `GetMoney() - startMoney` after all items are gone, which is always accurate.

## [1.3.21] - 2026-04-09

### Fixed

- **[All] Comprehensive code review hardening pass** — 16 findings addressed across all five modules:
  - **[PriorityRotation/Core] SafeQuote injection** — `InjectSequence` now dynamically selects a long-string nesting level that cannot appear in the macro body, eliminating the theoretical edge case where a macro containing `]==]` would corrupt the secure Execute call.
  - **[PriorityRotation/Core] MAX_ACCOUNT_MACROS nil guard** — `UpdateMacroStub` now falls back to `120` if `MAX_ACCOUNT_MACROS` is nil, preventing a Lua error that would silently block macro creation in Midnight if the constant is renamed.
  - **[PriorityRotation/Core] Remove dead WrapScript guard** — `if not step or not macros[step] then step = 1 end` was unreachable dead code after `step % #macros + 1`; removed.
  - **[PriorityRotation/Core] Icon ticker only starts when a bar button is overridden** — Starting the ticker in Strategy 3 (keybind-only mode) caused a permanent 4 Hz idle ticker that immediately returned on every tick; ticker now only starts when `overriddenButton` is non-nil.
  - **[PriorityRotation/Editor] Guard PanelTemplates_GetSelectedTab** — Added existence check before calling this Blizzard global, which could be nil or renamed in Midnight.
  - **[CleanSolo] NUM_CHAT_WINDOWS nil guard** — Loop now uses `(NUM_CHAT_WINDOWS or 10)` to prevent a `compare number with nil` error if the constant is absent.
  - **[CleanSolo] Chat tab scan skips missing frames** — Changed `break` on a missing chat frame to a `skip`; non-contiguous frame slots no longer abort the entire scan.
  - **[CleanSolo] PLAYER_REGEN events moved into SetupPlayerFrameFade** — Combat enter/leave events are now only registered when the Player Frame Fade feature is active, eliminating unconditional event overhead for users with the feature disabled.
  - **[CleanSolo] Document HideBagButtons retry pattern** — Added comment explaining why KillAll runs at 0s, 0.5s, and 2.0s (login-sequence re-show bursts from Blizzard bag frames).
  - **[QualityOfLife] AutoRepair race condition eliminated** — `GetRepairAllCost()` called synchronously after `RepairAllItems(true)` returns the pre-repair client-cached value before the server updates it, making the guild-vs-personal cost split unreliable. Now always follows guild repair with a personal repair call to cover any remainder, and reports the original total cost with a guild-bank note.
  - **[QualityOfLife] Document bank slot magic number** — Added comment clarifying that the `28` slot-count limit in the SetItemButtonQuality hook refers to Midnight's bank container (-1) slot range.
  - **[ZoneQuests] Skip BuildZoneNameSet when disabled** — Zone change events now invalidate the name cache but skip the expensive map-hierarchy rebuild when ZoneQuests filtering is off; the next enabled sync rebuilds lazily via `cachedNameSet or BuildZoneNameSet()`.
  - **[ZoneQuests] HeaderMatches threshold lowered** — Substring fallback search now applies to zone names longer than 2 characters (was 4), catching short zone names like "Vale" that weren't matched by the exact-lookup path.
  - **[ZoneQuests] Correct SnapshotWatched comment** — Comment previously said disabling ZQ "re-tracks everything"; corrected to accurately describe that RestoreWatched restores the snapshot taken at enable/login time, not at disable time.
  - **[Lib] Remove unnecessary pcall on GetAlpha** — `GetAlpha()` never raises on a valid WoW Frame; replaced with a direct call. Alpha is a rendering property, not a game-state value subject to Midnight secret-value restrictions.
  - **[Lib] HookAllChildren no longer called on every OnEnter** — MicroMenu child-hook registration now runs only once at setup; removed the redundant per-hover-enter iteration that fired on every mouse-enter of MicroMenu despite the `hooked[child]` guard.

## [1.3.20] - 2026-04-07

### Fixed

- **[Lib] Restore Reload UI button in AddOn settings panel** — v1.3.12 replaced the working OnUpdate polling approach with an event-driven hook on `SettingsPanel.SelectCategory` which does not fire correctly in Midnight 12.0.1, causing the button to never appear. Reverted to the original 0.25s poll which works regardless of API shape.

## [1.3.19] - 2026-04-07

### Changed

- **[PriorityRotation] Automatically manage `ActionButtonUseKeyDown` CVar** — PR now sets the CVar to `0` (key-up firing) on login when enabled and on toggle-on, and restores it to `1` (key-down / Press and Hold Casting) on login when disabled and on toggle-off. Previously the conflict was only warned about; users had to manage the CVar manually, leading to a permanently desynced state where neither PR nor P&H casting worked correctly.

## [1.3.18] - 2026-04-07

### Fixed

- **[QualityOfLife] Guard item-level overlay against Midnight secret value errors in raid combat** — `C_Item.GetItemInfoInstant` and `C_Item.GetDetailedItemLevelInfo` can return secret values during raid encounters in 12.0.1; the comparisons `equipLoc ~= ""` and `ilvl <= 0` were outside any pcall, causing "attempt to compare secret value" Lua errors on every item button update (loot windows, gear inspection). Both comparisons are now wrapped in pcall so they degrade silently — overlays simply won't display for items with restricted data during encounters.
- **[QualityOfLife] Guard auto-sell junk price tally against secret vendor prices** — `C_Item.GetItemInfo` returns vendor price as a secret value in Midnight; arithmetic on it (`qty * vp`) threw an unguarded error on every sell-session tally. Both the GetItemInfo call and the multiplication are now pcall-protected; if the price can't be read, the item count is still announced without a gold amount.

## [1.3.17] - 2026-04-02

### Fixed

- **[ZoneQuests] Manually highlighted cross-zone quests now reliably preserved** — v1.3.16 attempted to use `QUEST_WATCH_LIST_CHANGED` to track player highlights but the event handler only captured one argument, so the `added` flag was always `nil` and the quest was never pinned; replaced the event-based approach entirely: `SyncTracking` now calls `C_SuperTrack.GetSuperTrackedQuestID()` directly at sync time and exempts the active super-tracked quest (the one with the minimap arrow) from zone-based removal; `SUPER_TRACKING_CHANGED` triggers a debounced re-sync so the quest is removed from the tracker promptly when the player clears the arrow

## [1.3.16] - 2026-04-02

### Fixed

- **[ZoneQuests] Manually highlighted cross-zone quests no longer auto-removed** — clicking a quest on the world map to set a minimap direction arrow triggered a zone-sync that immediately removed the quest from the Objective Tracker; the addon now tracks player-initiated highlight events via `QUEST_WATCH_LIST_CHANGED` and exempts those quests from zone-based removal until the player explicitly un-highlights them; quests un-highlighted while in a different zone are removed from the tracker normally

## [1.3.15] - 2026-04-01

### Fixed

- **[QualityOfLife] Fix Auto Sell Junk selling no items at all** — `MERCHANT_SHOW` fires before `MerchantFrame:IsShown()` returns `true`; the sell guard was immediately killing `sellState` and unregistering `BAG_UPDATE_DELAYED` before any items were sold. Fix: defer `AutoSellJunk()` by one frame with `C_Timer.After(0, AutoSellJunk)`.

## [1.3.14] - 2026-04-01

### Fixed

- **[QualityOfLife] Fix Auto Sell Junk stopping prematurely when server-throttled items remain locked mid-batch; reduce batch size from 12 to 9 to stay within WoW's server-side sell rate limit (matches Scrap addon's approach)**

## [1.3.13] - 2026-03-31

### Fixed

- **[CleanSolo] Fix syntax error from v1.3.12 audit** — the `inCombat` variable deletion merged two `local` declarations onto one line (`falselocal`), producing a Lua syntax error that prevented CleanSolo from loading; all fading features (chat tabs, micro menu, player frame) were non-functional

### Removed

- **[TOC] Revert Addon Compartment IconTexture** — removed the `## IconTexture` directive added in v1.3.12; the modules now use the default compartment icon as before

## [1.3.12] - 2026-03-31

### Changed

- **[Lib] SmoothFade zero-allocation iteration** — replaced `pairs()` iterator in the OnUpdate handler with `next()`-based traversal, eliminating a per-frame closure allocation during active fades
- **[Lib] Event-driven reload button visibility** — replaced the 0.25 s OnUpdate poll with `hooksecurefunc` on `SettingsPanel.SelectCategory`, so the Reload UI button now updates only on category changes instead of every frame while settings are open
- **[CleanSolo] Use `InCombatLockdown()` directly** — removed the redundant manual `inCombat` state variable; the player-frame fade system now queries `InCombatLockdown()` as the authoritative combat check, eliminating duplicate state tracking
- **[CleanSolo] Remove unnecessary pcall in chat tab hook** — the `SetAlpha` hook guard logic only accesses local variables and safe frame methods; the defensive `pcall(function() ... end)` wrapper was creating a closure on every `SetAlpha` call across all chat tabs
- **[QualityOfLife] Localize `C_Navigation` and `C_SuperTrack`** — added file-scope locals consistent with the rest of the hot-globals discipline
- **[QualityOfLife] `/way` comma normalization** — `gsub(",", ".")` on input so European-locale coordinate pastes (e.g. `45,2 56,3`) parse correctly
- **[QualityOfLife] Cache `IsQuestRewardButton` results** — the `SetItemButtonQuality` global hook now caches button-name lookups, avoiding repeated `string.find` + parent-chain walks on every bag open
- **[ZoneQuests] Cache zone name set** — `BuildZoneNameSet()` (which walks the `C_Map` hierarchy) is now called only on `ZONE_CHANGED*` events; `QUEST_LOG_UPDATE` syncs reuse the cached set
- **[ZoneQuests] Single-pass `SyncTracking`** — merged the previous two-pass remove-then-add design into one pass over the quest log, halving API calls and eliminating a theoretical stale-header race between passes

### Fixed

- **[CleanSolo] Stale section comment** — removed a duplicate `-- Feature: Hide Social Button` header left behind by the v1.3.11 neutral-nameplate removal

### Added

- **[TOC] Addon Compartment icon** — all five `.toc` files now specify `## IconTexture: Interface\Icons\INV_Misc_Gear_01` so the modules display a consistent gear icon in the minimap Addon Compartment menu instead of a generic placeholder

## [1.3.11] - 2026-03-31

### Removed

- **[CleanSolo] Remove Hide Neutral Nameplates feature** — the feature never worked reliably across all zone types (Blizzard housing neighborhoods, phased areas, etc.) and required 9 iterative fix attempts (v1.3.2–v1.3.10) without reaching a stable state; the entire feature has been removed: default setting, ~190-line `SetupHideNeutralPlates()` function, options panel checkbox, and activation call; `CleanSolo.lua` reduced from 570 to 380 lines

### Changed

- **[QualityOfLife] Rewrite Auto Sell Junk with event-driven batch selling** — the previous timer-based approach (`C_Timer.NewTicker(0)` with batches of 6) hit the WoW client's implicit action throttle at ~9 items, requiring multiple merchant window reopens to sell large inventories; the new implementation follows the pattern used by Scrap (the most popular junk-selling addon): sells up to 12 items per cycle, then waits for `BAG_UPDATE_DELAYED` (fired after the client processes bag changes) before selling the next batch; the game's own event cadence provides natural throttling, handling any number of junk items reliably; also adds `isLocked` checks to avoid selling items mid-transfer and `MERCHANT_CLOSED` registration to clean up if the vendor window closes mid-sell

## [1.3.10] - 2026-03-29

### Changed

- **[CleanSolo] Restore v1.3.1 neutral nameplate code as the definitive implementation** — confirmed working correctly in standard game zones (tested in Eversong Woods: neutral mobs hidden, nameplate appears as hostile immediately on aggro); the taint errors observed in v1.3.2–v1.3.9 were triggered by Blizzard housing neighborhood zones which use non-standard NPC behavior, not by the addon code itself; v1.3.1 logic is restored verbatim and this is now the stable baseline

## [1.3.9] - 2026-03-29

### Changed

- **[CleanSolo] Rewrite neutral nameplate hiding — no combat log, no taint** — removed all combat log / GUID tracking code; the new approach is: hide neutral plates (reaction == 4) out of combat via `plate:SetAlpha(0)` on the NamePlate parent frame (not `plate.UnitFrame`); on `PLAYER_REGEN_DISABLED` lift all suppression immediately so Blizzard's default combat display runs untouched; Blizzard fires `UNIT_FACTION` when a neutral mob is attacked and its reaction changes to hostile — the re-evaluation triggered by that event keeps the plate visible naturally; after combat ends (`PLAYER_REGEN_ENABLED`) neutral plates are re-hidden

## [1.3.8] - 2026-03-29

### Fixed

- **[CleanSolo] Fix persistent `ADDON_ACTION_BLOCKED` taint — root cause: `SetAlpha()` on `plate.UnitFrame`** — in TWW (11.0) and Midnight (12.0), `SetAlpha()` on `CompactUnitFrame` objects (nameplate UnitFrames) became a protected action that is blocked during combat lockdown; every previous fix attempt still called `uf:SetAlpha()` directly or indirectly; the correct fix is to operate exclusively on the `plate` frame (the NamePlate parent, which is not a CompactUnitFrame and whose `SetAlpha` is not protected); a `hiddenPlates` table tracks suppressed plates, and a lightweight `OnUpdate` loop continuously holds them at alpha 0 — idling when no plates are suppressed; `ShowPlate` removes the plate from `hiddenPlates` and does NOT call `SetAlpha(1)`, allowing `NamePlateDriverFrame` to restore the alpha naturally on the next frame; the entire `CompactUnitFrame_UpdateAll` hook was removed; no code anywhere in the feature now touches `plate.UnitFrame` for alpha/visibility

## [1.3.7] - 2026-03-29

### Fixed

- **[CleanSolo] Remove quest-name-visibility code that was causing taint** — the `ApplyQuestName` / `_vui_questName` system (added in v1.2.2) forced `uf.name:SetAlpha(1)` on nameplate sub-elements and re-applied it in the `CompactUnitFrame_UpdateAll` hook; accessing and writing to sub-elements of protected nameplate UnitFrames was the source of the persistent `ADDON_ACTION_BLOCKED` warning; removed the feature entirely — neutral plate hiding and quest-related plate showing both continue to work correctly

## [1.3.6] - 2026-03-29

### Fixed

- **[CleanSolo] Fix remaining "action blocked" taint error** — the combat log handler was calling `EvaluateNameplate`, which calls `IsQuestRelated` → `C_TooltipInfo.GetUnit`; calling tooltip APIs mid-combat is the taint source; the handler now only does the one thing it needs to — directly clears `_vui_hideNeutral` and restores alpha on the matching plate, with no tooltip scanning or other API calls

## [1.3.5] - 2026-03-29

### Fixed

- **[CleanSolo] Fix "action blocked" taint error** — `ClearQuestName` called Blizzard's `CompactUnitFrame_UpdateName(uf)` which internally calls `Show()` on protected nameplate sub-elements; the new combat log handler triggers `EvaluateNameplate` mid-combat far more frequently than before, making the taint reliably reproducible; removed the direct call entirely — clearing the `_vui_questName` flag is sufficient because Blizzard's own `CompactUnitFrame_UpdateAll` refresh cycle restores the name state naturally

## [1.3.4] - 2026-03-29

### Fixed

- **[CleanSolo] Fix taint error from combat log listener** — `COMBAT_LOG_EVENT_UNFILTERED` was registered on the same frame as nameplate events; `CombatLogGetCurrentEventInfo()` tainted the secure nameplate dispatch path, triggering "action blocked" warnings; the combat log listener now runs on its own isolated frame

## [1.3.3] - 2026-03-29

### Fixed

- **[CleanSolo] Neutral nameplates now reliably appear when the mob is attacked** — `UnitReaction` permanently returns 4 (neutral) even after aggro, and `UnitThreatSituation` returns nil for mobs without a standard threat table, so previous detection (events + API checks) silently failed; now uses `COMBAT_LOG_EVENT_UNFILTERED` to track GUIDs the player has exchanged damage with — the only fully reliable signal; engaged GUIDs are cleared on `PLAYER_REGEN_ENABLED` so plates re-hide after combat ends

## [1.3.2] - 2026-03-29

### Fixed

- **[CleanSolo] Neutral nameplates now appear when the mob is attacked** — attacking a neutral mob hid its nameplate because the `UNIT_FACTION` event does not fire on aggro and `UnitAffectingCombat` may not update in time; now listens for `UNIT_THREAT_LIST_UPDATE` (fires the instant a mob's threat table changes) and checks `UnitThreatSituation("player", unit)` as a secondary combat indicator, so the plate reappears immediately when you engage a neutral target

## [1.3.1] - 2026-03-29

### Added

- **[QualityOfLife] `/way` auto-clears on arrival** — after setting a waypoint, a background ticker polls `C_Navigation.GetDistance()` once per second; when the player comes within 10 yards the waypoint is automatically cleared and the minimap arrow dismissed, matching the feel of Blizzard's native destination pins; `/way clear` and any external clear (right-click map UI) also cancel the tracker via the `USER_WAYPOINT_UPDATED` event

## [1.3.0] - 2026-03-29

### Added

- **[QualityOfLife] TomTom-compatible `/way` waypoint command** — parses the standard TomTom waypoint syntax and places a native Blizzard user waypoint pin on the World Map; activates the minimap directional arrow automatically via `C_SuperTrack`, identical to right-clicking the map and choosing "Set Waypoint"; no TomTom addon required
  - `/way #mapID x y` — set a waypoint on a specific map by numeric ID (e.g. `/way #2351 45.2 56.3`)
  - `/way x y` — set a waypoint on the current zone at the given coordinates
  - Optional label appended after coordinates is echoed in the confirmation message (e.g. `/way #2351 45.2 56.3 Herb Node`)
  - `/way clear` — removes the active waypoint and deactivates the minimap arrow
  - Validates that the map ID exists via `C_Map.GetMapInfo()` and that coordinates are in the 0–100 range before setting; prints a usage hint on malformed input

## [1.2.2] - 2026-03-28

### Fixed

- **[CleanSolo] Quest enemy and neutral nameplate names now reliably visible** — `NAME_PLATE_UNIT_ADDED` was evaluating quest status synchronously on the first frame, before `C_TooltipInfo.GetUnit` had populated tooltip data for the new nameplate token; a deferred re-evaluation (`C_Timer.After(0.15)`) now corrects any false-hide applied on that first frame

### Added

- **[CleanSolo] Enemy quest NPCs now show their name in the nameplate** — previously the feature only controlled whether neutral nameplates were hidden; now any unit (neutral or hostile) that is quest-related has its nameplate name forced visible via `uf.name:SetAlpha(1)`, persisted through Blizzard's refresh cycle by the existing `CompactUnitFrame_UpdateAll` hook; non-quest enemy nameplates are unaffected and follow the player's Blizzard nameplate settings

## [1.2.1] - 2026-03-28

### Fixed

- **[PriorityRotation] Disable during combat now properly defers override cleanup** — unchecking "Enable Priority Rotation" in the Settings panel while in combat silently skipped `ClearOverride()`, leaving keybind overrides active until the next recompile or `/reload`; a new `needsClearOverride` flag now queues the cleanup for `PLAYER_REGEN_ENABLED`
- **[QualityOfLife] Auto-repair now correctly reports split guild/personal costs** — when guild bank funds only partially covered repair costs, the fallthrough to personal gold reported the total cost without qualifier; now reports the breakdown (e.g. "800g guild, 200g personal")
- **[CleanSolo] Nameplate evaluation now safe against Midnight Secret Values** — `UnitReaction()` and `UnitAffectingCombat()` on nameplate unit tokens may return Secret Values in Midnight 12.0; both calls are now pcall-wrapped with `issecretvalue()` checks, degrading gracefully (show the plate if uncertain)

### Changed

- **[QualityOfLife] `SetItemButtonQuality` hook deduplicated** — removed ~30 lines of duplicated equippability/skip/ilvl checks; the hook now resolves the item link and delegates to the existing `ProcessItem()` function
- **[CleanSolo] Nameplate evaluation logic collapsed** — three copy-pasted "restore and return" blocks replaced with a shared `RestoreNameplate()` helper and a combined condition
- **[ZoneQuests] `RestoreWatched` reduced from two passes to one** — uses idempotent `AddQuestWatch`/`RemoveQuestWatch` in a single loop
- **[PriorityRotation] `PR.VERSION` now references `VUI.VERSION`** — eliminates version string drift; only Lib.lua needs updating for future releases
- **[PriorityRotation] `SECURE_HANDLER` frame named `"PRSecureHandler"`** — visible in `/fstack` and `/dump` for easier debugging
- **[QualityOfLife] Added `## OptionalDeps: Blizzard_WorldMap`** to TOC — reduces deferred loader path for Map Coordinates
- **[QualityOfLife] Map coordinates `SavePosition` guarded against zero effective scale** — added `containerScale == 0` early return before division
- **[CleanSolo] Added documentation comments for Midnight API risks** — `CompactUnitFrame_UpdateAll` hook and tooltip color heuristic fragility noted inline

## [1.2.0] - 2026-03-28

### Added

- **QualityOfLife module** — map coordinates, item levels, auto-repair, and auto-sell extracted from CleanSolo into their own dedicated module (`VeritasUI_QualityOfLife`)
- **Macro support in Priority Rotation** — rotation slots now accept WoW macros in addition to spellbook spells; macro tooltips resolve the underlying spell via `#showtooltip` / `/cast` parsing
- **Neutral nameplate hiding** in CleanSolo — hides nameplates for neutral mobs unless they are quest-related or in combat; re-evaluates on combat state changes

### Fixed

- **Priority Rotation profile header** showing "Vengeance 0" — replaced broken seventh return value from `GetSpecializationInfo` with `UnitClass("player")`
- **Junk selling overcounting** — all `UseContainerItem` calls were firing in a single frame, hitting server throttle limits; rewritten to batch sells at 6 per frame with re-verification
- **Map coordinates position not persisting** — `StartMoving()` silently re-anchors to `UIParent`; fixed by saving `GetLeft()`/`GetBottom()` screen-space coordinates normalized through effective scales
- **Map coordinates box width** reduced from 146px to 126px to remove dead space
- **Chat tab fade persistence** — tabs remaining visible after mouse leaves; replaced `OnUpdate` enforcer with synchronous `hooksecurefunc(tab, "SetAlpha")` three-state guard
- **Item level display on legacy legendaries** (Heart of Azeroth showing 371 instead of 72) and junk items showing inflated values
- **Addon compartment handlers** not opening settings panels — was passing string display names to `Settings.OpenToCategory()` instead of numeric category ID from `category:GetID()`

### Changed

- **Comprehensive code audit** across all 8 Lua files — adopted recommendations from external review including: `pcall` wrapping on chat tab `SetAlpha` hook, guild-vs-personal funding source reporting in auto-repair, `PR.db` alias for PriorityRotation, `sv` renamed to `db` in ZoneQuests for suite-wide consistency
- **Reload UI button** moved from per-addon implementation to shared `VUI.RegisterSettingsLabel()` infrastructure in Lib.lua — only shows when a VeritasUI category is active
- Character-specific macros now correctly resolve tab-relative vs. absolute index using `MAX_ACCOUNT_MACROS` offset

## [1.1.0] - 2026-03-26

### Added

- **Map Coordinates** display on the World Map — player and cursor coordinates using native tooltip backdrop textures
- **Lock/unlock repositioning** for map coordinates — lock icon button (not right-click, which conflicts with map zoom); click to unlock (border turns cyan), drag freely, click to save and lock
- **"Create / Update Macro" button** added to Priority Rotation Settings UI
- **Static `SLOT_TO_FRAME` lookup table** for action bar detection in Priority Rotation — replaces unreliable `action` attribute polling

### Fixed

- **Action bar detection** in Priority Rotation — `SetOverrideBindingClick` requires a shown target; `PRAttackButton` made visible at 1×1px off-screen
- **Map coordinates positioned bottom-right** to avoid Blizzard's faction icons (was bottom-left)
- **`OnDragStop` firing on simple clicks** — removed auto-lock-on-drop; lock button is the sole toggle

### Changed

- Adopted external audit as new baseline — acknowledged missed bugs (SuppressFrame stacking, sparse array handling in HandleDrop, fade system inconsistency, AutoRepair fallback)
- Quest reward item level display **fully removed** — fundamental async loading and base vs. effective ilvl mismatch makes reliable display impractical

## [1.0.0] - 2026-03-23

### Added

- **VeritasUI suite created** — unified CleanSolo, PriorityRotation, and ZoneQuests under a single package with shared library, following ElvUI's multi-folder pattern
- **VeritasUI\_Lib** — shared utilities: `VUI.Print()` formatter, `SmoothFade` per-frame fade manager, `HookPlayerFrameFade` with event-timing health detection, native settings panel helpers
- **Hide Macro Names** on action bar buttons — hooks `SetText` and `Show` on button name fontstrings across all action bars
- **Hide Error Text** — unregisters `UI_ERROR_MESSAGE` from `UIErrorsFrame`
- **Auto Sell Junk** — sells gray items on `MERCHANT_SHOW` with `GetCoinTextureString` coin icon output
- **Auto Repair** — repairs gear at repair merchants, guild funds first with fallback to personal gold
- **Item Level Overlays** — universal `SetItemButtonQuality` hook covering bags, character panel, bank, and warband bank with full link resolution cascade
- **Merchant item level scanner** — dedicated scanner using `GetMerchantItemLink(idx)` since `SetItemButtonQuality` doesn't fire on merchant buttons
- **Native settings panels** for all modules using `Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnSetting` + `Settings.CreateCheckbox`
- **Addon Compartment** integration for all modules

### Fixed

- **"Interface action failed" combat errors** — Priority Rotation icon ticker was modifying secure button textures from tainted code; added `InCombatLockdown()` guard
- **Player frame invisible at low health** — Midnight Secret Values block all health comparison from addon code; implemented event-timing via `UNIT_HEALTH` (~2s regen cadence) with 3-second idle timer
- **Player frame stuck visible** — hover detection gap when mouse moves from parent to child frame; added 200ms poll ticker
- **Overlapping fade conflicts** — replaced Blizzard's global `UIFrameFadeIn`/`UIFrameFadeOut` with custom per-frame `SmoothFade` manager
- **False spec-switch messages** in Priority Rotation on battleground entry — track `PR._lastProfileKey` to only react on actual spec changes
- **Bag button taint errors** — `Hide()` on SecureActionButton children guarded with `InCombatLockdown()`, `SetAlpha(0)` as visual fallback
- **Item level showing base ilvl instead of effective** — added link resolution cascade: `GetItemLink()` → `GetBagID/GetID` → `GetBankTabID/GetContainerSlotID` → main bank check → `GetInventoryItemLink`
- **Settings panel `SetValueChangedCallback`** — fixed 3-arg signature to correct 2-arg `(setting, value)` for Midnight

### Changed

- **Comprehensive code polish** — localized hot globals across all files, conditional event registration, extracted named functions from anonymous closures to reduce GC pressure

## Pre-VeritasUI History

The addons below were developed as standalone projects before being unified into VeritasUI.

### PriorityRotation (standalone)

#### v2.2.0 — 2026-03-22

- Final standalone version before VeritasUI consolidation
- Clean verification pass: removed dead auto-mode code, unused debug flags, stale references
- Macro renamed from "PriorityRot" to "Attack"

#### v2.1.0 — 2026-03-22

- Renamed macro and button from "PriorityRot" / "PriorityRotButton" to "Attack" / "PRAttackButton"
- Added dynamic icon showing current spell on the action bar via 150ms ticker

#### v2.0.0 — 2026-03-22

- **Major rewrite** — discovered GSE's action bar override mechanism via source code analysis
- Replaced broken `SecureActionButton` + `PreClick` approach with `SecureHandlerWrapScript` restricted snippet
- Zero-taint combat execution: restricted snippet cycles macros via attributes only, no addon code contact
- Discovered `GetCursorInfo()` returns 4 values for spells (spell ID is 4th, not 2nd)
- Discovered Press and Hold Casting (`ActionButtonUseKeyDown` CVar) conflicts with override mechanism
- Added weighted sequence compiler with zip-interleave distribution
- Per-spec profiles with auto-switch on `PLAYER_SPECIALIZATION_CHANGED`
- Drag-and-drop editor with spellbook integration
- DPS tested: 32.5K (addon) vs 31K (raw G-Hub) vs 44.6K (Blizzard SBA with Press and Hold)

#### v1.0.0 — 2026-03-21

- Initial version with custom floating editor window
- Broken: `/pr` command not working (frame GetWidth() returning 0 during construction)
- Broken: Options panel (OptionsSliderTemplate deprecated, RegisterCanvasLayoutCategory wrong args)

### CleanSolo (standalone)

#### v4.1 — 2026-03-22

- Removed health check from player frame fade (too much friction with Secret Values)
- Added `InCombatLockdown()` guards on all `Hide()` calls with `SetAlpha(0)` fallback

#### v4.0 — 2026-03-22

- Settings panel rewrite using `Settings.RegisterVerticalLayoutCategory`
- Added Reload UI button anchored to Defaults button
- Fixed `SetValueChangedCallback` 3-arg → 2-arg signature

#### v3.7 — 2026-03-22

- Stripped player frame fade to absolute minimum: `C_Timer.NewTicker(0.2)` with direct `SetAlpha`
- Removed all `hooksecurefunc` and `UIFrameFadeIn/Out` calls that caused infinite loops

#### v3.6 — 2026-03-22

- Added `hooksecurefunc(pf, "SetAlpha")` — caused infinite recursion (thousands of errors/sec)

#### v2.0 — 2026-03-22

- Added fade micro menu, fade player frame, hide bag buttons
- Settings panel with SavedVariables

#### v1.1 — 2026-03-21

- Changed chat tabs from hard-hide to fade-with-chat-window behavior
- Tabs now visible and interactable on mouseover

#### v1.0 — 2026-03-21

- Initial version: hide chat tabs, social button, chat buttons, voice chat button

### ZoneQuests (standalone)

#### v7.0 — 2026-03-21

- Final standalone version — stable, full-featured
- Always-show categories: Campaign, Important, Legendary, Meta, Repeatable
- Important quests identified via `GetQuestTagInfo` returning tagID 282
- Settings panel integrated into both floating panel and Options canvas

#### v5.0–v6.0 — 2026-03-21

- Added settings panel with always-show category checkboxes
- Fixed Options canvas content overlap (`TOP_OFFSET` -16 → -72)
- Fixed `UpdateState` not firing on panel open (added `OnShow` scripts)
- Fixed blank toggle button text

#### v3.0–v4.0 — 2026-03-21

- Robust zone matching: `C_Map` hierarchy walk, directional prefix stripping
- Infinite loop guard (visited set + hard cap of 20 iterations)
- Nil map ID handling for loading screens
- Event debouncing for `QUEST_LOG_UPDATE` bursts

#### v2.0 — 2026-03-21

- **Major rewrite** — switched from custom floating panel to managing the native Objective Tracker via quest watch state
- Fixed SavedVariables initialization timing (must use `ADDON_LOADED`, not file scope)
- Discovered `IsQuestWatched` removed in Midnight 12.0 — use `Add/RemoveQuestWatch` directly

#### v1.0 — 2026-03-21

- Initial version: custom floating panel showing zone-filtered quests
- Basic zone matching with bidirectional substring check
