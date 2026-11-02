-- VeritasUI_CleanSolo / BannerProbe.lua — TEMPORARY test-branch probe, never released.
--
-- Feature batch item 17 (Hide Top Banners as a dropdown): which frame, and which toast type, shows the
-- Delve Nemesis-defeated banner? Records every top banner while you play; /csprobe prints the log.
-- Kept in memory only, so read it before any /reload.
--   * Event toasts: post-hook EventToastManagerFrame:DisplayToast (EventToastManager.lua:327-362), the one
--     place a toast is put on screen, and its toastInfo (UIEventToastManagerDocumentation EventToastInfo).
--     Also DISPLAY_EVENT_TOASTS itself, peeking the queue head, so the type is seen even while Hide Top
--     Banners stops Blizzard's frame from showing it.
--   * Every other top banner (boss kill, loot, level up...): post-hook TopBannerManager_Show
--     (TopBannerManager.lua:18), which names the frame.
--   * BOSS_KILL arguments, and raid-warning / boss-emote lines (RaidNotice_AddMessage).

local VUI = _G.VeritasUI
if not VUI then return end

local log = {}
local MAX = 60

local function S(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    return tostring(v)
end

local function EnumName(enum, value)
    for k, v in pairs(enum or {}) do if v == value then return k end end
    return S(value)
end

local function Add(line)
    log[#log + 1] = date("%H:%M:%S ") .. line
    if #log > MAX then table.remove(log, 1) end
end

local function ToastLine(tag, info)
    if type(info) ~= "table" then Add(tag .. " (no toast info)"); return end
    Add(string.format("%s id=%s display=%s event=%s kit=%s title=%s | subtitle=%s", tag,
        S(info.eventToastID),
        EnumName(Enum and Enum.EventToastDisplayType, info.displayType),
        EnumName(Enum and Enum.EventToastEventType, info.eventType),
        S(info.uiTextureKit), S(info.title), S(info.subtitle)))
end

local etm = _G.EventToastManagerFrame
if etm and etm.DisplayToast then
    hooksecurefunc(etm, "DisplayToast", function(self)
        local t = self.currentDisplayingToast
        if t then ToastLine("TOAST shown", t.toastInfo) end
    end)
end

if _G.TopBannerManager_Show then
    hooksecurefunc("TopBannerManager_Show", function(frame, data)
        local name = frame and frame.GetName and frame:GetName() or "?"
        local keys = {}
        if type(data) == "table" then
            for k, v in pairs(data) do
                if type(v) ~= "table" and type(v) ~= "function" then keys[#keys + 1] = k .. "=" .. S(v) end
            end
        end
        Add("BANNER " .. S(name) .. " " .. table.concat(keys, " "))
    end)
end

if _G.RaidNotice_AddMessage then
    hooksecurefunc("RaidNotice_AddMessage", function(frame, text)
        local name = frame and frame.GetName and frame:GetName() or "?"
        Add("NOTICE " .. S(name) .. ": " .. S(text))
    end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("DISPLAY_EVENT_TOASTS")
f:RegisterEvent("BOSS_KILL")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "DISPLAY_EVENT_TOASTS" then
        local ok, info = pcall(C_EventToastManager.GetNextToastToDisplay)
        ToastLine("TOAST queued", ok and info or nil)
    else
        local a, b = ...
        Add("BOSS_KILL encounter=" .. S(a) .. " name=" .. S(b))
    end
end)

SLASH_VERITASUI_CSPROBE1 = "/csprobe"
SlashCmdList["VERITASUI_CSPROBE"] = function()
    if #log == 0 then VUI.Print("Clean Solo", "banner probe: nothing recorded yet"); return end
    for _, line in ipairs(log) do VUI.Print("Clean Solo", line) end
end
