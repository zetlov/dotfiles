local options_config = assert(arg[1], "Neovim options config path is required")
local configured_options = {}

vim = {
  opt = setmetatable({}, {
    __newindex = function(_, name, value)
      configured_options[name] = value
    end,
  }),
}

dofile(options_config)

assert(
  configured_options.guicursor == "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50",
  "Neovim should use a block cursor in normal modes and a thin bar in insert mode"
)
