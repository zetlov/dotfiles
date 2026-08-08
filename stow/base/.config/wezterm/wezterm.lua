local wezterm = require 'wezterm'

local config = wezterm.config_builder()

config.default_domain = 'WSL:archlinux'

config.font = wezterm.font_with_fallback {
  'JetBrainsMono Nerd Font',
  'Noto Sans Mono CJK JP',
}
config.font_size = 13

config.default_cursor_style = 'SteadyBar'
config.hide_mouse_cursor_when_typing = true

config.color_scheme = 'Catppuccin Mocha'
config.window_background_opacity = 0.7
config.window_decorations = 'RESIZE'
config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0,
}

config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = true

config.keys = {
  {
    key = 'Enter',
    mods = 'SHIFT',
    action = wezterm.action.SendKey { key = 'j', mods = 'CTRL' },
  },
}

config.colors = {
  foreground = '#CDD6F4',
  background = '#1E1E2E',
  cursor_bg = '#F5E0DC',
  cursor_fg = '#1E1E2E',
  cursor_border = '#F5E0DC',
  selection_fg = '#1E1E2E',
  selection_bg = '#F5E0DC',

  ansi = {
    '#45475A',
    '#F38BA8',
    '#A6E3A1',
    '#F9E2AF',
    '#89B4FA',
    '#F5C2E7',
    '#94E2D5',
    '#BAC2DE',
  },
  brights = {
    '#585B70',
    '#F38BA8',
    '#A6E3A1',
    '#F9E2AF',
    '#89B4FA',
    '#F5C2E7',
    '#94E2D5',
    '#A6ADC8',
  },

  tab_bar = {
    background = '#11111B',
    active_tab = {
      fg_color = '#11111B',
      bg_color = '#CBA6F7',
    },
    inactive_tab = {
      fg_color = '#CDD6F4',
      bg_color = '#181825',
    },
    inactive_tab_hover = {
      fg_color = '#CDD6F4',
      bg_color = '#181825',
    },
    new_tab = {
      fg_color = '#CDD6F4',
      bg_color = '#181825',
    },
    new_tab_hover = {
      fg_color = '#11111B',
      bg_color = '#CBA6F7',
    },
  },
}

config.window_close_confirmation = 'NeverPrompt'

return config
