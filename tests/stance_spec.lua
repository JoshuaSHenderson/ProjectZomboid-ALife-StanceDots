-- Self-check for the status resolution in ALifeStanceDots.lua.
-- Run with any Lua 5.x:
--   lua tests/stance_spec.lua
-- MODFILE may be preset by the harness; otherwise the default path is used.

MODFILE = MODFILE or
    "ALifeStanceDots/Contents/mods/ALifeStanceDots/42/media/lua/client/ALifeStanceDots/ALifeStanceDots.lua"

Events = {}
isClient = function() return false end

local player = { getPlayerNum = function() return 0 end }
function player:getUsername() return nil end
setmetatable(player, { __index = function() return function() return nil end end })

local Dots = dofile(MODFILE)

local friendlyFaction = { spawn = { peaceable = true } }
local raiders = { spawn = { peaceable = false } }
local militia = { spawn = { peaceable = true }, relations = { player = "suspicious" } }
local guard = { relations = { player = "allied" } }

local function reset()
    ProjectALife = { Catalog = { faction = function(id)
        return ({ ranger = friendlyFaction, raiders = raiders, militia = militia, guard = guard })[id]
    end } }
    ProjectALifeJimmy = nil
    Dots.cache = {}
end
reset()

local function status(record) return Dots.statusOf(record, player) end

-- faction default carries the stance (MP fallback, no Relations loaded)
assert(status({ factionId = "ranger" }) == "friendly")
assert(status({ factionId = "raiders" }) == "hostile")
assert(status({ factionId = "militia" }) == "careful")
assert(status({ factionId = "guard" }) == "allied")

-- authored spawn stance beats the faction default
assert(status({ factionId = "raiders", memory = { spawnStance = "neutral" } }) == "neutral")

-- per-actor overrides
assert(status({ factionId = "ranger", memory = { hostileOverride = true } }) == "hostile")
assert(status({ factionId = "raiders", memory = { hostileOverride = false } }) == "friendly")
assert(status({ factionId = "ranger", memory = { hostileToPlayerKeys = { ["sp:0"] = true } } }) == "hostile")

-- earned reputation: hostile beats even a forced friend, others shift the stance
ProjectALife.StatusStore = { reputation = { relations = {
    { factionId = "ranger", status = "hostile", cause = "attack" },
    { factionId = "raiders", status = "neutral" },
} } }
assert(status({ factionId = "ranger" }) == "hostile")
assert(status({ factionId = "ranger", memory = { hostileOverride = false } }) == "hostile")
assert(status({ factionId = "raiders" }) == "neutral")
ProjectALife.StatusStore = nil

-- careful/neutral NPCs that are fighting you or hunting you go red
assert(status({ factionId = "militia", activity = "combat",
    memory = { combatTargetKind = "player", combatTargetPlayerKey = "sp:0" } }) == "hostile")
assert(status({ factionId = "militia", activity = "combat",
    memory = { combatTargetKind = "player", combatTargetPlayerKey = "bob" } }) == "careful")
assert(status({ factionId = "ranger", memory = { targetUsername = "sp:0" } }) == "hostile")

-- companions: walking with you (until it runs out), Jeem ally following you
assert(status({ factionId = "ranger", memory = { walkWith = { key = "sp:0", untilHours = 1e9 } } }) == "companion")
assert(status({ factionId = "ranger", memory = { walkWith = { key = "bob", untilHours = 1e9 } } }) == "friendly")
assert(status({ factionId = "ranger", memory = { admin = { jimmy = { jimmyOrder = { ally = true, player = "sp:0" } } } } })
    == "companion")
-- a companion who turns on you is hostile
assert(status({ factionId = "ranger", memory = { hostileOverride = true,
    walkWith = { key = "sp:0", untilHours = 1e9 } } }) == "hostile")

-- A-Life's own Relations wins when loaded (singleplayer), incl. fairness' "careful"
ProjectALife.Relations = {
    playerStance = function() return "careful" end,
    hostileToPlayer = function() return false end,
}
assert(status({ factionId = "raiders" }) == "careful")
ProjectALife.Relations.hostileToPlayer = function() return true end
assert(status({ factionId = "raiders" }) == "hostile")
ProjectALife.Relations = { playerStance = function() return "friendly" end }
ProjectALife.Party = { friendly = function(record) return record.uid == "pal" end }
assert(status({ uid = "pal", factionId = "ranger" }) == "companion")
assert(status({ uid = "other", factionId = "ranger" }) == "friendly")
reset()

-- Jeem: residents of your base, allies, and attackers from friendly factions
ProjectALifeJimmy = { NpcSafety = {
    yourResident = function(record) return record.uid == "home" end,
    yourAlly = function(record) return record.uid == "crew" end,
    attacking = function(record) return record.uid == "raid" end,
} }
assert(status({ uid = "home", factionId = "ranger" }) == "resident")
assert(status({ uid = "crew", factionId = "ranger" }) == "allied")
assert(status({ uid = "raid", factionId = "ranger" }) == "hostile")
reset()

-- unknown faction with no record data is neutral, as in Relations.basePlayerStance
assert(status({ factionId = "ghosts" }) == "neutral")
assert(status(nil) == nil)

-- every status has an icon and a dot
for name in pairs(Dots.STATUSES) do
    for _, file in ipairs({ name, "dot_" .. name }) do
        local path = MODFILE:gsub("lua/client/ALifeStanceDots/ALifeStanceDots%.lua$", "ui/ALifeStanceDots/" .. file .. ".png")
        assert(io.open(path, "rb"), "missing texture " .. path):close()
    end
end

-- sandbox options override the built-in settings
SandboxVars = nil
local icons, height = Dots.options()
assert(icons == true and height == 1.15)
SandboxVars = { ALifeStanceDots = { Style = 1, HeadHeight = 2.0 } }
icons, height = Dots.options()
assert(icons == false and height == 2.0)
SandboxVars = nil

-- Viewpoint add-on: 3D projection only while Viewpoint's 3D view is on
local VPFILE = MODFILE:gsub("mods/ALifeStanceDots/42/media/lua/client/ALifeStanceDots/ALifeStanceDots%.lua$",
    "mods/ALifeStanceDotsViewpoint/42/media/lua/client/ALifeStanceDotsViewpoint.lua")
local isometric = function() return 1, 2 end
Dots.project = isometric
package.loaded["ALifeStanceDots/ALifeStanceDots"] = Dots
dofile(VPFILE)
local nextView, front = "first", true
Viewpoint = { View = { next = function() return nextView end } }
ALifeStanceDotsViewpoint = {
    pixel = function() return front end,
    pixelX = function() return 30 end,
    pixelY = function() return 40 end,
}
local sx, sy = Dots.project(0, 0, 0, 1)
assert(sx == 1 and sy == 2)                 -- isometric view
nextView = "third"                          -- first person on
sx, sy = Dots.project(0, 0, 0, 1)
assert(sx == 30 and sy == 40)
front = false                               -- behind the camera
assert(Dots.project(0, 0, 0, 1) == nil)
ALifeStanceDotsViewpoint = nil              -- 3D without the bridge: hide, never iso maths
front = true
assert(Dots.project(0, 0, 0, 1) == nil)
Viewpoint = nil

-- map markers: range, line of sight, status filter, residents at any distance
local MAPFILE = MODFILE:gsub("ALifeStanceDots%.lua$", "ALifeStanceDotsMap.lua")
local function shellAt(uid, x, y, seen)
    return { isDead = function() return false end, getX = function() return x end, getY = function() return y end,
        getModData = function() return { ProjectALifeUID = uid } end,
        getSquare = function() return { isCanSee = function() return seen end } end }
end
local loaded = { shellAt("near", 10, 0, true), shellAt("hidden", 5, 0, false) }
getCell = function() return { getZombieList = function()
    return { size = function() return #loaded end, get = function(_, i) return loaded[i + 1] end } end } end
reset()
local records = {
    { uid = "near", factionId = "raiders" },
    { uid = "hidden", factionId = "ranger" },
    { uid = "far", factionId = "ranger", worldPosition = { x = 500, y = 0 } },
    { uid = "home", factionId = "ranger", worldPosition = { x = 900, y = 0 }, memory = { jimmyResident = {} } },
    { uid = "gone", factionId = "ranger", lifecycle = "dead", worldPosition = { x = 1, y = 0 } },
}
ProjectALife.ActorRegistry = { each = function(visit) for _, r in ipairs(records) do visit(r) end end }
ProjectALifeJimmy = { NpcSafety = { yourResident = function(record) return record.memory ~= nil end } }
local me = { getX = function() return 0 end, getY = function() return 0 end }
setmetatable(me, getmetatable(player))
local Map = dofile(MAPFILE)
local clock = 0
local function shown(settings)
    local out = {}
    clock = clock + 1000
    local shells = {}
    for _, shell in ipairs(loaded) do shells[shell.getModData().ProjectALifeUID] = shell end
    Map.spot(shells, clock)
    for _, row in ipairs(Map.collect(me, settings, clock, shells)) do out[#out + 1] = row.status .. "@" .. row.x end
    table.sort(out)
    return table.concat(out, " ")
end
local function with(changes)
    local s = {}
    for k, v in pairs(Map.settings) do s[k] = v end
    s.show = {}
    for k, v in pairs(Map.settings.show) do s.show[k] = v end
    for k, v in pairs(changes) do s[k] = v end
    return s
end
assert(shown(with({})) == "friendly@5 hostile@10 resident@900")
assert(shown(with({ lineOfSight = true })) == "hostile@10 resident@900")
-- out of sight: stays where last seen until the memory runs out
loaded[1] = shellAt("near", 20, 0, false)
assert(shown(with({ lineOfSight = true, memory = 5 })) == "hostile@10 resident@900")
clock = clock + 5000
assert(shown(with({ lineOfSight = true, memory = 5 })) == "resident@900")
loaded[1] = shellAt("near", 10, 0, true)
assert(shown(with({ residentsAnywhere = false })) == "friendly@5 hostile@10")
assert(shown(with({ show = { hostile = true } })) == "hostile@10")
assert(shown(with({ range = 1000 })) == "friendly@5 friendly@500 hostile@10 resident@900")
assert(shown(with({ enabled = false })) == "")
-- a resident the MP mirror dropped stays at the last known spot
local function track() Map.track(me, clock, {}) end
track()
local home = table.remove(records, 4)
track()
assert(shown(with({})) == "friendly@5 hostile@10 resident@900")
assert(shown(with({ residentsAnywhere = false })) == "friendly@5 hostile@10")
-- ...and a grey X where they die, for deathMinutes
home.lifecycle = "dead"
home.worldPosition = { x = 950, y = 0 }
records[#records + 1] = home
track()
assert(shown(with({})) == "dead@950 friendly@5 hostile@10")
assert(shown(with({ deathMinutes = 0 })) == "friendly@5 hostile@10")
clock = clock + 6 * 60 * 1000
assert(shown(with({})) == "friendly@5 hostile@10")
table.remove(records)
records[#records + 1] = { uid = "home", factionId = "ranger", worldPosition = { x = 900, y = 0 },
    memory = { jimmyResident = {} } }
Map.deaths = {}
-- server sandbox options cap the player's picks
SandboxVars = { ALifeStanceDots = { MapMaxRange = 10, MapForceLineOfSight = true, MapResidentsAnywhere = false } }
local capped = Map.limit(with({ range = 1000 }))
assert(capped.range == 10 and capped.lineOfSight and not capped.residentsAnywhere and capped.enabled)
SandboxVars.ALifeStanceDots = { MapEnabled = false }
assert(Map.limit(with({})).enabled == false)
assert(Map.read().range == 100)
-- statuses: the player's ticks in singleplayer, the server's in multiplayer
SandboxVars.ALifeStanceDots = { MapShowHostile = false }
assert(Map.limit(with({})).show.hostile == true)
isClient = function() return true end
local served = Map.limit(with({ show = {} }))
assert(served.show.hostile == false and served.show.friendly == true and served.show.resident == true)
isClient = function() return false end
SandboxVars = nil
reset()

print("stance_spec: ok")
