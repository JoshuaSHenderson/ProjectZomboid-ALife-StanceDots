--[[
    A-Life Stance Dots
    Draws a coloured dot over every Project A-Life NPC: green = friendly,
    red = hostile (or "careful", which A-Life treats as hostile in combat),
    yellow = neutral.

    A-Life NPCs are zombie shells stamped with ALifeUID / ProjectALifeUID.
    The actor record behind a shell carries the faction and the per-actor
    stance overrides; ProjectALife.Relations.playerStance is the authority.
]]

local Dots = { textures = {} }
ALifeStanceDots = Dots

-- Tuning knobs. Screen offsets depend on resolution and UI scale; nudge
-- headHeight if the dot sits on the hair or floats too high.
Dots.settings = {
    headHeight = 1.15,   -- tiles above the shell's feet
    size = 12,           -- dot size in UI pixels
    alpha = 0.9,
    range = 30,          -- tiles from the player
    requireVisible = true,
}

local STANCES = { friendly = true, neutral = true, careful = true, hostile = true }

local COLOURS = {
    friendly = "green",
    neutral = "yellow",
    careful = "red",
    hostile = "red",
}

local function texture(name)
    local cached = Dots.textures[name]
    if cached ~= nil then return cached end
    local ok, value = pcall(getTexture, "media/ui/ALifeStanceDots/dot_" .. name .. ".png")
    if not ok or value == nil then return nil end
    Dots.textures[name] = value
    return value
end

-- Same key Reputation.playerKey builds server-side.
local function playerKey(player)
    if type(isClient) == "function" and isClient() then
        local ok, username = pcall(function() return player:getUsername() end)
        if ok and username ~= nil and tostring(username) ~= "" then return tostring(username) end
    end
    local ok, number = pcall(function() return player:getPlayerNum() end)
    return "sp:" .. tostring(math.max(0, math.floor(tonumber(ok and number or 0) or 0)))
end

local function reputationStatus(factionId)
    local store = ProjectALife and ProjectALife.StatusStore or nil
    local sync = store and store.reputation or nil
    local relations = type(sync) == "table" and sync.relations or nil
    if type(relations) ~= "table" then return nil end
    for _, row in ipairs(relations) do
        if type(row) == "table" and row.factionId == factionId and STANCES[row.status] then
            return row.status
        end
    end
    return nil
end

local function normalized(value)
    value = string.lower(tostring(value or ""))
    if value == "allied" then return "friendly" end
    if value == "suspicious" then return "careful" end
    return STANCES[value] and value or nil
end

-- ponytail: only used on multiplayer clients, where A-Life's server-side
-- Relations module is not loaded. Mirrors Relations.playerStance minus the
-- timed truces, which never survive the trip to the client anyway.
local function fallbackStance(record, player)
    local memory = type(record.memory) == "table" and record.memory or {}
    if memory.hostileOverride == true then return "hostile" end
    if type(memory.hostileToPlayerKeys) == "table"
            and memory.hostileToPlayerKeys[playerKey(player)] == true then
        return "hostile"
    end
    if memory.hostileOverride == false then return "friendly" end

    local catalog = ProjectALife and ProjectALife.Catalog or nil
    local faction = catalog and type(catalog.faction) == "function"
        and catalog.faction(record.factionId) or nil
    local declared = faction and faction.relations
        and normalized(faction.relations.player) or nil
    local default = declared
        or (faction and faction.spawn and faction.spawn.friendly == true and "friendly" or "hostile")

    local stance = normalized(memory.spawnStance) or default
    local earned = reputationStatus(record.factionId)
    if earned ~= nil then stance = earned end
    return stance
end

function Dots.stanceOf(record, player)
    if type(record) ~= "table" then return nil end
    local relations = ProjectALife and ProjectALife.Relations or nil
    if relations ~= nil and type(relations.playerStance) == "function" then
        local ok, value = pcall(relations.playerStance, record, player)
        if ok and STANCES[value] then return value end
    end
    return fallbackStance(record, player)
end

function Dots.actorFor(uid)
    local executor = ProjectALife and ProjectALife.Executor or nil
    local mirrored = executor and executor.mirror and executor.mirror.records or nil
    local record = type(mirrored) == "table" and mirrored[uid] or nil
    if type(record) == "table" then return record end
    local registry = ProjectALife and ProjectALife.ActorRegistry or nil
    if registry ~= nil and type(registry.read) == "function" then
        local ok, value = pcall(registry.read, uid)
        if ok and type(value) == "table" then return value end
    end
    return nil
end

local function uidOf(shell)
    local speech = ProjectALife and ProjectALife.Speech or nil
    if speech ~= nil and type(speech.variable) == "function" then
        local ok, value = pcall(speech.variable, shell, "ALifeUID")
        if ok and value ~= nil and tostring(value) ~= "" then return tostring(value) end
    end
    local ok, data = pcall(function() return shell:getModData() end)
    if ok and type(data) == "table" and type(data.ProjectALifeUID) == "string" then
        return data.ProjectALifeUID
    end
    return nil
end

local function visible(shell)
    if not Dots.settings.requireVisible then return true end
    local ok, seen = pcall(function()
        local square = shell:getSquare() or shell:getCurrentSquare()
        return square == nil or square:isCanSee(0)
    end)
    return not ok or seen ~= false
end

function Dots.render()
    if ProjectALife == nil then return end
    local player = getSpecificPlayer(0)
    if player == nil or player:isDead() then return end

    local settings = Dots.settings
    local list = getCell():getZombieList()
    local zoom = getCore():getZoom(0)
    if zoom == nil or zoom <= 0 then zoom = 1 end
    local offsetX, offsetY = getCameraOffX(), getCameraOffY()
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local range2 = settings.range * settings.range
    local half = settings.size / 2

    for index = 0, list:size() - 1 do
        local shell = list:get(index)
        if shell ~= nil and not shell:isDead() then
            local x, y, z = shell:getX(), shell:getY(), shell:getZ()
            if math.floor(z) == math.floor(pz)
                    and (x - px) ^ 2 + (y - py) ^ 2 <= range2 then
                local uid = uidOf(shell)
                local record = uid ~= nil and Dots.actorFor(uid) or nil
                local colour = record ~= nil and COLOURS[Dots.stanceOf(record, player) or ""] or nil
                local dot = colour ~= nil and visible(shell) and texture(colour) or nil
                if dot ~= nil then
                    local sx = (IsoUtils.XToScreen(x, y, z + settings.headHeight, 0) - offsetX) / zoom
                    local sy = (IsoUtils.YToScreen(x, y, z + settings.headHeight, 0) - offsetY) / zoom
                    UIManager.DrawTexture(dot, sx - half, sy - half,
                        settings.size, settings.size, settings.alpha)
                end
            end
        end
    end
end

local function safeRender()
    local ok, err = pcall(Dots.render)
    if not ok and not Dots.faulted then
        Dots.faulted = true
        print("[ALifeStanceDots] render failed: " .. tostring(err))
    end
end

if type(Events) == "table" and Events.OnPreUIDraw ~= nil then
    Events.OnPreUIDraw.Add(safeRender)
end

return Dots
