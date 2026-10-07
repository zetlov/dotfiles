local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.default_domain = "WSL:archlinux"

config.font = wezterm.font_with_fallback({
	"JetBrainsMono Nerd Font",
	"Noto Sans Mono CJK JP",
})
config.font_size = 13

config.default_cursor_style = "SteadyBar"
config.hide_mouse_cursor_when_typing = true

config.color_scheme = "Catppuccin Mocha"
config.window_background_opacity = 0.9
config.window_decorations = "RESIZE"
config.window_padding = {
	left = 0,
	right = 0,
	top = 0,
	bottom = 0,
}

config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = true

config.inactive_pane_hsb = {
	saturation = 0.85,
	brightness = 0.75,
}

config.keys = {
	{
		key = "Enter",
		mods = "SHIFT",
		action = wezterm.action.SendKey({ key = "j", mods = "CTRL" }),
	},
}

config.window_background_gradient = {
	orientation = "Vertical",
	colors = {
		"#08090d",
		"#0a0e16",
		"#0d1422",
	},
}

config.window_close_confirmation = "NeverPrompt"

return config
