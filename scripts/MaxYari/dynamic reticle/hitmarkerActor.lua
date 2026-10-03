local mp = "scripts/MaxYari/dynamic reticle/"

local omwself = require('openmw.self')
local I = require('openmw.interfaces')
local core = require("openmw.core")
local types = require("openmw.types")

local gutils = require(mp.."gutils")
local EventsManager = require(mp .. "events_manager")
local DEFS = require(mp .. "defs")

local selfObject = omwself.object

local onDamageEvents = EventsManager:new()

DebugLevel = 2

local recordBlackList = {"ab01alsonar","ab01bird01"} -- From where all birds going, don't need to process those, only wastes performance.
if gutils.foundInList(recordBlackList, omwself.recordId) then return end

local damageEventData = {} -- Allegedly making a new table every frame is bad for performance, probably a microoptimisation, but whatever, better than nothing

-- A health decrease of this actor, from Max Yari's Script Services (MSS). It's hostile damage when this
-- actor fights the player (its combat targets, from MSS) or when the player's weapon hit it; the latter
-- also covers guards pursuing the player.
local function onHealthDecrease(e)
    -- In case max health changed - this should not trigger damage
    local damageValue = math.min(e.previousHealth, e.baseHealth) - e.health
    if damageValue <= 0 then return end

    local targets = I.MSS.getCombatTargets()
    local attacker = e.hit and e.hit.attacker
    local playerHit = attacker ~= nil and types.Player.objectIsInstance(attacker)
    if not targets and not playerHit then return end

    damageEventData.hostile = selfObject
    damageEventData.damage = damageValue
    damageEventData.damageFrac = damageValue / e.baseHealth
    damageEventData.currentHealth = e.health
    damageEventData.glancedHit = false

    if I.GlancedHits and I.GlancedHits.lastHitInfo then
        local now = core.getRealTime()
        if now - I.GlancedHits.lastHitInfo.time <= 0.1 then
            damageEventData.glancedHit = I.GlancedHits.lastHitInfo.glancedHit
        end
    end

    local attackerTold = false
    if targets then
        for _, actor in ipairs(targets) do
            actor:sendEvent(DEFS.e.HostileDamaged, damageEventData)
            if playerHit and actor == attacker then attackerTold = true end
        end
    end
    if playerHit and not attackerTold then
        attacker:sendEvent(DEFS.e.HostileDamaged, damageEventData)
    end

    onDamageEvents:emit(damageEventData)
end

-- Registered once all scripts on this actor are loaded (onActive), so I.MSS exists.
local registered = false
local function onActive()
    if registered then return end
    registered = true
    I.MSS.addDamageListener(onHealthDecrease)
end


-- A hit that damages this actor's fatigue (hand-to-hand, or a weapon given fatigue damage by a mod), told
-- to the same actors as a health decrease. Spells that damage fatigue don't come through here.
local staminaDamageEventData = { hostile = selfObject }
local function onStaminaHit(attackInfo)
    local targets = I.MSS.getCombatTargets()
    local attacker = attackInfo.attacker
    local playerHit = attacker ~= nil and types.Player.objectIsInstance(attacker)
    if not targets and not playerHit then return end

    local attackerTold = false
    if targets then
        for _, actor in ipairs(targets) do
            actor:sendEvent(DEFS.e.StaminaDamaged, staminaDamageEventData)
            if playerHit and actor == attacker then attackerTold = true end
        end
    end
    if playerHit and not attackerTold then
        attacker:sendEvent(DEFS.e.StaminaDamaged, staminaDamageEventData)
    end
end

I.Combat.addOnHitHandler(function(attackInfo)
    if not attackInfo.successful then
        if types.Player.objectIsInstance(attackInfo.attacker) then
            attackInfo.attacker:sendEvent(DEFS.e.MissedAttack)
        end
    elseif attackInfo.damage and (attackInfo.damage.fatigue or 0) > 0 then
        onStaminaHit(attackInfo)
    end
end)


return {
    engineHandlers = {
        onActive = onActive,
    },
    interfaceName = "DynamicReticle",
    interface = {
        version=1.2,
        onDamage = onDamageEvents,
    }
}
