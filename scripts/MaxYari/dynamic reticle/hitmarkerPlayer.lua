-- Mod version, published to Nexus by .github/workflows/nexus-release.yml (the first `version = ...` in this file)
local VERSION = "1.5"

local mp = "scripts/MaxYari/dynamic reticle/"

local ui_elements = require(mp .. "ui_elements")
local animConf = ui_elements.animConf
local Tweener = require(mp .. "tweener")
local gutils = require(mp .. "gutils")
local SettingsHelper = require(mp .. "settings_helper")
local DEFS = require(mp .. "defs")
local shaderUtils = require(mp .. "shader_utils")
local animManager = require(mp .. "anim_manager")
local ArcBar = require(mp .. "arc_bar")
local ownership = require(mp .. "ownership")

local core = require("openmw.core")
local util = require("openmw.util")
local I = require("openmw.interfaces")
local omwself = require("openmw.self")
local camera = require("openmw.camera")
local ui = require("openmw.ui")
local types = require('openmw.types')

-- Max Yari's Script Services (MSS) is a required dependency: checked once, when this script loads.
if not core.contentFiles.has("MaxYariScriptServices.omwscripts") then
    print("[Dynamic Reticle] ERROR: critical dependency is missing: Max Yari's Script Services (MSS). Please install it.")
    ui.showMessage("Dynamic Reticle: Critical dependency is missing, please install Max Yari's Script Services (MSS)")
end

-- Ui Elements
local reticleEl = ui_elements.getElementByName("reticle")
local stealthArrowLEl = ui_elements.getElementByName("stealthArrowL")
local stealthArrowREl = ui_elements.getElementByName("stealthArrowR")

-- Settings, live: what is only applied once (element props, shader uniforms) is applied again whenever
-- it changes, by applyVisualSettings, applyWidgetSettings and applyOpacitySettings further down.
local applyVisualSettings, applyWidgetSettings, applyOpacitySettings
local visualSettings = SettingsHelper:new(DEFS.settings.visual, nil, function() applyVisualSettings() end)
local widgetSettings = SettingsHelper:new(DEFS.settings.widget, nil, function() applyWidgetSettings() end)
local opacitySettings = SettingsHelper:new(DEFS.settings.opacity, nil, function() applyOpacitySettings() end)

local currentTargetActor = nil
local wasSneaking = false

local tweeners = {}

-- Reticle multiplier state: each slot has its own scale/alpha multipliers and tweener
-- Final values are computed by multiplying all slots together with the opacity for what is readied
local reticleState = {
    sneak = { scale = 1.0, alpha = 1.0, tweener = nil },
    shoot = { scale = 1.0, alpha = 1.0, tweener = nil },
    miss = { scale = 1.0, alpha = 1.0, tweener = nil },
}

-- What is readied, by its Reticle Opacity setting's key. The reticle's opacity fades towards that setting.
local RANGED_WEAPON_TYPES = {
    [types.Weapon.TYPE.MarksmanBow] = true,
    [types.Weapon.TYPE.MarksmanCrossbow] = true,
    [types.Weapon.TYPE.MarksmanThrown] = true,
}
local SLOT_CARRIED_RIGHT = types.Actor.EQUIPMENT_SLOT.CarriedRight
-- How old the weapon and the selected spell may be: they can change while readied (quick keys)
local WEAPON_MAX_AGE = 0.2
local CASTABLE_CHECK_INTERVAL = 0.2

local readiedKey = nil
local readiedAlpha = nil -- nil until the first update, which starts at the setting
local lastStance = nil

-- The selected spell, else the selected enchanted item (the order the engine casts them in), is a ranged
-- spell if any of its effects is on target. Effects are only read when what is selected changes.
local castableCheckTimer = 0
local lastSpellId = nil
local lastItemId = nil
local castableKey = 'TouchSelfSpellOpacity'

local function effectsOpacityKey(effects)
    if effects then
        for _, effect in ipairs(effects) do
            if effect.range == core.magic.RANGE.Target then return 'RangedSpellOpacity' end
        end
    end
    return 'TouchSelfSpellOpacity'
end

local function readCastable()
    local spell = types.Actor.getSelectedSpell(omwself)
    if spell then
        if spell.id ~= lastSpellId then
            lastSpellId, lastItemId = spell.id, nil
            castableKey = effectsOpacityKey(spell.effects)
        end
        return
    end
    local item = types.Actor.getSelectedEnchantedItem(omwself)
    local itemId = item and item.recordId
    if itemId ~= lastItemId or lastSpellId then
        lastSpellId, lastItemId = nil, itemId
        local record = item and item.type.record(item)
        local enchantment = record and record.enchant and core.magic.enchantments.records[record.enchant]
        castableKey = effectsOpacityKey(enchantment and enchantment.effects)
    end
end

local function readiedOpacityKey(stance, dt)
    local stanceChanged = stance ~= lastStance
    lastStance = stance
    if stance == types.Actor.STANCE.Weapon then
        local info = I.MSS.getEquipmentInfo(SLOT_CARRIED_RIGHT, WEAPON_MAX_AGE)
        if info and info.type == types.Weapon and RANGED_WEAPON_TYPES[info.record.type] then
            return 'RangedWeaponOpacity'
        end
        return 'MeleeOpacity'
    elseif stance == types.Actor.STANCE.Spell then
        castableCheckTimer = castableCheckTimer - dt
        if stanceChanged or castableCheckTimer <= 0 then
            castableCheckTimer = CASTABLE_CHECK_INTERVAL
            readCastable()
        end
        return castableKey
    end
    return 'StowedOpacity'
end

-- Other mods' say over the reticle's opacity, by whoever asked, multiplied in
-- with the slots above. Combat Juice uses it to fade the reticle out from under
-- a kill marker drawn on top of it.
local externalAlpha = {}

local function setAlphaMultiplier(source, alpha)
    if alpha == nil or alpha >= 1 then
        externalAlpha[source] = nil
    else
        externalAlpha[source] = math.max(alpha, 0)
    end
end

-- Compute final reticle size and alpha from all multiplier slots
local function computeReticleValues()
    local s = reticleState
    local ru = reticleEl.userData
    local finalScale = s.sneak.scale * s.shoot.scale * s.miss.scale
    local finalAlpha = (readiedAlpha or 0) * s.sneak.alpha * s.shoot.alpha * s.miss.alpha
    for _, alpha in pairs(externalAlpha) do finalAlpha = finalAlpha * alpha end
    reticleEl.props.size = ru.size * finalScale
    reticleEl.props.alpha = util.clamp(finalAlpha, 0, 1)
end

-- Owned tint: 0 is the reticle's own color, 1 the owned color. Reaches either in OWNED_TINT_TIME.
local OWNED_TINT_TIME = 0.1
local ownedTint = 0

local function setReticleColor(color)
    reticleEl.props.color = color
    stealthArrowLEl.props.color = color
    stealthArrowREl.props.color = color
end

local function applyTintColor()
    local baseColor = reticleEl.userData.color
    local ownedColor = visualSettings["OwnedReticleColor"]
    if ownedTint >= 1 then
        setReticleColor(ownedColor)
    elseif ownedTint <= 0 then
        setReticleColor(baseColor)
    else
        setReticleColor(util.color.rgb(
            gutils.lerp(baseColor.r, ownedColor.r, ownedTint),
            gutils.lerp(baseColor.g, ownedColor.g, ownedTint),
            gutils.lerp(baseColor.b, ownedColor.b, ownedTint)))
    end
end

-- The owned tint asks MSS's interaction ray from onUpdate, which MSS allows since its version 2. With an
-- older MSS the tint stays off, and the player is told once.
local mssRayChecked = false
local mssRayReady = false
local function canCheckOwned()
    if not mssRayChecked and I.MSS then
        mssRayChecked = true
        mssRayReady = (I.MSS.version or 1) >= 2
        if not mssRayReady then
            print("[Dynamic Reticle] Max Yari's Script Services (MSS) is older than version 2: the owned reticle tint is off until it is updated.")
            ui.showMessage("Dynamic Reticle: please update Max Yari's Script Services (MSS) for the owned-item reticle tint")
        end
    end
    return mssRayReady
end

local function updateOwnedTint(dt, owned)
    local goal = owned and 1 or 0
    if ownedTint == goal then return end
    ownedTint = util.clamp(ownedTint + (owned and dt or -dt) / OWNED_TINT_TIME, 0, 1)
    -- A new color only while it changes
    applyTintColor()
end

local targetDistanceTimer = 0
local stanceNoneTimer = 0

-- The stamina arc sits inside the hp arc, this far from the hp arc's inner edge (pixels, before uScale).
local STAMINA_ARC_GAP = 4
local HP_ARC_RADIUS = 60
local HP_ARC_THICKNESS = 2

-- Arc lengths, by the target's max hp and max stamina: MIN_ARC_ANGLE at a range's low end, MAX_ARC_ANGLE at
-- its top and above. In the load order 200 hp is the 85th percentile of hostile NPCs (92nd of all hostiles);
-- the stamina range is the hp one times 1.6, which puts its top at the same 85th percentile of hostile NPCs'
-- stamina. Creatures' stamina is a set 300-1000, so nearly all of them get the full arc.
local MIN_ARC_ANGLE = math.rad(30)
local MAX_ARC_ANGLE = math.rad(180)
local HP_ARC_RANGE = { 10, 200 }
local STAMINA_ARC_RANGE = { 16, 320 }

local function arcAngleFor(maxValue, range)
    local angle = util.remap(maxValue, range[1], range[2], MIN_ARC_ANGLE, MAX_ARC_ANGLE)
    return util.clamp(angle, MIN_ARC_ANGLE, MAX_ARC_ANGLE)
end

local hpWidgetShader = shaderUtils.ShaderWrapper:new('hpWidget', {
    uOpacity = 0,
    uArcRadius = HP_ARC_RADIUS,
    uStaminaOpacity = 0,
})

-- The widget settings that are uniforms; on load and whenever they change.
function applyWidgetSettings()
    local u = hpWidgetShader.u
    local staminaThickness = HP_ARC_THICKNESS * widgetSettings["StaminaWidgetThickness"]
    u.uColor = widgetSettings["HpWidgetColor"]:asRgb()
    u.uDamageColor = widgetSettings["HpWidgetDamageColor"]:asRgb()
    u.uScale = widgetSettings["HpWidgetScale"]
    u.uStaminaColor = widgetSettings["StaminaWidgetColor"]:asRgb()
    u.uStaminaDamageColor = widgetSettings["StaminaWidgetDamageColor"]:asRgb()
    u.uStaminaThickness = staminaThickness
    u.uStaminaRadius = HP_ARC_RADIUS - HP_ARC_THICKNESS / 2 - STAMINA_ARC_GAP - staminaThickness / 2
end
applyWidgetSettings()

local hpArc = ArcBar:new(hpWidgetShader, {
    opacity = "uOpacity",
    maxArc = "uMaxArcAngle",
    curArc = "uCurArcAngle",
    tail = "uLostHpTailAngle",
    wave = "uOnHitWaveProgress",
    sectors = "uAnimatedSectors",
})

local staminaArc = ArcBar:new(hpWidgetShader, {
    opacity = "uStaminaOpacity",
    maxArc = "uStaminaMaxArcAngle",
    curArc = "uStaminaCurArcAngle",
    tail = "uStaminaLostTailAngle",
    wave = "uStaminaOnHitWaveProgress",
    sectors = "uStaminaAnimatedSectors",
})

-- Stamina hits: with StaminaWidgetOnlyOnDamage the arc shows for STAMINA_SHOW_TIME after the target's
-- stamina was last hit. Only decreases near a hit play the loss animations, so the target tiring itself
-- (swinging, running) only shrinks the arc.
local STAMINA_HIT_WINDOW = 0.5
local STAMINA_SHOW_TIME = 3
local lastStaminaHitAt = -math.huge


-- Sneak arrows: `shown` is animated when sneaking starts or stops, `bounce` (outward) on every footstep. They
-- are placed only when one of the two changes. Their opacity is their own, or with Sneak Arrows Use Reticle
-- Opacity the reticle's for what is readied, following its fade.
local sneakArrows = { shown = 0, bounce = 0 }

local function applySneakArrowsAlpha()
    local alpha = animConf.sneakArrowAlpha
    if visualSettings["SneakArrowsUseReticleOpacity"] then alpha = readiedAlpha or 0 end
    alpha = util.clamp(alpha * sneakArrows.shown, 0, 1)
    stealthArrowLEl.props.alpha = alpha
    stealthArrowREl.props.alpha = alpha
end

local function placeSneakArrows()
    local dist = gutils.lerp(animConf.sneakArrowPartFromDist, animConf.sneakArrowPartToDist, sneakArrows.shown)
        + animConf.sneakArrowStepBounceDist * visualSettings["SneakStepBounceStrength"] * sneakArrows.bounce
    for _, el in ipairs({stealthArrowLEl, stealthArrowREl}) do
        el.props.relativePosition = util.vector2(0.5, 0.5) + el.userData.direction * dist
    end
    applySneakArrowsAlpha()
end

local function bounceSneakArrows()
    local tweener = Tweener:new()
    local from = sneakArrows.bounce
    tweener:add(0.16, Tweener.easings.easeOutQuad, function(t)
        sneakArrows.bounce = gutils.lerp(from, 1, t)
        placeSneakArrows()
    end):add(0.7, Tweener.easings.springOutMed, function(t)
        sneakArrows.bounce = 1 - t
        placeSneakArrows()
    end)
    tweeners["sneak_arrows_step"] = tweener
end

-- The reticle settings, whenever they change: the HUD element takes what it keeps (ui_elements), and what
-- is animated from those is redrawn at once, the game being paused in the settings.
function applyVisualSettings()
    ui_elements.applySettings(visualSettings)
    applyTintColor()
    -- Sneaking and settled: the reticle takes its new sneak size at once
    local sneakSlot = reticleState.sneak
    if wasSneaking and not (sneakSlot.tweener and #sneakSlot.tweener.animations > 0) then
        sneakSlot.scale = animConf.reticleSneakSizeMult
    end
    placeSneakArrows()
    computeReticleValues()
    ui_elements.parentElement:update()
end

-- The opacities, whenever they change (a visibility preset picked, for one): the reticle takes the one for
-- what is readied at once, the game being paused in the settings.
function applyOpacitySettings()
    if readiedKey then readiedAlpha = opacitySettings[readiedKey] end
    applySneakArrowsAlpha()
    computeReticleValues()
    ui_elements.parentElement:update()
end

local function animateStealthStuff(show)
    local slot = reticleState.sneak

    -- Cancel existing sneak animation and reset multiplier
    if slot.tweener then
        slot.tweener:finish()
        slot.scale = 1.0
    end

    slot.tweener = Tweener:new()
    tweeners["reticle_sneak"] = slot.tweener

    local function animateArrows(t)
        sneakArrows.shown = t
        placeSneakArrows()
    end

    if show then
        slot.tweener:add(0.5, Tweener.easings.springOutStrong, function(t)
            slot.scale = gutils.lerp(1, animConf.reticleSneakSizeMult, t)
            animateArrows(t)
        end)
    else
        slot.tweener:add(0.5, Tweener.easings.springOutStrong, function(t)
            slot.scale = gutils.lerp(animConf.reticleSneakSizeMult, 1, t)
            animateArrows(1 - t)
        end)
    end
end

local function setReticleScreenPos(screenPos)
    ui_elements.parentElement.layout.props.relativePosition = screenPos
    hpWidgetShader.u.uPosition = screenPos
    ui_elements.parentElement:update()
end

local function setReticleWorldPos(worldPos)
    local screenPosAbs = camera.worldToViewportVector(worldPos)
    local screenPosRel = util.vector2(screenPosAbs.x/ui.screenSize().x, screenPosAbs.y/ui.screenSize().y)
    setReticleScreenPos(screenPosRel)
    return screenPosRel
end

local function setCurrentEnemy(enemy)
    if enemy == nil then
        currentTargetActor = nil
        return
    end
    if not currentTargetActor or currentTargetActor.gameObject ~= enemy then
        currentTargetActor = gutils.Actor:new(enemy)

        -- Reset some shader variables
        hpArc:reset()
        staminaArc:reset()
        lastStaminaHitAt = -math.huge
    end
end

-- Hitmarker and hp widget update on hosile damaged event --------------------
------------------------------------------------------------------------------
local function onHostileDamaged(data)
    targetDistanceTimer = 0
    stanceNoneTimer = 0
    -- Hit markers and their sounds moved to Combat Juice; the hp widget is what
    -- this event is still for.
    setCurrentEnemy(data.hostile)
end

-- A hit on a hostile's stamina: it becomes the target like any hostile damage, and its stamina arc shows.
local function onStaminaDamaged(data)
    targetDistanceTimer = 0
    stanceNoneTimer = 0
    setCurrentEnemy(data.hostile)

    local now = core.getSimulationTime()
    lastStaminaHitAt = now
    -- The decrease can be seen a frame before the hit is reported
    staminaArc:playLastLoss(now, STAMINA_HIT_WINDOW)
end

-- Missed attack reticle fadeout --------------------
-------------------------------------------------------
local function onMissedAttack()
    local slot = reticleState.miss

    -- Cancel existing miss animation and reset multiplier
    if slot.tweener then
        slot.tweener:finish()
        slot.scale = 1.0
        slot.alpha = 1.0
    end

    slot.tweener = Tweener:new()
    tweeners["reticle_miss"] = slot.tweener

    slot.tweener:add(0.1, Tweener.easings.easeOutCubic, function(t)
        slot.alpha = gutils.lerp(1, visualSettings["MissedReticleAlpha"], t)
    end):add(0.3, Tweener.easings.easeOutCubic, function(t)
        slot.alpha = gutils.lerp(visualSettings["MissedReticleAlpha"], 1, t)
    end)
end

-- Reticle bounce on shoot, sneak arrows bounce on footsteps -----------------
------------------------------------------------------------------------------
animManager.addOnKeyHandler(function(groupname, key)
    -- Footsteps are "soundgen: left" / "soundgen: right", optionally followed by volume and pitch
    if groupname == "soundgen" and wasSneaking and visualSettings["SneakStepBounceStrength"] > 0
        and (key:sub(1, 4) == "left" or key:sub(1, 5) == "right") then
        bounceSneakArrows()
    elseif key == "shoot release" then
        local slot = reticleState.shoot

        -- Cancel existing shoot animation and reset multiplier
        if slot.tweener then
            slot.tweener:finish()
            slot.scale = 1.0
            slot.alpha = 1.0
        end

        slot.tweener = Tweener:new()
        tweeners["reticle_shoot"] = slot.tweener

        -- Animate size and alpha when extending
        slot.tweener:add(0.1, Tweener.easings.springOutStrong, function(t)
            slot.scale = gutils.lerp(1, 1.75, t)
            slot.alpha = gutils.lerp(1, 0.33, t)
        end)
        -- Animate size and alpha when shrinking back
        :add(0.3, Tweener.easings.easeOutCubic, function(t)
            slot.scale = gutils.lerp(1.75, 1, t)
            slot.alpha = gutils.lerp(0.33, 1, t)
        end)
    end
end)

-- onUpdate -------------------------------------------
-------------------------------------------------------
local function onUpdate(dt)
    if dt <= 0 then return end
    local isHudVisible = I.UI.isHudVisible()
    local now = core.getSimulationTime()

    -- Hiding/Showing widgets based on hud visibility and ensuring that hp widget is above hex dof from first person view dynamics.
    ui_elements.parentElement.layout.props.alpha = isHudVisible and 1 or 0
    -- Health widget is also hidden based on isHudVisible, but later down the line

    local widgetShouldStart = false
    if I.DynamicCamera then
        widgetShouldStart = I.DynamicCamera.shaders["hexDoFProgrammable"].enabled
    else
        widgetShouldStart = true
    end

    -- Shader is off entirely while the HUD is hidden (F11), not just faded.
    local anyWidget = widgetSettings["ShowHpWidget"] or widgetSettings["ShowStaminaWidget"]
    if widgetShouldStart and anyWidget and isHudVisible then
        hpWidgetShader:enable()
    else
        hpWidgetShader:disable()
    end


    -- Handle sneak state
    local isSneaking = omwself.controls.sneak
    if isSneaking ~= wasSneaking then
        animateStealthStuff(isSneaking)
        wasSneaking = isSneaking
    end


    -- Update all tweeners
    for _, tweener in pairs(tweeners) do
        tweener:tick(dt)
    end

    -- Fade towards the opacity for what is readied
    local stance = types.Actor.getStance(omwself)
    readiedKey = readiedOpacityKey(stance, dt)
    local readiedGoal = opacitySettings[readiedKey]
    if readiedAlpha == nil then
        readiedAlpha = readiedGoal
    else
        readiedAlpha = gutils.lerp(readiedAlpha, readiedGoal, gutils.dtForLerp(dt, 5))
    end
    if sneakArrows.shown ~= 0 and visualSettings["SneakArrowsUseReticleOpacity"] then applySneakArrowsAlpha() end

    -- Update reticle from multiplier slots
    computeReticleValues()

    -- Tint the reticle over what would be a crime to take or use. The center ray is wrong with a menu open
    -- (the Unpause mod keeps the game running there), so it's skipped then.
    local owned = visualSettings["OwnedReticle"] and isHudVisible and not I.UI.getMode()
        and canCheckOwned() and ownership.isTargetOwned(now, isSneaking)
    updateOwnedTint(dt, owned)

    if currentTargetActor then
        local target = currentTargetActor.gameObject
        if not target:isValid() then
            -- Removed from the game (an expired summon, a disposed corpse): nothing more can be read from it.
            currentTargetActor = nil
        else
            -- Distance can't be more than 10 meters for more than 3 seconds
            local distance = (target.position - I.MSS.getPosition()):length()
            if distance > 10*DEFS.GUtoM then
                targetDistanceTimer = targetDistanceTimer + dt
                if targetDistanceTimer >= 3 then
                    currentTargetActor = nil
                    targetDistanceTimer = 0
                end
            else
                targetDistanceTimer = 0
            end
        end
    end

    if currentTargetActor then
        -- No-weapon stance hides enemy hp bar after 1 second
        if types.Actor.isDead(currentTargetActor.gameObject) or stance == types.Actor.STANCE.Nothing then
            stanceNoneTimer = stanceNoneTimer + dt
            if stanceNoneTimer > 1 then
                currentTargetActor = nil
                stanceNoneTimer = 0
            end
        else
            stanceNoneTimer = 0
        end
    end

    -- Update health and stamina widgets
    local hpOpacity = 0
    local staminaOpacity = 0
    if currentTargetActor then
        local healthStat = currentTargetActor:healthStat()
        local maxHealth = healthStat.base
        local hpFraction = healthStat.current/maxHealth

        -- Target actor was damaged: a decrease plays all relevant hp widget animations
        hpArc:setFraction(hpFraction, arcAngleFor(maxHealth, HP_ARC_RANGE), true, now)
        if widgetSettings["ShowHpWidget"] then hpOpacity = widgetSettings["HpWidgetOpacity"] end

        -- Stamina, on an arc sized by the target's max stamina
        local fatigueStat = widgetSettings["ShowStaminaWidget"] and currentTargetActor:fatigueStat()
        if fatigueStat and fatigueStat.base > 0 then
            local staminaFraction = util.clamp(fatigueStat.current/fatigueStat.base, 0, 1)
            local sinceStaminaHit = now - lastStaminaHitAt
            staminaArc:setFraction(staminaFraction, arcAngleFor(fatigueStat.base, STAMINA_ARC_RANGE),
                sinceStaminaHit <= STAMINA_HIT_WINDOW, now)

            if sinceStaminaHit <= STAMINA_SHOW_TIME or not widgetSettings["StaminaWidgetOnlyOnDamage"] then
                staminaOpacity = widgetSettings["StaminaWidgetOpacity"]
            end
        end
    end

    if isHudVisible then
        hpArc:fadeTo(hpOpacity, dt)
        staminaArc:fadeTo(staminaOpacity, dt)
    else
        hpArc:hide()
        staminaArc:hide()
    end

    hpArc:update(dt, now)
    staminaArc:update(dt, now)

    ui_elements.parentElement:update()
end

return {
    engineHandlers = {
        onUpdate = onUpdate,
    },
    eventHandlers = {
        [DEFS.e.HostileDamaged] = onHostileDamaged,
        [DEFS.e.StaminaDamaged] = onStaminaDamaged,
        [DEFS.e.MissedAttack] = onMissedAttack,
        [DEFS.e.GlobalVarValue] = ownership.onGlobalVarValue,
    },
    interfaceName = "DynamicReticle",
    interface = {
        version=1.1,
        setReticleWorldPos=setReticleWorldPos,
        -- setAlphaMultiplier(source, alpha): fade the reticle for as long as
        -- `source` asks; 1 or nil hands it back. Since 1.1.
        setAlphaMultiplier = setAlphaMultiplier,
        setReticleScreenPos = setReticleScreenPos,
        setCurrentEnemy = setCurrentEnemy
    }
}
