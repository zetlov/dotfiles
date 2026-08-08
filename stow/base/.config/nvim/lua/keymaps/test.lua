local M = {}

function M.setup(u)
  if u.is_vscode then return end

  local function nt()
    local ok, neotest = pcall(require, "neotest")
    if not ok then
      vim.notify("neotest が入ってないよ", vim.log.levels.WARN)
      return nil
    end
    return neotest
  end

  u.nmap("<leader>tt", function()
    local t = nt(); if t then t.run.run() end
  end, { desc = "Test: Run Nearest" })

  u.nmap("<leader>tT", function()
    local t = nt(); if t then t.run.run(vim.fn.expand("%")) end
  end, { desc = "Test: Run File" })

  u.nmap("<leader>ts", function()
    local t = nt(); if t then t.summary.toggle() end
  end, { desc = "Test: Toggle Summary" })

  u.nmap("<leader>to", function()
    local t = nt(); if t then t.output_panel.toggle() end
  end, { desc = "Test: Toggle Output Panel" })

  u.nmap("<leader>tS", function()
    local t = nt(); if t then t.run.stop() end
  end, { desc = "Test: Stop" })
end

return M
