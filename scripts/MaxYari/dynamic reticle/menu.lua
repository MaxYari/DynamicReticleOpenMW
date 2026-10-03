-- Menu-side half of the settings: the reticle and stealth arrow pickers, each with a preview of what is
-- picked. Custom setting renderers may only be registered from a menu script.

local ui = require("openmw.ui")
local util = require("openmw.util")
local async = require("openmw.async")
local storage = require("openmw.storage")
local I = require("openmw.interfaces")

local mp = "scripts/MaxYari/dynamic reticle/"
local reticleLayout = require(mp .. "reticle_layout")
local DEFS = require(mp .. "defs")

local visualSettings = storage.playerSection(DEFS.settings.visual)
local opacitySettings = storage.playerSection(DEFS.settings.opacity)

local function label(text, size)
    return {
        type = ui.TYPE.Text,
        props = {
            text = text,
            textSize = size or 15,
            textColor = util.color.rgb(0.87, 0.816, 0.702),
        },
    }
end

local function button(text, onClick)
    return {
        type = ui.TYPE.Container,
        content = ui.content {
            {
                type = ui.TYPE.Text,
                props = {
                    text = text,
                    textSize = 15,
                    textColor = util.color.rgb(0.792, 0.651, 0.463),
                },
                events = { mouseClick = async:callback(onClick) },
            },
        },
    }
end

local function prettify(name)
    return (name:gsub("_", " "))
end

-- "< name >": steps through `items`, wrapping round at either end.
local function stepper(items, value, text, set)
    local index = 1
    for i, item in ipairs(items) do
        if item == value then index = i end
    end

    local function step(by)
        if #items == 0 then return end
        set(items[(index - 1 + by) % #items + 1])
    end

    return {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            button(" < ", function() step(-1) end),
            {
                type = ui.TYPE.Widget,
                props = { size = util.vector2(150, 20) },
                content = ui.content { label(text) },
            },
            button(" > ", function() step(1) end),
        },
    }
end

-- Previews ----------------------------------------------------------------------
--
-- Drawn the way the HUD draws them, by the same layout function, at rest: the reticle as it is when not
-- sneaking, or sneaking, with the arrows out and the reticle at its sneak size. In the reticle's colour
-- and sizes, the reticle at its most visible opacity and the arrows at theirs (or the reticle's, when they
-- use it). The backdrop is a dark, blurred still (Combat Juice's hit marker one), so the reticle is judged
-- against something like the game rather than against the menu.

local PREVIEW_SIZE = util.vector2(168, 170) -- the backdrop's own size, drawn 1:1
local backdrop = ui.texture { path = "textures/dynamic reticle/preview_backdrop.png" }

-- The highest of the Reticle Opacity settings
local function mostVisibleAlpha()
    local alpha = 0
    for _, value in pairs(opacitySettings:asTable()) do
        if type(value) == 'number' and value > alpha then alpha = value end
    end
    return alpha
end

-- kind: 'reticle' or 'sneak'. value: the image picked. argument: the setting's, with its images' paths.
local function previewLayout(kind, value, argument)
    local paths = argument.paths or {}
    local opts = {
        color = visualSettings:get('ReticleColor'),
        alpha = mostVisibleAlpha(),
        scale = visualSettings:get('ReticleScale') or 1,
        sneakScale = visualSettings:get('ReticleSneakScale') or 1,
    }
    if visualSettings:get('SneakArrowsUseReticleOpacity') then
        opts.arrowAlpha = opts.alpha
    else
        opts.arrowAlpha = visualSettings:get('SneakArrowsOpacity') or 1
    end
    if kind == 'sneak' then
        opts.reticlePath = argument.reticlePaths and argument.reticlePaths[visualSettings:get('Reticle')]
        opts.arrowPaths = paths[value]
        opts.sneak = 1
    else
        opts.reticlePath = paths[value]
        opts.sneak = 0
    end

    local drawn = {}
    if opts.reticlePath then
        drawn = {
            type = ui.TYPE.Widget,
            props = {
                size = reticleLayout.WIDGET_SIZE,
                relativePosition = util.vector2(0.5, 0.5),
                anchor = util.vector2(0.5, 0.5),
            },
            content = reticleLayout.content(opts),
        }
    end

    return {
        template = I.MWUI.templates.box,
        content = ui.content {
            {
                type = ui.TYPE.Widget,
                props = { size = PREVIEW_SIZE },
                content = ui.content {
                    {
                        type = ui.TYPE.Image,
                        props = { relativeSize = util.vector2(1, 1), resource = backdrop },
                    },
                    drawn,
                },
            },
        },
    }
end

-- The previews on screen, by kind. The settings page only redraws the setting that changed, so the
-- reticle's colour, opacities and sizes (and, for the sneak preview, the reticle picked) have to be
-- followed here. A preview the page has since thrown away ignores the update.
local previews = {}
local PREVIEW_INPUTS = {
    Reticle = true,
    ReticleColor = true,
    SneakArrowsOpacity = true,
    SneakArrowsUseReticleOpacity = true,
    ReticleScale = true,
    ReticleSneakScale = true,
}

local function redrawPreviews()
    for kind, preview in pairs(previews) do
        preview.element.layout = previewLayout(kind, preview.value, preview.argument)
        preview.element:update()
    end
end

visualSettings:subscribe(async:callback(function(_, key)
    if key ~= nil and not PREVIEW_INPUTS[key] then return end
    redrawPreviews()
end))
opacitySettings:subscribe(async:callback(redrawPreviews))

I.Settings.registerRenderer('drImageSelect', function(value, set, argument)
    argument = argument or {}
    local items = argument.items or {}
    local kind = argument.preview or 'reticle'

    local preview = ui.create(previewLayout(kind, value, argument))
    previews[kind] = { element = preview, value = value, argument = argument }

    return {
        type = ui.TYPE.Flex,
        props = { arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            stepper(items, value, prettify(tostring(value)), set),
            { props = { size = util.vector2(0, 6) }, type = ui.TYPE.Widget },
            preview,
        },
    }
end)
