local M = {}

local function nvim_format()
  local ok, conform = pcall(require, "conform")
  if ok then
    conform.format({ lsp_fallback = true, async = true })
    return
  end
  vim.lsp.buf.format({ async = true })
end

local function nvim_source_action()
  vim.lsp.buf.code_action({
    context = { only = { "source" }, diagnostics = {} },
  })
end

local function nvim_organize_imports()
  vim.lsp.buf.code_action({
    context = { only = { "source.organizeImports" }, diagnostics = {} },
  })
end

local function nvim_rename_file()
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.rename and snacks.rename.rename_file then
    snacks.rename.rename_file()
  else
    vim.notify("Snacks.rename.rename_file() が見つからないよ", vim.log.levels.WARN)
  end
end

function M.setup(u)
  -- VSCode-Neovim
  if u.is_vscode then
    u.map({ "n", "x" }, "<leader>ca", u.vscode_action("editor.action.quickFix"), { desc = "Code Action (Quick Fix)" })
    u.map("n", "<leader>cA", u.vscode_action("editor.action.sourceAction"), { desc = "Source Action" })
    u.map("n", "<leader>co", u.vscode_action("editor.action.organizeImports"), { desc = "Organize Imports" })
    u.map("n", "<leader>cr", u.vscode_action("editor.action.rename"), { desc = "Rename Symbol" })

    u.map("n", "<leader>cf", u.vscode_action("editor.action.formatDocument"), { desc = "Format Document" })
    u.map("x", "<leader>cf", u.vscode_action("editor.action.formatSelection"), { desc = "Format Selection" })

    u.map("n", "<leader>cR", u.vscode_action("renameFile"), { desc = "Rename File" })
    u.map("n", "<leader>cd", u.vscode_action("editor.action.showHover"), { desc = "Line Info (Hover)" })
    u.map("n", "<leader>cl", u.vscode_action("workbench.actions.view.problems"), { desc = "Problems" })
    u.map("n", "<leader>cm", u.vscode_action("workbench.view.extensions"), { desc = "Extensions" })

    -- CodeLens: “Show CodeLens Commands For Current Line”
    u.map("n", "<leader>cc", u.vscode_action("codelens.showLensesInCurrentLine"), { desc = "CodeLens (Current Line)" })
    return
  end

  -- Neovim
  u.map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "Code Action" })
  u.map("n", "<leader>cA", nvim_source_action, { desc = "Source Action" })
  u.map("n", "<leader>co", nvim_organize_imports, { desc = "Organize Imports" })
  u.map("n", "<leader>cr", vim.lsp.buf.rename, { desc = "Rename" })
  u.map("n", "<leader>cR", nvim_rename_file, { desc = "Rename File" })
  u.map({ "n", "x" }, "<leader>cf", nvim_format, { desc = "Format" })
  u.map("n", "<leader>cd", function()
    vim.diagnostic.open_float(nil, { scope = "line" })
  end, { desc = "Line Diagnostics" })

  u.map("n", "<leader>cc", function()
    pcall(vim.lsp.codelens.run)
  end, { desc = "Run CodeLens" })
  u.map("n", "<leader>cC", function()
    pcall(vim.lsp.codelens.refresh)
  end, { desc = "Refresh CodeLens" })

  u.map("n", "<leader>cl", function()
    if vim.fn.exists(":LspInfo") == 2 then
      vim.cmd("LspInfo")
    else
      vim.cmd("checkhealth lsp")
    end
  end, { desc = "LSP Info" })

  u.map("n", "<leader>cm", function()
    if vim.fn.exists(":Mason") == 2 then
      vim.cmd("Mason")
    else
      vim.notify("mason.nvim が入ってないよ", vim.log.levels.WARN)
    end
  end, { desc = "Mason" })
end

return M
