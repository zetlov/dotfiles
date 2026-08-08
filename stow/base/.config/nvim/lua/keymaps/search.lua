local M = {}

-- 超ミニ root 取得（とりあえず git root 優先）
local function root_dir()
  local buf = vim.api.nvim_buf_get_name(0)
  local start = (buf ~= "" and vim.fs.dirname(buf)) or (vim.uv or vim.loop).cwd()
  local git = vim.fs.find(".git", { path = start, upward = true })[1]
  return git and vim.fs.dirname(git) or (vim.uv or vim.loop).cwd()
end

function M.setup(u)
  if u.is_vscode then
    local vscode = require("vscode") -- vscode-neovim のLua API

    u.nmap("<leader>sb", function() vscode.action("actions.find") end, { desc = "Find (in file)" })
    u.nmap("<leader>sg", function() vscode.action("workbench.action.findInFiles") end, { desc = "Find in Files" })
    u.nmap("<leader>sw", function()
      vscode.action("workbench.action.findInFiles", { args = { query = vim.fn.expand("<cword>") } })
    end, { desc = "Find word in Files" }) -- READMEに例あり

    u.nmap("<leader>sr", function() vscode.action("workbench.action.replaceInFiles") end, { desc = "Replace in Files" })
    u.nmap("<leader>sd", function() vscode.action("workbench.actions.view.problems") end, { desc = "Problems" })
    u.nmap("<leader>ss", function() vscode.action("workbench.action.gotoSymbol") end, { desc = "Symbols (file)" })
    u.nmap("<leader>sS", function() vscode.action("workbench.action.showAllSymbols") end, { desc = "Symbols (workspace)" })

    u.nmap("<leader>sc", function() vscode.action("workbench.action.showCommands") end, { desc = "Command Palette" })
    u.nmap("<leader>sk", function() vscode.action("workbench.action.openGlobalKeybindings") end, { desc = "Keyboard Shortcuts" })

    return
  end

  -- ===== Neovim =====
  local Snacks = require("snacks")

  u.nmap("<leader>sb", function() Snacks.picker.lines() end, { desc = "Buffer Lines" })
  u.nmap("<leader>sg", function() Snacks.picker.grep({ cwd = root_dir() }) end, { desc = "Grep (root)" })
  u.nmap("<leader>sG", function() Snacks.picker.grep() end, { desc = "Grep (cwd)" })

  -- 「単語/選択範囲」検索（LazyVimは source=grep_word を使ってる）
  u.map({ "n", "x" }, "<leader>sw", function()
    Snacks.picker.pick("grep_word", { cwd = root_dir() })
  end, { desc = "Word/Selection (root)" })
  u.map({ "n", "x" }, "<leader>sW", function()
    Snacks.picker.pick("grep_word")
  end, { desc = "Word/Selection (cwd)" })

  u.nmap("<leader>sB", function() Snacks.picker.grep_buffers() end, { desc = "Grep Open Buffers" })

  -- 置換：grug-far（入れてないなら後で差し替えOK）
  u.map({ "n", "x" }, "<leader>sr", "<cmd>GrugFar<cr>", { desc = "Search & Replace (GrugFar)" })

  u.nmap("<leader>sd", function() Snacks.picker.diagnostics() end, { desc = "Diagnostics" })
  u.nmap("<leader>sD", function() Snacks.picker.diagnostics_buffer() end, { desc = "Buffer Diagnostics" })

  u.nmap("<leader>ss", function() Snacks.picker.lsp_symbols() end, { desc = "LSP Symbols" })
  u.nmap("<leader>sS", function() Snacks.picker.lsp_workspace_symbols() end, { desc = "LSP Workspace Symbols" })

  u.nmap("<leader>sc", function() Snacks.picker.command_history() end, { desc = "Command History" })
  u.nmap("<leader>sC", function() Snacks.picker.commands() end, { desc = "Commands" })
  u.nmap("<leader>sk", function() Snacks.picker.keymaps() end, { desc = "Keymaps" })
  u.nmap("<leader>sR", function() Snacks.picker.resume() end, { desc = "Resume" })
end

return M
