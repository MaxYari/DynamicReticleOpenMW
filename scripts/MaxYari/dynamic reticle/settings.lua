local I = require('openmw.interfaces')
local util = require("openmw.util")
local vfs = require("openmw.vfs")
local storage = require("openmw.storage")
local async = require("openmw.async")

local DEFS = require("scripts/MaxYari/dynamic reticle/defs")

local FileSelectInstances = {}

local FileSelect = {}
FileSelect.__index = FileSelect

function FileSelect:new(params)
    local instance = setmetatable({}, self)
    instance.key = params.key
    instance.description = params.description
    instance.folderPath = params.folderPath
    instance.withGroupingSuffix = params.withGroupingSuffix
    instance.settingsGroup = params.settingsGroup
    instance.cleanNames = {}
    instance.files = {}

    for filePath in vfs.pathsWithPrefix(instance.folderPath) do
        local fileName = filePath:match("([^/\\]+)$")
        local baseName = fileName:match("^(.-)%.") or fileName -- Remove file extension
        local cleanName, suffix = baseName, nil
        if instance.withGroupingSuffix then
            cleanName = baseName:match("^(.*)_") or baseName -- Match up to the last "_"
            suffix = baseName:sub(#cleanName + 2) -- +2 accounts for the underscore            
        end
        
        instance.cleanNames[cleanName] = true
        table.insert(instance.files, { cleanName = cleanName, fullPath = filePath, suffix = suffix })
    end

    FileSelectInstances[instance.key] = instance

    local items = {}    
    for cleanName, bool in pairs(instance.cleanNames) do
        table.insert(items, cleanName)
    end
    table.sort(items)

    -- For the preview: [cleanName] = path, or with a grouping suffix [cleanName] = { [suffix] = path }
    local paths = {}
    for _, file in ipairs(instance.files) do
        if instance.withGroupingSuffix then
            paths[file.cleanName] = paths[file.cleanName] or {}
            paths[file.cleanName][file.suffix] = file.fullPath
        else
            paths[file.cleanName] = file.fullPath
        end
    end

    local default = params.default and instance.cleanNames[params.default] and params.default or items[1]

    -- A picker with a preview of the image as the HUD draws it; the renderer lives in menu.lua.
    return {
        key = instance.key,
        renderer = 'drImageSelect',
        default = default,
        argument = {
            items = items,
            paths = paths,
            preview = params.preview,
        },
        name = params.name or instance.key,
        description = instance.description,
    }
end

function FileSelect:getFilePath(suffix)
    if not self.settings then
        self.settings = storage.playerSection(self.settingsGroup)
    end    
    local cleanName = self.settings:get(self.key)
    for _, file in ipairs(self.files) do
        if file.cleanName == cleanName and file.suffix == suffix then            
            return file.fullPath
        end
    end
    return nil
end


I.Settings.registerPage {
    key = 'DynamicReticlePage',
    l10n = 'DynamicReticle',
    name = 'Dynamic Reticle',
    description = "~~ Animated reticle and enemy hp and stamina widget (hit markers are in Combat Juice now).",
}

-- Reticle visibility ---------------------------------------------------------------------------------------
-- The reticle's opacity by what is readied, and presets of those. Picking a preset writes its opacities; an
-- opacity changed by hand makes the preset the one the opacities now match, or Custom.

local OPACITY_KEYS = { 'StowedOpacity', 'MeleeOpacity', 'RangedWeaponOpacity', 'RangedSpellOpacity', 'TouchSelfSpellOpacity' }
local PRESET_NAMES = { 'Normal', 'Immersive' }
local CUSTOM = 'Custom'
local PRESETS = {
    -- The reticle as it was before the presets: 0.75, and stowed 0.3 of that
    Normal = {
        StowedOpacity = 0.225,
        MeleeOpacity = 0.75,
        RangedWeaponOpacity = 0.75,
        RangedSpellOpacity = 0.75,
        TouchSelfSpellOpacity = 0.75,
    },
    Immersive = {
        StowedOpacity = 0,
        MeleeOpacity = 0,
        RangedWeaponOpacity = 0.5,
        RangedSpellOpacity = 0.5,
        TouchSelfSpellOpacity = 0,
    },
}

-- The preset that `values` (opacities by key) are, or CUSTOM. Typed-in numbers are compared with some slack.
local function matchingPreset(values)
    for _, name in ipairs(PRESET_NAMES) do
        local matches = true
        for _, key in ipairs(OPACITY_KEYS) do
            local value = values[key]
            if type(value) ~= 'number' or math.abs(value - PRESETS[name][key]) > 1e-4 then
                matches = false
                break
            end
        end
        if matches then return name end
    end
    return CUSTOM
end

-- The opacity used to be one setting (Reticle Opacity) and a multiplier of it for stowed (Stowed Reticle
-- Opacity), both in the Visuals group. Found there, they are carried over, once: drawn and readied take the
-- opacity, stowed the two multiplied, the sneak arrows the opacity, and the preset is the one that matches.
local function moveOpacitySettings()
    local visual = storage.playerSection(DEFS.settings.visual)
    local opacity = visual:get('ReticleOpacity')
    local stowed = visual:get('StowedReticleAlpha')
    if opacity == nil and stowed == nil then return end
    opacity = opacity or 0.75
    stowed = stowed or 0.3

    local values = {
        StowedOpacity = opacity * stowed,
        MeleeOpacity = opacity,
        RangedWeaponOpacity = opacity,
        RangedSpellOpacity = opacity,
        TouchSelfSpellOpacity = opacity,
    }
    local preset = matchingPreset(values)
    values = PRESETS[preset] or values
    local to = storage.playerSection(DEFS.settings.opacity)
    for _, key in ipairs(OPACITY_KEYS) do to:set(key, values[key]) end
    storage.playerSection(DEFS.settings.visibility):set('Preset', preset)

    if visual:get('SneakArrowsOpacity') == nil then visual:set('SneakArrowsOpacity', opacity) end
    visual:set('ReticleOpacity', nil)
    visual:set('StowedReticleAlpha', nil)
end
moveOpacitySettings()

I.Settings.registerGroup {
    key = DEFS.settings.visibility,
    page = 'DynamicReticlePage',
    l10n = 'DynamicReticle',
    name = 'Reticle Visibility',
    order = 1,
    permanentStorage = true,
    settings = {
        {
            key = 'Preset',
            renderer = 'select',
            default = 'Normal',
            argument = {
                l10n = 'DynamicReticle',
                items = { 'Normal', 'Immersive', CUSTOM },
            },
            name = 'Visibility Preset',
            description = "Normal: the reticle is always there, at different degrees of visibility for what you have readied.\nImmersive: the reticle is only there when you need it, when aiming a bow, crossbow, thrown weapon or ranged spell.\nA preset sets the opacities below; changing one of them makes it Custom."
        },
    },
}

local function opacitySetting(key, name, description)
    return {
        key = key,
        renderer = "number",
        default = PRESETS.Normal[key],
        argument = {
            min = 0,
            max = 1
        },
        name = name,
        description = description
    }
end

I.Settings.registerGroup {
    key = DEFS.settings.opacity,
    page = 'DynamicReticlePage',
    l10n = 'DynamicReticle',
    name = 'Reticle Opacity',
    description = "The reticle's opacity (0-1 range) for what you have readied. It fades to the new one when that changes.",
    order = 2,
    permanentStorage = true,
    settings = {
        opacitySetting('StowedOpacity', 'Stowed', "No weapon or spell readied."),
        opacitySetting('MeleeOpacity', 'Melee', "A melee weapon or bare hands, lockpicks and probes too."),
        opacitySetting('RangedWeaponOpacity', 'Ranged Weapon', "A bow, crossbow or thrown weapon."),
        opacitySetting('RangedSpellOpacity', 'Ranged Spell', "A spell or enchanted item with any on-target effect."),
        opacitySetting('TouchSelfSpellOpacity', 'Touch / Self Spell', "A spell or enchanted item with only touch and self effects."),
    },
}

-- Keeping the preset and the opacities in agreement. They are separate groups because a storage callback may
-- not write the section it handles. Callbacks run as a value is set, so `syncing` keeps one side's writes
-- from coming back to it.
local visibilitySection = storage.playerSection(DEFS.settings.visibility)
local opacitySection = storage.playerSection(DEFS.settings.opacity)
local syncing = false

local function sync(fn)
    syncing = true
    local ok, err = pcall(fn)
    syncing = false
    if not ok then print("[Dynamic Reticle] Reticle visibility preset: " .. tostring(err)) end
end

visibilitySection:subscribe(async:callback(function(_, key)
    if syncing or (key ~= nil and key ~= 'Preset') then return end
    local values = PRESETS[visibilitySection:get('Preset')]
    if not values then return end -- Custom: the opacities stay as they are
    sync(function()
        for _, opacityKey in ipairs(OPACITY_KEYS) do
            if opacitySection:get(opacityKey) ~= values[opacityKey] then
                opacitySection:set(opacityKey, values[opacityKey])
            end
        end
    end)
end))

opacitySection:subscribe(async:callback(function()
    if syncing then return end
    local preset = matchingPreset(opacitySection:asTable())
    if preset ~= visibilitySection:get('Preset') then
        sync(function() visibilitySection:set('Preset', preset) end)
    end
end))

local reticleSelect = FileSelect:new {
    key = 'Reticle',
    name = 'Reticle',
    description = "Any image found in 'textures/dynamic reticle/reticles/' will be selectable here.",
    folderPath = "textures/dynamic reticle/reticles/",
    withGroupingSuffix = false,
    default = "angle_brackets",
    settingsGroup = 'DynamicReticleVisualSettings',
    preview = 'reticle',
}
local stealthArrowsSelect = FileSelect:new {
    key = 'StealthArrows',
    name = 'Stealth Arrows',
    description = "Any image found in 'textures/dynamic reticle/stealth/' will be selectable here.",
    folderPath = "textures/dynamic reticle/stealth/",
    withGroupingSuffix = true,
    settingsGroup = 'DynamicReticleVisualSettings',
    preview = 'sneak',
}
-- The sneak preview draws the chosen reticle too, at its sneak size
stealthArrowsSelect.argument.reticlePaths = reticleSelect.argument.paths

local SNEAK_ARROWS_OPACITY_ARGUMENT = { min = 0, max = 1 }

I.Settings.registerGroup {
    key = DEFS.settings.visual,
    page = 'DynamicReticlePage',
    l10n = 'DynamicReticle',
    name = 'Visuals',
    order = 3,
    permanentStorage = true,
    settings = {
        reticleSelect,
        stealthArrowsSelect,
        {
            key = 'ReticleColor',
            renderer = 'color',
            default = util.color.hex("caa676"),
            name = 'Reticle Color'
        },
        {
            key = 'SneakArrowsUseReticleOpacity',
            renderer = 'checkbox',
            default = false,
            name = 'Sneak Arrows Use Reticle Opacity',
            description = "The arrows around the reticle while sneaking take the reticle's opacity for what you have readied (Reticle Opacity, above) instead of their own."
        },
        {
            key = 'SneakArrowsOpacity',
            renderer = "number",
            default = 0.75,
            argument = SNEAK_ARROWS_OPACITY_ARGUMENT,
            name = "Sneak Arrows Opacity",
            description = "The arrows' own opacity, whatever is readied. The visibility presets leave it as it is."
        },
        {
            key = 'MissedReticleAlpha',
            renderer = "number",
            default = 0.3,
            argument = {
                min = 0,
                max = 1
            },
            name = "Missed Reticle Opacity",
            description = "Temporarily fades-out to this opacity level (0-1 range) when your attack misses."
        },
        {
            key = 'ReticleScale',
            renderer = "number",
            default = 0.75,
            argument = {
                min = 0,
                max = 10
            },
            name = "Reticle Size Multiplier"
        },
        {
            key = 'ReticleSneakScale',
            renderer = "number",
            default = 0.66,
            argument = {
                min = 0.1,
                max = 1
            },
            name = "Reticle Sneak Scale",
            description = "Adjust the size multiplier for the reticle when sneaking."
        },
        {
            key = 'SneakStepBounceStrength',
            renderer = "number",
            default = 0.75,
            argument = {
                min = 0,
                max = 5
            },
            name = "Sneak Reticle Step Bounce Strength",
            description = "How far the sneak arrows bounce out on every footstep while sneaking. 0 turns the bounce off."
        },
        {
            key = 'OwnedReticle',
            renderer = 'checkbox',
            default = true,
            name = 'Tint Reticle Over Owned Things',
            description = "Tints the reticle when taking or using what's under it would be a crime, under the same rules that turn the engine's tooltip red ('Show owned' in the launcher): owned items, containers and beds, locked or trapped owned doors, and pickpocketing while sneaking."
        },
        {
            key = 'OwnedReticleColor',
            renderer = 'color',
            default = util.color.hex("c8412e"),
            name = 'Owned Reticle Color'
        },
    },
}

-- Sneak Arrows Opacity is greyed out while the arrows use the reticle's
local visualSection = storage.playerSection(DEFS.settings.visual)
local function updateSneakArrowsOpacityArgument()
    I.Settings.updateRendererArgument(DEFS.settings.visual, 'SneakArrowsOpacity', {
        min = SNEAK_ARROWS_OPACITY_ARGUMENT.min,
        max = SNEAK_ARROWS_OPACITY_ARGUMENT.max,
        disabled = visualSection:get('SneakArrowsUseReticleOpacity') == true,
    })
end
updateSneakArrowsOpacityArgument()
visualSection:subscribe(async:callback(function(_, key)
    if key == nil or key == 'SneakArrowsUseReticleOpacity' then updateSneakArrowsOpacityArgument() end
end))

-- The hp and stamina widget's settings used to be in the Visuals group. A value found there is carried
-- over, once, so the move doesn't reset what was set.
local WIDGET_KEYS = {
    'ShowHpWidget', 'HpWidgetColor', 'HpWidgetOpacity', 'HpWidgetDamageColor', 'HpWidgetScale',
    'ShowStaminaWidget', 'StaminaWidgetOnlyOnDamage', 'StaminaWidgetColor', 'StaminaWidgetOpacity',
    'StaminaWidgetDamageColor', 'StaminaWidgetThickness',
}
local function moveWidgetSettings()
    local from = storage.playerSection(DEFS.settings.visual)
    local to = storage.playerSection(DEFS.settings.widget)
    for _, key in ipairs(WIDGET_KEYS) do
        local value = from:get(key)
        if value ~= nil then
            if to:get(key) == nil then to:set(key, value) end
            from:set(key, nil)
        end
    end
end
moveWidgetSettings()

I.Settings.registerGroup {
    key = DEFS.settings.widget,
    page = 'DynamicReticlePage',
    l10n = 'DynamicReticle',
    name = 'Enemy HP & Stamina Widget',
    order = 4,
    permanentStorage = true,
    settings = {
        {
            key = 'ShowHpWidget',
            renderer = 'checkbox',
            default = true,
            name = 'Show Enemy HP Widget',
            description = "Displays a subtle enemy hp widget under the reticle in combat."
        },
        {
            key = 'HpWidgetColor',
            renderer = 'color',
            default = util.color.rgb(0.792, 0.651, 0.463),
            name = 'Hp Widget Color'
        },
        {
            key = 'HpWidgetOpacity',
            renderer = "number",
            default = 1,
            argument = {
                min = 0,
                max = 1
            },
            name = "Hp Widget Opacity"
        },
        {
            key = 'HpWidgetDamageColor',
            renderer = 'color',            
            default = util.color.hex("590211"),
            name = 'Hp Widget Damage Color'
        },
        {
            key = "HpWidgetScale",
            renderer = "number",
            default = 1.1,
            argument = {
                min = 0.1,
                max = 10
            },
            name = "Hp Widget Size Multiplier"
        },
        {
            key = 'ShowStaminaWidget',
            renderer = 'checkbox',
            default = true,
            name = 'Show Enemy Stamina Widget',
            description = "A thinner arc just inside the hp widget with the enemy's stamina (fatigue)."
        },
        {
            key = 'StaminaWidgetOnlyOnDamage',
            renderer = 'checkbox',
            default = true,
            name = 'Stamina Only After Stamina Damage',
            description = "Shows the stamina arc only for 3 seconds after the enemy's stamina was hit (hand-to-hand, for one). Off: shown whenever the hp widget is."
        },
        {
            key = 'StaminaWidgetColor',
            renderer = 'color',
            default = util.color.hex("ffffff"),
            name = 'Stamina Widget Color'
        },
        {
            key = 'StaminaWidgetOpacity',
            renderer = "number",
            default = 0.75,
            argument = {
                min = 0,
                max = 1
            },
            name = "Stamina Widget Opacity"
        },
        {
            key = 'StaminaWidgetDamageColor',
            renderer = 'color',
            default = util.color.hex("285e32"),
            name = 'Stamina Widget Damage Color'
        },
        {
            key = "StaminaWidgetThickness",
            renderer = "number",
            default = 0.75,
            argument = {
                min = 0.1,
                max = 5
            },
            name = "Stamina Widget Thickness",
            description = "Relative to the hp widget's."
        }
    },
}

return {
    fileSelectors = FileSelectInstances,
}
