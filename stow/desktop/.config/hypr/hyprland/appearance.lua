local theme = require("hyprland.theme")

local M = {}

local state_home = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
local color_override_path = state_home .. "/zetshell/hyprland-colors.lua"

function M.setup()
    hl.config({
        general = {
            gaps_in = 8,
            gaps_out = 10,
            border_size = 3,
            col = {
                active_border = "rgba(23,147,209,0.5)",
                inactive_border = "rgba(0,0,0,0)",
            },
            resize_on_border = true,
            allow_tearing = false,
            layout = "dwindle",
        },
        decoration = {
            rounding = 10,
            rounding_power = 2,
            active_opacity = 0.9,
            inactive_opacity = 0.8,
            shadow = {
                enabled = true,
                range = 5,
                render_power = 3,
                color = "rgba(1a1a1aee)",
            },
            blur = {
                enabled = true,
                size = 8,
                passes = 3,
                new_optimizations = true,
                ignore_opacity = true,
                vibrancy = 0.1696,
            },
        },
    })

    local color_overrides, load_err = theme.load_lua_overrides(color_override_path)
    if color_overrides then
        hl.config(color_overrides)
    elseif load_err then
        print("failed to load dynamic hyprland colors: " .. tostring(load_err))
    end

    hl.config({
        animations = {
            enabled = true,
        },
    })

    hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
    hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
    hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
    hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
    hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

    hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
    hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
    hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
    hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
    hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
    hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
    hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
    hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
    hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
    hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
    hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
    hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
    hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
    hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
    hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
    hl.animation({ leaf = "zoomFactor", enabled = true, speed = 7, bezier = "quick" })

    hl.config({
        dwindle = {
            preserve_split = true,
        },
        master = {
            new_status = "master",
        },
        misc = {
            force_default_wallpaper = -1,
            disable_hyprland_logo = false,
        },
    })

    hl.layer_rule({
        blur = true,
        match = {
            namespace = "zetshell-bar",
        },
    })

    hl.layer_rule({
        ignore_alpha = 0,
        match = {
            namespace = "zetshell-bar",
        },
    })

    hl.layer_rule({
        blur = true,
        match = {
            namespace = "zetshell-app-launcher",
        },
    })

    hl.layer_rule({
        ignore_alpha = 0,
        match = {
            namespace = "zetshell-app-launcher",
        },
    })
end

return M
