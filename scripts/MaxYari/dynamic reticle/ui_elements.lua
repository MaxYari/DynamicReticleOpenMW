local mp = "scripts/MaxYari/dynamic reticle/"
local ui = require("openmw.ui")
local util = require("openmw.util")
local storage = require("openmw.storage")

local gutils = require(mp .. "gutils")
local settings = require(mp .. "settings")
local reticleLayout = require(mp .. "reticle_layout")

local visualSettings = storage.playerSection('DynamicReticleVisualSettings')


-- Reticles
local reticleColor = visualSettings:get("ReticleColor")
local sneakArrowAlpha = visualSettings:get("SneakArrowsOpacity")
local reticleSneakScale = visualSettings:get("ReticleSneakScale")
local reticleScale = visualSettings:get("ReticleScale")

local animConf = {
    sneakArrowAlpha = sneakArrowAlpha,
    reticleSneakSizeMult = reticleSneakScale,
    sneakArrowPartFromDist = reticleLayout.ARROW_HIDDEN_DIST,
    sneakArrowPartToDist = reticleLayout.ARROW_SNEAK_DIST,
    sneakArrowStepBounceDist = 0.02, -- outward, on every footstep while sneaking
}

-- Create a parent element
local parentElement = ui.create({
    layer = 'HUD',
    type = ui.TYPE.Widget,
    props = {
        size = reticleLayout.WIDGET_SIZE,
        alpha = 1,
        relativePosition = util.vector2(0.5, 0.5),
        anchor = util.vector2(0.5, 0.5),
    },
    content = reticleLayout.content {
        reticlePath = settings.fileSelectors["Reticle"]:getFilePath(),
        arrowPaths = {
            l = settings.fileSelectors["StealthArrows"]:getFilePath("l"),
            r = settings.fileSelectors["StealthArrows"]:getFilePath("r"),
        },
        color = reticleColor,
        alpha = 0, -- the player script sets it for what is readied
        arrowAlpha = sneakArrowAlpha,
        scale = reticleScale,
        sneakScale = reticleSneakScale,
        sneak = 0,
    },
})

local function saveStartParams(el)
    if el.content then
        for name, child in pairs(el.content) do
            if not child.name then goto continue end
            saveStartParams(child)
            ::continue::
        end
    end
    if not el.userData then el.userData = {} end
    gutils.shallowMergeTables(el.userData, el.props)
end

saveStartParams(parentElement.layout)

-- Function to fetch elements by name
local function getElementByName(name)
    return parentElement.layout.content[name]
end

-- The images picked, by element; a texture is only made again when its image changes.
local function texturePaths()
    return {
        reticle = settings.fileSelectors["Reticle"]:getFilePath(),
        stealthArrowL = settings.fileSelectors["StealthArrows"]:getFilePath("l"),
        stealthArrowR = settings.fileSelectors["StealthArrows"]:getFilePath("r"),
    }
end
for name, path in pairs(texturePaths()) do getElementByName(name).userData.texturePath = path end

-- The reticle settings, applied again whenever they change (`helper`: the player script's settings
-- helper). Only what the animations don't set every frame: animConf, the base size and colour they start
-- from, and the textures. The player script redraws what it animates from these.
local function applySettings(helper)
    animConf.sneakArrowAlpha = helper["SneakArrowsOpacity"]
    animConf.reticleSneakSizeMult = helper["ReticleSneakScale"]

    local reticle = getElementByName("reticle")
    reticle.userData.size = reticleLayout.RETICLE_SIZE * helper["ReticleScale"]
    reticle.userData.color = helper["ReticleColor"]
    getElementByName("stealthArrowL").props.color = helper["ReticleColor"]
    getElementByName("stealthArrowR").props.color = helper["ReticleColor"]

    for name, path in pairs(texturePaths()) do
        local el = getElementByName(name)
        if path and path ~= el.userData.texturePath then
            el.userData.texturePath = path
            el.props.resource = ui.texture { path = path }
        end
    end
end


return {
    animConf = animConf,
    parentElement = parentElement,
    getElementByName = getElementByName,
    applySettings = applySettings,
}
