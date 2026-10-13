local _, addon = ...

-- Lazily built index of uiMapID by lowercased map name (zones and instances),
-- used to open the world map on a mount's zone.
local mapIndex

local function BuildMapIndex()
    mapIndex = {}
    if not (C_Map and C_Map.GetMapInfo) then
        return
    end

    -- Zone (3) and dungeon (4) maps win over micro/orphan maps with the same name.
    local preferredTypes = { [3] = 1, [4] = 2, [6] = 3, [5] = 4 }
    local ranks = {}
    for mapID = 1, 2800 do
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name and info.name ~= "" then
            local key = string.lower(info.name)
            local rank = preferredTypes[info.mapType] or 9
            -- On ties prefer the higher (newer) map ID, e.g. revamped zones.
            if not mapIndex[key] or rank <= ranks[key] then
                mapIndex[key] = mapID
                ranks[key] = rank
            end
        end
    end
end

function addon.FindMapIDForZone(zoneName)
    if type(zoneName) ~= "string" or zoneName == "" then
        return nil
    end
    if not mapIndex then
        BuildMapIndex()
    end
    return mapIndex[string.lower(zoneName)]
end
