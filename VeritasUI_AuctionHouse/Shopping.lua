-- VeritasUI_AuctionHouse / Shopping.lua
-- Phase 4 Layer 3: the Shopping tab's PERSISTENCE layer — saved Shopping Lists and
-- Recent Searches. Data-only, no UI (mirrors Search.lua's separation): the Shopping
-- tab calls these to mutate/read, and re-renders its left panel from GetAll().
--
-- Storage lives under AH.db.shopping (seeded in Core.lua's defaults; account-wide):
--   shopping.lists  = array of { name = "Flasks", items = { "Flask of ...", ... } }
--   shopping.recent = newest-first array of search-term strings (capped RECENT_CAP)
--
-- This is a UI feature, NOT the price-DB layout, so it deliberately does NOT touch
-- db.dbVersion (which versions the prices schema). InitDB's nil-seed upgrades any
-- pre-Layer-3 saved var transparently — no migration.
--
-- Conventions matching the rest of the module:
--   * AH.db is read lazily (load order: Core seeds db on ADDON_LOADED; this file's
--     functions only ever run from UI callbacks, long after login) — every public
--     function guards on a live db handle via Store().
--   * List/recent terms are stored as the NORMALIZED search string (plain item name),
--     produced by AH.Search.NormalizeSearchTerm, so a shift-clicked link and a typed
--     name dedupe to the same entry and re-run identically.

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local ipairs   = ipairs
local type     = type
local strtrim  = strtrim
local tinsert  = table.insert
local tremove  = table.remove

local RECENT_CAP = 20   -- most-recent searches retained (newest first)

----------------------------------------------------------------
--  Shared helpers
----------------------------------------------------------------
-- Live handle to the persisted shopping container. Returns nil if the DB isn't ready
-- yet (pre-ADDON_LOADED) — callers no-op gracefully. Self-heals the sub-tables in case
-- an older saved var has shopping but not both children.
local function Store()
    if not AH.db then return nil end
    local s = AH.db.shopping
    if type(s) ~= "table" then
        s = { lists = {}, recent = {} }
        AH.db.shopping = s
    end
    if type(s.lists)  ~= "table" then s.lists  = {} end
    if type(s.recent) ~= "table" then s.recent = {} end
    return s
end

-- Normalize a term to its canonical stored form (plain name). Falls back to a trim if
-- the Search layer isn't present for some reason. Returns "" for empty/garbage.
local function Norm(term)
    if AH.Search and AH.Search.NormalizeSearchTerm then
        return AH.Search.NormalizeSearchTerm(term)
    end
    if type(term) ~= "string" then return "" end
    return strtrim(term)
end

-- Case-insensitive find of `value` in array `arr`; returns index or nil.
local function FindCI(arr, value)
    local lv = value:lower()
    for i = 1, #arr do
        if type(arr[i]) == "string" and arr[i]:lower() == lv then return i end
    end
    return nil
end

----------------------------------------------------------------
--  AH.Recent — recent search terms (newest-first, deduped, capped)
----------------------------------------------------------------
AH.Recent = {}

-- Record a search. Moves an existing (case-insensitive) match to the top rather than
-- duplicating; trims the tail to RECENT_CAP. No-ops on empty terms. Returns true if
-- the list changed (so the UI can decide whether to re-render).
function AH.Recent.Add(term)
    local s = Store(); if not s then return false end
    local t = Norm(term)
    if t == "" then return false end

    local existing = FindCI(s.recent, t)
    if existing == 1 and s.recent[1] == t then
        return false   -- already newest with identical casing; nothing to do
    end
    if existing then tremove(s.recent, existing) end
    tinsert(s.recent, 1, t)
    while #s.recent > RECENT_CAP do
        tremove(s.recent)   -- drop oldest (tail)
    end
    return true
end

-- The recent list, newest first. Returns the live array (read-only by convention —
-- callers must not mutate it; use the API).
function AH.Recent.GetAll()
    local s = Store(); if not s then return {} end
    return s.recent
end

function AH.Recent.Remove(index)
    local s = Store(); if not s then return false end
    if type(s.recent[index]) ~= "string" then return false end
    tremove(s.recent, index)
    return true
end

function AH.Recent.Clear()
    local s = Store(); if not s then return false end
    if #s.recent == 0 then return false end
    s.recent = {}
    return true
end

----------------------------------------------------------------
--  AH.Lists — saved multi-item Shopping Lists
--
--  A list = { name = string, items = { term, term, ... } }. Lists are addressed by
--  their array index (the UI tracks a selected index); names are NOT required unique
--  but Create rejects an exact-duplicate name to avoid confusion.
----------------------------------------------------------------
AH.Lists = {}

function AH.Lists.GetAll()
    local s = Store(); if not s then return {} end
    return s.lists
end

function AH.Lists.Count()
    local s = Store(); if not s then return 0 end
    return #s.lists
end

function AH.Lists.Get(index)
    local s = Store(); if not s then return nil end
    return s.lists[index]
end

-- Create a new empty list. Rejects blank names and exact (case-insensitive) duplicates.
-- Returns (index, list) on success, or (nil, reason) on failure.
function AH.Lists.Create(name)
    local s = Store(); if not s then return nil, "not ready" end
    name = type(name) == "string" and strtrim(name) or ""
    if name == "" then return nil, "empty name" end
    for _, l in ipairs(s.lists) do
        if type(l.name) == "string" and l.name:lower() == name:lower() then
            return nil, "duplicate name"
        end
    end
    local list = { name = name, items = {} }
    s.lists[#s.lists + 1] = list
    return #s.lists, list
end

function AH.Lists.Delete(index)
    local s = Store(); if not s then return false end
    if not s.lists[index] then return false end
    tremove(s.lists, index)
    return true
end

-- Rename a list. Rejects blank / exact-duplicate (ignoring the list being renamed).
function AH.Lists.Rename(index, name)
    local s = Store(); if not s then return false, "not ready" end
    local list = s.lists[index]
    if not list then return false, "no such list" end
    name = type(name) == "string" and strtrim(name) or ""
    if name == "" then return false, "empty name" end
    for i, l in ipairs(s.lists) do
        if i ~= index and type(l.name) == "string" and l.name:lower() == name:lower() then
            return false, "duplicate name"
        end
    end
    list.name = name
    return true
end

-- Add a search term to a list (normalized, deduped case-insensitively). Returns true
-- if added, false if it was a no-op (blank term, no such list, or already present).
function AH.Lists.AddItem(index, term)
    local s = Store(); if not s then return false end
    local list = s.lists[index]
    if not list then return false end
    local t = Norm(term)
    if t == "" then return false end
    if FindCI(list.items, t) then return false end   -- already in this list
    list.items[#list.items + 1] = t
    return true
end

function AH.Lists.RemoveItem(index, itemIndex)
    local s = Store(); if not s then return false end
    local list = s.lists[index]
    if not (list and list.items[itemIndex]) then return false end
    tremove(list.items, itemIndex)
    return true
end

-- Convenience: the items array for a list (or empty). Read-only by convention.
function AH.Lists.GetItems(index)
    local list = AH.Lists.Get(index)
    return (list and list.items) or {}
end
