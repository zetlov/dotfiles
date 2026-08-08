return {
  {
    "stevearc/conform.nvim",
    cond = function() return not vim.g.vscode end,
    event = "BufWritePre",
    opts = {
      format_on_save = {
        timeout_ms = 500,
        lsp_format = "fallback",
      },
      formatters_by_ft = {
        python = { "ruff_format" },
        lua = { "stylua" },
        c = { "clang_format" },
        cpp = { "clang_format" },
        tex = { "latexindent" },
      },
    },
  },
}
