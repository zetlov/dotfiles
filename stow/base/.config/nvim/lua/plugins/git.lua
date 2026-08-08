return {
  {
    "lewis6991/gitsigns.nvim",
    cond = function() return not vim.g.vscode end,
    event = "VeryLazy",
    opts = {},
  },
}
