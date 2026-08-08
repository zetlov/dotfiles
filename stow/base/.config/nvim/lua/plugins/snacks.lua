return {
  {
    "folke/snacks.nvim",
    cond = function() return not vim.g.vscode end,
    priority = 1000,
    lazy = false,
    opts = {
      dashboard = { enabled = true },
      picker = { enabled = true },
    },
  },
}
