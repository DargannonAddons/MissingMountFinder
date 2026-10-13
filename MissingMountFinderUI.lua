local _, addon = ...

local state = addon.state
local STATUS = addon.STATUS
local REQ = addon.REQ
local C = addon.constants
local THEME = addon.theme
local L = addon.GetString

local REQ_ICONS = {
    [REQ.MET] = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t",
    [REQ.UNMET] = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t",
    [REQ.PARTIAL] = "|TInterface\\COMMON\\Indicator-Yellow:14|t",
    [REQ.UNKNOWN] = "",
    [REQ.INFO] = "|cffb3b3b3-|r",
}

local GROUP_MODE_LABELS = {
    zone = "GROUP_ZONE",
    source = "GROUP_SOURCE",
    status = "GROUP_STATUS",
    farm = "GROUP_FARM",
}

local OPTION_CHECKBOXES = {
    { key = "showCollected", label = "OPT_COLLECTED" },
    { key = "showUnavailable", label = "OPT_UNAVAILABLE" },
    { key = "showUnobtainable", label = "OPT_UNOBTAINABLE" },
    { key = "showShop", label = "OPT_SHOP" },
    { key = "readyOnly", label = "OPT_READY" },
    { key = "goalsOnly", label = "OPT_GOALS" },
}

local ui = {
    frame = nil,
    modeButtons = {},
    checkboxes = {},
    detailStrings = {},
}

local function ColorHex(rgb)
    return string.format("ff%02x%02x%02x", rgb[1] * 255, rgb[2] * 255, rgb[3] * 255)
end

local function Colorize(text, rgb)
    return "|c" .. ColorHex(rgb) .. text .. "|r"
end

local function StatusText(status)
    return Colorize(L("STATUS_" .. status), addon.statusColors[status])
end

local function CreatePanel(parent)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(unpack(THEME.panelBg))
    panel:SetBackdropBorderColor(unpack(THEME.panelBorder))
    return panel
end

local function CreateScrollList(parent, extent, initializer, extentCalculator)
    local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", -16, 4)

    local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

    local view = CreateScrollBoxListLinearView()
    if extentCalculator then
        view:SetElementExtentCalculator(extentCalculator)
    else
        view:SetElementExtent(extent)
    end
    view:SetElementInitializer("Button", initializer)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    return scrollBox
end

local function SetRowBackground(button, index, selected)
    if selected then
        button.bg:SetColorTexture(unpack(THEME.rowSelectedBg))
        button.accent:Show()
    else
        local color = (index % 2 == 0) and THEME.rowEvenBg or THEME.rowOddBg
        button.bg:SetColorTexture(unpack(color))
        button.accent:Hide()
    end
end

local function SetupRowBase(button)
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()

    button.accent = button:CreateTexture(nil, "ARTWORK")
    button.accent:SetPoint("TOPLEFT")
    button.accent:SetPoint("BOTTOMLEFT")
    button.accent:SetWidth(3)
    button.accent:SetColorTexture(unpack(THEME.rowSelectedBorder))

    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.06)
end

------------------------------------------------------------------------------
-- Group sidebar
------------------------------------------------------------------------------

local function InitGroupRow(button, group)
    if not button.initialized then
        SetupRowBase(button)
        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.label:SetJustifyH("LEFT")
        button.label:SetWordWrap(false)
        button.sub = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        button.sub:SetPoint("BOTTOMLEFT", 8, 5)
        button.sub:SetPoint("RIGHT", -6, 0)
        button.sub:SetJustifyH("LEFT")
        button.sub:SetWordWrap(false)
        button.count = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.count:SetPoint("RIGHT", -6, 0)
        button.count:SetJustifyH("RIGHT")
        button:SetScript("OnClick", function(self)
            state.selectedGroup = self.group.key
            addon.SetStoredSelectedGroup(addon.GetOption("groupBy"), self.group.key)
            addon.RefreshUI()
        end)
        -- Farm rows (currency, rep...) show the resource's tooltip on hover.
        button:SetScript("OnEnter", function(self)
            if self.group and self.group.result then
                addon.ShowRequirementTooltip(self, self.group.result)
            end
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        button.initialized = true
    end

    button.group = group
    button.label:ClearAllPoints()
    button.count:ClearAllPoints()
    if group.sub then
        button.label:SetPoint("TOPLEFT", 8, -5)
        button.count:SetPoint("TOPRIGHT", -6, -5)
    else
        button.label:SetPoint("LEFT", 8, 0)
        button.count:SetPoint("RIGHT", -6, 0)
    end
    button.label:SetPoint("RIGHT", -56, 0)
    button.label:SetText(group.label)
    button.sub:SetText(group.sub or "")
    button.sub:SetShown(group.sub ~= nil)
    local readyText = group.ready > 0 and Colorize(" (" .. group.ready .. ")", addon.statusColors[STATUS.READY]) or ""
    button.count:SetText(group.count .. readyText)
    SetRowBackground(button, 1, state.selectedGroup == group.key)
end

------------------------------------------------------------------------------
-- Mount list
------------------------------------------------------------------------------

local function ShowMountTooltip(button)
    local mount = button.mount
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if mount.spellID and GameTooltip.SetMountBySpellID then
        GameTooltip:SetMountBySpellID(mount.spellID)
    else
        GameTooltip:SetText(mount.name)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click to toggle goal. Shift-click to link.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function InitMountRow(button, mount)
    if not button.initialized then
        SetupRowBase(button)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(C.MOUNT_ROW_HEIGHT - 6, C.MOUNT_ROW_HEIGHT - 6)
        button.icon:SetPoint("LEFT", 6, 0)

        button.goal = button:CreateTexture(nil, "OVERLAY")
        button.goal:SetSize(16, 16)
        button.goal:SetPoint("TOPLEFT", button.icon, "TOPLEFT", -4, 4)
        button.goal:SetAtlas("PetJournal-FavoritesIcon")

        button.status = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.status:SetPoint("RIGHT", -8, 0)
        button.status:SetJustifyH("RIGHT")

        button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.name:SetPoint("TOPLEFT", button.icon, "TOPRIGHT", 8, -2)
        button.name:SetPoint("RIGHT", button.status, "LEFT", -8, 0)
        button.name:SetJustifyH("LEFT")
        button.name:SetWordWrap(false)

        button.sub = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        button.sub:SetPoint("BOTTOMLEFT", button.icon, "BOTTOMRIGHT", 8, 2)
        button.sub:SetPoint("RIGHT", button.status, "LEFT", -8, 0)
        button.sub:SetJustifyH("LEFT")
        button.sub:SetWordWrap(false)

        button:SetScript("OnClick", function(self, mouseButton)
            local clicked = self.mount
            if mouseButton == "RightButton" then
                addon.ToggleGoal(clicked.mountID)
                addon.RefreshUI()
                return
            end
            if IsModifiedClick("CHATLINK") and clicked.spellID then
                local link = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(clicked.spellID)
                if link then
                    ChatEdit_InsertLink(link)
                end
                return
            end
            state.selectedMountID = clicked.mountID
            addon.RefreshSelection()
        end)
        button:SetScript("OnEnter", ShowMountTooltip)
        button:SetScript("OnLeave", GameTooltip_Hide)
        button.initialized = true
    end

    button.mount = mount
    button.icon:SetTexture(mount.icon)
    button.icon:SetDesaturated(mount.status == STATUS.COLLECTED)
    button.goal:SetShown(addon.IsGoal(mount.mountID))
    button.name:SetText(mount.name)

    local subParts = {}
    if mount.zone then
        subParts[#subParts + 1] = mount.zone
    end
    subParts[#subParts + 1] = mount.sourceLabel
    button.sub:SetText(table.concat(subParts, "  \194\183  "))

    button.status:SetText(StatusText(mount.status))
    SetRowBackground(button, button.GetElementDataIndex and button:GetElementDataIndex() or 1,
        state.selectedMountID == mount.mountID)
end

------------------------------------------------------------------------------
-- Detail actions
------------------------------------------------------------------------------

StaticPopupDialogs["MISSINGMOUNTFINDER_URL"] = {
    text = L("WOWHEAD_PROMPT"),
    button1 = OKAY,
    hasEditBox = true,
    editBoxWidth = 320,
    OnShow = function(self, data)
        local editBox = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
        if editBox then
            editBox:SetText(data or "")
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end,
    EditBoxOnEscapePressed = function(editBox)
        editBox:GetParent():Hide()
    end,
    EditBoxOnEnterPressed = function(editBox)
        editBox:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function GetMapTarget(mount)
    for _, result in ipairs(mount.results) do
        if result.nextQuestID and addon.ATT then
            local mapID, x, y = addon.ATT.GetQuestLocation(result.nextQuestID)
            if mapID and x then
                return mapID, { mapID = mapID, x = x, y = y, title = addon.ATT.GetQuestTitle(result.nextQuestID) }
            end
        end
    end
    local att = mount.attData
    if att and att.mapID and att.x then
        return att.mapID, { mapID = att.mapID, x = att.x, y = att.y, title = att.npcName or mount.name }
    end
    local waypoint = mount.curated and mount.curated.waypoint
    if waypoint and waypoint.mapID then
        return waypoint.mapID, waypoint
    end
    return addon.FindMapIDForZone(mount.zone), nil
end

local function GetAchievementResult(mount)
    for _, result in ipairs(mount.results) do
        if result.achievementID then
            return result
        end
    end
    return nil
end

local function OpenMap(mount)
    local mapID = GetMapTarget(mount)
    if not mapID then
        addon.Print(L("MAP_NOT_FOUND", tostring(mount.zone)))
        return
    end
    if OpenWorldMap then
        OpenWorldMap(mapID)
    elseif WorldMapFrame then
        ShowUIPanel(WorldMapFrame)
        WorldMapFrame:SetMapID(mapID)
    end
end

local function SetWaypoint(mount)
    local mapID, waypoint = GetMapTarget(mount)
    if not (mapID and waypoint and waypoint.x and waypoint.y) then
        return
    end
    local x, y = waypoint.x / 100, waypoint.y / 100
    local title = waypoint.title or mount.name

    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(mapID, x, y, { title = title, persistent = false })
    end
    if C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        addon.Print(L("WAYPOINT_SET", title))
    elseif not TomTom then
        addon.Print(L("WAYPOINT_FAILED"))
    end
end

local function TrackAchievement(mount, openUI)
    local result = GetAchievementResult(mount)
    if not result then
        return
    end
    local id = result.achievementID

    if openUI then
        if OpenAchievementFrameToAchievement then
            OpenAchievementFrameToAchievement(id)
        end
        return
    end

    local tracked = false
    if C_ContentTracking and C_ContentTracking.StartTracking and Enum.ContentTrackingType then
        local err = C_ContentTracking.StartTracking(Enum.ContentTrackingType.Achievement, id)
        tracked = (err == nil) or (C_ContentTracking.IsTracking and C_ContentTracking.IsTracking(Enum.ContentTrackingType.Achievement, id))
    elseif AddTrackedAchievement then
        AddTrackedAchievement(id)
        tracked = true
    end

    local _, name = GetAchievementInfo(id)
    addon.Print(tracked and L("TRACK_STARTED", name or id) or L("TRACK_FAILED"))
end

function addon.OpenInMountJournal(mountID)
    if InCombatLockdown() then
        return
    end
    if not CollectionsJournal then
        if C_AddOns and C_AddOns.LoadAddOn then
            C_AddOns.LoadAddOn("Blizzard_Collections")
        elseif CollectionsJournal_LoadUI then
            CollectionsJournal_LoadUI()
        end
    end
    if SetCollectionsJournalShown then
        SetCollectionsJournalShown(true, COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS or 1)
    elseif CollectionsJournal then
        ShowUIPanel(CollectionsJournal)
    end
    if mountID and MountJournal_SelectByMountID then
        pcall(MountJournal_SelectByMountID, mountID)
    end
end

------------------------------------------------------------------------------
-- Detail panel
------------------------------------------------------------------------------

-- Shows the game's own tooltip for whatever a requirement refers to, so small
-- currency icons can be identified by hovering.
function addon.ShowRequirementTooltip(owner, result)
    local req = result and result.req
    if not req then
        return
    end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local shown = false
    if req.type == "currency" and GameTooltip.SetCurrencyByID then
        shown = pcall(GameTooltip.SetCurrencyByID, GameTooltip, req.id)
    elseif req.type == "item" and GameTooltip.SetItemByID then
        shown = pcall(GameTooltip.SetItemByID, GameTooltip, req.id)
    elseif req.type == "achievement" and GetAchievementLink then
        local link = GetAchievementLink(req.id)
        shown = link ~= nil and pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    elseif req.type == "quest" then
        shown = pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. req.id)
    elseif req.type == "unverified" and req.texture then
        GameTooltip:SetText("|T" .. req.texture .. ":32:32|t  " .. L("TOOLTIP_UNVERIFIED_TITLE"))
        GameTooltip:AddLine(L("TOOLTIP_UNVERIFIED_BODY"), 1, 1, 1, true)
        GameTooltip:AddLine(req.texture, 0.5, 0.5, 0.5, true)
        shown = true
    end

    if not shown then
        GameTooltip:SetText(result.label or result.text or "", 1, 1, 1, 1, true)
    end
    if result.text and result.text ~= "" then
        GameTooltip:AddLine(" ")
        local color = addon.reqColors[result.status] or THEME.textBright
        GameTooltip:AddLine(result.text, color[1], color[2], color[3], true)
    end
    GameTooltip:Show()
end

local function OnDetailLineEnter(self)
    if self.result then
        addon.ShowRequirementTooltip(self, self.result)
    end
end

-- Each detail line is a frame holding a font string, so requirement lines can
-- show a tooltip on hover.
local function AcquireDetailLine(index)
    local line = ui.detailStrings[index]
    if not line then
        line = CreateFrame("Frame", nil, ui.detailChild)
        line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.text:SetPoint("TOPLEFT")
        line.text:SetJustifyH("LEFT")
        line.text:SetJustifyV("TOP")
        line.text:SetWordWrap(true)
        line.text:SetSpacing(2)
        line:SetScript("OnEnter", OnDetailLineEnter)
        line:SetScript("OnLeave", GameTooltip_Hide)
        ui.detailStrings[index] = line
    end
    return line
end

local function RenderDetail()
    local detail = ui.detail
    local mount = state.selectedMountID and state.mountsByID[state.selectedMountID]

    for _, fs in ipairs(ui.detailStrings) do
        fs:Hide()
    end

    if not mount then
        detail.header:Hide()
        detail.actions:Hide()
        detail.scroll:Hide()
        detail.placeholder:Show()
        return
    end

    detail.placeholder:Hide()
    detail.header:Show()
    detail.actions:Show()
    detail.scroll:Show()

    detail.icon:SetTexture(mount.icon)
    detail.name:SetText(mount.name)
    detail.status:SetText(StatusText(mount.status))

    -- Action buttons
    local mapID, waypoint = GetMapTarget(mount)
    local achievement = GetAchievementResult(mount)
    detail.goalButton:SetText(addon.IsGoal(mount.mountID) and L("BUTTON_GOAL_REMOVE") or L("BUTTON_GOAL_ADD"))
    detail.mapButton:SetEnabled(mapID ~= nil)
    detail.waypointButton:SetEnabled(waypoint ~= nil and waypoint.x ~= nil)
    detail.trackButton:SetEnabled(achievement ~= nil and achievement.status ~= REQ.MET)

    -- Scrollable body
    local width = ui.detailChild:GetWidth()
    local index, y = 0, 0
    local function AddLine(text, font, indent, spacingAfter, result)
        index = index + 1
        local line = AcquireDetailLine(index)
        local lineWidth = width - (indent or 0)
        line.text:SetFontObject(font or "GameFontHighlightSmall")
        line.text:SetWidth(lineWidth)
        line.text:SetText(text)
        local height = line.text:GetStringHeight()
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", ui.detailChild, "TOPLEFT", indent or 0, -y)
        line:SetSize(lineWidth, math.max(height, 1))
        line.result = result
        line:EnableMouse(result ~= nil)
        line:Show()
        y = y + height + (spacingAfter or 4)
    end

    local gold = THEME.textGold
    local function Label(key)
        return Colorize(L(key) .. ": ", gold)
    end

    AddLine(Label("DETAIL_ZONE") .. (mount.zone or "-"))
    AddLine(Label("DETAIL_SOURCE") .. mount.sourceLabel, nil, 0, 12)

    AddLine(L("DETAIL_REQUIREMENTS"), "GameFontNormal", 0, 6)
    if #mount.results == 0 then
        AddLine(L("DETAIL_NO_REQUIREMENTS"), nil, 8)
    end
    for _, result in ipairs(mount.results) do
        AddLine(REQ_ICONS[result.status] .. " " .. Colorize(result.text, addon.reqColors[result.status]), nil, 8, nil, result)
        if result.lines and result.status ~= REQ.MET then
            for _, line in ipairs(result.lines) do
                -- Quest lines carry a questID so they can show the quest tooltip.
                local lineResult = line[3] and { req = { type = "quest", id = line[3] }, text = line[2], status = line[1] }
                local text = REQ_ICONS[line[1]] .. " " .. line[2]
                if line[3] and line[3] == result.nextQuestID then
                    text = text .. Colorize("  " .. L("DETAIL_NEXT"), THEME.textGold)
                end
                AddLine(text, "GameFontDisableSmall", 26, 2, lineResult)
            end
        elseif result.achievementID and result.status == REQ.MET and mount.status ~= STATUS.COLLECTED then
            AddLine(L("REQ_ACHIEVEMENT_DONE_NOT_LEARNED"), "GameFontDisableSmall", 26, 2)
        end
    end
    y = y + 8

    AddLine(L("DETAIL_HOW_TO"), "GameFontNormal", 0, 6)
    for i, step in ipairs(addon.GetHowToSteps(mount)) do
        AddLine(i .. ". " .. step, nil, 8)
    end
    y = y + 8

    if mount.sourceText ~= "" then
        AddLine(L("DETAIL_SOURCE_TEXT"), "GameFontNormal", 0, 6)
        AddLine(mount.sourceText, nil, 8, 8)
    end
    if mount.description and mount.description ~= "" then
        AddLine(Colorize(mount.description, THEME.textMuted), "GameFontHighlightSmall", 8, 8)
    end

    ui.detailChild:SetHeight(math.max(y, 1))
end

local function CreateDetailPanel(parent)
    local panel = CreatePanel(parent)
    ui.detail = panel

    panel.placeholder = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.placeholder:SetPoint("TOPLEFT", 16, -16)
    panel.placeholder:SetPoint("BOTTOMRIGHT", -16, 16)
    panel.placeholder:SetText(L("NO_SELECTION"))

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 8, -8)
    header:SetPoint("TOPRIGHT", -8, -8)
    header:SetHeight(52)
    panel.header = header

    panel.icon = header:CreateTexture(nil, "ARTWORK")
    panel.icon:SetSize(48, 48)
    panel.icon:SetPoint("TOPLEFT")

    panel.name = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    panel.name:SetPoint("TOPLEFT", panel.icon, "TOPRIGHT", 10, -4)
    panel.name:SetPoint("RIGHT")
    panel.name:SetJustifyH("LEFT")

    panel.status = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.status:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -6)

    -- Two rows of three action buttons pinned to the bottom of the panel.
    local actions = CreateFrame("Frame", nil, panel)
    actions:SetPoint("BOTTOMLEFT", 8, 8)
    actions:SetPoint("BOTTOMRIGHT", -8, 8)
    actions:SetHeight(48)
    panel.actions = actions

    local buttonWidth = (C.DETAIL_PANEL_WIDTH - 16 - 8) / 3
    local function MakeButton(textKey, row, col, onClick)
        local button = CreateFrame("Button", nil, actions, "UIPanelButtonTemplate")
        button:SetSize(buttonWidth, 22)
        button:SetPoint("TOPLEFT", (col - 1) * (buttonWidth + 4), -(row - 1) * 26)
        button:SetText(L(textKey))
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(_, mouseButton)
            local mount = state.selectedMountID and state.mountsByID[state.selectedMountID]
            if mount then
                onClick(mount, mouseButton)
            end
        end)
        return button
    end

    panel.goalButton = MakeButton("BUTTON_GOAL_ADD", 1, 1, function(mount)
        addon.ToggleGoal(mount.mountID)
        addon.RefreshUI()
    end)
    panel.mapButton = MakeButton("BUTTON_MAP", 1, 2, OpenMap)
    panel.waypointButton = MakeButton("BUTTON_WAYPOINT", 1, 3, SetWaypoint)
    panel.trackButton = MakeButton("BUTTON_TRACK", 2, 1, function(mount, mouseButton)
        TrackAchievement(mount, mouseButton == "RightButton")
    end)
    panel.trackButton:SetMotionScriptsWhileDisabled(true)
    panel.trackButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L("BUTTON_TRACK"))
        GameTooltip:AddLine("Left-click: track in the objective tracker", 1, 1, 1)
        GameTooltip:AddLine("Right-click: open in the Achievements window", 1, 1, 1)
        GameTooltip:Show()
    end)
    panel.trackButton:SetScript("OnLeave", GameTooltip_Hide)
    MakeButton("BUTTON_JOURNAL", 2, 2, function(mount)
        addon.OpenInMountJournal(mount.mountID)
    end)
    MakeButton("BUTTON_WOWHEAD", 2, 3, function(mount)
        if mount.spellID then
            StaticPopup_Show("MISSINGMOUNTFINDER_URL", nil, nil, "https://www.wowhead.com/spell=" .. mount.spellID)
        end
    end)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("BOTTOMRIGHT", actions, "TOPRIGHT", -18, 8)
    panel.scroll = scroll

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(C.DETAIL_PANEL_WIDTH - 16 - 18, 1)
    scroll:SetScrollChild(child)
    ui.detailChild = child

    return panel
end

------------------------------------------------------------------------------
-- Main frame
------------------------------------------------------------------------------

local function UpdateModeButtons()
    local mode = addon.GetOption("groupBy")
    for buttonMode, button in pairs(ui.modeButtons) do
        if buttonMode == mode then
            button:LockHighlight()
            button:GetFontString():SetTextColor(unpack(THEME.textGold))
        else
            button:UnlockHighlight()
            button:GetFontString():SetTextColor(unpack(THEME.textBright))
        end
    end
end

local function CreateMainFrame()
    local frame = CreatePanel(UIParent)
    frame:SetSize(C.FRAME_WIDTH, C.FRAME_HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        addon.SaveWindowPosition(self)
    end)
    frame:Hide()
    _G.MissingMountFinderFrame = frame
    tinsert(UISpecialFrames, "MissingMountFinderFrame")
    ui.frame = frame

    -- Title bar
    local titleBar = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(28)
    titleBar:SetColorTexture(unpack(THEME.headerBg))

    local titleIcon = frame:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(20, 20)
    titleIcon:SetPoint("TOPLEFT", 8, -5)
    titleIcon:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", titleIcon, "RIGHT", 6, 0)
    title:SetText(L("FRAME_TITLE"))

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    ui.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.summary:SetPoint("RIGHT", close, "LEFT", -8, -1)
    ui.summary:SetJustifyH("RIGHT")

    -- Toolbar: group mode buttons, search, rescan
    local groupLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    groupLabel:SetPoint("TOPLEFT", 12, -40)
    groupLabel:SetText(L("GROUP_BY"))

    local previous = groupLabel
    for _, mode in ipairs(addon.groupModes) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(96, 22)
        button:SetPoint("LEFT", previous, "RIGHT", previous == groupLabel and 8 or 4, 0)
        button:SetText(L(GROUP_MODE_LABELS[mode]))
        button:SetScript("OnClick", function()
            addon.SetOption("groupBy", mode)
            state.selectedGroup = addon.GetStoredSelectedGroup(mode)
            UpdateModeButtons()
            addon.RefreshUI()
        end)
        ui.modeButtons[mode] = button
        previous = button
    end

    local rescan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    rescan:SetSize(80, 22)
    rescan:SetPoint("TOPRIGHT", -12, -35)
    rescan:SetText(L("BUTTON_REFRESH"))
    rescan:SetScript("OnClick", function()
        addon.ScanMounts()
        addon.RefreshUI()
    end)

    local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    search:SetSize(240, 20)
    search:SetPoint("RIGHT", rescan, "LEFT", -10, 0)
    search:SetAutoFocus(false)
    if search.Instructions then
        search.Instructions:SetText(L("SEARCH_PLACEHOLDER"))
    end
    search:HookScript("OnTextChanged", function()
        addon.RefreshUI()
    end)
    ui.search = search

    -- Options row
    local xOffset = 8
    for _, option in ipairs(OPTION_CHECKBOXES) do
        local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        check:SetSize(22, 22)
        check:SetPoint("TOPLEFT", xOffset, -62)
        local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", check, "RIGHT", 2, 0)
        label:SetText(L(option.label))
        check:SetScript("OnClick", function(self)
            addon.SetOption(option.key, self:GetChecked() and true or false)
            addon.RefreshUI()
        end)
        ui.checkboxes[option.key] = check
        xOffset = xOffset + 28 + label:GetStringWidth() + 18
    end

    -- Content panels
    local top = -90
    local groupPanel = CreatePanel(frame)
    groupPanel:SetPoint("TOPLEFT", 8, top)
    groupPanel:SetPoint("BOTTOMLEFT", 8, 8)
    groupPanel:SetWidth(C.GROUP_PANEL_WIDTH)
    ui.groupList = CreateScrollList(groupPanel, C.GROUP_ROW_HEIGHT, InitGroupRow, function(_, group)
        return group.sub and C.GROUP_ROW_TALL_HEIGHT or C.GROUP_ROW_HEIGHT
    end)

    local detailPanel = CreateDetailPanel(frame)
    detailPanel:SetPoint("TOPRIGHT", -8, top)
    detailPanel:SetPoint("BOTTOMRIGHT", -8, 8)
    detailPanel:SetWidth(C.DETAIL_PANEL_WIDTH)

    local listPanel = CreatePanel(frame)
    listPanel:SetPoint("TOPLEFT", groupPanel, "TOPRIGHT", 6, 0)
    listPanel:SetPoint("BOTTOMRIGHT", detailPanel, "BOTTOMLEFT", -6, 0)
    ui.mountList = CreateScrollList(listPanel, C.MOUNT_ROW_HEIGHT, InitMountRow)

    ui.emptyText = listPanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    ui.emptyText:SetPoint("CENTER")
    ui.emptyText:SetText(L("NO_MOUNTS"))

    frame:SetScript("OnShow", function()
        addon.RefreshUI()
    end)

    addon.RestoreWindowPosition(frame)
    UpdateModeButtons()
    return frame
end

function addon.RefreshSelection()
    if not (ui.frame and ui.frame:IsShown()) then
        return
    end
    ui.mountList:ForEachFrame(function(button)
        if button.mount then
            SetRowBackground(button, button.GetElementDataIndex and button:GetElementDataIndex() or 1,
                state.selectedMountID == button.mount.mountID)
        end
    end)
    RenderDetail()
end

function addon.RefreshUI()
    if not (ui.frame and ui.frame:IsShown()) then
        return
    end

    if not state.scanned then
        addon.ScanMounts()
    elseif state.dirty then
        addon.ReevaluateMounts()
    end

    for key, check in pairs(ui.checkboxes) do
        check:SetChecked(addon.GetOption(key) and true or false)
    end

    addon.BuildView(ui.search:GetText())

    local collected, total, missing, ready, check, locked = addon.GetSummary()
    ui.summary:SetText(L("SUMMARY", collected, total, missing, ready, check, locked))

    ui.groupList:SetDataProvider(CreateDataProvider(state.groups), ScrollBoxConstants.RetainScrollPosition)
    ui.mountList:SetDataProvider(CreateDataProvider(state.filtered), ScrollBoxConstants.RetainScrollPosition)
    ui.emptyText:SetShown(#state.filtered == 0)

    RenderDetail()
end

function addon.ToggleUI()
    if not ui.frame then
        CreateMainFrame()
        state.selectedGroup = addon.GetStoredSelectedGroup(addon.GetOption("groupBy"))
    end
    if state.attMissing then
        state.scanned = false
    end
    ui.frame:SetShown(not ui.frame:IsShown())
end

function addon.ShowMount(mountID)
    if not ui.frame then
        addon.ToggleUI()
    elseif not ui.frame:IsShown() then
        ui.frame:Show()
    end
    state.selectedMountID = mountID
    RenderDetail()
end

function addon.IsUIShown()
    return ui.frame and ui.frame:IsShown()
end

-- Button on the Blizzard Mount Journal that opens our window on the selected
-- mount. It sits inside the mount preview (top-right) because the journal's
-- title bar border is drawn above child frames and would cover it.
function addon.InstallJournalButton()
    if ui.journalButton or not MountJournal then
        return
    end

    local anchor = MountJournal.MountDisplay or MountJournal
    local button = CreateFrame("Button", nil, MountJournal, "UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -8, -8)
    button:SetFrameLevel(anchor:GetFrameLevel() + 20)
    button:SetText(L("JOURNAL_BUTTON"))
    button:SetScript("OnClick", function()
        local selected = MountJournal.selectedMountID
        if selected then
            addon.ShowMount(selected)
        else
            addon.ToggleUI()
        end
    end)
    ui.journalButton = button
end

------------------------------------------------------------------------------
-- Minimap button (drag to move around the minimap edge)
------------------------------------------------------------------------------

local function UpdateMinimapButtonPosition()
    local button = ui.minimapButton
    local angle = math.rad(addon.GetDB().minimap.angle or 200)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnMinimapButtonDrag()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    addon.GetDB().minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    UpdateMinimapButtonPosition()
end

function addon.CreateMinimapButton()
    if ui.minimapButton or not Minimap then
        return
    end

    local button = CreateFrame("Button", "MissingMountFinderMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function()
        addon.ToggleUI()
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnMinimapButtonDrag)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L("FRAME_TITLE"))
        if state.scanned then
            local collected, total, _, ready = addon.GetSummary()
            GameTooltip:AddLine(string.format("%d / %d collected, %d eligible now", collected, total, ready), 1, 1, 1)
        end
        GameTooltip:AddLine(L("MINIMAP_TOOLTIP_CLICK"), 0.6, 0.6, 0.6)
        GameTooltip:AddLine(L("MINIMAP_TOOLTIP_DRAG"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    ui.minimapButton = button
    UpdateMinimapButtonPosition()
    button:SetShown(not addon.GetDB().minimap.hide)
end

function addon.ToggleMinimapButton()
    local db = addon.GetDB().minimap
    db.hide = not db.hide
    if ui.minimapButton then
        ui.minimapButton:SetShown(not db.hide)
    end
    addon.Print(db.hide and L("MINIMAP_HIDDEN") or L("MINIMAP_SHOWN"))
end
