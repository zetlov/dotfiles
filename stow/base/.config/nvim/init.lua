vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("core.options")
require("core.autocmds")
require("core.bootstrap")
require("core.keymaps")
require("core.clipboard")
require("core.lsp")
if not vim.g.vscode then
  require("core.diagnostics")
end
