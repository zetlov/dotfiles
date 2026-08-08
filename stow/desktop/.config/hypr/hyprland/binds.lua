local M = {}

local workspace_keys = {
	{ key = "1", workspace = "1" },
	{ key = "2", workspace = "2" },
	{ key = "3", workspace = "3" },
	{ key = "4", workspace = "4" },
	{ key = "5", workspace = "5" },
	{ key = "6", workspace = "6" },
	{ key = "7", workspace = "7" },
	{ key = "8", workspace = "8" },
	{ key = "9", workspace = "9" },
	{ key = "0", workspace = "10" },
	{ key = "minus", workspace = "11" },
}

local function bind_exec(keys, cmd, opts, rules)
	hl.bind(keys, hl.dsp.exec_cmd(cmd, rules), opts)
end

function M.setup(settings)
	local main_mod = settings.main_mod
	local sub_mod = settings.sub_mod

	bind_exec(main_mod .. " + RETURN", settings.terminal)
	hl.bind(main_mod .. " + Q", hl.dsp.window.close())
	bind_exec(main_mod .. " + SPACE", "qs -c zetshell ipc call appLauncher toggle")
	bind_exec(
		main_mod .. " + SHIFT + M",
		"command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"
	)
	bind_exec(main_mod .. " + B", settings.browser)

	bind_exec(main_mod .. " + t", "~/.config/rofi/scripts/task.sh")
	bind_exec(main_mod .. " + m", "~/.local/bin/switch_audio.sh")
	bind_exec(main_mod .. " + w", "qs -c zetshell ipc call wallpaperLauncher toggle")
	bind_exec("SUPER + n", "qs -c zetshell ipc call notifications toggleCenter")
	bind_exec("SUPER + c", "qs -c zetshell ipc call controlCenter toggle")
	bind_exec("SUPER + d", "qs -c zetshell ipc call dashboard toggleHome")

	bind_exec(main_mod .. " + v", "hyprvoice toggle")
	hl.bind(main_mod .. " + v", hl.dsp.exec_cmd("hyprvoice toggle"), {
		release = true,
	})

	bind_exec(main_mod .. " + s", "qs -c zetshell ipc call picker open region clipboard")
	bind_exec("SHIFT + " .. main_mod .. " + s", "qs -c zetshell ipc call picker open window clipboard")
	bind_exec("CONTROL + " .. main_mod .. " + s", "qs -c zetshell ipc call captureLauncher open clipboard")

	bind_exec(main_mod .. " + r", "qs -c zetshell ipc call record toggle true")
	bind_exec("SHIFT + " .. main_mod .. " + r", "qs -c zetshell ipc call record openLauncher")
	bind_exec(main_mod .. " + P", "playerctl --player spotify play-pause")

	bind_exec(sub_mod .. " + p", "~/.config/hypr/scripts/pomodoro.sh toggle")
	bind_exec("SHIFT + " .. sub_mod .. " + p", "~/.config/hypr/scripts/pomodoro.sh reset")
	bind_exec("CONTROL + " .. sub_mod .. " + p", "~/.config/hypr/scripts/pomodoro.sh cycle")

	hl.bind(main_mod .. " + h", hl.dsp.focus({ direction = "l" }))
	hl.bind(main_mod .. " + l", hl.dsp.focus({ direction = "r" }))
	hl.bind(main_mod .. " + k", hl.dsp.focus({ direction = "u" }))
	hl.bind(main_mod .. " + j", hl.dsp.focus({ direction = "d" }))

	hl.bind(main_mod .. " + CTRL + h", hl.dsp.window.move({ direction = "l" }))
	hl.bind(main_mod .. " + CTRL + l", hl.dsp.window.move({ direction = "r" }))
	hl.bind(main_mod .. " + CTRL + k", hl.dsp.window.move({ direction = "u" }))
	hl.bind(main_mod .. " + CTRL + j", hl.dsp.window.move({ direction = "d" }))

	for _, mapping in ipairs(workspace_keys) do
		hl.bind(main_mod .. " + " .. mapping.key, hl.dsp.focus({ workspace = mapping.workspace }))
		hl.bind(main_mod .. " + SHIFT + " .. mapping.key, hl.dsp.window.move({ workspace = mapping.workspace }))
	end

	hl.bind(main_mod .. " + F", hl.dsp.window.float({ action = "toggle" }))
	hl.bind(main_mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ action = "toggle" }))
	hl.bind(main_mod .. " + SHIFT + J", hl.dsp.layout("togglesplit"))

	hl.bind(main_mod .. " + equal", hl.dsp.workspace.toggle_special("magic"))
	hl.bind(main_mod .. " + SHIFT + equal", hl.dsp.window.move({ workspace = "special:magic" }))

	hl.bind(main_mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
	hl.bind(main_mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

	hl.bind(main_mod .. " + mouse:272", hl.dsp.window.drag())
	hl.bind(main_mod .. " + mouse:273", hl.dsp.window.resize())

	bind_exec("XF86AudioRaiseVolume", "qs -c zetshell ipc call osd volumeStep 5", { locked = true, repeating = true })
	bind_exec("XF86AudioLowerVolume", "qs -c zetshell ipc call osd volumeStep -5", { locked = true, repeating = true })
	bind_exec("XF86AudioMute", "qs -c zetshell ipc call osd volumeMute", { locked = true, repeating = true })
	bind_exec("XF86AudioMicMute", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", { locked = true, repeating = true })
	bind_exec(
		"XF86MonBrightnessUp",
		"qs -c zetshell ipc call osd brightnessStep 5",
		{ locked = true, repeating = true }
	)
	bind_exec(
		"XF86MonBrightnessDown",
		"qs -c zetshell ipc call osd brightnessStep -5",
		{ locked = true, repeating = true }
	)

	bind_exec("XF86AudioNext", "playerctl next", { locked = true })
	bind_exec("XF86AudioPause", "playerctl play-pause", { locked = true })
	bind_exec("XF86AudioPlay", "playerctl play-pause", { locked = true })
	bind_exec("XF86AudioPrev", "playerctl previous", { locked = true })
end

return M
