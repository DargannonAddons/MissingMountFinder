local addonName, addon = ...

local state = addon.state
local L = addon.GetString

local refreshPending = false

local function ScheduleRefresh()
    if refreshPending then
        return
    end
    refreshPending = true
    C_Timer.After(1, function()
        refreshPending = false
        if addon.IsUIShown() then
            addon.RefreshUI()
        end
    end)
end

-- Events that change which mounts are collected: full journal rescan.
local RESCAN_EVENTS = {
    NEW_MOUNT_ADDED = true,
    COMPANION_LEARNED = true,
}

-- Events that change whether requirements are met: re-evaluate only.
local REEVALUATE_EVENTS = {
    UPDATE_FACTION = true,
    MAJOR_FACTION_RENOWN_LEVEL_CHANGED = true,
    ACHIEVEMENT_EARNED = true,
    PLAYER_MONEY = true,
    QUEST_TURNED_IN = true,
    QUEST_DATA_LOAD_RESULT = true,
    CURRENCY_DISPLAY_UPDATE = true,
    BAG_UPDATE_DELAYED = true,
    SKILL_LINES_CHANGED = true,
    PLAYER_LEVEL_UP = true,
}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
if C_CurrencyInfo and C_CurrencyInfo.RequestCurrencyDataForAccountCharacters then
    eventFrame:RegisterEvent("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED")
end
for event in pairs(RESCAN_EVENTS) do
    eventFrame:RegisterEvent(event)
end
for event in pairs(REEVALUATE_EVENTS) do
    eventFrame:RegisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            addon.GetDB()
        end
        -- Other addons can force-load Blizzard_Collections before or after us,
        -- so try on every load; InstallJournalButton is a no-op once installed.
        if MountJournal then
            addon.InstallJournalButton()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        addon.CreateMinimapButton()
        -- Ask for warband currency totals (arrives via ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED).
        if C_CurrencyInfo and C_CurrencyInfo.RequestCurrencyDataForAccountCharacters then
            pcall(C_CurrencyInfo.RequestCurrencyDataForAccountCharacters)
        end
        if MountJournal then
            addon.InstallJournalButton()
        end
        -- Request calendar data so world-event requirements can be checked.
        if C_Calendar and C_Calendar.OpenCalendar then
            C_Calendar.OpenCalendar()
        end
        print(L("ADDON_LOADED"))
        return
    end

    if event == "ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED" then
        state.dirty = true
        ScheduleRefresh()
        return
    end

    if event == "CALENDAR_UPDATE_EVENT_LIST" then
        addon.RefreshActiveEvents()
        state.dirty = true
        ScheduleRefresh()
        return
    end

    if RESCAN_EVENTS[event] then
        state.scanned = false
    else
        state.dirty = true
    end
    ScheduleRefresh()
end)

local function PrintStats()
    if not state.scanned then
        addon.ScanMounts()
    end
    local collected, total, missing, ready, check, locked = addon.GetSummary()
    addon.Print(string.format("Collected %d / %d, missing %d (eligible now %d, unverified %d, locked %d).",
        collected, total, missing, ready, check, locked))
end

SLASH_MISSINGMOUNTFINDER1 = "/mmf"
SLASH_MISSINGMOUNTFINDER2 = "/missingmounts"
SLASH_MISSINGMOUNTFINDER3 = "/missingmountfinder"
SlashCmdList["MISSINGMOUNTFINDER"] = function(msg)
    local arg = string.lower(strtrim(msg or ""))
    if arg == "" or arg == "toggle" then
        addon.ToggleUI()
    elseif arg == "help" then
        print(L("CMD_HELP_HEADER"))
        print(L("CMD_HELP_TOGGLE"))
        print(L("CMD_HELP_SCAN"))
        print(L("CMD_HELP_VERIFY"))
        print(L("CMD_HELP_STATS"))
        print(L("CMD_HELP_MINIMAP"))
        print(L("CMD_HELP_COST"))
    elseif arg == "cost" then
        local mount = state.selectedMountID and addon.GetMount(state.selectedMountID)
        if mount then
            addon.DebugCosts(mount)
        else
            addon.Print(L("NO_SELECTION"))
        end
    elseif arg == "minimap" then
        addon.ToggleMinimapButton()
    elseif arg == "scan" then
        addon.ScanMounts()
        addon.RefreshUI()
        PrintStats()
    elseif arg == "verify" then
        if not state.scanned then
            addon.ScanMounts()
        end
        addon.VerifyCuratedData()
    elseif arg == "stats" then
        PrintStats()
    else
        addon.Print(L("CMD_UNKNOWN"))
    end
end

-- Addon compartment (the addon list button by the minimap).
function MissingMountFinder_OnAddonCompartmentClick()
    addon.ToggleUI()
end

function MissingMountFinder_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText(L("FRAME_TITLE"))
    if state.scanned then
        local collected, total, _, ready = addon.GetSummary()
        GameTooltip:AddLine(string.format("%d / %d collected, %d eligible now", collected, total, ready), 1, 1, 1)
    end
    GameTooltip:AddLine("Click to open", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function MissingMountFinder_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
