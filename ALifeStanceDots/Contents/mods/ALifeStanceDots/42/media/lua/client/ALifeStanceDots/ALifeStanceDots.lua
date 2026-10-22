--[[
    A-Life Stance Dots
    Draws an icon over every Project A-Life NPC saying where they stand with you:

      hostile    red crossed swords  will attack you, or is attacking you / your people
      careful    orange triangle     wary: won't shoot first, but watch them
      neutral    yellow dot          leaves you alone unless provoked
      friendly   green dot           won't attack you
      allied     green shield        allied faction or crew (Jeem's standing)
      companion  blue star           in your party, walking with you, or an ally following you
      resident   blue house          lives at a base you manage (Jeem's residents)

    A-Life NPCs are zombie shells stamped with ALifeUID / ProjectALifeUID.
    ProjectALife.Relations is the authority where it is loaded (singleplayer / host);
    a multiplayer client rebuilds the stance from the mirrored record.
]]

local Dots = { textures = {}, cache = {} }
ALifeStanceDots = Dots

-- Tuning knobs. Style and height come from the sandbox options
-- (SandboxVars.ALifeStanceDots) when set; these are the fallbacks.
Dots.settings = {
    icons = true,        -- false: plain coloured dots
    headHeight = 1.15,   -- tiles above the shell's feet
    size = 16,           -- icon size in UI pixels
    alpha = 0.9,
    range = 30,          -- tiles from the player
    requireVisible = true,
    cacheMs = 500,       -- how long one NPC's status is reused
}

local STANCES = { friendly = true, neutral = true, careful = true, hostile = true }
Dots.STATUSES = { hostile = true, careful = true, neutral = true, friendly = true,
    allied = true, companion = true, resident = true }

-- Sandbox options win over Dots.settings.
function Dots.options()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALifeStanceDots or nil
    local settings = Dots.settings
    local style = type(vars) == "table" and tonumber(vars.Style) or nil
    local height = type(vars) == "table" and tonumber(vars.HeadHeight) or nil
    local icons = settings.icons
    if style ~= nil then icons = style ~= 1 end
    return icons, height or settings.headHeight
end

local function texture(name)
    local cached = Dots.textures[name]
    if cached ~= nil then return cached end
    local ok, value = pcall(getTexture, "media/ui/ALifeStanceDots/" .. name .. ".png")
    if not ok or value == nil then return nil end
    Dots.textures[name] = value
    return value
end
Dots.texture = texture

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
    return nil
end

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function worldHours()
    local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
    return ok and tonumber(hours) or nil
end

-- Same key A-Life's Reputation.playerKey builds server-side.
local function playerKey(player)
    local speech = ProjectALife and ProjectALife.Speech or nil
    local key = speech and call(speech.playerKey, player) or nil
    if type(key) == "string" and key ~= "" then return key end
    if type(isClient) == "function" and isClient() then
        local ok, username = pcall(function() return player:getUsername() end)
        if ok and username ~= nil and tostring(username) ~= "" then return tostring(username) end
    end
    local ok, number = pcall(function() return player:getPlayerNum() end)
    return "sp:" .. tostring(math.max(0, math.floor(tonumber(ok and number or 0) or 0)))
end

local function normalized(value)
    value = string.lower(tostring(value or ""))
    if value == "allied" then return "friendly" end
    if value == "suspicious" then return "careful" end
    return STANCES[value] and value or nil
end

-- Jeem keeps its fields on the record, or in the MP relay copy under memory.admin.jimmy.
local function jeemField(memory, key)
    if type(memory) ~= "table" then return nil end
    if memory[key] ~= nil then return memory[key] end
    local relay = type(memory.admin) == "table" and type(memory.admin.jimmy) == "table" and memory.admin.jimmy or nil
    return relay and relay[key] or nil
end

local function jeemSafety()
    return ProjectALifeJimmy and ProjectALifeJimmy.NpcSafety or nil
end

local function factionOf(record)
    local catalog = ProjectALife and ProjectALife.Catalog or nil
    return catalog and call(catalog.faction, record.factionId) or nil
end

-- The faction's word toward this player, raw ("allied" kept apart from "friendly").
local function factionWord(record, player)
    local faction = factionOf(record)
    if type(faction) ~= "table" then return nil end
    local layers = ProjectALife and ProjectALife.RelationLayers or nil
    if layers ~= nil and type(layers.towardPlayer) == "function" then
        return call(layers.towardPlayer, faction, call(layers.professionOf, player))
    end
    local declared = type(faction.relations) == "table" and faction.relations.player or nil
    if declared ~= nil then return declared end
    local spawn = type(faction.spawn) == "table" and faction.spawn or {}
    return (spawn.peaceable == true or spawn.friendly == true) and "friendly" or "hostile"
end

local function reputationStatus(factionId)
    local store = ProjectALife and ProjectALife.StatusStore or nil
    local sync = store and store.reputation or nil
    local relations = type(sync) == "table" and sync.relations or nil
    if type(relations) ~= "table" then return nil end
    for _, row in ipairs(relations) do
        if type(row) == "table" and row.factionId == factionId then return normalized(row.status) end
    end
    return nil
end

-- ponytail: only used on multiplayer clients, where A-Life's server-side
-- Relations module is not loaded. Mirrors Relations.basePlayerStance minus
-- party membership, personal first-contact reputation, fairness and the timed
-- truces, none of which reach the client.
local function fallbackStance(record, player)
    local memory = type(record.memory) == "table" and record.memory or {}
    if memory.hostileOverride == true then return "hostile" end
    if type(memory.hostileToPlayerKeys) == "table"
            and memory.hostileToPlayerKeys[playerKey(player)] == true then
        return "hostile"
    end

    local stance = normalized(memory.spawnStance) or normalized(factionWord(record, player)) or "neutral"
    local forced = memory.hostileOverride == false
    if forced then stance = "friendly" end
    local earned = reputationStatus(record.factionId)
    if earned == "hostile" then return "hostile" end
    if not forced and earned ~= nil and not (earned == "neutral" and stance == "careful") then
        stance = earned
    end
    return stance
end

function Dots.stanceOf(record, player)
    if type(record) ~= "table" then return nil end
    local relations = ProjectALife and ProjectALife.Relations or nil
    local value = relations and call(relations.playerStance, record, player) or nil
    if STANCES[value] then return value end
    return fallbackStance(record, player)
end

-- Is this NPC out to hurt this player, whatever their stance says?
function Dots.attacking(record, player, key)
    local relations = ProjectALife and ProjectALife.Relations or nil
    if relations and call(relations.hostileToPlayer, record, player) == true then return true end
    local safety = jeemSafety()
    if safety and call(safety.attacking, record, player) == true then return true end
    local memory = type(record.memory) == "table" and record.memory or {}
    -- fighting you right now (what the server mirrors of its combat target)
    if record.activity == "combat" and jeemField(memory, "combatTargetKind") == "player"
            and jeemField(memory, "combatTargetPlayerKey") == key then
        return true
    end
    -- sent to hunt you by name (Relations.orderedHostile)
    local named = memory.targetUsername
    return type(named) == "string" and named ~= "" and memory.hostileOverride ~= false
        and string.lower(named) == string.lower(tostring(key))
end

function Dots.companion(record, player, key)
    local party = ProjectALife and ProjectALife.Party or nil
    if party and call(party.friendly, record, player) == true then return true end
    local memory = type(record.memory) == "table" and record.memory or {}
    local walk = memory.walkWith
    if type(walk) == "table" and walk.key == key then
        local hours = worldHours()
        if hours == nil or hours < (tonumber(walk.untilHours) or math.huge) then return true end
    end
    local order = jeemField(memory, "jimmyOrder")
    return type(order) == "table" and order.ally == true and order.player == key
end

function Dots.statusOf(record, player)
    if type(record) ~= "table" then return nil end
    local key = playerKey(player)
    local stance = Dots.stanceOf(record, player)
    if stance == "hostile" or Dots.attacking(record, player, key) then return "hostile" end
    if Dots.companion(record, player, key) then return "companion" end
    local safety = jeemSafety()
    if safety and call(safety.yourResident, record, player) == true then return "resident" end
    if safety and call(safety.yourAlly, record, player) == true then return "allied" end
    if stance == "friendly" and string.lower(tostring(factionWord(record, player))) == "allied" then
        return "allied"
    end
    return stance
end

function Dots.actorFor(uid)
    local executor = ProjectALife and ProjectALife.Executor or nil
    local mirrored = executor and executor.mirror and executor.mirror.records or nil
    local record = type(mirrored) == "table" and mirrored[uid] or nil
    if type(record) == "table" then return record end
    local registry = ProjectALife and ProjectALife.ActorRegistry or nil
    if registry ~= nil then
        record = call(registry.peek, uid) or call(registry.read, uid)
        if type(record) == "table" then return record end
    end
    return nil
end

local function cachedStatus(uid, player, now)
    local kept = Dots.cache[uid]
    if kept ~= nil and now >= kept.at and now - kept.at < Dots.settings.cacheMs then return kept.status end
    local record = Dots.actorFor(uid)
    local status = record ~= nil and Dots.statusOf(record, player) or nil
    Dots.cache[uid] = { at = now, status = status }
    return status
end

local function uidOf(shell)
    local speech = ProjectALife and ProjectALife.Speech or nil
    local value = speech and call(speech.variable, shell, "ALifeUID") or nil
    if value ~= nil and tostring(value) ~= "" then return tostring(value) end
    local ok, data = pcall(function() return shell:getModData() end)
    if ok and type(data) == "table" and type(data.ProjectALifeUID) == "string" then
        return data.ProjectALifeUID
    end
    return nil
end
Dots.uidOf = uidOf

-- Can player 0 see this shell's square?
function Dots.inSight(shell)
    local ok, seen = pcall(function()
        local square = shell:getSquare() or shell:getCurrentSquare()
        return square == nil or square:isCanSee(0)
    end)
    return not ok or seen ~= false
end

local function visible(shell)
    return not Dots.settings.requireVisible or Dots.inSight(shell)
end

-- World position -> UI pixels, or nil when off camera. The isometric view;
-- the Viewpoint add-on replaces this while a 3D view is on.
function Dots.project(x, y, z, height)
    local zoom = getCore():getZoom(0)
    if zoom == nil or zoom <= 0 then zoom = 1 end
    return (IsoUtils.XToScreen(x, y, z + height, 0) - getCameraOffX()) / zoom,
        (IsoUtils.YToScreen(x, y, z + height, 0) - getCameraOffY()) / zoom
end

function Dots.render()
    if ProjectALife == nil then return end
    local player = getSpecificPlayer(0)
    if player == nil or player:isDead() then return end

    local settings = Dots.settings
    local list = getCell():getZombieList()
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local range2 = settings.range * settings.range
    local half = settings.size / 2
    local now = nowMs()
    local seen = {}
    local icons, height = Dots.options()
    local prefix = icons and "" or "dot_"

    for index = 0, list:size() - 1 do
        local shell = list:get(index)
        if shell ~= nil and not shell:isDead() then
            local x, y, z = shell:getX(), shell:getY(), shell:getZ()
            if math.floor(z) == math.floor(pz)
                    and (x - px) ^ 2 + (y - py) ^ 2 <= range2 then
                local uid = uidOf(shell)
                local status = uid ~= nil and cachedStatus(uid, player, now) or nil
                if uid ~= nil then seen[uid] = Dots.cache[uid] end
                local icon = status ~= nil and visible(shell) and texture(prefix .. status) or nil
                local sx, sy
                if icon ~= nil then sx, sy = Dots.project(x, y, z, height) end
                if sx ~= nil then
                    UIManager.DrawTexture(icon, sx - half, sy - half,
                        settings.size, settings.size, settings.alpha)
                end
            end
        end
    end
    Dots.cache = seen   -- drop NPCs that left range
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
