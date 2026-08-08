local M = {}

function M.setup()
	hl.window_rule({
		name = "suppress-maximize-events",
		match = {
			class = ".*",
		},
		suppress_event = "maximize",
	})

	hl.window_rule({
		name = "fix-xwayland-drags",
		match = {
			class = "^$",
			title = "^$",
			xwayland = true,
			float = true,
			fullscreen = false,
			pin = false,
		},
		no_focus = true,
	})

	hl.window_rule({
		name = "move-hyprland-run",
		match = {
			class = "hyprland-run",
		},
		move = "20 monitor_h-120",
		float = true,
	})

	hl.window_rule({
		name = "vesktop",
		match = {
			class = "^(vesktop)$",
		},
		workspace = "6",
	})

	hl.window_rule({
		name = "slack",
		match = {
			class = "^(Slack)$",
		},
		workspace = "6",
	})

	hl.window_rule({
		name = "tana",
		match = {
			class = "^(tana)$",
		},
		workspace = "2",
	})

	hl.window_rule({
		name = "vivaldi-pwa",
		match = {
			class = "^(Vivaldi-stable)",
		},
		tile = true,
	})
end

return M
