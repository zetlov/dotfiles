local ui_config = assert(arg[1], "Neovim UI config path is required")
local specs = dofile(ui_config)
local call_order = {}
local configured_opts

vim = {
  g = {},
  cmd = {},
}

local tokyonight_spec
for _, spec in ipairs(specs) do
  if spec[1] == "folke/tokyonight.nvim" then
    tokyonight_spec = spec
    break
  end
end

assert(tokyonight_spec, "TokyoNight plugin spec is missing")
assert(tokyonight_spec.opts.transparent == true, "TokyoNight background should be transparent")
assert(tokyonight_spec.opts.styles.sidebars == "transparent", "TokyoNight sidebars should be transparent")
assert(tokyonight_spec.opts.styles.floats == "transparent", "TokyoNight floats should be transparent")

package.preload.tokyonight = function()
  return {
    setup = function(opts)
      configured_opts = opts
      table.insert(call_order, "setup")
    end,
  }
end

vim.cmd.colorscheme = function(name)
  assert(name == "tokyonight", "Unexpected colorscheme")
  table.insert(call_order, "colorscheme")
end

tokyonight_spec.config(nil, tokyonight_spec.opts)

assert(configured_opts == tokyonight_spec.opts, "TokyoNight setup should receive the declared options")
assert(call_order[1] == "setup" and call_order[2] == "colorscheme", "TokyoNight should be configured before loading")
assert(#call_order == 2, "TokyoNight configuration should not perform unexpected calls")
