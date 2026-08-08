local M = {}

-- Check if we are running inside VSCode
M.is_vscode = vim.g.vscode == true

function M.map(mode, lhs, rhs, opts)
  vim.keymap.set(mode, lhs, rhs, opts or { silent = true })
end

function M.nmap(lhs, rhs, opts)
  M.map("n", lhs, rhs, opts)
end
function M.vmap(lhs, rhs, opts)
  M.map("v", lhs, rhs, opts)
end
function M.imap(lhs, rhs, opts)
  M.map("i", lhs, rhs, opts)
end

function M.vscode_action(name, opts)
  return function()
    require("vscode").action(name, opts)
  end
end

return M
