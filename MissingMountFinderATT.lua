local _, addon = ...

-- Optional AllTheThings integration. When ATT is loaded we read its database
-- for each mount: prerequisite quest chains, vendor/drop NPC locations, exact
-- costs (currency and item IDs), reputation gates and removed-from-game flags.
-- Everything is wrapped in pcall; if ATT changes its internals we just get
-- nothing back and fall through to the Mount Journal data.

local ATT = {}
addon.ATT = ATT

local MAX_CHAIN_QUESTS = 40
local UNOBTAINABLE_PHASES = {
    [1] = true, -- Never Implemented
    [2] = true, -- Removed From Game
}
-- Standard reputation thresholds (total points earned) -> standing 1..8.
local STANDING_THRESHOLDS = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000 }

local mountCache = {}

local function GetApp()
    local app = _G.ATTC or _G.AllTheThings
    if type(app) == "table" and type(app.SearchForField) == "function" then
        return app
    end
    return nil
end

function ATT.IsAvailable()
    return GetApp() ~= nil
end

function ATT.ResetCache()
    mountCache = {}
end

local function Search(field, id)
    local app = GetApp()
    if not app or not id then
        return nil
    end
    local ok, results = pcall(app.SearchForField, field, id)
    if ok and type(results) == "table" and #results > 0 then
        return results
    end
    return nil
end

local function Get(group, field)
    local ok, value = pcall(function()
        return group[field]
    end)
    if ok then
        return value
    end
    return nil
end

local function IsUnobtainableGroup(group)
    local node, depth = group, 0
    while node and depth < 6 do
        local u = Get(node, "u")
        if u and UNOBTAINABLE_PHASES[u] then
            return true
        end
        node = Get(node, "parent")
        depth = depth + 1
    end
    return false
end

-- ATT faction restriction: r = 1 Horde, 2 Alliance.
local function IsForPlayer(group)
    local r = Get(group, "r")
    if r then
        local faction = UnitFactionGroup("player")
        if (r == 1 and faction ~= "Horde") or (r == 2 and faction ~= "Alliance") then
            return false
        end
    end
    local classes = Get(group, "c")
    if type(classes) == "table" then
        local _, _, classID = UnitClass("player")
        local match = false
        for _, id in ipairs(classes) do
            if id == classID then
                match = true
            end
        end
        if not match then
            return false
        end
    end
    return true
end

-- First coordinate on the group or its ancestors -> mapID, x, y (0-100).
local function FindCoords(group)
    local node, depth = group, 0
    while node and depth < 6 do
        local coords = Get(node, "coords")
        if type(coords) == "table" then
            local first = coords[1]
            if type(first) == "table" and type(first[1]) == "number" then
                -- Flat format: { { x, y, mapID }, ... }
                return first[3], first[1], first[2]
            end
            for mapID, points in pairs(coords) do
                if type(mapID) == "number" and type(points) == "table" and type(points[1]) == "table" then
                    return mapID, points[1][1], points[1][2]
                end
            end
        end
        node = Get(node, "parent")
        depth = depth + 1
    end
    return nil
end

local function FindAncestor(group, key, maxDepth)
    local node, depth = Get(group, "parent"), 0
    while node and depth < (maxDepth or 6) do
        if Get(node, "key") == key then
            return node
        end
        node = Get(node, "parent")
        depth = depth + 1
    end
    return nil
end

local function GetQuestGroup(questID)
    local results = Search("questID", questID)
    if not results then
        return nil
    end
    for _, group in ipairs(results) do
        if Get(group, "sourceQuests") then
            return group
        end
    end
    return results[1]
end

function ATT.GetQuestTitle(questID)
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    if title and title ~= "" then
        return title
    end
    if C_QuestLog.RequestLoadQuestByID then
        C_QuestLog.RequestLoadQuestByID(questID)
    end
    local group = GetQuestGroup(questID)
    local name = group and Get(group, "name")
    if type(name) == "string" and name ~= "" and not string.find(name, "^Quest #") then
        return name
    end
    return "Quest #" .. questID
end

local function IsQuestDone(questID)
    return C_QuestLog.IsQuestFlaggedCompleted(questID) == true
end

-- Builds the ordered prerequisite chain (earliest quest first) for a set of
-- required quests by following each quest's own sourceQuests in ATT.
local function BuildQuestChain(rootQuests)
    local chain, visited = {}, {}

    local function Visit(questID, depth)
        if #chain >= MAX_CHAIN_QUESTS or visited[questID] or depth > 30 then
            return
        end
        visited[questID] = true
        local group = GetQuestGroup(questID)
        if group and not IsForPlayer(group) then
            return
        end
        -- Once a quest is done, its prerequisites are too; no need to list them.
        if not IsQuestDone(questID) and group then
            local prereqs = Get(group, "sourceQuests")
            if type(prereqs) == "table" then
                local numRequired = Get(group, "sourceQuestNumRequired")
                if numRequired and numRequired < #prereqs then
                    -- "Any one of": follow a completed option if there is one, else the first.
                    local pick = prereqs[1]
                    for _, id in ipairs(prereqs) do
                        if IsQuestDone(id) then
                            pick = id
                            break
                        end
                    end
                    Visit(pick, depth + 1)
                else
                    for _, id in ipairs(prereqs) do
                        Visit(id, depth + 1)
                    end
                end
            end
        end
        if group and Get(group, "isBreadcrumb") and not IsQuestDone(questID) then
            return
        end
        chain[#chain + 1] = questID
    end

    for _, questID in ipairs(rootQuests) do
        Visit(questID, 0)
    end
    return chain
end

function ATT.GetQuestLocation(questID)
    local group = GetQuestGroup(questID)
    if not group then
        return nil
    end
    local mapID, x, y = FindCoords(group)
    if not mapID then
        local providers = Get(group, "providers")
        if type(providers) == "table" then
            for _, provider in ipairs(providers) do
                if provider[1] == "n" then
                    local npc = Search("npcID", provider[2])
                    if npc then
                        mapID, x, y = FindCoords(npc[1])
                    end
                end
                if mapID then
                    break
                end
            end
        end
    end
    return mapID, x, y
end

local function StandingFromPoints(points)
    for standing = 8, 1, -1 do
        if points >= STANDING_THRESHOLDS[standing] then
            return standing
        end
    end
    return 1
end

local function ConvertMinReputation(minRep)
    if type(minRep) ~= "table" or not minRep[1] or not minRep[2] then
        return nil
    end
    local factionID, points = minRep[1], minRep[2]
    if C_MajorFactions and C_MajorFactions.GetMajorFactionData and C_MajorFactions.GetMajorFactionData(factionID) then
        return nil -- renown factions are handled from the journal text
    end
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local friendship = C_GossipInfo.GetFriendshipReputation(factionID)
        if friendship and friendship.friendshipFactionID and friendship.friendshipFactionID > 0 then
            return { type = "friendshipPoints", factionID = factionID, points = points, inferred = true }
        end
    end
    return { type = "reputation", factionID = factionID, standing = StandingFromPoints(points), inferred = true }
end

local function ConvertCosts(cost)
    local list = {}
    if type(cost) == "number" then
        list[#list + 1] = { type = "gold", amount = cost, inferred = true }
        return list
    end
    if type(cost) ~= "table" then
        return list
    end
    for _, entry in ipairs(cost) do
        local kind, id, amount = entry[1], entry[2], entry[3] or 1
        if kind == "c" and id then
            list[#list + 1] = { type = "currency", id = id, amount = amount, inferred = true }
        elseif kind == "i" and id then
            list[#list + 1] = { type = "item", id = id, count = amount, inferred = true }
        elseif kind == "g" and id then
            list[#list + 1] = { type = "gold", amount = id, inferred = true }
        end
    end
    return list
end

-- Picks the best ATT entry for a mount: obtainable ones first, then ones with
-- a cost or location.
local function ChooseMountGroup(results)
    local best, bestScore
    for _, group in ipairs(results) do
        local score = 0
        if not IsUnobtainableGroup(group) then
            score = score + 100
        end
        if IsForPlayer(group) then
            score = score + 50
        end
        if Get(group, "cost") or Get(Get(group, "parent") or {}, "cost") then
            score = score + 10
        end
        if FindCoords(group) then
            score = score + 5
        end
        if not bestScore or score > bestScore then
            best, bestScore = group, score
        end
    end
    return best
end

-- Returns a table describing what ATT knows about the mount, or nil.
function ATT.GetMountData(spellID)
    if not spellID or not GetApp() then
        return nil
    end
    if mountCache[spellID] ~= nil then
        return mountCache[spellID] or nil
    end

    local results = Search("mountID", spellID) or Search("spellID", spellID)
    if not results then
        mountCache[spellID] = false
        return nil
    end

    local group = ChooseMountGroup(results)
    local data = {
        unobtainable = IsUnobtainableGroup(group),
        requirements = {},
    }

    -- Cost: on the mount itself, or on the item that teaches it.
    local cost = Get(group, "cost")
    local parent = Get(group, "parent")
    if not cost and parent and Get(parent, "key") == "itemID" then
        cost = Get(parent, "cost")
    end
    data.costs = ConvertCosts(cost)

    -- Reputation gate on the mount, the teaching item, or the vendor.
    local node, depth = group, 0
    while node and depth < 3 and not data.reputation do
        data.reputation = ConvertMinReputation(Get(node, "minReputation"))
        node = Get(node, "parent")
        depth = depth + 1
    end

    -- Quest prerequisites: sourceQuests on the mount or its vendor, plus the
    -- quest itself when the mount is a quest reward.
    local roots = {}
    node, depth = group, 0
    while node and depth < 4 do
        local sourceQuests = Get(node, "sourceQuests")
        if type(sourceQuests) == "table" then
            for _, questID in ipairs(sourceQuests) do
                if type(questID) == "number" then
                    roots[#roots + 1] = questID
                end
            end
        end
        if Get(node, "key") == "questID" then
            roots[#roots + 1] = Get(node, "questID")
            break
        end
        node = Get(node, "parent")
        depth = depth + 1
    end
    if #roots > 0 then
        data.questRoots = roots
        data.finalQuest = roots[#roots]
    end

    -- Where to go: the vendor / drop NPC (or object) and its coordinates.
    local npc = FindAncestor(group, "npcID", 4)
    if npc then
        local name = Get(npc, "name")
        if type(name) == "string" and name ~= "" then
            data.npcName = name
        end
    end
    local mapID, x, y = FindCoords(group)
    if mapID then
        data.mapID, data.x, data.y = mapID, x, y
        local info = C_Map.GetMapInfo(mapID)
        data.mapName = info and info.name
    end

    mountCache[spellID] = data
    return data
end

-- Evaluated live (quests complete over time), so the chain is rebuilt each time.
function ATT.EvaluateQuestline(req)
    local chain = BuildQuestChain(req.quests)
    local lines = {}
    local done = 0
    local nextQuest
    for _, questID in ipairs(chain) do
        local complete = IsQuestDone(questID)
        if complete then
            done = done + 1
        elseif not nextQuest then
            nextQuest = questID
        end
        lines[#lines + 1] = { complete and addon.REQ.MET or addon.REQ.UNMET, ATT.GetQuestTitle(questID), questID }
    end
    return chain, lines, done, nextQuest
end
