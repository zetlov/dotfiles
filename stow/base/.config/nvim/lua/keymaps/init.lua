local M = {}

function M.setup()
  local u = require("keymaps.util")

  require("keymaps.groups")

  require("keymaps.buffer").setup(u)
  require("keymaps.code").setup(u)
  require("keymaps.debug").setup(u)
  require("keymaps.diagnostics").setup(u)
  require("keymaps.file").setup(u)
  require("keymaps.git").setup(u)
  -- require("keymaps.goto").setup(u)
  require("keymaps.search").setup(u)
  require("keymaps.test").setup(u)
  require("keymaps.ui").setup(u)
end

return M
