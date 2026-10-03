local prefix = "DR_"

return {
    GUtoM = 69.99,
    -- The Reticle Opacity settings for what is readied
    readiedOpacityKeys = { 'StowedOpacity', 'MeleeOpacity', 'RangedWeaponOpacity', 'RangedSpellOpacity', 'TouchSelfSpellOpacity' },
    settings = {
        visual = "DynamicReticleVisualSettings",
        widget = "DynamicReticleWidgetSettings",
        visibility = "DynamicReticleVisibilitySettings",
        opacity = "DynamicReticleOpacitySettings",
    },
    e = {
        HostileDamaged = prefix .. "HostileDamaged",
        StaminaDamaged = prefix .. "StaminaDamaged",
        MissedAttack = prefix .. "MissedAttack",
        GlobalVarRequest = prefix .. "GlobalVarRequest",
        GlobalVarValue = prefix .. "GlobalVarValue",
    }
}
