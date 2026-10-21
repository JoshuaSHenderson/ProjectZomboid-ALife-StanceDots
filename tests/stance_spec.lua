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

print("stance_spec: ok")
