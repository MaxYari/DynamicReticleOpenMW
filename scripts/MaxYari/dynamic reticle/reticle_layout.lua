local ui = require("openmw.ui")
local util = require("openmw.util")

-- The reticle and the sneak arrows, laid out the way the HUD draws them. The HUD makes its element from
-- this and animates the props; the settings previews (menu.lua) draw it at rest.
local layout = {
    -- The widget the three sit in, and their sizes at a Reticle Size Multiplier of 1
    WIDGET_SIZE = util.vector2(200, 200),
    RETICLE_SIZE = util.vector2(21, 21),
    ARROW_SIZE = util.vector2(30.5, 7) * 0.75,
    -- The arrows' distance from the middle, relative to the widget: hidden, and shown while sneaking
    ARROW_HIDDEN_DIST = 0.25,
    ARROW_SNEAK_DIST = 0.1,
}

local CENTER = util.vector2(0.5, 0.5)

local function arrow(name, path, anchorX, direction, dist, opts)
    return {
        name = name,
        type = ui.TYPE.Image,
        props = {
            alpha = util.clamp(opts.alpha * opts.sneak, 0, 1),
            color = opts.color,
            size = layout.ARROW_SIZE,
            relativePosition = CENTER + direction * dist,
            anchor = util.vector2(anchorX, 0.5),
            resource = ui.texture { path = path },
        },
        userData = { direction = direction },
    }
end

-- opts: reticlePath, arrowPaths ({ l, r }; nil for no arrows), color, alpha, arrowAlpha (the arrows' when
-- shown; alpha if nil), scale (Reticle Size Multiplier), sneakScale (Reticle Sneak Scale), sneak (0 not
-- sneaking .. 1 sneaking).
function layout.content(opts)
    local sneak = opts.sneak or 0
    local sneakScale = 1 + ((opts.sneakScale or 1) - 1) * sneak
    local content = {
        {
            name = "reticle",
            type = ui.TYPE.Image,
            props = {
                alpha = opts.alpha,
                color = opts.color,
                size = layout.RETICLE_SIZE * opts.scale * sneakScale,
                relativePosition = CENTER,
                anchor = CENTER,
                resource = ui.texture { path = opts.reticlePath },
            },
            userData = {},
        },
    }
    if opts.arrowPaths then
        local arrowOpts = { alpha = opts.arrowAlpha or opts.alpha, color = opts.color, sneak = sneak }
        local dist = layout.ARROW_HIDDEN_DIST + (layout.ARROW_SNEAK_DIST - layout.ARROW_HIDDEN_DIST) * sneak
        table.insert(content, arrow("stealthArrowL", opts.arrowPaths.l, 1, util.vector2(-1, 0), dist, arrowOpts))
        table.insert(content, arrow("stealthArrowR", opts.arrowPaths.r, 0, util.vector2(1, 0), dist, arrowOpts))
    end
    return ui.content(content)
end

return layout
