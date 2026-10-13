local addonName, addon = ...

addon.name = addonName

addon.constants = {
    FRAME_WIDTH = 1040,
    FRAME_HEIGHT = 620,
    GROUP_PANEL_WIDTH = 210,
    DETAIL_PANEL_WIDTH = 380,
    GROUP_ROW_HEIGHT = 24,
    GROUP_ROW_TALL_HEIGHT = 38,
    MOUNT_ROW_HEIGHT = 38,
    MAX_CRITERIA_LINES = 30,
}

addon.theme = {
    panelBg = { 0.08, 0.08, 0.08, 0.97 },
    panelBorder = { 0.42, 0.42, 0.42, 0.95 },
    headerBg = { 0.13, 0.13, 0.13, 0.96 },
    rowOddBg = { 0.11, 0.11, 0.11, 0.90 },
    rowEvenBg = { 0.13, 0.13, 0.13, 0.90 },
    rowHoverBg = { 0.18, 0.17, 0.15, 0.95 },
    rowSelectedBg = { 0.22, 0.19, 0.14, 0.97 },
    rowSelectedBorder = { 0.76, 0.62, 0.26, 0.95 },
    rowText = { 0.94, 0.94, 0.94 },
    rowSubText = { 0.74, 0.74, 0.74 },
    textMuted = { 0.74, 0.74, 0.74 },
    textBright = { 0.95, 0.95, 0.95 },
    textGold = { 1.0, 0.82, 0.0 },
}

-- Overall acquisition status of a mount for the current character.
addon.STATUS = {
    COLLECTED = "collected",
    READY = "ready",
    CHECK = "check",
    LOCKED = "locked",
    SHOP = "shop",
    UNOBTAINABLE = "unobtainable",
    UNAVAILABLE = "unavailable",
}

addon.statusOrder = {
    addon.STATUS.READY,
    addon.STATUS.CHECK,
    addon.STATUS.LOCKED,
    addon.STATUS.SHOP,
    addon.STATUS.UNAVAILABLE,
    addon.STATUS.UNOBTAINABLE,
    addon.STATUS.COLLECTED,
}

addon.statusColors = {
    [addon.STATUS.COLLECTED] = { 0.55, 0.55, 0.55 },
    [addon.STATUS.READY] = { 0.25, 0.95, 0.35 },
    [addon.STATUS.CHECK] = { 0.95, 0.85, 0.30 },
    [addon.STATUS.LOCKED] = { 1.00, 0.55, 0.20 },
    [addon.STATUS.SHOP] = { 0.35, 0.75, 1.00 },
    [addon.STATUS.UNOBTAINABLE] = { 0.65, 0.30, 0.30 },
    [addon.STATUS.UNAVAILABLE] = { 0.60, 0.50, 0.70 },
}

-- Result of evaluating a single requirement.
addon.REQ = {
    MET = "met",
    UNMET = "unmet",
    PARTIAL = "partial",
    UNKNOWN = "unknown",
    INFO = "info",
}

addon.reqColors = {
    [addon.REQ.MET] = { 0.25, 0.95, 0.35 },
    [addon.REQ.UNMET] = { 1.00, 0.30, 0.30 },
    [addon.REQ.PARTIAL] = { 1.00, 0.82, 0.10 },
    [addon.REQ.UNKNOWN] = { 0.95, 0.85, 0.30 },
    [addon.REQ.INFO] = { 0.70, 0.70, 0.70 },
}

addon.groupModes = { "zone", "source", "status", "farm" }

addon.state = {
    mounts = {},
    mountsByID = {},
    filtered = {},
    groups = {},
    selectedGroup = nil,
    selectedMountID = nil,
    scanned = false,
}

addon.defaults = {
    version = 1,
    window = {
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = 0,
    },
    ui = {
        groupBy = "zone",
        selectedGroupByMode = {},
        showCollected = false,
        showUnavailable = false,
        showUnobtainable = false,
        showShop = true,
        goalsOnly = false,
        readyOnly = false,
    },
    goals = {},
    minimap = {
        hide = false,
        angle = 200,
    },
}

local function CopyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            CopyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function ValidateWindowDB(db)
    local window = db.window
    if type(window.point) ~= "string" then
        window.point = addon.defaults.window.point
    end
    if type(window.relPoint) ~= "string" then
        window.relPoint = addon.defaults.window.relPoint
    end
    if type(window.x) ~= "number" then
        window.x = addon.defaults.window.x
    end
    if type(window.y) ~= "number" then
        window.y = addon.defaults.window.y
    end
end

local function ValidateUIDB(db)
    local ui = db.ui
    local validMode = false
    for _, mode in ipairs(addon.groupModes) do
        if ui.groupBy == mode then
            validMode = true
        end
    end
    if not validMode then
        ui.groupBy = addon.defaults.ui.groupBy
    end
    if type(ui.selectedGroupByMode) ~= "table" then
        ui.selectedGroupByMode = {}
    end
end

function addon.GetDB()
    if type(MissingMountFinderDB) ~= "table" then
        MissingMountFinderDB = {}
    end

    CopyDefaults(MissingMountFinderDB, addon.defaults)
    ValidateWindowDB(MissingMountFinderDB)
    ValidateUIDB(MissingMountFinderDB)
    MissingMountFinderDB.version = addon.defaults.version

    return MissingMountFinderDB
end

function addon.GetOption(key)
    return addon.GetDB().ui[key]
end

function addon.SetOption(key, value)
    addon.GetDB().ui[key] = value
end

function addon.IsGoal(mountID)
    return addon.GetDB().goals[mountID] == true
end

function addon.ToggleGoal(mountID)
    local goals = addon.GetDB().goals
    if goals[mountID] then
        goals[mountID] = nil
    else
        goals[mountID] = true
    end
end

function addon.GetStoredSelectedGroup(mode)
    return addon.GetDB().ui.selectedGroupByMode[mode]
end

function addon.SetStoredSelectedGroup(mode, key)
    addon.GetDB().ui.selectedGroupByMode[mode] = key
end

function addon.RestoreWindowPosition(frame)
    local db = addon.GetDB()
    frame:ClearAllPoints()
    frame:SetPoint(db.window.point, UIParent, db.window.relPoint, db.window.x, db.window.y)
end

function addon.SaveWindowPosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint()
    if not point then
        return
    end

    local db = addon.GetDB()
    db.window.point = point
    db.window.relPoint = relPoint
    db.window.x = x
    db.window.y = y
end

function addon.Print(message)
    print("|cff00ccffMissingMountFinder:|r " .. tostring(message))
end
