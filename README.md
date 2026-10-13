# MissingMountFinder

A World of Warcraft addon for completing your mount collection. It lists every mount you are missing, checks whether your character meets the requirements for each one, and tells you how to get it.

## Features

- **Eligible now:** shows which missing mounts you can go get right now. Every requirement is met, including having enough gold, currency and reputation.
- **What to Farm:** lists everything standing between you and your missing mounts (each currency, reputation, gold amount or achievement), sorted by how many mounts each one unlocks. It shows what you have, the next unlock, and the total for all of them.
- **Requirement checks:** each requirement is marked ✓ met, ✗ not met, or ◐ in progress
  - Achievements, with criteria-by-criteria progress
  - Reputation standing, renown level, friendship rank
  - Gold and currency costs (read from the journal's Cost line), items
  - Professions, class, race, faction, character level
  - World events (checked against the in-game calendar)
- **AllTheThings integration (optional):** if ATT is installed, MissingMountFinder reads ATT's database for each mount. It uses the prerequisite quest chain (with your progress and the next quest to pick up), the vendor or drop NPC's location (used by the Waypoint button), exact currency and item costs, reputation gates, and removed-from-game flags
- **Browse by** zone, how to get it (drop, vendor, achievement, etc.), status, or what to farm
- **How to get it:** step-by-step guidance per mount. It uses curated steps where available, otherwise steps built from the journal source
- **Goals:** right-click a mount to star it, then filter to "Goals only"
- **Actions:** open the zone map, set a waypoint (also TomTom), track the achievement, open in the Mount Journal, copy the Wowhead link
- Filters for collected, other faction/class, unobtainable and shop/promo mounts, plus search across name, zone and source

## Slash Commands

| Command | Description |
|---------|-------------|
| `/mmf` | Toggle the window (also `/missingmounts`) |
| `/mmf scan` | Rescan the mount journal |
| `/mmf stats` | Print collection stats |
| `/mmf verify` | Check the curated data against the live client |
| `/mmf minimap` | Show or hide the minimap button |
| `/mmf help` | List commands |

You can also open it from the minimap button (drag it to move it), the addon compartment, or the **Missing Mounts** button in the top-right of the Mount Journal's preview. That button opens on the selected mount.

## Statuses

| Status | Meaning |
|--------|---------|
| Eligible Now | Missing, and nothing checkable stands in your way |
| Unverified | Missing; the journal lists a cost or reputation the addon can't check (e.g. item tokens) |
| Requirements Not Met | Missing, and at least one requirement is unmet or in progress (not enough currency, gold, rep...) |
| Shop / Promotion | In-game shop, promotion, or TCG |
| Not For This Character | Restricted to another faction, class, race or covenant |
| Unobtainable | No longer available |
| Collected | Already learned |

## How Data Is Resolved

1. **Mount Journal (live):** name, collected state, faction restriction, source type and source text (`Drop:`, `Zone:`, `Vendor:`, `Cost:`, `Achievement:` ...)
2. **Inference:** achievement names in the source text are matched to achievement IDs; reputation, gold cost, profession and world event are parsed out
3. **Curated data** (`MissingMountFinderSources.lua`): requirements the journal does not expose (reputation gates, quest chains), step-by-step directions, and unobtainable flags

## Adding Curated Mounts

Edit `MissingMountFinderSources.lua`. The field reference is at the top of the file. Example:

```lua
Add("Red Drake", {
    zone = "Dragonblight",
    requirements = { Rep(1091, EXALTED) },
    steps = { "Earn Exalted with the Wyrmrest Accord.", "Buy from the quartermaster at Wyrmrest Temple." },
})
```

Then run `/reload` and `/mmf verify` to confirm the names and IDs resolve.

## Installation

1. Download or clone this repository.
2. Copy the `MissingMountFinder` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Launch (or reload) the game and enable the addon in the AddOns menu.

## Compatibility

Retail only (Midnight, 12.x). The Mount Journal APIs it depends on are retail APIs.

## Files

| File | Purpose |
|------|---------|
| `MissingMountFinder.lua` | Entry point: constants, theme, status enums, SavedVariables |
| `MissingMountFinderLocalization.lua` | Localized strings |
| `MissingMountFinderZones.lua` | Zone name → world map lookup (for Open Map) |
| `MissingMountFinderSources.lua` | Curated mount requirements, directions, unobtainable list |
| `MissingMountFinderATT.lua` | Optional AllTheThings lookup: quest chains, locations, costs, reputation |
| `MissingMountFinderRequirements.lua` | Requirement evaluation and inference from journal text |
| `MissingMountFinderData.lua` | Journal scanning, source parsing, status, filtering and grouping |
| `MissingMountFinderUI.lua` | Main window, lists, detail panel, Mount Journal button, minimap button |
| `MissingMountFinderInit.lua` | Events, slash commands, addon compartment |

## SavedVariables

`MissingMountFinderDB` (per account) stores the window position, filters, group selection and your goal list.

## Author

tglass1976

## Version

1.0.0
