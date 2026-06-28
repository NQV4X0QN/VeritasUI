# VeritasUI — Probe Library & Verified Blizzard Reference

**Status:** LIVING DOCUMENT — append-only reference, never "done."
**Target:** WoW Midnight retail, Interface `120005` (12.0.7).
**Last updated:** 2026-06-27, suite at **v1.7.15**, `main` @ `64a7ede`.

> **Why this file exists.** Over many sessions we have repeatedly burned hours
> rediscovering the same in-game facts by trial and error — exact atlas names, coin
> markup, font objects, frame coordinates — and then *thrown away the probe scripts
> that found them.* Worse, several "verified" claims baked into code comments turned
> out to be **wrong** when finally re-measured (the tooltip coin size was commented
> "13×13" but is actually 14×14; `NumberFontNormalRight` was called the money font
> that "tracks Blizzard automatically" but did not). This document is the corrective:
>
> 1. A **library of probe scripts** that work, so we never reinvent them.
> 2. A table of **known-good Blizzard values** confirmed by those probes on a real
>    client — the values we trust over any code comment.
> 3. **Revert recipes** for changes that were hard-won and might need backing out if
>    Blizzard reverses course.
>
> **Trust rule established by experience:** a value in THIS file (with a date + the
> probe that produced it) outranks any assertion in code comments or SKILL.md. If they
> disagree, re-run the probe and update here.

---

## 0. How to use a probe in-game

Most users run with **chat input disabled**, so pasted `/run` lines may not be an
option, and the 255-char chat limit truncates long commands silently. The reliable
patterns, in order of preference:

1. **Inject → reload → read → strip.** Add a one-shot probe block into the relevant
   addon hook (guarded by an `AH._probeFlag` so it fires once), `rsync` to live,
   have the user `/reload`, read what it prints to chat, then **remove the probe**
   before shipping. This is the workhorse — it needs zero typing from the user and
   works regardless of chat settings. Mark every injected probe with
   `-- >>> ONE-SHOT … PROBE — REMOVE BEFORE SHIPPING <<<` / `-- <<< END PROBE >>>`
   so it is grep-findable (`grep -rn 'PROBE\|REMOVE BEFORE'`) before release.
2. **Macro button** (if a quick read is wanted without an addon edit): put the line
   in a `/macro`, drag to the action bar, hover the target, press the key. Keeps the
   mouse on the element (chat box would steal focus).
3. **Always measure command length first** against the 255 limit (use the python
   sandbox to `len()` it) before handing a `/run` line to the user.

**Lua tooling on this machine:** `luac` lives at
`/opt/homebrew/opt/lua@5.4/bin/luac` (keg-only, not on PATH — `command -v luac`
returns nothing; check the explicit path). `luacheck` IS on PATH. Always
`luac -p <file>` and `luacheck <file>` before every deploy. Expect benign
"accessing undefined variable" warnings for WoW globals (`GameTooltip`,
`NumberFontNormalRight`, `GameTooltipText`, `C_Texture`, etc.) — luacheck has no
WoW symbol table; those are not real errors.

---

## 1. Probe scripts (copy, adapt the flag name, strip after)

### 1.1 Texture / atlas under the mouse
Find what atlas a hovered UI element uses. `GetMouseFoci()` returns frames under the
cursor; many fills are **texture regions**, not StatusBars, so scan regions too.
```lua
/run local m=GetMouseFoci() print("n",#m) for _,f in ipairs(m) do print(f:GetName() or "?") for _,r in ipairs({f:GetRegions()}) do local a=r.GetAtlas and r:GetAtlas() if a then print("a",a) end end end
```
(201 chars.) If `n 0` → element is not mouse-enabled; target it by name instead.

### 1.2 Font object resolution (font / size / flags)
```lua
local function pf(o) if not o or not o.GetFont then return "nil" end local f,s,fl=o:GetFont() return (f or "?").." / "..tostring(s).." / "..(fl or "(none)") end
```
Call `pf(NumberFontNormalRight)`, `pf(GameTooltipText)`, or any fontstring. Used to
discover the tooltip restyle in 12.0.7.

### 1.3 Tooltip text-line scan (find a line + its font)
Walk a tooltip's left/right fontstrings, match a localized label, dump its font:
```lua
local name=tooltip:GetName()
for i=1,tooltip:NumLines() do
  for _,side in ipairs({"TextLeft","TextRight"}) do
    local fs=_G[name..side..i]; local t=fs and fs:GetText()
    if t and t:find(SELL_PRICE,1,true) then print(side..i, t, pf(fs)) end
  end
end
```

### 1.4 RAW markup of a tooltip line (read inline atlas dimensions)
`GetText()` resolves `|A:…|a` markup to a texture. Escape `|`→`||` to see the LITERAL
markup, including coin sizes/offsets:
```lua
print((fs:GetText():gsub("|","||")))
```
This is how we learned native coins are `|A:coin-gold:14:14:2:0|a`, not `13:13`.

### 1.5 Rendered string width (for column alignment)
Position a column to match native text width exactly instead of eyeballing:
```lua
local s=UIParent:CreateFontString(nil,"OVERLAY","GameTooltipText")
s:SetText((SELL_PRICE or "Sell Price")..": ")
print("prefix width =", s:GetStringWidth())
```
Gave `COIN_COLUMN_X = 59` for the tooltip "Auction:" coin column.

### 1.6 Frame rendered rectangle (screen pixels)
For positioning/centering against real geometry. `force-show` a hidden frame so no
scan/cooldown is needed:
```lua
local f=VUIAHScanProgress; f:Show()
local F=math.floor
print("f",F(f:GetTop()),F(f:GetBottom()))
for _,r in ipairs({f:GetRegions()}) do print(r:GetAtlas() or "box",F(r:GetTop()),F(r:GetBottom())) end
```
Higher number = higher on screen. Used to center the scan-progress bar.

---

## 2. Known-good Blizzard values (verified by probe, 12.0.7)

These are measured facts, each with the date and probe that produced it. **Trust
these over code comments.**

| Thing | Verified value | Probe | Date |
|---|---|---|---|
| Tooltip body font (`GameTooltipText`) | `Fonts\FRIZQT__.TTF` / 12 / no-outline | 1.2 | 2026-06-27 |
| Native tooltip "Sell Price:" line font | `Fonts\FRIZQT__.TTF` / 12 / no-outline (= body font) | 1.3 | 2026-06-27 |
| `NumberFontNormalRight` (old "money" font) | `Fonts\ARIALN.TTF` / 14 / OUTLINE | 1.2 | 2026-06-27 |
| Native tooltip coin markup | `\|A:coin-gold:14:14:2:0\|a` (14×14, `:2:0` baseline offset; lowercase atlas) | 1.4 | 2026-06-27 |
| Width of `"Sell Price: "` in body font | 59.08 px | 1.5 | 2026-06-27 |
| Modern smooth bar-fill atlas | `UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health` (tintable) | 1.1 | 2026-06-27 |
| AH money frame | `MoneyFrameBorder` — x41 y534 w158 h19 (present on all AH tabs) | 1.6 / SellStrip | earlier |
| AH card/frame art atlas | `auctionhouse-itemheaderframe` | code/probe | earlier |

**12.0.7 tooltip architecture change (key fact):** Blizzard moved the native
"Sell Price:" line **off the `MoneyFrame` widget** to an **inline body-font text
line** with `|A|` coin markup. `GameTooltipMoneyFrame1` is no longer shown for item
sell prices — a money-frame probe returns nothing. This is *why* the font changed and
why it feels permanent (architecture, not a skin tweak).

---

## 3. Revert recipes

### 3.1 Tooltip pricing: revert v1.7.15 → v1.7.14 styling
**When:** if Blizzard reverts the 12.0.7 tooltip restyle (e.g. they "discover the bug"
and the native "Sell Price:" goes back to ArialN/14/outline money-frame coins). Our
v1.7.15 match would then look wrong and we'd want the old styling back.

**Scope:** entirely in `VeritasUI_AuctionHouse/Tooltip.lua`. Nothing else touched the
pricing. (`git diff v1.7.14 v1.7.15 -- VeritasUI_AuctionHouse/Tooltip.lua` is the
authoritative source.)

**The three changes to undo:**

| Knob | v1.7.15 (current) | v1.7.14 (revert to) |
|---|---|---|
| `COIN_COLUMN_X` | `59` | `70` |
| Coin markup `COIN_G/S/C` | `\|A:coin-gold:14:14:2:0\|a` etc. | `\|A:Coin-Gold:12:12\|a` etc. |
| Coin fontstring | `CreateFontString(nil,"OVERLAY","GameTooltipText")` **plus** the render-time `local lf,ls,lflags=left:GetFont(); if lf then fs:SetFont(lf,ls,lflags or "") end` | `CreateFontString(nil,"OVERLAY","NumberFontNormalRight")` **and remove** the `left:GetFont()`/`SetFont` block |

**Fastest path:** check out the v1.7.14 version of just that one file —
```
cd ~/Desktop/VeritasUI-Updated
git show v1.7.14:VeritasUI_AuctionHouse/Tooltip.lua > VeritasUI_AuctionHouse/Tooltip.lua
```
— then `luac -p` + `luacheck` it, `rsync` to live, `/reload`, verify, and ship as a
new patch version. **Caveat:** this also reverts the comment-correction we made; if the
font fix is reverted but you want to keep other Tooltip.lua edits, do the 3-knob manual
revert from the table instead of the whole-file checkout. As of v1.7.15 there were no
*other* Tooltip.lua edits, so whole-file checkout is clean — re-check with
`git log --oneline v1.7.15.. -- VeritasUI_AuctionHouse/Tooltip.lua` before assuming.

**Best of both worlds (recommended if Blizzard's behavior becomes version-dependent):**
rather than a hard revert, make the coin font/size *adaptive* — at render time, read
the native "Sell Price:" line with probe 1.3/1.4 and copy whatever it currently uses.
That self-heals across any future flip in either direction. We already do this for the
font (we copy `left:GetFont()`); extending it to read the native coin markup size would
make the whole line fully self-tracking. Larger change; note it as the durable fix.

---

## 4. Deploy / verify loop (reference)

Working copy: `~/Desktop/VeritasUI-Updated/` (git source of truth).
Live (what WoW loads): `/Applications/World of Warcraft/_retail_/Interface/AddOns/`.
**They are NOT linked.** Every edit must be rsynced or the game never sees it:
```
rsync -a --delete "$HOME/Desktop/VeritasUI-Updated/VeritasUI_AuctionHouse/" \
  "/Applications/World of Warcraft/_retail_/Interface/AddOns/VeritasUI_AuctionHouse/"
```
Then user `/reload`s. Release ZIP contains the **7 `VeritasUI_*` folders only** (no
CHANGELOG/README/git); a file at repo root or in this skill dir never ships to users.

---

## 5. Log of facts added (newest first)

- **2026-06-27 (v1.7.15):** Initial file. Captured the 12.0.7 tooltip restyle facts
  (§2), the probe library (§1), and the tooltip-pricing revert recipe (§3.1).
  Triggered by the AH session that added the scan-progress bar, fixed the sell-strip
  flicker, and matched the tooltip pricing to Blizzard's 12.0.7 styling.
