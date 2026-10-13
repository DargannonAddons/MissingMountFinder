local _, addon = ...

local REQ = addon.REQ
local L = addon.GetString
local MAX_CRITERIA_LINES = addon.constants.MAX_CRITERIA_LINES

local PROFESSION_NAMES = {
    [171] = "Alchemy",
    [164] = "Blacksmithing",
    [333] = "Enchanting",
    [202] = "Engineering",
    [182] = "Herbalism",
    [773] = "Inscription",
    [755] = "Jewelcrafting",
    [165] = "Leatherworking",
    [186] = "Mining",
    [393] = "Skinning",
    [197] = "Tailoring",
    [356] = "Fishing",
    [185] = "Cooking",
    [794] = "Archaeology",
}

local function FormatNumber(value)
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(value or 0)
    end
    return tostring(value or 0)
end

local function FormatMoney(copper)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper or 0)
    end
    if GetMoneyString then
        return GetMoneyString(copper or 0, true)
    end
    return FormatNumber(math.floor((copper or 0) / 10000)) .. "g"
end

local function GetStandingLabel(standing)
    local key = "FACTION_STANDING_LABEL" .. tostring(standing)
    if GetText and UnitSex then
        local ok, text = pcall(GetText, key, UnitSex("player"))
        if ok and text then
            return text
        end
    end
    return _G[key] or tostring(standing)
end

addon.GetStandingLabel = GetStandingLabel

local function PlayerFaction()
    return (UnitFactionGroup("player"))
end

------------------------------------------------------------------------------
-- Lookup indexes (built lazily, once per session)
------------------------------------------------------------------------------

local achievementIndex
local factionIndex
local standingIndex

local function IndexAchievementCategories(categories)
    if type(categories) ~= "table" then
        return
    end
    for _, categoryID in ipairs(categories) do
        local total = GetCategoryNumAchievements(categoryID, true) or 0
        for i = 1, total do
            local id, name = GetAchievementInfo(categoryID, i)
            if id and name then
                achievementIndex[string.lower(name)] = achievementIndex[string.lower(name)] or id
            end
        end
    end
end

function addon.FindAchievementByName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if not achievementIndex then
        achievementIndex = {}
        if GetCategoryList and GetCategoryNumAchievements then
            IndexAchievementCategories(GetCategoryList())
            if GetGuildCategoryList then
                IndexAchievementCategories(GetGuildCategoryList())
            end
        end
    end
    return achievementIndex[string.lower(name)]
end

local function GetFactionData(factionID)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local data = C_Reputation.GetFactionDataByID(factionID)
        if data and data.name and data.name ~= "" then
            return data.name, data.reaction
        end
        return nil
    end
    if GetFactionInfoByID then
        local name, _, standingID = GetFactionInfoByID(factionID)
        if name then
            return name, standingID
        end
    end
    return nil
end

function addon.FindFactionByName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if not factionIndex then
        factionIndex = {}
        for factionID = 1, 2800 do
            local factionName = GetFactionData(factionID)
            if factionName then
                factionIndex[string.lower(factionName)] = factionID
            end
        end
    end
    return factionIndex[string.lower(name)]
end

local function FindStandingByLabel(label)
    if type(label) ~= "string" then
        return nil
    end
    if not standingIndex then
        standingIndex = {}
        for standing = 1, 8 do
            standingIndex[string.lower(_G["FACTION_STANDING_LABEL" .. standing] or "")] = standing
            local female = _G["FACTION_STANDING_LABEL" .. standing .. "_FEMALE"]
            if female then
                standingIndex[string.lower(female)] = standing
            end
        end
    end
    return standingIndex[string.lower(label)]
end

------------------------------------------------------------------------------
-- Active world events (from the in-game calendar)
------------------------------------------------------------------------------

local activeEvents = nil

function addon.RefreshActiveEvents()
    if not (C_Calendar and C_Calendar.GetNumDayEvents and C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime) then
        return
    end

    local now = C_DateAndTime.GetCurrentCalendarTime()
    local shown = C_Calendar.GetMonthInfo and C_Calendar.GetMonthInfo(0)
    if not (now and shown and shown.year) then
        return
    end

    local offset = (now.year - shown.year) * 12 + (now.month - shown.month)
    local count = C_Calendar.GetNumDayEvents(offset, now.monthDay) or 0
    local events = {}
    for i = 1, count do
        local event = C_Calendar.GetDayEvent(offset, now.monthDay, i)
        if event and event.title and event.calendarType == "HOLIDAY" then
            events[#events + 1] = string.lower(event.title)
        end
    end
    activeEvents = events
end

local function IsEventActive(name)
    if not activeEvents then
        return nil
    end
    local lower = string.lower(name)
    for _, title in ipairs(activeEvents) do
        if string.find(title, lower, 1, true) or string.find(lower, title, 1, true) then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------------
-- Requirement evaluators. Each returns a result table:
--   { status = REQ.*, text = "...", lines = { {status, text}, ... }, achievementID = id }
------------------------------------------------------------------------------

local evaluators = {}

function evaluators.achievement(req)
    local id, name, _, completed = GetAchievementInfo(req.id)
    if not id then
        return { status = REQ.INFO, text = L("REQ_UNKNOWN_ACHIEVEMENT", req.id) }
    end

    local result = {
        status = completed and REQ.MET or REQ.UNMET,
        text = L("REQ_ACHIEVEMENT", name),
        label = name,
        achievementID = id,
        lines = {},
    }

    local numCriteria = GetAchievementNumCriteria(id) or 0
    local done = 0
    for i = 1, numCriteria do
        local criteriaString, _, criteriaCompleted, quantity, reqQuantity, _, flags, _, quantityString =
            GetAchievementCriteriaInfo(id, i)
        if criteriaCompleted then
            done = done + 1
        end
        if i <= MAX_CRITERIA_LINES then
            local text = criteriaString or ""
            local isProgressBar = flags and bit and bit.band(flags, 1) == 1
            if isProgressBar and quantityString then
                text = (text ~= "" and (text .. ": ") or "") .. quantityString
            elseif reqQuantity and reqQuantity > 1 then
                text = string.format("%s (%s / %s)", text, FormatNumber(quantity), FormatNumber(reqQuantity))
            end
            result.lines[#result.lines + 1] = { criteriaCompleted and REQ.MET or REQ.UNMET, text }
        end
    end
    if numCriteria > MAX_CRITERIA_LINES then
        result.lines[#result.lines + 1] = { REQ.INFO, L("DETAIL_CRITERIA_MORE", numCriteria - MAX_CRITERIA_LINES) }
    end

    result.have, result.need = done, numCriteria
    if not completed and done > 0 then
        result.status = REQ.PARTIAL
        result.text = string.format("%s  (%d / %d)", result.text, done, numCriteria)
    end

    return result
end

function evaluators.quest(req)
    local done
    if req.account and C_QuestLog.IsQuestFlaggedCompletedOnAccount then
        done = C_QuestLog.IsQuestFlaggedCompletedOnAccount(req.id)
    else
        done = C_QuestLog.IsQuestFlaggedCompleted(req.id)
    end
    local title = (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(req.id)) or req.name or ("#" .. req.id)
    return { status = done and REQ.MET or REQ.UNMET, text = L("REQ_QUEST", title), label = title }
end

function evaluators.reputation(req)
    local name, reaction = GetFactionData(req.factionID)
    if not name then
        return { status = REQ.INFO, text = L("REQ_UNKNOWN_FACTION", req.factionID) }
    end
    reaction = reaction or 0
    local met = reaction >= req.standing
    local status = met and REQ.MET or (reaction >= 5 and REQ.PARTIAL or REQ.UNMET)
    return {
        status = status,
        text = L("REQ_REPUTATION", name, GetStandingLabel(req.standing), GetStandingLabel(math.max(1, reaction))),
        label = name,
        have = reaction,
        need = req.standing,
    }
end

function evaluators.renown(req)
    local current = 0
    local name = "#" .. req.factionID
    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local data = C_MajorFactions.GetMajorFactionData(req.factionID)
        if data then
            name = data.name or name
            current = data.renownLevel or 0
            if data.isUnlocked == false then
                current = 0
            end
        end
    end
    local status = current >= req.level and REQ.MET or (current > 0 and REQ.PARTIAL or REQ.UNMET)
    return { status = status, text = L("REQ_RENOWN", name, req.level, current), label = name, have = current, need = req.level }
end

function evaluators.friendship(req)
    local current = 0
    local name = (GetFactionData(req.factionID)) or ("#" .. req.factionID)
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputationRanks then
        local ranks = C_GossipInfo.GetFriendshipReputationRanks(req.factionID)
        if ranks and ranks.currentLevel then
            current = ranks.currentLevel
        end
    end
    local status = current >= req.rank and REQ.MET or (current > 0 and REQ.PARTIAL or REQ.UNMET)
    return { status = status, text = L("REQ_FRIENDSHIP", name, req.rank, current), label = name, have = current, need = req.rank }
end

function evaluators.currency(req)
    local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(req.id)
    if not (info and info.name and info.name ~= "") then
        return { status = REQ.INFO, text = L("REQ_UNKNOWN_CURRENCY", req.id) }
    end
    local have = info.quantity or 0
    local icon = info.iconFileID and ("|T" .. info.iconFileID .. ":16:16|t ") or ""
    local text = L("REQ_CURRENCY", icon .. info.name, FormatNumber(have), FormatNumber(req.amount))
    local status = have >= req.amount and REQ.MET or REQ.UNMET

    -- Warband-transferable currencies: count what your other characters hold.
    -- Enough across the warband = "transfer, then buy" (partial), not met.
    if status ~= REQ.MET then
        local warbandTotal = addon.GetWarbandCurrencyTotal(req.id, have)
        if warbandTotal and warbandTotal > have then
            text = text .. L("REQ_CURRENCY_WARBAND", FormatNumber(warbandTotal))
            if warbandTotal >= req.amount then
                status = REQ.PARTIAL
                text = text .. L("REQ_CURRENCY_TRANSFER")
            end
        end
    end

    return {
        status = status,
        text = text,
        label = icon .. info.name,
        have = have,
        need = req.amount,
    }
end

-- Sum of a currency across this character and the rest of the warband, or nil
-- when the client has not sent account data (or the currency is not transferable).
function addon.GetWarbandCurrencyTotal(currencyID, currentQuantity)
    if not (C_CurrencyInfo and C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters) then
        return nil
    end
    local ok, data = pcall(C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters, currencyID)
    if not ok or type(data) ~= "table" or #data == 0 then
        return nil
    end
    local total = currentQuantity or 0
    for _, entry in ipairs(data) do
        total = total + (entry.quantity or 0)
    end
    return total
end

function evaluators.gold(req)
    local have = GetMoney() or 0
    local status = have >= req.amount and REQ.MET or REQ.UNMET
    return {
        status = status,
        text = L("REQ_GOLD", FormatMoney(req.amount), FormatMoney(have)),
        label = L("FARM_GOLD"),
        have = have,
        need = req.amount,
    }
end

function evaluators.item(req)
    local count = 0
    if C_Item and C_Item.GetItemCount then
        count = C_Item.GetItemCount(req.id, true, false, true, true) or 0
    elseif GetItemCount then
        count = GetItemCount(req.id, true) or 0
    end
    local needed = req.count or 1
    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(req.id)) or req.name or ("Item #" .. req.id)
    local status = count >= needed and REQ.MET or REQ.UNMET
    return { status = status, text = L("REQ_ITEM", name, count, needed), label = name, have = count, need = needed }
end

function evaluators.level(req)
    local level = UnitLevel("player") or 0
    return {
        status = level >= req.level and REQ.MET or REQ.UNMET,
        text = L("REQ_LEVEL", req.level, level),
        label = L("FARM_LEVEL"),
        have = level,
        need = req.level,
    }
end

local function FindPlayerProfession(skillLine, name)
    local lowerName = name and string.lower(name)
    local indices = { GetProfessions() }
    for i = 1, 5 do
        local index = indices[i]
        if index then
            local profName, _, rank, _, _, _, profSkillLine = GetProfessionInfo(index)
            if (skillLine and profSkillLine == skillLine) or (lowerName and profName and string.lower(profName) == lowerName) then
                return profName, rank or 0
            end
        end
    end
    return nil
end

function evaluators.profession(req)
    local displayName = req.name or PROFESSION_NAMES[req.skillLine] or ("#" .. tostring(req.skillLine))
    if req.skillLine and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        displayName = C_TradeSkillUI.GetTradeSkillDisplayName(req.skillLine) or displayName
    end

    local profName, rank = FindPlayerProfession(req.skillLine, req.name)
    if not profName then
        return { status = REQ.UNMET, text = L("REQ_PROFESSION", displayName), label = displayName }
    end
    if req.skill then
        local status = rank >= req.skill and REQ.MET or REQ.PARTIAL
        return { status = status, text = L("REQ_PROFESSION_SKILL", profName, req.skill, rank), label = profName }
    end
    return { status = REQ.MET, text = L("REQ_PROFESSION", profName), label = profName }
end

-- Expansion tier of a profession, e.g. "Khaz Algar Engineering".
local function FindTierSkill(tierName)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines and C_TradeSkillUI.GetProfessionInfoBySkillLineID) then
        return nil
    end
    local lower = string.lower(tierName)
    for _, skillLine in ipairs(C_TradeSkillUI.GetAllProfessionTradeSkillLines() or {}) do
        local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLine)
        if info and info.professionName and string.lower(info.professionName) == lower then
            return info.skillLevel or 0, info.maxSkillLevel or 0
        end
    end
    return nil
end

function evaluators.professionTier(req)
    local baseName = FindPlayerProfession(nil, req.base)
    if not baseName then
        return { status = REQ.UNMET, text = L("REQ_PROFESSION_TIER_MISSING", req.name, req.base), label = req.name }
    end
    local skill, maxSkill = FindTierSkill(req.name)
    if skill == nil then
        return { status = REQ.MET, text = L("REQ_PROFESSION_TIER_UNCHECKED", req.name), label = req.name }
    end
    if skill > 0 then
        return {
            status = REQ.MET,
            text = L("REQ_PROFESSION_TIER", req.name, skill, maxSkill),
            label = req.name,
            have = skill,
            need = maxSkill,
        }
    end
    return { status = REQ.PARTIAL, text = L("REQ_PROFESSION_TIER_LEARN", req.name), label = req.name }
end

-- Friendship factions gated by reputation points (from AllTheThings data).
function evaluators.friendshipPoints(req)
    local data = C_GossipInfo and C_GossipInfo.GetFriendshipReputation and C_GossipInfo.GetFriendshipReputation(req.factionID)
    local name = (data and data.name) or (GetFactionData(req.factionID)) or ("#" .. req.factionID)
    local have = (data and data.standing) or 0
    local status = have >= req.points and REQ.MET or (have > 0 and REQ.PARTIAL or REQ.UNMET)
    return {
        status = status,
        text = L("REQ_FRIENDSHIP_POINTS", name, FormatNumber(have), FormatNumber(req.points)),
        label = name,
        have = have,
        need = req.points,
    }
end

-- Prerequisite quest chain (from AllTheThings data), evaluated live.
function evaluators.questline(req)
    if not (addon.ATT and addon.ATT.IsAvailable()) then
        return { status = REQ.INFO, text = "" }
    end
    local chain, lines, done, nextQuest = addon.ATT.EvaluateQuestline(req)
    local finalTitle = addon.ATT.GetQuestTitle(req.keyQuest or chain[#chain] or req.quests[1])
    local total = #chain
    local status = REQ.MET
    if done < total then
        status = done > 0 and REQ.PARTIAL or REQ.UNMET
    end
    return {
        status = status,
        text = L("REQ_QUESTLINE", finalTitle, done, total),
        label = L("FARM_QUESTLINE", finalTitle),
        lines = lines,
        nextQuestID = nextQuest,
        have = done,
        need = total,
    }
end

function evaluators.class(req)
    local _, classFile = UnitClass("player")
    local display = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[req.class]) or req.class
    return { status = classFile == req.class and REQ.MET or REQ.UNMET, text = L("REQ_CLASS", display) }
end

function evaluators.race(req)
    local raceName, raceFile = UnitRace("player")
    local met = raceFile == req.race or raceName == req.race
    return { status = met and REQ.MET or REQ.UNMET, text = L("REQ_RACE", req.race) }
end

function evaluators.faction(req)
    local display = req.faction == "Alliance" and (FACTION_ALLIANCE or "Alliance") or (FACTION_HORDE or "Horde")
    return { status = PlayerFaction() == req.faction and REQ.MET or REQ.UNMET, text = L("REQ_FACTION", display) }
end

function evaluators.event(req)
    local active = IsEventActive(req.name)
    if active == nil then
        return { status = REQ.INFO, text = L("REQ_EVENT_UNKNOWN", req.name) }
    end
    return { status = active and REQ.MET or REQ.UNMET, text = L("REQ_EVENT", req.name), label = req.name }
end

-- A cost or requirement the journal lists but we cannot check (e.g. an item
-- token, or a reputation we could not match to a faction).
function evaluators.unverified(req)
    local label = L("FARM_UNVERIFIED")
    if req.texture then
        label = "|T" .. req.texture .. ":16:16|t " .. L("FARM_UNKNOWN_COST")
    end
    return { status = REQ.UNKNOWN, text = req.text or "", label = label }
end

function evaluators.note(req)
    return { status = REQ.INFO, text = req.text or "" }
end

function addon.EvaluateRequirement(req)
    local evaluator = evaluators[req.type]
    if not evaluator then
        return { status = REQ.INFO, text = tostring(req.text or req.type) }
    end
    local ok, result = pcall(evaluator, req)
    if not ok then
        return { status = REQ.INFO, text = tostring(req.type) .. ": " .. tostring(result) }
    end
    return result
end

------------------------------------------------------------------------------
-- Requirement inference from the mount journal
------------------------------------------------------------------------------

-- Currency lookup by icon file ID. Journal costs only show the currency's icon
-- ("2000|Tinterface\icons\...:0|t"), so we match the icon back to a currency.
local currencyByIcon

local function FindCurrencyByIcon(fileID)
    if not fileID then
        return nil
    end
    if not currencyByIcon then
        currencyByIcon = {}
        local discovered = {}
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            for currencyID = 1, 6000 do
                local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
                if info and info.name and info.name ~= "" and info.iconFileID then
                    local icon = info.iconFileID
                    local isDiscovered = info.discovered or (info.quantity or 0) > 0
                    -- Several currencies can share an icon; prefer one this account has seen.
                    if not currencyByIcon[icon] or (isDiscovered and not discovered[icon]) then
                        currencyByIcon[icon] = currencyID
                        discovered[icon] = isDiscovered
                    end
                end
            end
        end
    end
    return currencyByIcon[fileID]
end

local probeTexture

local function TextureToFileID(texture)
    local numeric = tonumber(texture)
    if numeric then
        return numeric
    end
    if GetFileIDFromPath then
        local fileID = GetFileIDFromPath(texture)
        if fileID and fileID > 0 then
            return fileID
        end
    end
    -- Fallback: let the client resolve the path by loading it into a hidden texture.
    if not probeTexture then
        probeTexture = UIParent:CreateTexture(nil, "BACKGROUND")
        probeTexture:Hide()
    end
    probeTexture:SetTexture(nil)
    probeTexture:SetTexture(texture)
    local fileID = probeTexture.GetTextureFileID and probeTexture:GetTextureFileID()
    if fileID and fileID > 0 then
        return fileID
    end
    return nil
end

-- Splits a journal "Cost:" value into { amount, kind, value, texture } tokens.
-- Costs come in several shapes:
--   5000|Hcurrency:1979|h|T...|t|h   currency link (carries the currency ID)
--   2|Hitem:12345:...|h[Name]|h      item link (carries the item ID)
--   500|Tinterface\icons\x:0|t       bare icon (matched to a currency by icon)
--   100|A:atlas-name:0:0|a           atlas icon
-- Escape sequences are collapsed into placeholders first so digits inside
-- them (IDs, texture sizes) are never mistaken for amounts.
local function TokenizeCosts(costText)
    local tokens = {}
    if type(costText) ~= "string" or costText == "" then
        return tokens
    end

    local work = costText:gsub("|H(%a+):(%d+)[^|]*|h(.-)|h", function(kind, id, inner)
        local texture = inner:match("|T([^:|]+)") or ""
        -- The amount can also sit inside the link text ("|h5000|T...|t|h").
        local innerAmount = inner:gsub("|T.-|t", ""):match("^%s*(%d[%d,%.]*)") or ""
        return innerAmount .. "\001" .. kind .. "\003" .. id .. "\003" .. texture .. "\002"
    end)
    work = work:gsub("|T([^:|]+)[^|]*|t", function(texture)
        return "\001tex\003" .. texture .. "\003" .. texture .. "\002"
    end)
    work = work:gsub("|A:?([^:|]+)[^|]*|a", function(atlas)
        return "\001atlas\003" .. atlas .. "\003\002"
    end)

    for amountText, kind, value, texture in work:gmatch("(%d[%d,%.]*)%s*\001(%a+)\003([^\003]*)\003([^\002]*)\002") do
        local amount = tonumber((amountText:gsub("[^%d]", "")))
        if amount and amount > 0 then
            tokens[#tokens + 1] = {
                amount = amount,
                kind = kind,
                value = value,
                texture = texture ~= "" and texture or nil,
            }
        end
    end

    return tokens
end

local function IconMarkup(token)
    if token.texture then
        return "|T" .. token.texture .. ":16:16|t"
    elseif token.kind == "atlas" then
        return "|A:" .. token.value .. ":16:16|a"
    end
    return ""
end

-- Prints how each cost on a mount was resolved (/mmf cost).
function addon.DebugCosts(mount)
    local costText = mount.sourceRawFields and mount.sourceRawFields["Cost"]
    addon.Print(mount.name .. " cost: " .. tostring(costText))
    if not costText then
        return
    end
    print("  raw: " .. costText:gsub("|", "||"))
    for _, token in ipairs(TokenizeCosts(costText)) do
        local resolved = "none"
        if token.kind == "currency" then
            resolved = "currency link " .. token.value
        elseif token.kind == "item" then
            resolved = "item link " .. token.value
        elseif token.kind == "tex" then
            local fileID = TextureToFileID(token.value)
            local currencyID = FindCurrencyByIcon(fileID)
            local info = currencyID and C_CurrencyInfo.GetCurrencyInfo(currencyID)
            resolved = string.format("icon fileID=%s currency=%s", tostring(fileID),
                currencyID and (currencyID .. " " .. (info and info.name or "?")) or "none")
        end
        print(string.format("  %d  %s=%s  -> %s", token.amount, token.kind, token.value, resolved))
    end
end

-- Turns a journal "Cost:" value into gold / currency / item / unverified requirements.
local function ParseCosts(costText, list)
    if type(costText) ~= "string" or costText == "" then
        return
    end

    local copper = 0
    local tokens = TokenizeCosts(costText)
    for _, token in ipairs(tokens) do
        local amount = token.amount
        local lowerValue = string.lower(token.value)
        if token.kind == "currency" then
            list[#list + 1] = { type = "currency", id = tonumber(token.value), amount = amount, inferred = true }
        elseif token.kind == "item" then
            list[#list + 1] = { type = "item", id = tonumber(token.value), count = amount, inferred = true }
        elseif token.kind == "tex" and string.find(lowerValue, "goldicon", 1, true) then
            copper = copper + amount * 10000
        elseif token.kind == "tex" and string.find(lowerValue, "silvericon", 1, true) then
            copper = copper + amount * 100
        elseif token.kind == "tex" and string.find(lowerValue, "coppericon", 1, true) then
            copper = copper + amount
        else
            local currencyID = token.kind == "tex" and FindCurrencyByIcon(TextureToFileID(token.value))
            if currencyID then
                list[#list + 1] = { type = "currency", id = currencyID, amount = amount, inferred = true }
            else
                list[#list + 1] = {
                    type = "unverified",
                    text = L("REQ_UNVERIFIED_COST", FormatNumber(amount) .. " " .. IconMarkup(token)),
                    texture = token.texture,
                    amount = amount,
                    inferred = true,
                }
            end
        end
    end

    if copper > 0 then
        list[#list + 1] = { type = "gold", amount = copper, inferred = true }
    end

    -- A cost we could not tokenize at all still means "you need something".
    if #tokens == 0 then
        local plain = costText:gsub("|T.-|t", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if plain ~= "" or costText ~= "" then
            list[#list + 1] = { type = "unverified", text = L("REQ_UNVERIFIED_COST", costText), inferred = true }
        end
    end
end

-- Words in the journal text that mean a reputation gate exists.
local function MentionsReputation(mount)
    local text = string.lower(mount.sourceText or "")
    if string.find(text, "renown", 1, true) then
        return true
    end
    for standing = 5, 8 do
        local label = _G["FACTION_STANDING_LABEL" .. standing]
        if label and string.find(text, string.lower(label), 1, true) then
            return true
        end
    end
    return false
end

local realProfessionNames

local function IsRealProfession(name)
    if not realProfessionNames then
        realProfessionNames = {}
        for skillLine, englishName in pairs(PROFESSION_NAMES) do
            realProfessionNames[string.lower(englishName)] = true
            if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
                local localized = C_TradeSkillUI.GetTradeSkillDisplayName(skillLine)
                if localized then
                    realProfessionNames[string.lower(localized)] = true
                end
            end
        end
    end
    return realProfessionNames[string.lower(name or "")] == true
end

-- "Khaz Algar Engineering" -> "Engineering" (the base profession it belongs to).
local function GetTierBaseProfession(name)
    if type(name) ~= "string" then
        return nil
    end
    for _, baseName in pairs(PROFESSION_NAMES) do
        if #name > #baseName and string.sub(name, -#baseName - 1) == " " .. baseName then
            return baseName
        end
    end
    return nil
end

local function HasRequirementType(list, reqType)
    for _, req in ipairs(list) do
        if req.type == reqType then
            return true
        end
    end
    return false
end

-- Builds the full requirement list for a mount: faction restriction, curated
-- requirements, then anything we can infer from the journal source text.
function addon.BuildRequirements(mount)
    local list = {}
    local playerFaction = PlayerFaction()

    if mount.isFactionSpecific and mount.faction ~= nil then
        list[#list + 1] = { type = "faction", faction = (mount.faction == 1) and "Alliance" or "Horde", inferred = true }
    end

    local curated = mount.curated
    if curated and curated.requirements then
        for _, req in ipairs(curated.requirements) do
            if not req.onlyFaction or req.onlyFaction == playerFaction then
                list[#list + 1] = req
            end
        end
    end

    local fields = mount.sourceFields or {}

    -- AllTheThings data (when loaded): quest chain, reputation gate, exact costs.
    local att = addon.ATT and addon.ATT.GetMountData(mount.spellID)
    mount.attData = att
    local attCosts = false
    if att then
        if att.questRoots then
            list[#list + 1] = { type = "questline", quests = att.questRoots, keyQuest = att.finalQuest, inferred = true }
        end
        if att.reputation and not HasRequirementType(list, "reputation") then
            list[#list + 1] = att.reputation
        end
        if #att.costs > 0 and not HasRequirementType(list, "gold") and not HasRequirementType(list, "currency") then
            for _, req in ipairs(att.costs) do
                list[#list + 1] = req
            end
            attCosts = true
        end
    end

    if not HasRequirementType(list, "achievement") and fields["Achievement"] then
        local achievementID = addon.FindAchievementByName(fields["Achievement"])
        if achievementID then
            list[#list + 1] = { type = "achievement", id = achievementID, inferred = true }
        end
    end

    if not HasRequirementType(list, "reputation") and not HasRequirementType(list, "renown")
        and not HasRequirementType(list, "friendshipPoints") then
        local factionName = fields["Faction"] or fields["Reputation Faction"]
        local standingText = fields["Reputation"] or fields["Standing"]
        if factionName and not standingText then
            local namePart, standingPart = factionName:match("^(.-)%s*%-%s*(.+)$")
            if namePart then
                factionName, standingText = namePart, standingPart
            end
        end
        local factionID = addon.FindFactionByName(factionName)
        if factionID then
            local renownLevel = fields["Renown"] and tonumber(fields["Renown"]:match("(%d+)"))
            local standing = FindStandingByLabel(standingText)
            if renownLevel then
                list[#list + 1] = { type = "renown", factionID = factionID, level = renownLevel, inferred = true }
            elseif standing then
                list[#list + 1] = { type = "reputation", factionID = factionID, standing = standing, inferred = true }
            end
        end
    end

    local hasRepCheck = HasRequirementType(list, "reputation") or HasRequirementType(list, "renown")
        or HasRequirementType(list, "friendship") or HasRequirementType(list, "friendshipPoints")
    if not hasRepCheck and MentionsReputation(mount) then
        local hint = fields["Faction"] or fields["Reputation"] or fields["Renown"] or ""
        list[#list + 1] = { type = "unverified", text = L("REQ_UNVERIFIED_REP", hint), inferred = true }
    end

    if not attCosts and not HasRequirementType(list, "gold") and not HasRequirementType(list, "currency") then
        ParseCosts(mount.sourceRawFields and mount.sourceRawFields["Cost"], list)
    end

    if not HasRequirementType(list, "profession") and fields["Profession"] then
        local profName = fields["Profession"]:gsub("%s*%(.-%)%s*$", "")
        local tierBase = GetTierBaseProfession(profName)
        if IsRealProfession(profName) then
            list[#list + 1] = { type = "profession", name = profName, inferred = true }
        elseif tierBase then
            list[#list + 1] = { type = "professionTier", name = profName, base = tierBase, inferred = true }
        else
            -- e.g. Protoform Synthesis: unlocked by a questline, not learnable as a profession.
            list[#list + 1] = { type = "unverified", text = L("REQ_UNVERIFIED_PROFESSION", profName), inferred = true }
        end
    end

    if not HasRequirementType(list, "event") and fields["World Event"] then
        list[#list + 1] = { type = "event", name = fields["World Event"], inferred = true }
    end

    return list
end

-- Verifies curated data against the live client. Returns the problem count.
function addon.VerifyCuratedData()
    local problems = 0
    local entries = 0
    addon.Print(L("VERIFY_HEADER"))

    local names = {}
    for name in pairs(addon.curatedMounts or {}) do
        names[#names + 1] = name
    end
    table.sort(names)

    for _, name in ipairs(names) do
        entries = entries + 1
        local entry = addon.curatedMounts[name]
        if not addon.FindMountByName(name) then
            problems = problems + 1
            print(L("VERIFY_NO_MOUNT", name))
        end
        for _, req in ipairs(entry.requirements or {}) do
            if req.type == "achievement" and not GetAchievementInfo(req.id) then
                problems = problems + 1
                print(L("VERIFY_BAD_ACH", name, req.id))
            elseif (req.type == "reputation" or req.type == "friendship") and not GetFactionData(req.factionID) then
                problems = problems + 1
                print(L("VERIFY_BAD_FACTION", name, req.factionID))
            elseif req.type == "currency" then
                local info = C_CurrencyInfo.GetCurrencyInfo(req.id)
                if not (info and info.name and info.name ~= "") then
                    problems = problems + 1
                    print(L("VERIFY_BAD_CURRENCY", name, req.id))
                end
            end
        end
    end

    addon.Print(L("VERIFY_DONE", entries, problems))
    return problems
end
