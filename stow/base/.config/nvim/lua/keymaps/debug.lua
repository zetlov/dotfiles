local M = {}

local function input(prompt)
  return vim.fn.input(prompt)
end

function M.setup(u)
  -- =========================
  -- VSCode-Neovim
  -- =========================
  if u.is_vscode then
    local vscode = require("vscode")

    -- セッション操作
    u.nmap("<leader>dd", u.vscode_action("workbench.action.debug.start"), { desc = "Debug: Start" })
    u.nmap("<leader>dc", u.vscode_action("workbench.action.debug.continue"), { desc = "Debug: Continue" })
    u.nmap("<leader>ds", u.vscode_action("workbench.action.debug.stop"), { desc = "Debug: Stop" })
    u.nmap("<leader>dR", u.vscode_action("workbench.action.debug.restart"), { desc = "Debug: Restart" })

    -- ステップ
    u.nmap("<leader>do", u.vscode_action("workbench.action.debug.stepOver"), { desc = "Debug: Step Over" })
    u.nmap("<leader>di", u.vscode_action("workbench.action.debug.stepInto"), { desc = "Debug: Step Into" })
    u.nmap("<leader>dO", u.vscode_action("workbench.action.debug.stepOut"), { desc = "Debug: Step Out" })

    -- ブレークポイント
    u.nmap("<leader>db", u.vscode_action("editor.debug.action.toggleBreakpoint"), { desc = "Breakpoint: Toggle" })
    u.nmap("<leader>dB", u.vscode_action("editor.debug.action.conditionalBreakpoint"), { desc = "Breakpoint: Conditional" })
    u.nmap("<leader>dl", u.vscode_action("editor.debug.action.toggleLogPoint"), { desc = "Breakpoint: Logpoint" })

    -- 便利系
    u.nmap("<leader>dt", u.vscode_action("editor.debug.action.runToCursor"), { desc = "Debug: Run to Cursor" })
    u.nmap("<leader>dv", u.vscode_action("workbench.view.debug"), { desc = "Debug View" })
    u.nmap("<leader>dr", u.vscode_action("workbench.debug.action.toggleRepl"), { desc = "Debug Console (REPL)" })

    return
  end

  -- =========================
  -- Neovim (nvim-dap)
  -- =========================
  local ok_dap, dap = pcall(require, "dap")
  if not ok_dap then
    vim.notify("nvim-dap が入ってないよ（<leader>d を有効にするなら入れるのがおすすめ）", vim.log.levels.WARN)
    return
  end

  local ok_ui, dapui = pcall(require, "dapui")

  -- セッション操作
  u.nmap("<leader>dd", dap.continue, { desc = "DAP: Continue/Start" })
  u.nmap("<leader>ds", dap.terminate, { desc = "DAP: Stop" })
  u.nmap("<leader>dR", dap.restart, { desc = "DAP: Restart" })

  -- ステップ
  u.nmap("<leader>do", dap.step_over, { desc = "DAP: Step Over" })
  u.nmap("<leader>di", dap.step_into, { desc = "DAP: Step Into" })
  u.nmap("<leader>dO", dap.step_out, { desc = "DAP: Step Out" })

  -- ブレークポイント
  u.nmap("<leader>db", dap.toggle_breakpoint, { desc = "DAP: Toggle Breakpoint" })
  u.nmap("<leader>dB", function()
    dap.set_breakpoint(input("Breakpoint condition: "))
  end, { desc = "DAP: Conditional Breakpoint" })
  u.nmap("<leader>dl", function()
    dap.set_breakpoint(nil, nil, input("Log point message: "))
  end, { desc = "DAP: Logpoint" })

  -- 便利系
  u.nmap("<leader>dt", dap.run_to_cursor, { desc = "DAP: Run to Cursor" })
  u.nmap("<leader>dr", function() dap.repl.open() end, { desc = "DAP: REPL" })
  u.nmap("<leader>dv", function()
    if ok_ui then dapui.open() else vim.notify("nvim-dap-ui が入ってないよ", vim.log.levels.WARN) end
  end, { desc = "DAP UI: Open" })
  u.nmap("<leader>du", function()
    if ok_ui then dapui.toggle() else vim.notify("nvim-dap-ui が入ってないよ", vim.log.levels.WARN) end
  end, { desc = "DAP UI: Toggle" })

  -- 評価（dap-uiある時だけ）
  u.map({ "n", "v" }, "<leader>de", function()
    if ok_ui then dapui.eval() else vim.notify("nvim-dap-ui が入ってないよ", vim.log.levels.WARN) end
  end, { desc = "DAP: Eval" })
end

return M
