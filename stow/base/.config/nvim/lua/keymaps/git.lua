local M = {}

local function git_root()
  local buf = vim.api.nvim_buf_get_name(0)
  local start = (buf ~= "" and vim.fs.dirname(buf)) or (vim.uv or vim.loop).cwd()
  local git = vim.fs.find(".git", { path = start, upward = true })[1]
  return git and vim.fs.dirname(git) or (vim.uv or vim.loop).cwd()
end

local function has(cmd)
  return vim.fn.executable(cmd) == 1
end

function M.setup(u)
  -- ===== VSCode (vscode-neovim) =====
  if u.is_vscode then
    -- TODO: vsocodeの拡張を開くようにする.
    return
  end

  -- ===== Neovim =====

  -- gg: LazyVim同様に Snacks.lazygit（git root）
  u.nmap("<leader>gg", function()
    if not has("lazygit") then
      vim.notify("lazygit が見つからないよ（:checkhealth とかで確認してね）", vim.log.levels.WARN)
      return
    end
    require("snacks").lazygit({ cwd = git_root() })
  end, { desc = "Lazygit (root)" })

  -- （任意）gG: cwdでlazygit（LazyVimもこの対にしてる）
  u.nmap("<leader>gG", function()
    if not has("lazygit") then
      vim.notify("lazygit が見つからないよ", vim.log.levels.WARN)
      return
    end
    require("snacks").lazygit()
  end, { desc = "Lazygit (cwd)" })

  -- gs: snacks picker の git_status（便利だから入口に置いとく）
  u.nmap("<leader>gs", function()
    require("snacks").picker.git_status({ cwd = git_root() })
  end, { desc = "Git Status (picker)" })
end

return M
