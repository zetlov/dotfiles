local M = {}

function M.setup(u)
  u.imap("jj", "<Esc>", { desc = "Exit insert mode" })
end

return M
