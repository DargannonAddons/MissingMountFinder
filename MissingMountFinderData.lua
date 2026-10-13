local _, addon = ...

local state = addon.state
local STATUS = addon.STATUS
local REQ = addon.REQ
local L = addon.GetString

local SOURCE_FALLBACK_NAMES = {
    [1] = "Drop",
    [2] = "Quest",
    [3] = "Vendor",
    [4] = "Profession",
    [5] = "Pet Battle",
    [6] = "Achievement",
    [7] = "World Event",
    [8] = "Promotion",
    [9] = "Trading Card Game",
    [10] = "In-Game Shop",
    [11] = "Discovery",
    [12] = "Trading Post",
}

local SOURCE_HOWTO_KEYS = {
    [1] = "HOWTO_Drop",
    [2] = "HOWTO_Quest",
    [3] = "HOWTO_Vendor",
    [4] = "HOWTO_Profession",
    [5] = "HOWTO_PetBattle",
    [6] = "HOWTO_Achievement",
    [7] = "HOWTO_WorldEvent",
    [8] = "HOWTO_Promotion",
    [9] = "HOWTO_TCG",
    [10] = "HOWTO_Store",
    [11] = "HOWTO_Discovery",
    [12] = "HOWTO_TradingPost",
}

local SHOP_SOURCE_TYPES = {
    [8] = true,
    [9] = true,
    [10] = true,
}

local UNKNOWN_SOURCE_TYPE = 99
local NO_ZONE_KEY = "__nozone"
addon.ALL_GROUP_KEY = "__all"

local statusOrderIndex = {}
for i, status in ipairs(addon.statusOrder) do
    statusOrderIndex[status] = i
end

function addon.GetSourceTypeName(sourceType)
    if sourceType == UNKNOWN_SOURCE_TYPE then
        return UNKNOWN or "Unknown"
    end
    return _G["BATTLE_PET_SOURCE_" .. tostring(sourceType)] or SOURCE_FALLBACK_NAMES[sourceType] or (UNKNOWN or "Unknown")
end

------------------------------------------------------------------------------
-- Source text parsing
------------------------------------------------------------------------------

local function StripColors(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function StripTextures(text)
    return (text:gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|A.-|a", ""))
end

local function Trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Splits "|cFFFFD200Drop: |rAttumen\n|cFFFFD200Zone: |rKarazhan" into
-- { Drop = "Attumen", Zone = "Karazhan" }. Raw values keep texture codes so
-- costs can still be parsed and displayed with their icons.
local function ParseSourceText(sourceText)
    local fields, rawFields = {}, {}
    if type(sourceText) ~= "string" or sourceText == "" then
        return fields, rawFields
    end

    local normalized = sourceText:gsub("|n", "\n")
    for line in normalized:gmatch("[^\r\n]+") do
        local clean = StripColors(line)
        local key, value = clean:match("^%s*([^:|]+):%s*(.-)%s*$")
        if key and value and value ~= "" then
            key = Trim(key)
            if not rawFields[key] then
                rawFields[key] = value
                fields[key] = Trim(StripTextures(value))
            end
        end
    end

    return fields, rawFields
end

------------------------------------------------------------------------------
-- Classification
------------------------------------------------------------------------------

local function IsUnobtainable(name, curated, attData)
    if curated and curated.unobtainable ~= nil then
        return curated.unobtainable
    end
    if attData and attData.unobtainable then
        return true
    end
    for _, pattern in ipairs(addon.unobtainablePatterns or {}) do
        if string.find(name, pattern, 1, true) then
            return true
        end
    end
    return false
end

local function ResolveZone(mount)
    local curated = mount.curated
    local fields = mount.sourceFields

    mount.zone = (curated and curated.zone) or fields["Zone"] or fields["Location"]
        or (mount.attData and mount.attData.mapName)
    if mount.zone then
        -- Some sources list several zones ("Zone: Nagrand, Talador"); keep the first.
        mount.zone = Trim(mount.zone:match("^([^,;]+)") or mount.zone)
    end
end

local function ComputeStatus(mount)
    if mount.isCollected then
        return STATUS.COLLECTED
    end
    if mount.unobtainable then
        return STATUS.UNOBTAINABLE
    end
    if mount.shouldHideOnChar then
        return STATUS.UNAVAILABLE
    end
    if SHOP_SOURCE_TYPES[mount.sourceType] then
        return STATUS.SHOP
    end

    local unverified = false
    for _, result in ipairs(mount.results) do
        if result.status == REQ.UNMET or result.status == REQ.PARTIAL then
            -- A wrong-faction mount is "not for this character", not "locked".
            if result.req and result.req.type == "faction" then
                return STATUS.UNAVAILABLE
            end
            return STATUS.LOCKED
        elseif result.status == REQ.UNKNOWN then
            unverified = true
        end
    end

    return unverified and STATUS.CHECK or STATUS.READY
end

function addon.EvaluateMount(mount)
    mount.results = {}
    for _, req in ipairs(mount.requirements) do
        local result = addon.EvaluateRequirement(req)
        result.req = req
        mount.results[#mount.results + 1] = result
    end
    mount.status = ComputeStatus(mount)
end

local function BuildSearchText(mount)
    local parts = {
        mount.name,
        mount.zone or "",
        mount.sourceLabel or "",
    }
    for _, value in pairs(mount.sourceFields) do
        parts[#parts + 1] = value
    end
    return string.lower(table.concat(parts, " "))
end

------------------------------------------------------------------------------
-- Scanning
------------------------------------------------------------------------------

local function ReadMount(mountID)
    local name, spellID, icon, _, isUsable, sourceType, _, isFactionSpecific, faction, shouldHideOnChar, isCollected =
        C_MountJournal.GetMountInfoByID(mountID)
    if not name then
        return nil
    end

    local _, description, sourceText = C_MountJournal.GetMountInfoExtraByID(mountID)

    local mount = {
        mountID = mountID,
        name = name,
        spellID = spellID,
        icon = icon,
        isUsable = isUsable,
        sourceType = (sourceType and sourceType > 0) and sourceType or UNKNOWN_SOURCE_TYPE,
        isFactionSpecific = isFactionSpecific,
        faction = faction,
        shouldHideOnChar = shouldHideOnChar,
        isCollected = isCollected,
        description = description,
        sourceText = sourceText or "",
        curated = addon.curatedMounts and addon.curatedMounts[name],
    }

    mount.sourceFields, mount.sourceRawFields = ParseSourceText(mount.sourceText)
    mount.sourceLabel = addon.GetSourceTypeName(mount.sourceType)
    mount.requirements = addon.BuildRequirements(mount)
    mount.unobtainable = IsUnobtainable(name, mount.curated, mount.attData)
    ResolveZone(mount)
    addon.EvaluateMount(mount)
    mount.searchText = BuildSearchText(mount)

    return mount
end

function addon.ScanMounts()
    if not (C_MountJournal and C_MountJournal.GetMountIDs) then
        return false
    end
    if addon.ATT then
        addon.ATT.ResetCache()
    end

    local mounts, byID, byName = {}, {}, {}
    for _, mountID in ipairs(C_MountJournal.GetMountIDs() or {}) do
        local ok, mount = pcall(ReadMount, mountID)
        if ok and mount then
            mounts[#mounts + 1] = mount
            byID[mountID] = mount
            byName[string.lower(mount.name)] = mount
        end
    end

    -- ATT builds its lookup caches some time after login; if nothing matched
    -- yet, remember to try again the next time the window opens.
    local attMatches = 0
    for _, mount in ipairs(mounts) do
        if mount.attData then
            attMatches = attMatches + 1
        end
    end
    state.attMissing = addon.ATT ~= nil and addon.ATT.IsAvailable() and attMatches == 0

    state.mounts = mounts
    state.mountsByID = byID
    state.mountsByName = byName
    state.scanned = true
    state.dirty = false
    return true
end

-- Re-evaluates requirements without re-reading the journal (rep, gold, etc. changed).
function addon.ReevaluateMounts()
    for _, mount in ipairs(state.mounts) do
        addon.EvaluateMount(mount)
    end
    state.dirty = false
end

function addon.FindMountByName(name)
    if not state.scanned then
        addon.ScanMounts()
    end
    return state.mountsByName and state.mountsByName[string.lower(name)]
end

function addon.GetMount(mountID)
    return state.mountsByID[mountID]
end

------------------------------------------------------------------------------
-- How-to guidance
------------------------------------------------------------------------------

function addon.GetHowToSteps(mount)
    local steps = {}

    if mount.status == STATUS.UNOBTAINABLE then
        steps[#steps + 1] = L("HOWTO_UNOBTAINABLE")
    elseif mount.status == STATUS.UNAVAILABLE then
        steps[#steps + 1] = L("HOWTO_UNAVAILABLE")
    end

    if mount.curated and mount.curated.steps then
        for _, step in ipairs(mount.curated.steps) do
            steps[#steps + 1] = step
        end
        return steps
    end

    -- Quest chain first: nothing else matters until it's unlocked.
    for _, result in ipairs(mount.results) do
        if result.nextQuestID then
            local title = addon.ATT.GetQuestTitle(result.nextQuestID)
            local mapID, x, y = addon.ATT.GetQuestLocation(result.nextQuestID)
            local mapInfo = mapID and C_Map.GetMapInfo(mapID)
            if mapInfo and x then
                steps[#steps + 1] = L("HOWTO_NEXT_QUEST_AT", title, mapInfo.name, x, y)
            else
                steps[#steps + 1] = L("HOWTO_NEXT_QUEST", title)
            end
        end
    end

    -- Where the vendor / drop source is, from AllTheThings.
    local att = mount.attData
    if att and att.mapName and att.x then
        steps[#steps + 1] = L("HOWTO_ATT_LOCATION", att.npcName or mount.name, att.mapName, att.x, att.y)
    end

    local fields = mount.sourceFields
    local zoneSuffix = mount.zone and L("HOWTO_IN_ZONE", mount.zone) or ""
    local key = SOURCE_HOWTO_KEYS[mount.sourceType]

    if key == "HOWTO_Drop" then
        steps[#steps + 1] = L(key, fields["Drop"] or mount.name, zoneSuffix)
    elseif key == "HOWTO_Quest" then
        steps[#steps + 1] = L(key, fields["Quest"] or "?", zoneSuffix)
    elseif key == "HOWTO_Vendor" then
        steps[#steps + 1] = L(key, fields["Vendor"] or "a vendor", zoneSuffix)
    elseif key == "HOWTO_Profession" then
        steps[#steps + 1] = L(key, fields["Profession"] or mount.sourceLabel)
    elseif key == "HOWTO_Achievement" then
        steps[#steps + 1] = L(key, fields["Achievement"] or "?")
    elseif key == "HOWTO_WorldEvent" then
        steps[#steps + 1] = L(key, fields["World Event"] or fields["Event"] or "?")
    elseif key == "HOWTO_PetBattle" then
        steps[#steps + 1] = L(key, fields["Pet Battle"] or zoneSuffix)
    elseif key == "HOWTO_Discovery" then
        steps[#steps + 1] = L(key, fields["Discovery"] or mount.zone or "?")
    elseif key then
        steps[#steps + 1] = L(key)
    else
        steps[#steps + 1] = L("HOWTO_Generic")
    end

    -- Point at the first unmet requirement so the player knows what to do next.
    for _, result in ipairs(mount.results) do
        local blocking = result.status == REQ.UNMET or result.status == REQ.PARTIAL or result.status == REQ.UNKNOWN
        -- Quest chains already got a specific "Next quest" step above.
        if blocking and not result.nextQuestID then
            steps[#steps + 1] = "Next: " .. result.text
            break
        end
    end

    return steps
end

------------------------------------------------------------------------------
-- Filtering and grouping
------------------------------------------------------------------------------

local function PassesFilters(mount, search)
    local db = addon.GetDB()
    local ui = db.ui
    local status = mount.status

    if status == STATUS.COLLECTED and not ui.showCollected then
        return false
    end
    if status == STATUS.UNAVAILABLE and not ui.showUnavailable then
        return false
    end
    if status == STATUS.UNOBTAINABLE and not ui.showUnobtainable then
        return false
    end
    if status == STATUS.SHOP and not ui.showShop then
        return false
    end
    if ui.readyOnly and status ~= STATUS.READY then
        return false
    end
    if ui.goalsOnly and not db.goals[mount.mountID] then
        return false
    end
    if search and search ~= "" and not string.find(mount.searchText, search, 1, true) then
        return false
    end
    return true
end

------------------------------------------------------------------------------
-- "What to Farm": one group per unmet requirement (currency, reputation, gold,
-- achievement...), aggregated across every missing mount that needs it.
------------------------------------------------------------------------------

local FARM_STATUSES = {
    [REQ.UNMET] = true,
    [REQ.PARTIAL] = true,
    [REQ.UNKNOWN] = true,
}

local FARM_KEY_FIELDS = {
    currency = "id",
    item = "id",
    achievement = "id",
    quest = "id",
    reputation = "factionID",
    renown = "factionID",
    friendship = "factionID",
    event = "name",
    unverified = "texture",
    questline = "keyQuest",
    friendshipPoints = "factionID",
    professionTier = "name",
}

local function GetFarmKey(result)
    local req = result.req
    if not req then
        return nil
    end
    local field = FARM_KEY_FIELDS[req.type]
    if field then
        return req.type .. ":" .. tostring(req[field])
    elseif req.type == "profession" then
        return "profession:" .. tostring(req.name or req.skillLine)
    end
    return req.type
end

local function GetFarmResults(mount)
    if mount.status ~= STATUS.LOCKED and mount.status ~= STATUS.CHECK then
        return nil
    end
    local list
    for _, result in ipairs(mount.results) do
        if FARM_STATUSES[result.status] and result.req and result.req.type ~= "faction" then
            list = list or {}
            list[#list + 1] = result
        end
    end
    return list
end

local function FormatAmount(reqType, value)
    if reqType == "gold" then
        value = math.floor(value / 10000)
        return (BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)) .. "g"
    end
    return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
end

local function AddFarmResult(group, result)
    group.reqType = result.req.type
    group.result = group.result or result
    if result.have then
        group.have = result.have
    end
    if result.need then
        group.minNeed = math.min(group.minNeed or result.need, result.need)
        group.maxNeed = math.max(group.maxNeed or result.need, result.need)
        group.totalNeed = (group.totalNeed or 0) + result.need
    end
end

local function GetFarmSubText(group)
    local reqType = group.reqType
    if not (group.have and group.maxNeed) then
        return nil
    end
    if reqType == "currency" or reqType == "item" or reqType == "gold" then
        if group.minNeed == group.totalNeed then
            return L("FARM_SUB_SINGLE", FormatAmount(reqType, group.have), FormatAmount(reqType, group.minNeed))
        end
        return L("FARM_SUB_AMOUNT", FormatAmount(reqType, group.have), FormatAmount(reqType, group.minNeed),
            FormatAmount(reqType, group.totalNeed))
    elseif reqType == "reputation" then
        return L("FARM_SUB_LEVEL", addon.GetStandingLabel(math.max(1, group.have)), addon.GetStandingLabel(group.maxNeed))
    elseif reqType == "achievement" then
        return L("FARM_SUB_CRITERIA", group.have, group.maxNeed)
    end
    return L("FARM_SUB_LEVEL", tostring(group.have), tostring(group.maxNeed))
end

------------------------------------------------------------------------------
-- Grouping
------------------------------------------------------------------------------

-- Returns the { key, label, result } groups a mount belongs to in this mode.
local function GetGroupEntries(mount, mode)
    if mode == "zone" then
        local key = mount.zone or NO_ZONE_KEY
        return { { key = key, label = key == NO_ZONE_KEY and L("GROUP_NO_ZONE") or key } }
    elseif mode == "source" then
        return { { key = mount.sourceType, label = addon.GetSourceTypeName(mount.sourceType) } }
    elseif mode == "status" then
        return { { key = mount.status, label = L("STATUS_" .. mount.status) } }
    elseif mode == "farm" then
        local entries = {}
        local seen = {}
        for _, result in ipairs(GetFarmResults(mount) or {}) do
            local key = GetFarmKey(result)
            if key and not seen[key] then
                seen[key] = true
                entries[#entries + 1] = { key = key, label = result.label or result.text, result = result }
            end
        end
        return entries
    end
    return {}
end

local function SortGroups(mode, a, b)
    if mode == "zone" then
        if a.key == NO_ZONE_KEY then
            return false
        end
        if b.key == NO_ZONE_KEY then
            return true
        end
        return a.label < b.label
    elseif mode == "source" then
        return a.key < b.key
    elseif mode == "status" then
        return (statusOrderIndex[a.key] or 999) < (statusOrderIndex[b.key] or 999)
    elseif mode == "farm" then
        -- Biggest payoff first: the requirement blocking the most mounts.
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.label < b.label
    end
    return a.label < b.label
end

local function SortMounts(a, b)
    local sa, sb = statusOrderIndex[a.status] or 999, statusOrderIndex[b.status] or 999
    if sa ~= sb then
        return sa < sb
    end
    return a.name < b.name
end

-- Rebuilds state.groups (sidebar) and state.filtered (mount list) from the
-- current options, search text and selected group.
function addon.BuildView(search)
    local mode = addon.GetOption("groupBy")
    search = search and string.lower(Trim(search)) or ""

    local groupsByKey = {}
    local groups = {}
    local all = { key = addon.ALL_GROUP_KEY, label = L("GROUP_ALL"), count = 0, ready = 0 }
    local visible = {}
    local mountKeys = {}

    for _, mount in ipairs(state.mounts) do
        if PassesFilters(mount, search) then
            local entries = GetGroupEntries(mount, mode)
            -- The farm view only lists mounts that have something to farm.
            if mode ~= "farm" or #entries > 0 then
                visible[#visible + 1] = mount
                local keys = {}
                mountKeys[mount] = keys
                all.count = all.count + 1
                if mount.status == STATUS.READY then
                    all.ready = all.ready + 1
                end

                for _, entry in ipairs(entries) do
                    keys[entry.key] = true
                    local group = groupsByKey[entry.key]
                    if not group then
                        group = { key = entry.key, label = entry.label, count = 0, ready = 0 }
                        groupsByKey[entry.key] = group
                        groups[#groups + 1] = group
                    end
                    group.count = group.count + 1
                    if mount.status == STATUS.READY then
                        group.ready = group.ready + 1
                    end
                    if entry.result then
                        AddFarmResult(group, entry.result)
                    end
                end
            end
        end
    end

    if mode == "farm" then
        for _, group in ipairs(groups) do
            group.sub = GetFarmSubText(group)
        end
    end

    table.sort(groups, function(a, b)
        return SortGroups(mode, a, b)
    end)
    table.insert(groups, 1, all)

    local selected = state.selectedGroup
    if selected == nil or (selected ~= addon.ALL_GROUP_KEY and not groupsByKey[selected]) then
        selected = addon.ALL_GROUP_KEY
    end
    state.selectedGroup = selected

    local filtered = {}
    for _, mount in ipairs(visible) do
        if selected == addon.ALL_GROUP_KEY or mountKeys[mount][selected] then
            filtered[#filtered + 1] = mount
        end
    end
    table.sort(filtered, SortMounts)

    state.groups = groups
    state.filtered = filtered
end

function addon.GetSummary()
    local collected, total, ready, check, locked = 0, 0, 0, 0, 0
    for _, mount in ipairs(state.mounts) do
        local status = mount.status
        if status == STATUS.COLLECTED then
            collected = collected + 1
            total = total + 1
        elseif status ~= STATUS.UNOBTAINABLE and status ~= STATUS.UNAVAILABLE then
            total = total + 1
            if status == STATUS.READY then
                ready = ready + 1
            elseif status == STATUS.CHECK then
                check = check + 1
            elseif status == STATUS.LOCKED then
                locked = locked + 1
            end
        end
    end
    return collected, total, total - collected, ready, check, locked
end
