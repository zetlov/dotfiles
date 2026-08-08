local M = {}

function M.setup(settings)
	hl.config({
		input = {
			kb_layout = "us",
			kb_variant = "",
			kb_model = "",
			kb_options = "",
			kb_rules = "",
			follow_mouse = 1,
			sensitivity = 0,
			touchpad = {
				natural_scroll = false,
			},
			tablet = {
				output = settings.main_monitor,
				left_handed = true,
			},
		},
	})

	hl.gesture({
		fingers = 3,
		direction = "horizontal",
		action = "workspace",
	})

	hl.device({
		name = "ydotoold-virtual-device",
		kb_layout = "us",
	})
end

return M
