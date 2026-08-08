return {
  {
    "folke/which-key.nvim",
    cond = function() return not vim.g.vscode end,
    event = "VeryLazy",
    config = function()
      local ok, wk = pcall(require, "config.whichkey")
      if ok and wk.setup then
        wk.setup()
      else
        require("which-key").setup({})
      end
    end,
  },
  {
    "folke/noice.nvim",
    cond = function() return not vim.g.vscode end,
    event = "VeryLazy",
    dependencies = {
      "MunifTanjim/nui.nvim",
    },
    opts = {
      presets = {
        bottom_search = true,
        command_palette = true,
        long_message_to_split = true,
      },
    },
  },
  {
    "nvim-lualine/lualine.nvim",
    cond = function() return not vim.g.vscode end,
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = { theme = "tokyonight" },
    },
  },
  {
    "akinsho/bufferline.nvim",
    cond = function() return not vim.g.vscode end,
    event = "VeryLazy",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        diagnostics = "nvim_lsp",
        always_show_bufferline = true,
      },
    },
  },
  {
    "folke/tokyonight.nvim",
    cond = function() return not vim.g.vscode end,
    lazy = false,
    priority = 1000,
    opts = {},
    config = function()
      vim.cmd([[colorscheme tokyonight]])
    end,
  },
  {
    "catppuccin/nvim",
    cond = function() return not vim.g.vscode end,
    name = "catppuccin",
    lazy = true,
    opts = {},
  },
  {
    "nvim-mini/mini.icons",
    lazy = true,
    opts = {},
  },
  { "MunifTanjim/nui.nvim", lazy = true },
}
