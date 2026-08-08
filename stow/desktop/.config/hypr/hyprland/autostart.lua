local M = {}

local startup_commands = {
	"hypridle",
	"~/.config/hypr/scripts/music-idle-inhibit.sh",
	"keyd-application-mapper",
	"/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1",
	"gnome-keyring-daemon --start --components=secrets",
	"gsettings set org.gnome.desktop.interface font-name 'JetBrainsMono Nerd Font 11'",
	"gsettings set org.gnome.desktop.interface document-font-name 'JetBrainsMono Nerd Font 12'",
	"gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 13'",
	"fcitx5 -D",
	"~/.config/hypr/scripts/start_wallpaper_daemon.sh",
	"~/.config/hypr/scripts/restore_wallpaper.sh",
	"wl-paste --type text --watch cliphist store",
	"wl-paste --type image --watch cliphist store",
}

local startup_apps = {
	-- { cmd = "tana", rules = { workspace = "2 silent" } },
	{ cmd = "discord", rules = { workspace = "6 silent" } },
	-- { cmd = "slack", rules = { workspace = "6 silent" } },
	{ cmd = "spotify", rules = { workspace = "3 silent" } },
	{ cmd = "vivaldi --app=https://calendar.notion.so", rules = { workspace = "2 silent" } },
	{ cmd = "vivaldi --app=https://app.todoist.com/app", rules = { workspace = "2 silent" } },
}

function M.setup(settings)
	hl.on("hyprland.start", function()
		for _, cmd in ipairs(startup_commands) do
			hl.exec_cmd(cmd)
		end

		for _, app in ipairs(startup_apps) do
			hl.exec_cmd(app.cmd, app.rules)
		end

		hl.exec_cmd(settings.browser, { workspace = "1 silent" })
	end)
end

return M
