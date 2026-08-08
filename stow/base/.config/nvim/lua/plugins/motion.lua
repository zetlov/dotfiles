return {
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {
      modes = {
        char = {
          enabled = true,
          -- f/t/F/T enhancements
          jump_labels = true,
        },
      },
    },
  },
  {
    "unblevable/quick-scope",
    event = "VeryLazy",
    init = function()
      vim.g.qs_highlight_on_keys = { "f", "F", "t", "T" }
      vim.g.qs_max_chars = 150
    end,
    config = function()
      local ok, qs = pcall(require, "config.quickscope")
      if ok and qs.setup then
        qs.setup()
      end
    end,
  },
}
