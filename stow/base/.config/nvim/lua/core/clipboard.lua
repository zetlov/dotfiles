local is_wsl = (os.getenv("WSL_DISTRO_NAME") ~= nil) or (os.getenv("WSL_INTEROP") ~= nil)

if is_wsl and vim.fn.executable("win32yank.exe") == 1 then
    local win32yank = vim.fn.exepath("win32yank.exe")
    vim.g.clipboard = {
        name = "win32yank-wsl",
        copy = {
            ["+"] = { win32yank, "-i", "--crlf" },
            ["*"] = { win32yank, "-i", "--crlf" }
        },
        paste = {
            ["+"] = { win32yank, "-o", "--crlf" },
            ["*"] = { win32yank, "-o", "--crlf" }
        },
        cache_enable = 0
    }
end

vim.opt.clipboard = "unnamedplus"
