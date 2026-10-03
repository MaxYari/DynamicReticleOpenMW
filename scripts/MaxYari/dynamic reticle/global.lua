local mp = "scripts/MaxYari/dynamic reticle/"

local world = require("openmw.world")

local DEFS = require(mp .. "defs")

-- Reads mwscript global variables for the player script, which can't (see ownership.lua).
local function readGlobal(player, name)
    return world.mwscript.getGlobalVariables(player)[name]
end

return {
    eventHandlers = {
        [DEFS.e.GlobalVarRequest] = function(e)
            local ok, value = pcall(readGlobal, e.player, e.name)
            e.player:sendEvent(DEFS.e.GlobalVarValue, { name = e.name, value = ok and value or nil })
        end,
    },
}
