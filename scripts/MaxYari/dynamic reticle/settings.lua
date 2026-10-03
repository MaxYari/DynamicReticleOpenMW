local I = require('openmw.interfaces')
local util = require("openmw.util")
local vfs = require("openmw.vfs")
local storage = require("openmw.storage")
local async = require("openmw.async")

local DEFS = require("scripts/MaxYari/dynamic reticle/defs")

local FileSelectInstances = {}

-- Most settings here use ownlyme's Super Settings Renderers (https://www.nexusmods.com/morrowind/mods/59673), bundled in
-- SuperSettingsRenderers/ as menu scripts: SuperSlider6 for opacities, SuperColorPicker4 for colors and SuperSelect3
-- for the visibility preset. Sizes and strengths stay plain number fields, without an upper bound.

-- A SuperSlider6 argument. Every setting needs a table of its own, and the default again for the default mark.
local function slider(min, max, step, default, extra)
    local argument = { min = min, max = max, step = step, default = default, showDefaultMark = true, width = 150, thickness = 14 }
    for key, value in pairs(extra or {}) do argument[key] = value end
    return argument
end

-- Color picker swatches: this mod's default colors, then the picker's usual Morrowind palette
local function colorArgument()
    return {
        presetColors = {
            "caa676", "c8412e", "590211", "ffffff", "285e32",
            "caa560", "d4b77f", "dfc99f", "eee2c9", "253170", "3a4daf", "6070ca", "707ecf", "c83c1e", "35459f", "00963c",
        },
    }
end

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

local OPACITY_KEYS = DEFS.readiedOpacityKeys
local PRESET_NAMES = { 'Normal', 'Immersive' }
local CUSTOM = 'Custom'
local NORMAL = {
    StowedOpacity = 0.2,
    MeleeOpacity = 0.2,
    RangedWeaponOpacity = 0.5,
    RangedSpellOpacity = 0.5,
    TouchSelfSpellOpacity = 0.2,
}
local PRESETS = {
    Normal = NORMAL,
    -- Normal, with the reticle hidden unless aiming: never more visible than Normal
    Immersive = {
        StowedOpacity = 0,
        MeleeOpacity = 0,
        RangedWeaponOpacity = NORMAL.RangedWeaponOpacity,
        RangedSpellOpacity = NORMAL.RangedSpellOpacity,
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
            renderer = 'SuperSelect3',
            default = 'Normal',
            argument = { items = { 'Normal', 'Immersive', CUSTOM }, width = 160 },
            name = 'Visibility Preset',
            description = "Normal: the reticle is always there, at different degrees of visibility for what you have readied.\nImmersive: the reticle is only there when you need it, when aiming a bow, crossbow, thrown weapon or ranged spell.\nA preset sets the opacities for what is readied below; changing one of them makes it Custom."
        },
    },
}

local function opacitySetting(key, name, description)
    return {
        key = key,
        renderer = "SuperSlider6",
        default = PRESETS.Normal[key],
        argument = slider(0, 1, 0.05, PRESETS.Normal[key]),
        name = name,
        description = description
    }
end

I.Settings.registerGroup {
    key = DEFS.settings.opacity,
    page = 'DynamicReticlePage',
    l10n = 'DynamicReticle',
    name = 'Reticle Opacity',
    description = "The reticle's opacity (0-1 range) for what you have readied, and multipliers of it while sneaking and in third person. It fades to the new one when that changes.",
    order = 2,
    permanentStorage = true,
    settings = {
        opacitySetting('StowedOpacity', 'Stowed', "No weapon or spell readied."),
        opacitySetting('MeleeOpacity', 'Melee', "A melee weapon or bare hands, lockpicks and probes too."),
        opacitySetting('RangedWeaponOpacity', 'Ranged Weapon', "A bow, crossbow or thrown weapon."),
        opacitySetting('RangedSpellOpacity', 'Ranged Spell', "A spell or enchanted item with any on-target effect."),
        opacitySetting('TouchSelfSpellOpacity', 'Touch / Self Spell', "A spell or enchanted item with only touch and self effects."),
        {
            key = 'SneakingOpacityMult',
            renderer = "SuperSlider6",
            default = 1,
            argument = slider(0, 1, 0.05, 1),
            name = 'While Sneaking',
            description = "Multiplies the reticle's opacity while sneaking, 0 hides it then. The sneak arrows keep their own opacity (Visuals)."
        },
        {
            key = 'ThirdPersonOpacityMult',
            renderer = "SuperSlider6",
            default = 0,
            argument = slider(0, 1, 0.05, 0),
            name = 'In Third Person',
            description = "Multiplies the opacity of the reticle and the sneak arrows in third person view. At 0 the reticle is hidden in third person."
        },
    },
}

-- Keeping the preset and the opacities in agreement. They are separate groups because a storage callback may
-- not write the section it handles. Callbacks run as a value is set, so `syncing` keeps one side's writes
-- from coming back to it.
local visibilitySection = storage.playerSection(DEFS.settings.visibility)
local opacitySection = storage.playerSection(DEFS.settings.opacity)
local syncing = false

-- On load: a preset's opacities may have changed since they were stored (a new version), and Custom
-- opacities may be a preset's by now.
local function reconcilePreset()
    local preset = visibilitySection:get('Preset')
    local values = PRESETS[preset]
    if values then
        for _, key in ipairs(OPACITY_KEYS) do
            if opacitySection:get(key) ~= values[key] then opacitySection:set(key, values[key]) end
        end
    else
        local matching = matchingPreset(opacitySection:asTable())
        if matching ~= preset then visibilitySection:set('Preset', matching) end
    end
end
reconcilePreset()

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
    default = "rhombus_tear",
    settingsGroup = 'DynamicReticleVisualSettings',
    preview = 'sneak',
}
-- The sneak preview draws the chosen reticle too, at its sneak size
stealthArrowsSelect.argument.reticlePaths = reticleSelect.argument.paths

-- Greyed out while the arrows use the reticle's opacity
local function sneakArrowsOpacityArgument(disabled)
    return slider(0, 1, 0.05, 0.75, { disabled = disabled })
end

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
            renderer = 'SuperColorPicker4',
            argument = colorArgument(),
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
            renderer = "SuperSlider6",
            default = 0.75,
            argument = sneakArrowsOpacityArgument(false),
            name = "Sneak Arrows Opacity",
            description = "The arrows' own opacity, whatever is readied. The visibility presets leave it as it is."
        },
        {
            key = 'MissedReticleAlpha',
            renderer = "SuperSlider6",
            default = 0.1,
            argument = slider(0, 1, 0.05, 0.1),
            name = "Missed Reticle Opacity",
            description = "Temporarily fades-out to this opacity level (0-1 range) when your attack misses."
        },
        {
            key = 'ReticleScale',
            renderer = "number",
            default = 1,
            argument = { min = 0 },
            name = "Reticle Size Multiplier"
        },
        {
            key = 'ReticleSneakScale',
            renderer = "SuperSlider6",
            default = 0.8,
            argument = slider(0.1, 1, 0.01, 0.8),
            name = "Reticle Sneak Scale",
            description = "Adjust the size multiplier for the reticle when sneaking."
        },
        {
            key = 'SneakStepBounceStrength',
            renderer = "number",
            default = 0.75,
            argument = { min = 0 },
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
            renderer = 'SuperColorPicker4',
            argument = colorArgument(),
            default = util.color.hex("c8412e"),
            name = 'Owned Reticle Color'
        },
    },
}

-- Sneak Arrows Opacity is greyed out while the arrows use the reticle's
local visualSection = storage.playerSection(DEFS.settings.visual)
local function updateSneakArrowsOpacityArgument()
    I.Settings.updateRendererArgument(DEFS.settings.visual, 'SneakArrowsOpacity',
        sneakArrowsOpacityArgument(visualSection:get('SneakArrowsUseReticleOpacity') == true))
end
updateSneakArrowsOpacityArgument()
visualSection:subscribe(async:callback(function(_, key)
    if key == nil or key == 'SneakArrowsUseReticleOpacity' then updateSneakArrowsOpacityArgument() end
end))

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
            default = false,
            name = 'Show Enemy HP Widget',
            description = "Displays a subtle enemy hp widget under the reticle in combat."
        },
        {
            key = 'HpWidgetColor',
            renderer = 'SuperColorPicker4',
            argument = colorArgument(),
            default = util.color.rgb(0.792, 0.651, 0.463),
            name = 'Hp Widget Color'
        },
        {
            key = 'HpWidgetOpacity',
            renderer = "SuperSlider6",
            default = 1,
            argument = slider(0, 1, 0.05, 1),
            name = "Hp Widget Opacity"
        },
        {
            key = 'HpWidgetDamageColor',
            renderer = 'SuperColorPicker4',
            argument = colorArgument(),            
            default = util.color.hex("590211"),
            name = 'Hp Widget Damage Color'
        },
        {
            key = "HpWidgetScale",
            renderer = "number",
            default = 1.1,
            argument = { min = 0.1 },
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
            renderer = 'SuperColorPicker4',
            argument = colorArgument(),
            default = util.color.hex("ffffff"),
            name = 'Stamina Widget Color'
        },
        {
            key = 'StaminaWidgetOpacity',
            renderer = "SuperSlider6",
            default = 0.5,
            argument = slider(0, 1, 0.05, 0.5),
            name = "Stamina Widget Opacity"
        },
        {
            key = 'StaminaWidgetDamageColor',
            renderer = 'SuperColorPicker4',
            argument = colorArgument(),
            default = util.color.hex("285e32"),
            name = 'Stamina Widget Damage Color'
        },
        {
            key = "StaminaWidgetThickness",
            renderer = "number",
            default = 0.1,
            argument = { min = 0.1 },
            name = "Stamina Widget Thickness",
            description = "Relative to the hp widget's."
        }
    },
}

return {
    fileSelectors = FileSelectInstances,
}
