local M = {
	terminal = "kitty",
	file_manager = "yazi",
	browser = "vivaldi",
	main_mod = "SUPER",
	sub_mod = "ALT",
	main_monitor = "",
	main_monitor_mode = "preferred",
	main_monitor_position = "auto",
	main_monitor_scale = 1,
	sub_monitor = "",
	sub_monitor_mode = "preferred",
	sub_monitor_position = "auto",
	sub_monitor_scale = 1,
	nvidia = false,
}

local home = os.getenv("HOME")
if home then
	local ok, overrides = pcall(dofile, home .. "/.config/hypr/settings.local.lua")
	if ok and type(overrides) == "table" then
		for key, value in pairs(overrides) do
			if M[key] ~= nil and type(value) == type(M[key]) then
				M[key] = value
			end
		end
	end
end

return M
