local M = {}

function M.setup(u)
  -- VSCode-Neovim
  if u.is_vscode then
    u.nmap("<leader>uw", u.vscode_action("editor.action.toggleWordWrap"), { desc = "Word Wrap" })
    u.nmap("<leader>uz", u.vscode_action("workbench.action.toggleZenMode"), { desc = "Zen Mode" })
    u.nmap("<leader>uB", u.vscode_action("workbench.action.toggleSidebarVisibility"), { desc = "Sidebar" })
    u.nmap("<leader>up", u.vscode_action("workbench.action.togglePanel"), { desc = "Panel" })
    u.nmap("<leader>ua", u.vscode_action("workbench.action.toggleActivityBarVisibility"), { desc = "Activity Bar" })
    u.nmap("<leader>um", u.vscode_action("editor.action.toggleMinimap"), { desc = "Minimap" })
    u.nmap("<leader>ul", u.vscode_action("editor.action.toggleRenderWhitespace"), { desc = "Render Whitespace" })
    return
  end

  -- Neovim
  local Snacks = require("snacks")

  -- まずは “いつでも便利” な表示トグルだけ
  Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
  Snacks.toggle.option("spell", { name = "Spell" }):map("<leader>us")
  Snacks.toggle.option("list", { name = "Listchars" }):map("<leader>ul")
  Snacks.toggle.option("number", { name = "Line Numbers" }):map("<leader>un")
  Snacks.toggle.option("cursorline", { name = "Cursor Line" }):map("<leader>uc")

  -- relativenumber は window-option なのでカスタムトグルにする（例はこの形がよく使われる）
  Snacks.toggle
    .new({
      id = "relativenumber",
      name = "Relative Numbers",
      get = function() return vim.wo.relativenumber end,
      set = function(state) vim.wo.relativenumber = state end,
    })
    :map("<leader>uN")

  -- diagnostics はあるならトグル（Snacks.toggle.diagnostics が無い環境でも落ちないように）
  pcall(function()
    Snacks.toggle.diagnostics({ name = "Diagnostics" }):map("<leader>ud")
  end)

  -- Zen（Snacks.zen() で切り替えできる想定）
  vim.keymap.set("n", "<leader>uz", function()
    Snacks.zen()
  end, { desc = "Zen Mode" })
end

return M
