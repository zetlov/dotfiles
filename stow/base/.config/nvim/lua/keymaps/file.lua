local M = {}

function M.setup(u)
  -- Explorer: NeovimはOil、VSCodeはExplorerビュー
  -- TODO: vscodeもoil.codeにする
  if u.is_vscode then
    u.nmap("<leader>fe", u.vscode_action("workbench.view.explorer"), { desc = "Explorer" })
  else
    u.nmap("<leader>fe", "<cmd>Oil<cr>", { desc = "Explorer (Oil)" })
  end

  if u.is_vscode then
    -- VSCode: Quick Open / Open Editors / Recent / Projects / Settings
    u.nmap("<leader>ff", u.vscode_action("workbench.action.quickOpen"), { desc = "Find Files" })
    u.nmap("<leader>fb", u.vscode_action("workbench.action.showAllEditors"), { desc = "Open Editors" })
    u.nmap("<leader>fr", u.vscode_action("workbench.action.quickOpenRecent"), { desc = "Recent" })
    u.nmap("<leader>fp", u.vscode_action("workbench.action.openRecent"), { desc = "Projects (Recent)" })
    u.nmap("<leader>fc", u.vscode_action("workbench.action.openSettingsJson"), { desc = "Config (settings.json)" })

    -- git files相当：VSCodeだとQuickOpenで十分なことが多いので同じにしておく（気になったら後で差し替え）
    u.nmap("<leader>fg", u.vscode_action("workbench.action.quickOpen"), { desc = "Find Files (git-ish)" })
  else
    -- Neovim: snacks picker
    u.nmap("<leader>ff", function() require("snacks").picker.files() end, { desc = "Find Files" })
    u.nmap("<leader>fb", function() require("snacks").picker.buffers() end, { desc = "Buffers" })
    u.nmap("<leader>fr", function() require("snacks").picker.recent() end, { desc = "Recent" })
    u.nmap("<leader>fg", function() require("snacks").picker.git_files() end, { desc = "Git Files" })
    u.nmap("<leader>fp", function() require("snacks").picker.projects() end, { desc = "Projects" })

    -- Config files: LazyVimは専用helperだけど、自前ならこれがシンプル
    u.nmap("<leader>fc", function()
      require("snacks").picker.files({ cwd = vim.fn.stdpath("config") })
    end, { desc = "Config Files" })
  end
end

return M
