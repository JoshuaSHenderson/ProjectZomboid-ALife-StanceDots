--[[
    A-Life Stance Dots - Viewpoint
    Keeps the stance markers over NPC heads in Project Viewpoint's first and
    third person views. The projection comes from the bundled Java bridge
    (the ALifeStanceDotsViewpoint Lua class), which reuses the camera Viewpoint
    places over-head speech with.
]]

require "ALifeStanceDots/ALifeStanceDots"

local Dots = ALifeStanceDots
local isometric = Dots.project

-- ponytail: the marker height option is in iso "tiles"; 1.75 m per unit puts
-- the default 1.15 at ~2 m, where Viewpoint floats speech. Retune if it sits off.
local METRES_PER_UNIT = 1.75

local warned = false

-- Viewpoint.View.next() names the view a press would switch to:
-- "first" means the 3D view is off, anything else means it is on.
local function in3D()
    local view = Viewpoint and Viewpoint.View or nil
    if view == nil then return false end
    local ok, nextView = pcall(view.next)
    return ok and nextView ~= nil and nextView ~= "first"
end

function Dots.project(x, y, z, height)
    if not in3D() then return isometric(x, y, z, height) end
    local java = ALifeStanceDotsViewpoint
    if java == nil or java.pixel == nil then
        -- iso maths would put the icon anywhere in 3D, so hide it instead
        if not warned then
            warned = true
            print("[ALifeStanceDots] Viewpoint 3D is on but the Java bridge is not loaded; markers hidden")
        end
        return nil
    end
    if not java.pixel(x, y, z, height * METRES_PER_UNIT) then return nil end
    return java.pixelX(), java.pixelY()
end
