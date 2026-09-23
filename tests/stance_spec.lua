-- Self-check for the stance resolution in ALifeStanceDots.lua.
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

local function factions(map)
    ProjectALife = ProjectALife or {}
    ProjectALife.Catalog = { faction = function(id) return map[id] end }
end

local friendlyFaction = { spawn = { friendly = true } }
local raiders = { spawn = { friendly = false } }
local militia = { spawn = { friendly = true }, relations = { player = "suspicious" } }

ProjectALife = {}
factions({ ranger = friendlyFaction, raiders = raiders, militia = militia })

-- faction default carries the stance
assert(Dots.stanceOf({ factionId = "ranger" }, player) == "friendly")
assert(Dots.stanceOf({ factionId = "raiders" }, player) == "hostile")
assert(Dots.stanceOf({ factionId = "militia" }, player) == "careful")

-- authored spawn stance beats the faction default
assert(Dots.stanceOf({ factionId = "raiders", memory = { spawnStance = "neutral" } }, player) == "neutral")

-- per-actor overrides beat everything
assert(Dots.stanceOf({ factionId = "ranger", memory = { hostileOverride = true } }, player) == "hostile")
assert(Dots.stanceOf({ factionId = "raiders", memory = { hostileOverride = false } }, player) == "friendly")
assert(Dots.stanceOf({ factionId = "ranger",
    memory = { hostileToPlayerKeys = { ["sp:0"] = true } } }, player) == "hostile")

-- earned reputation flips a friendly faction
ProjectALife.StatusStore = { reputation = { relations = {
    { factionId = "ranger", status = "hostile", cause = "attack" },
} } }
assert(Dots.stanceOf({ factionId = "ranger" }, player) == "hostile")
assert(Dots.stanceOf({ factionId = "raiders" }, player) == "hostile")
ProjectALife.StatusStore = nil

-- A-Life's own Relations module wins when it is loaded (singleplayer)
ProjectALife.Relations = { playerStance = function() return "neutral" end }
assert(Dots.stanceOf({ factionId = "raiders" }, player) == "neutral")
ProjectALife.Relations = nil

-- unknown faction with no record data is treated as hostile, never nil
assert(Dots.stanceOf({ factionId = "ghosts" }, player) == "hostile")
assert(Dots.stanceOf(nil, player) == nil)

print("stance_spec: ok")
