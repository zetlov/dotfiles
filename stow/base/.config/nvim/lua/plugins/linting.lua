return {
  {
    "mfussenegger/nvim-lint",
    cond = function() return not vim.g.vscode end,
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      local lint = require("lint")

      lint.linters_by_ft = {
        python = { "ruff" },
        lua = { "luacheck" },
        tex = { "chktex" },
        c = { "clangtidy" },
        cpp = { "clangtidy" },
      }

      vim.api.nvim_create_autocmd("BufWritePost", {
        callback = function()
          lint.try_lint()
        end,
      })
    end,
  },
}
