-- lua/keymaps/leader/buffer.lua
local M = {}

-- Neovim側: バッファ削除の最低限ヘルパ
local function buf_delete(buf, force)
  local ok = pcall(vim.api.nvim_buf_delete, buf, { force = force or false })
  return ok
end

local function delete_other_buffers()
  local cur = vim.api.nvim_get_current_buf()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= cur and vim.bo[b].buflisted then
      -- 変更ありは失敗することがある（その場合は残る）
      buf_delete(b, false)
    end
  end
end

function M.setup(u)
  -- ===== VSCode =====
  if u.is_vscode then
    u.nmap("<leader>bb", u.vscode_action("workbench.action.showAllEditors"), { desc = "Buffers / Open Editors" })
    u.nmap("<leader>bn", u.vscode_action("workbench.action.nextEditor"), { desc = "Next Editor" })
    u.nmap("<leader>bp", u.vscode_action("workbench.action.previousEditor"), { desc = "Prev Editor" })
    u.nmap("<leader>bd", u.vscode_action("workbench.action.closeActiveEditor"), { desc = "Close Editor" })
    u.nmap("<leader>bo", u.vscode_action("workbench.action.closeOtherEditors"), { desc = "Close Other Editors" })

    -- “バッファ+ウィンドウ”相当（現在のeditor groupごと閉じる）
    u.nmap("<leader>bD", u.vscode_action("workbench.action.closeEditorsAndGroup"), { desc = "Close Editors and Group" })
    return
  end

  -- ===== Neovim =====
  u.nmap("<leader>bb", function()
    require("snacks").picker.buffers()
  end, { desc = "Buffers" })

  u.nmap("<leader>bn", "<cmd>bnext<cr>", { desc = "Next Buffer" })
  u.nmap("<leader>bp", "<cmd>bprevious<cr>", { desc = "Prev Buffer" })

  u.nmap("<leader>bd", function()
    buf_delete(0, false) -- 変更ありはNeovimが止める
  end, { desc = "Delete Buffer" })

  u.nmap("<leader>bo", function()
    delete_other_buffers()
  end, { desc = "Delete Other Buffers" })

  u.nmap("<leader>bD", function()
    buf_delete(0, false)
    if #vim.api.nvim_list_wins() > 1 then
      vim.cmd("close")
    end
  end, { desc = "Delete Buffer and Window" })
end

return M
