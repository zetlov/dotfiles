local settings = require("hyprland.settings")

require("hyprland.monitors").setup(settings)
require("hyprland.autostart").setup(settings)
require("hyprland.environment").setup(settings)
require("hyprland.appearance").setup()
require("hyprland.input").setup(settings)
require("hyprland.binds").setup(settings)
require("hyprland.rules").setup()
