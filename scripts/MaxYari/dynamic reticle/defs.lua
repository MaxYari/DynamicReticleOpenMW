local prefix = "DR_"

return {
    GUtoM = 69.99,
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
