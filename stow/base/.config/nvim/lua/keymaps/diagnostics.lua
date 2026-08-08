local M = {}

function M.setup(u)
  -- VSCode-Neovim
  if u.is_vscode then
    u.nmap("<leader>xx", u.vscode_action("workbench.actions.view.problems"), { desc = "Problems" })
    u.nmap("<leader>xX", u.vscode_action("workbench.actions.view.problems"), { desc = "Problems (buffer)" })
    u.nmap("<leader>xd", u.vscode_action("editor.action.showHover"), { desc = "Line Diagnostics (Hover)" })

    -- VSCodeにはquickfix/loclist概念がないのでProblemsに寄せる
    u.nmap("<leader>xq", u.vscode_action("workbench.actions.view.problems"), { desc = "Quickfix (Problems)" })
    u.nmap("<leader>xl", u.vscode_action("workbench.actions.view.problems"), { desc = "Loclist (Problems)" })

    -- 診断ジャンプ
    u.nmap("]d", u.vscode_action("editor.action.marker.next"), { desc = "Next Diagnostic" })
    u.nmap("[d", u.vscode_action("editor.action.marker.prev"), { desc = "Prev Diagnostic" })
    return
  end

  -- Neovim
  local Snacks = require("snacks")

  -- 一覧（ワークスペース / バッファ）
  u.nmap("<leader>xx", function() Snacks.picker.diagnostics() end, { desc = "Diagnostics" })
  u.nmap("<leader>xX", function() Snacks.picker.diagnostics_buffer() end, { desc = "Buffer Diagnostics" })

  -- 行の診断
  u.nmap("<leader>xd", function()
    vim.diagnostic.open_float(nil, { scope = "line" })
  end, { desc = "Line Diagnostics" })

  -- quickfix / location list に流し込む（必要なら開く）
  u.nmap("<leader>xq", function()
    vim.diagnostic.setqflist()
    vim.cmd("copen")
  end, { desc = "Diagnostics → Quickfix" })

  u.nmap("<leader>xl", function()
    vim.diagnostic.setloclist()
    vim.cmd("lopen")
  end, { desc = "Diagnostics → Loclist" })

  -- Trouble
  u.nmap("<leader>xt", "<cmd>Trouble diagnostics toggle<cr>",        { desc = "Trouble: Workspace Diagnostics" })
  u.nmap("<leader>xT", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", { desc = "Trouble: Buffer Diagnostics" })
  u.nmap("<leader>xL", "<cmd>Trouble loclist toggle<cr>",             { desc = "Trouble: Location List" })
  u.nmap("<leader>xQ", "<cmd>Trouble qflist toggle<cr>",              { desc = "Trouble: Quickfix List" })

  -- 診断ジャンプ（押しやすいのでleader外）
  u.nmap("]d", vim.diagnostic.goto_next, { desc = "Next Diagnostic" })
  u.nmap("[d", vim.diagnostic.goto_prev, { desc = "Prev Diagnostic" })
end

return M
