--[[
    A-Life Stance Dots - map markers
    Puts the same stance icons on the world map and the minimap, for the NPCs
    around you: within a set distance (optionally only the ones you can see),
    plus your base's residents wherever they are, and a grey X for a while
    where one of them died. Each player picks which statuses show in
    Options > Mods.
]]

require "ALifeStanceDots/ALifeStanceDots"
pcall(require, "PZAPI/ModOptions")

local Dots = ALifeStanceDots
local Map = { rows = {}, seen = {}, residents = {}, deaths = {}, lastRefresh = 0 }
Dots.map = Map

Map.ORDER = { "hostile", "careful", "neutral", "friendly", "allied", "companion", "resident" }
Map.SANDBOX_NAMES = { hostile = "Hostile", careful = "Careful", neutral = "Neutral", friendly = "Friendly",
    allied = "Allied", companion = "Companion", resident = "Resident" }
Map.REFRESH_MS = 1000
Map.ICON_PX = 12              -- at 1080p, before the size option

-- Fallbacks; the Mod Options below win when the game has them.
Map.settings = {
    enabled = true,
    show = { hostile = true, careful = true, neutral = true, friendly = true,
        allied = true, companion = true, resident = true },
    range = 100,                -- tiles
    lineOfSight = false,        -- only NPCs you can see, or saw within `memory`
    memory = 30,                -- seconds a sighting stays on the map
    residentsAnywhere = true,   -- your base's residents ignore the range
    deathMinutes = 5,           -- how long a resident's death X stays; 0 = never shown
    size = 1,                   -- world map icon size
    miniSize = 0.75,            -- minimap icon size
}

local options = nil

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
    return nil
end

-- The server's sandbox options cap what each player picks. Which statuses
-- show is the player's call in singleplayer and the server's in multiplayer.
function Map.limit(settings)
    local vars = type(SandboxVars) == "table" and type(SandboxVars.ALifeStanceDots) == "table"
        and SandboxVars.ALifeStanceDots or nil
    if vars == nil then return settings end
    local limited = {}
    for key, value in pairs(settings) do limited[key] = value end
    if vars.MapEnabled == false then limited.enabled = false end
    local cap = tonumber(vars.MapMaxRange)
    if cap ~= nil then limited.range = math.min(limited.range, cap) end
    if vars.MapForceLineOfSight == true then limited.lineOfSight = true end
    if vars.MapResidentsAnywhere == false then limited.residentsAnywhere = false end
    if type(isClient) == "function" and isClient() then
        limited.show = {}
        for _, status in ipairs(Map.ORDER) do
            limited.show[status] = vars["MapShow" .. Map.SANDBOX_NAMES[status]] ~= false
        end
    end
    return limited
end

function Map.read()
    if options == nil then return Map.limit(Map.settings) end
    local show = {}
    for index, status in ipairs(Map.ORDER) do
        show[status] = options.statuses:getValue(index) == true
    end
    return Map.limit({
        enabled = options.enabled:getValue() == true,
        show = show,
        range = tonumber(options.range:getValue()) or Map.settings.range,
        lineOfSight = options.lineOfSight:getValue() == true,
        memory = tonumber(options.memory:getValue()) or Map.settings.memory,
        residentsAnywhere = options.residentsAnywhere:getValue() == true,
        deathMinutes = tonumber(options.deathMinutes:getValue()) or Map.settings.deathMinutes,
        size = tonumber(options.size:getValue()) or Map.settings.size,
        miniSize = tonumber(options.miniSize:getValue()) or Map.settings.miniSize,
    })
end

-- Every A-Life record this machine knows: the whole registry where A-Life runs
-- (singleplayer, host), the server's mirror on a multiplayer client.
-- The MP mirror only covers ~250 tiles around you; Map.track remembers where
-- your residents were last known so they stay on the map past that.
-- ponytail: a remembered resident who moves or dies out there stays put; a
-- server-side snapshot would lift that.
local function eachRecord(visit)
    local alife = ProjectALife
    local registry = alife and alife.ActorRegistry or nil
    if registry ~= nil and type(registry.each) == "function" then
        registry.each(function(record) visit(record, record.uid) end)
        return
    end
    local executor = alife and alife.Executor or nil
    local mirrored = executor and type(executor.mirror) == "table" and executor.mirror.records or nil
    if type(mirrored) ~= "table" then return end
    for uid, record in pairs(mirrored) do visit(record, record.uid or uid) end
end

local function loadedShells()
    local shells = {}
    local list = getCell():getZombieList()
    for index = 0, list:size() - 1 do
        local shell = list:get(index)
        if shell ~= nil and not shell:isDead() then
            local uid = Dots.uidOf(shell)
            if uid ~= nil then shells[uid] = shell end
        end
    end
    return shells
end

local function residentOf(record, player)
    local safety = ProjectALifeJimmy and ProjectALifeJimmy.NpcSafety or nil
    return safety ~= nil and call(safety.yourResident, record, player) == true
end

local function positionOf(record, shell)
    if shell ~= nil then return shell:getX(), shell:getY() end
    local at = record.worldPosition
    if type(at) ~= "table" then return nil end
    return tonumber(at.x), tonumber(at.y)
end

Map.MEMORY_MAX_S = 300
Map.DEATH_MAX_MS = 30 * 60 * 1000

-- Mark where one of your residents died.
function Map.died(uid, x, y, now)
    Map.residents[uid] = nil
    if x ~= nil and y ~= nil then Map.deaths[uid] = { x = x, y = y, at = now } end
end

-- Keep the last known spot of each of your residents (they leave the MP mirror
-- past ~250 tiles), note the ones that died, forget deaths past the longest time.
function Map.track(player, now, shells)
    eachRecord(function(record, uid)
        if type(record) ~= "table" or uid == nil then return end
        if record.lifecycle == "dead" then
            local known = Map.residents[uid]
            if known ~= nil then
                local x, y = positionOf(record, nil)
                Map.died(uid, x or known.x, y or known.y, now)
            end
            return
        end
        if not residentOf(record, player) then
            Map.residents[uid] = nil
            return
        end
        local x, y = positionOf(record, shells[uid])
        if x ~= nil and y ~= nil then Map.residents[uid] = { x = x, y = y } end
    end)
    for uid, death in pairs(Map.deaths) do
        if now - death.at > Map.DEATH_MAX_MS then Map.deaths[uid] = nil end
    end
end

-- Note where player 0 sees each loaded NPC now; forget sightings past the longest memory.
function Map.spot(shells, now)
    for uid, shell in pairs(shells) do
        if Dots.inSight(shell) then Map.seen[uid] = { at = now, x = shell:getX(), y = shell:getY() } end
    end
    for uid, spot in pairs(Map.seen) do
        if now - spot.at > Map.MEMORY_MAX_S * 1000 then Map.seen[uid] = nil end
    end
end

-- The markers to draw: { x, y, status, shell } per NPC that passes the settings.
-- With line of sight on, an NPC out of sight stays where you last saw it for
-- `memory` seconds. Call Map.spot(shells, now) first.
function Map.collect(player, settings, now, shells)
    local rows = {}
    if ProjectALife == nil or not settings.enabled then return rows end
    local px, py = player:getX(), player:getY()
    local range2 = settings.range * settings.range
    local memoryMs = settings.memory * 1000
    shells = shells or loadedShells()
    local anywhere = settings.residentsAnywhere and settings.show.resident
    local listed = {}

    eachRecord(function(record, uid)
        if uid ~= nil then listed[uid] = true end
        if type(record) ~= "table" or uid == nil or record.lifecycle == "dead" then return end
        local shell = shells[uid]
        local x, y = positionOf(record, shell)
        local sighted = true
        if settings.lineOfSight then
            local spot = Map.seen[uid]
            sighted = spot ~= nil and now - spot.at <= memoryMs
            if sighted and spot.at ~= now then x, y, shell = spot.x, spot.y, nil end   -- last seen here
        end
        if x == nil or y == nil then return end

        local near = sighted and (x - px) ^ 2 + (y - py) ^ 2 <= range2
        if not near and not (anywhere and residentOf(record, player)) then return end
        local status = Dots.statusOf(record, player)
        if status == nil or not settings.show[status] then return end
        if not near and status ~= "resident" then return end   -- a resident who turned on you
        rows[#rows + 1] = { x = x, y = y, status = status, shell = shell }
    end)
    if anywhere then
        for uid, spot in pairs(Map.residents) do
            if not listed[uid] then rows[#rows + 1] = { x = spot.x, y = spot.y, status = "resident" } end
        end
    end
    local deathMs = settings.deathMinutes * 60 * 1000
    for _, death in pairs(Map.deaths) do
        if now - death.at <= deathMs then rows[#rows + 1] = { x = death.x, y = death.y, status = "dead" } end
    end
    return rows
end

local function mapsVisible()
    local world = ISWorldMap_instance
    if world ~= nil and world:isVisible() then return true end
    local mini = getPlayerMiniMap and getPlayerMiniMap(0) or nil
    return mini ~= nil and mini:isVisible()
end

-- Sightings are noted with the map closed too, so they are there when it opens.
local function refresh()
    local now = getTimestampMs()
    if now - Map.lastRefresh < Map.REFRESH_MS then return end
    Map.lastRefresh = now
    local player = getSpecificPlayer(0)
    if player == nil or player:isDead() then
        Map.rows = {}
        return
    end
    local shells = loadedShells()
    Map.spot(shells, now)
    Map.track(player, now, shells)
    if not mapsVisible() then return end
    Map.rows = Map.collect(player, Map.read(), now, shells)
end

local function draw(map, mini)
    local api = map.mapAPI
    local settings = Map.read()
    if api == nil or not settings.enabled then return end
    local icons = Dots.options()
    local prefix = icons and "" or "dot_"
    local scale = math.max(1, getCore():getScreenHeight() / 1080) * (mini and settings.miniSize or settings.size)
    local size = math.max(4, math.floor(Map.ICON_PX * scale + 0.5))
    local half = size / 2
    for _, row in ipairs(Map.rows) do
        local x, y = row.x, row.y
        if row.shell ~= nil then x, y = row.shell:getX(), row.shell:getY() end   -- moves between refreshes
        local sx, sy = api:worldToUIX(x, y), api:worldToUIY(x, y)
        -- the minimap does not clip what it draws
        if sx >= half and sy >= half and sx <= map.width - half and sy <= map.height - half then
            local icon = Dots.texture(row.status == "dead" and "dead" or prefix .. row.status)
            if icon ~= nil then map:drawTextureScaled(icon, sx - half, sy - half, size, size, 1) end
        end
    end
end

local function hook(class, name, mini)
    if class == nil or type(class.render) ~= "function" then return end
    local original = class.render
    class.render = function(self, ...)
        original(self, ...)
        local ok, err = pcall(draw, self, mini)
        if not ok and not Map.faulted then
            Map.faulted = true
            print("[ALifeStanceDots] " .. name .. " markers failed: " .. tostring(err))
        end
    end
end

local function install()
    if Map.installed then return end
    Map.installed = true
    hook(ISWorldMap, "world map")
    hook(ISMiniMapInner, "minimap", true)
end

local function safeRefresh()
    local ok, err = pcall(refresh)
    if not ok and not Map.faulted then
        Map.faulted = true
        print("[ALifeStanceDots] map refresh failed: " .. tostring(err))
    end
end

if PZAPI ~= nil and PZAPI.ModOptions ~= nil then
    local o = PZAPI.ModOptions:create("ALifeStanceDots", "IGUI_ALifeStanceDots_Map")
    options = {
        enabled = o:addTickBox("mapEnabled", "IGUI_ALifeStanceDots_MapEnabled", true,
            "IGUI_ALifeStanceDots_MapEnabled_tooltip"),
        statuses = o:addMultipleTickBox("mapStatuses", "IGUI_ALifeStanceDots_MapStatuses",
            "IGUI_ALifeStanceDots_MapStatuses_tooltip"),
        range = o:addSlider("mapRange", "IGUI_ALifeStanceDots_MapRange", 10, 250, 10, Map.settings.range,
            "IGUI_ALifeStanceDots_MapRange_tooltip"),
        lineOfSight = o:addTickBox("mapLineOfSight", "IGUI_ALifeStanceDots_MapLineOfSight", false,
            "IGUI_ALifeStanceDots_MapLineOfSight_tooltip"),
        memory = o:addSlider("mapMemory", "IGUI_ALifeStanceDots_MapMemory", 5, Map.MEMORY_MAX_S, 5,
            Map.settings.memory, "IGUI_ALifeStanceDots_MapMemory_tooltip"),
        residentsAnywhere = o:addTickBox("mapResidentsAnywhere", "IGUI_ALifeStanceDots_MapResidents", true,
            "IGUI_ALifeStanceDots_MapResidents_tooltip"),
        deathMinutes = o:addSlider("mapDeathMinutes", "IGUI_ALifeStanceDots_MapDeaths", 0, 30, 1,
            Map.settings.deathMinutes, "IGUI_ALifeStanceDots_MapDeaths_tooltip"),
        size = o:addSlider("mapSize", "IGUI_ALifeStanceDots_MapSize", 0.5, 3, 0.25, 1,
            "IGUI_ALifeStanceDots_MapSize_tooltip"),
        miniSize = o:addSlider("mapMiniSize", "IGUI_ALifeStanceDots_MiniMapSize", 0.25, 3, 0.25,
            Map.settings.miniSize, "IGUI_ALifeStanceDots_MiniMapSize_tooltip"),
    }
    for _, status in ipairs(Map.ORDER) do
        options.statuses:addTickBox("IGUI_ALifeStanceDots_Status_" .. status, true)
    end
    function o:apply() Map.lastRefresh = 0 end
end

-- A resident's shell dying in view: the record may not say so before the next refresh.
local function zombieDied(zombie)
    local uid = Dots.uidOf(zombie)
    if uid ~= nil and Map.residents[uid] ~= nil then
        Map.died(uid, zombie:getX(), zombie:getY(), getTimestampMs())
        Map.lastRefresh = 0
    end
end

if type(Events) == "table" and Events.OnGameStart ~= nil then
    Events.OnGameStart.Add(install)
    Events.OnTick.Add(safeRefresh)
    if Events.OnZombieDead ~= nil then
        Events.OnZombieDead.Add(function(zombie) pcall(zombieDied, zombie) end)
    end
end

return Map
