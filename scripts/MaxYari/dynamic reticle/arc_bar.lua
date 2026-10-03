local mp = "scripts/MaxYari/dynamic reticle/"

local util = require("openmw.util")

local gutils = require(mp .. "gutils")
local Tweener = require(mp .. "tweener")

-- One arc of the hp widget shader: its size, the animations of a lost part and its opacity. The hp arc and
-- the stamina arc are one each, writing their own uniforms of the same shader.
local ArcBar = {}
ArcBar.__index = ArcBar

local SECTORS_LEN = 3
local NO_SECTOR = util.vector3(0, 0, 1)

-- `names` are this arc's uniforms: opacity, maxArc, curArc, tail, wave, sectors.
function ArcBar:new(shader, names)
    return setmetatable({
        u = shader.u,
        names = names,
        sectors = {},
        sectorsSent = false,
        tweeners = {},
        fraction = nil,
    }, self)
end

-- A new target: its arc starts without any animation of the previous one.
function ArcBar:reset()
    for key, tweener in pairs(self.tweeners) do
        tweener:finish()
        self.tweeners[key] = nil
    end
    self.sectors = {}
    self.sectorsSent = false
    self.fraction = nil
end

-- Wavy on-hit animation around the arc's current end.
function ArcBar:playWave()
    local u, name = self.u, self.names.wave
    local tweener = Tweener:new()
    tweener:add(0.3, Tweener.easings.easeOutCubic, function(t)
        u[name] = t
    end)
    self.tweeners.wave = tweener
end

-- The arc lost the part between fromAngle and toAngle (fromAngle > toAngle).
function ArcBar:playLoss(fromAngle, toAngle, now)
    -- Adding an animated sector for the part which was gone. If last added sector is still very fresh -
    -- update it
    local recentSector = self.sectors[#self.sectors]
    if recentSector and now - recentSector.startedAt <= recentSector.duration/3 then
        recentSector.startAngle = toAngle
        recentSector.startedAt = now
    else
        table.insert(self.sectors, {
            startAngle = toAngle,
            endAngle = fromAngle,
            startedAt = now,
            duration = 0.3
        })
    end
    if #self.sectors > SECTORS_LEN then table.remove(self.sectors, 1) end
    self.sectorsSent = false

    -- Adding a lingering damage tail
    local u, name = self.u, self.names.tail
    local tailAngle = u[name]
    if not tailAngle or fromAngle > tailAngle then tailAngle = fromAngle end
    local tweener = Tweener:new()
    tweener:add(2, Tweener.easings.easeInCubic, function(t)
        u[name] = gutils.lerp(tailAngle, toAngle, t)
    end)
    self.tweeners.tail = tweener
end

-- fraction: current/max of the stat. arcAngle: the full arc's size. lossIsDamage: whether a decrease since
-- the last update plays the loss animations; if not, the arc only shrinks, and the decrease is kept as
-- lastLoss so that a hit reported a moment later can still play them (see playLastLoss).
function ArcBar:setFraction(fraction, arcAngle, lossIsDamage, now)
    local u, names = self.u, self.names
    u[names.maxArc] = arcAngle
    u[names.curArc] = arcAngle*fraction

    local lastFraction = self.fraction
    self.fraction = fraction
    if lastFraction and fraction < lastFraction then
        if lossIsDamage then
            self:playLoss(arcAngle*lastFraction, arcAngle*fraction, now)
            self:playWave()
            self.lastLoss = nil
        else
            self.lastLoss = { from = arcAngle*lastFraction, to = arcAngle*fraction, at = now }
        end
    end
end

-- Plays the loss animations for a decrease that happened within `window` seconds and didn't play them.
function ArcBar:playLastLoss(now, window)
    local loss = self.lastLoss
    if loss and now - loss.at <= window then
        self:playLoss(loss.from, loss.to, now)
        self:playWave()
    end
    self.lastLoss = nil
end

function ArcBar:fadeTo(opacity, dt)
    local u, name = self.u, self.names.opacity
    u[name] = gutils.lerp(u[name], opacity, gutils.dtForLerp(dt, 5))
end

function ArcBar:hide()
    self.u[self.names.opacity] = 0
end

function ArcBar:update(dt, now)
    for _, tweener in pairs(self.tweeners) do
        tweener:tick(dt)
    end

    -- Sectors go to the shader while one animates, and once more when they're all done (they're invisible
    -- at the end), so an idle arc makes no new tables or vectors.
    if self.sectorsSent then return end
    local animating = false
    local uAnimatedSectors = {}
    for _, sectorTable in ipairs(self.sectors) do
        local prog = (now - sectorTable.startedAt)/sectorTable.duration
        if prog < 1 then animating = true end
        prog = Tweener.easings.easeOutCubic(prog)
        if prog > 1 then prog = 1 end
        table.insert(uAnimatedSectors, util.vector3(sectorTable.startAngle, sectorTable.endAngle, prog))
    end
    while #uAnimatedSectors < SECTORS_LEN do
        table.insert(uAnimatedSectors, NO_SECTOR)
    end
    self.u[self.names.sectors] = uAnimatedSectors
    self.sectorsSent = not animating
end

return ArcBar
