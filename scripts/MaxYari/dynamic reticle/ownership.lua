local mp = "scripts/MaxYari/dynamic reticle/"

local core = require("openmw.core")
local types = require("openmw.types")
local omwself = require("openmw.self")
local I = require("openmw.interfaces")

local DEFS = require(mp .. "defs")

-- Whether taking or using what the player looks at would be a crime: the check that turns the engine's
-- tooltip and crosshair red ("Show owned" in the launcher). It's ToolTips::checkOwned ->
-- MechanicsManager::isAllowedToUse and isOwned of OpenMW 0.51, in the same order. What Lua can't see:
-- knocked down NPCs (pickpocketing them), fleeing creatures and harvested Graphic Herbalism plants.
--
-- The object comes from MSS's interaction ray (the engine's own focus object isn't in the Lua API of 0.51),
-- which is cast like the engine's but without the Telekinesis range. Every cast makes a few userdata (the
-- result, the object, vectors), so the ray is at most RAY_MAX_AGE old rather than cast every frame. The
-- object is checked again when it or the sneak state changes and every RECHECK_INTERVAL otherwise (a door
-- unlocked, an NPC dying); the checks read the object's owner and record, which make userdata too.

local RAY_MAX_AGE = 0.1
local RECHECK_INTERVAL = 1
local GLOBAL_MAX_AGE = 1

-- mwscript global variables can only be read by a global script: a value is asked for when an object
-- names its global, and kept for GLOBAL_MAX_AGE. [name] = { value, askedAt }
local globals = {}

local lastObject = nil
local lastSneak = nil
local lastOwned = false
local nextCheckAt = 0

local function globalIsSet(name, now)
    local entry = globals[name]
    if not entry then
        entry = {}
        globals[name] = entry
    end
    if not entry.askedAt or now - entry.askedAt > GLOBAL_MAX_AGE then
        entry.askedAt = now
        core.sendGlobalEvent(DEFS.e.GlobalVarRequest, { player = omwself.object, name = name })
    end
    return entry.value ~= nil and entry.value ~= 0
end

local function onGlobalVarValue(e)
    local entry = globals[e.name]
    if not entry then return end
    if entry.value ~= e.value then nextCheckAt = 0 end
    entry.value = e.value
end

local function isInCombat(actor)
    return I.MSS.getCombatTargetsOther(actor.id) ~= nil
end

-- The owner or faction on the object, unless its global variable is set (a rented bed, for one).
local function isOwned(obj, now)
    local owner = obj.owner
    local ownerId = owner.recordId
    local owned = ownerId ~= nil and ownerId:lower() ~= "player"

    local factionOwned = false
    local factionId = owner.factionId
    if factionId then
        -- Both ranks count from 1; the player's is 0 outside the faction, the object's nil if any rank will do.
        local rank = types.NPC.getFactionRank(omwself, factionId)
        local requiredRank = owner.factionRank
        factionOwned = rank == 0 or (requiredRank ~= nil and rank < requiredRank)
    end

    if owned or factionOwned then
        local globalVariable = obj.globalVariable
        if globalVariable and globalIsSet(globalVariable, now) then return false end
    end
    return owned or factionOwned
end

local function isCrimeToUse(obj, now, sneak)
    if types.Door.objectIsInstance(obj) then
        -- There is no harm to use unlocked doors
        if not types.Lockable.isLocked(obj) and types.Lockable.getTrapSpell(obj) == nil then return false end
    elseif types.Light.objectIsInstance(obj) then
        -- Lights that can't be carried have no tooltip
        if not types.Light.record(obj).isCarriable then return false end
    elseif types.Activator.objectIsInstance(obj) then
        local record = types.Activator.record(obj)
        if record.name == "" then return false end
        -- The engine's own test for an owned bed: a script whose name starts with "Bed"
        local script = record.mwscript
        if not script or script:sub(1, 3):lower() ~= "bed" then return false end
    elseif types.NPC.objectIsInstance(obj) then
        if types.Actor.isDead(obj) or isInCombat(obj) then return false end
        -- Pickpocketing
        return sneak
    elseif types.Creature.objectIsInstance(obj) then
        if not types.Actor.isDead(obj) and isInCombat(obj) then return false end
    elseif not (types.Item.objectIsInstance(obj) or types.Container.objectIsInstance(obj)) then
        -- Statics and the rest have no tooltip
        return false
    end

    -- A special case for evidence chest - taking from it is never permitted
    if obj.recordId == "stolen_goods" then return true end
    return isOwned(obj, now)
end

-- Whether the object under the crosshair is owned. now: simulation time. sneak: the player's sneak control.
local function isTargetOwned(now, sneak)
    local obj = I.MSS.getInteractionTarget(RAY_MAX_AGE).hitObject
    if obj == nil then
        lastObject = nil
        lastOwned = false
        return false
    end

    if obj == lastObject and sneak == lastSneak and now < nextCheckAt then return lastOwned end
    lastObject = obj
    lastSneak = sneak
    nextCheckAt = now + RECHECK_INTERVAL

    -- An object can go away between the ray and the check, or name a faction that no longer exists.
    local ok, owned = pcall(isCrimeToUse, obj, now, sneak)
    lastOwned = ok and owned or false
    return lastOwned
end

return {
    isTargetOwned = isTargetOwned,
    onGlobalVarValue = onGlobalVarValue,
}
