local _, addon = ...

--[[
Curated mount data, keyed by the mount's name as shown in the Mount Journal
(enUS). Everything here is optional: mounts without an entry are still listed,
and their requirements are inferred from the journal (faction, achievement
named in the source text, gold cost, profession, world event).

Entry fields:
    zone         = zone name (overrides the journal's "Zone:" line)
    unobtainable = true when the mount can no longer be earned
    requirements = list of requirement tables (see below)
    steps        = list of strings shown under "How To Get It"
    waypoint     = { mapID = uiMapID, x = 0-100, y = 0-100, title = "..." }

Requirement types (all accept an optional onlyFaction = "Alliance"|"Horde"):
    { type = "achievement", id = achievementID }
    { type = "quest", id = questID, name = "Quest Name", account = true }
    { type = "reputation", factionID = id, standing = 1-8 }   -- 5 Friendly, 6 Honored, 7 Revered, 8 Exalted
    { type = "renown", factionID = id, level = n }
    { type = "friendship", factionID = id, rank = n }
    { type = "currency", id = currencyID, amount = n }
    { type = "item", id = itemID, count = n, name = "Item Name" }
    { type = "gold", amount = copper }
    { type = "level", level = n }
    { type = "profession", skillLine = id, skill = n }    -- skill is optional
    { type = "class", class = "PALADIN" }
    { type = "race", race = "Dracthyr" }
    { type = "event", name = "Brewfest" }
    { type = "note", text = "Free text shown as info" }

Run /mmf verify in game to check every entry against the live client. It
reports names that do not match a journal mount and IDs that do not resolve.
]]

local EXALTED = 8
local REVERED = 7

local function Rep(factionID, standing, onlyFaction)
    return { type = "reputation", factionID = factionID, standing = standing, onlyFaction = onlyFaction }
end

local function Ach(id)
    return { type = "achievement", id = id }
end

local curated = {}
addon.curatedMounts = curated

local function Add(names, entry)
    if type(names) == "string" then
        names = { names }
    end
    for _, name in ipairs(names) do
        curated[name] = entry
    end
end

-- The Burning Crusade -------------------------------------------------------

Add({
    "Azure Netherwing Drake", "Cobalt Netherwing Drake", "Onyx Netherwing Drake",
    "Purple Netherwing Drake", "Veridian Netherwing Drake", "Violet Netherwing Drake",
}, {
    zone = "Shadowmoon Valley",
    requirements = { Rep(1015, EXALTED) },
    steps = {
        "Start the Netherwing chain at Mordenai in Shadowmoon Valley (Outland).",
        "Do the Netherwing daily quests on the Netherwing Ledge until Exalted.",
        "Buy the drake from Drake Dealer Hurlunk in Dragonmaw Base Camp.",
    },
})

Add({
    "Blue Riding Nether Ray", "Green Riding Nether Ray", "Purple Riding Nether Ray",
    "Red Riding Nether Ray", "Silver Riding Nether Ray",
}, {
    zone = "Terokkar Forest",
    requirements = { Rep(1031, EXALTED) },
    steps = {
        "Earn Exalted with Sha'tari Skyguard (Skettis dailies in Terokkar Forest, or the Skyguard quests in Blade's Edge).",
        "Buy the ray from the Sha'tari Skyguard quartermaster at Blackwind Landing.",
    },
})

Add("Cenarion War Hippogryph", {
    zone = "Zangarmarsh",
    requirements = { Rep(942, EXALTED) },
    steps = {
        "Earn Exalted with Cenarion Expedition (Coilfang Reservoir dungeons and turn-ins at Cenarion Refuge).",
        "Buy from the Cenarion Expedition quartermaster at Cenarion Refuge, Zangarmarsh.",
    },
})

Add({
    "Cobalt Riding Talbuk", "Silver Riding Talbuk", "Tan Riding Talbuk", "White Riding Talbuk",
}, {
    zone = "Nagrand",
    requirements = {
        Rep(978, EXALTED, "Alliance"),
        Rep(941, EXALTED, "Horde"),
    },
    steps = {
        "Earn Exalted with Kurenai (Alliance) or The Mag'har (Horde) in Nagrand, Outland.",
        "Buy from the quartermaster in Telaar (Alliance) or Garadar (Horde).",
    },
})

-- Wrath of the Lich King ----------------------------------------------------

Add("Ice Mammoth", {
    zone = "The Storm Peaks",
    requirements = { Rep(1119, REVERED) },
    steps = {
        "Complete the Storm Peaks quest line to unlock The Sons of Hodir in Dun Niffelem.",
        "Do the Sons of Hodir dailies until Revered, then buy from the quartermaster.",
    },
})

Add("Grand Ice Mammoth", {
    zone = "The Storm Peaks",
    requirements = { Rep(1119, EXALTED) },
    steps = {
        "Complete the Storm Peaks quest line to unlock The Sons of Hodir in Dun Niffelem.",
        "Do the Sons of Hodir dailies until Exalted, then buy from the quartermaster.",
    },
})

Add("Red Drake", {
    zone = "Dragonblight",
    requirements = { Rep(1091, EXALTED) },
    steps = {
        "Earn Exalted with the Wyrmrest Accord (Dragonblight quests and dailies).",
        "Buy from the Wyrmrest Accord quartermaster at Wyrmrest Temple.",
    },
})

Add("Red Proto-Drake", {
    requirements = { Ach(2136) },
    steps = {
        "Complete Glory of the Hero: the heroic Wrath dungeon achievements.",
        "Most of them can be soloed at max level. Track the achievement to see what's left.",
    },
})

Add("Violet Proto-Drake", {
    requirements = { Ach(2144) },
    steps = {
        "Complete What a Long, Strange Trip It's Been: every world-event meta achievement.",
        "This takes a full calendar year of holidays. Check the calendar for the next event.",
    },
})

-- Cataclysm -----------------------------------------------------------------

Add("Spectral Steed", {
    zone = "Tol Barad Peninsula",
    requirements = { Rep(1177, EXALTED) },
    steps = {
        "Earn Exalted with Baradin's Wardens (Tol Barad Peninsula dailies).",
        "Buy from the Baradin's Wardens quartermaster with Tol Barad Commendations.",
    },
})

Add("Spectral Wolf", {
    zone = "Tol Barad Peninsula",
    requirements = { Rep(1178, EXALTED) },
    steps = {
        "Earn Exalted with Hellscream's Reach (Tol Barad Peninsula dailies).",
        "Buy from the Hellscream's Reach quartermaster with Tol Barad Commendations.",
    },
})

-- Mists of Pandaria ---------------------------------------------------------

Add({ "Jade Cloud Serpent", "Azure Cloud Serpent", "Golden Cloud Serpent" }, {
    zone = "The Jade Forest",
    requirements = { Rep(1271, EXALTED) },
    steps = {
        "Unlock the Order of the Cloud Serpent at the Arboretum in The Jade Forest.",
        "Do the hatchling dailies until Exalted (Grand Commendation on a max-level alt doubles gains).",
        "Then get the serpent from the Order of the Cloud Serpent at the Arboretum.",
    },
})

Add({ "Green Shado-Pan Riding Tiger", "Blue Shado-Pan Riding Tiger", "Red Shado-Pan Riding Tiger" }, {
    zone = "Townlong Steppes",
    requirements = { Rep(1270, EXALTED) },
    steps = {
        "Earn Exalted with the Shado-Pan (Shado-Pan Monastery dailies, Kun-Lai Summit).",
        "Buy from the Shado-Pan quartermaster at Shado-Pan Monastery.",
    },
})

Add({ "Black Riding Goat", "Brown Riding Goat", "White Riding Goat" }, {
    zone = "Valley of the Four Winds",
    requirements = { Rep(1272, EXALTED) },
    steps = {
        "Earn Exalted with The Tillers (Sunsong Ranch farming dailies, Valley of the Four Winds).",
        "Buy from Gina Mudclaw at the Halfhill Market.",
    },
})

-- Unobtainable ----------------------------------------------------------------

local UNOBTAINABLE = {
    "Black Qiraji Battle Tank",
    "Swift Zulian Tiger",
    "Swift Razzashi Raptor",
    "Amani War Bear",
    "Amani Battle Bear",
    "Black Proto-Drake",
    "Plagued Proto-Drake",
    "Rusted Proto-Drake",
    "Ironbound Proto-Drake",
    "Bloodbathed Frostbrood Vanquisher",
    "Icebound Frostbrood Vanquisher",
    "Swift Nether Drake",
    "Merciless Nether Drake",
    "Vengeful Nether Drake",
    "Brutal Nether Drake",
}

for _, name in ipairs(UNOBTAINABLE) do
    curated[name] = curated[name] or {}
    curated[name].unobtainable = true
end

-- Name patterns treated as unobtainable (past PvP season rewards). The current
-- season's mount will match too; add a curated entry with unobtainable = false
-- to keep it visible.
addon.unobtainablePatterns = {
    "Gladiator's ",
}
