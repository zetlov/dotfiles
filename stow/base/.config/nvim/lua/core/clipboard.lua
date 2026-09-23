local is_wsl = (os.getenv("WSL_DISTRO_NAME") ~= nil) or (os.getenv("WSL_INTEROP") ~= nil)

if is_wsl and vim.fn.executable("win32yank.exe") == 1 then
    local win32yank = vim.fn.exepath("win32yank.exe")
    -- A shell preserves /init's launch semantics under Neovim's process API.
    -- /init consumes the executable path; win32yank also needs argv[0].
    local launcher = vim.fn.executable("/init") == 1
        and { "/bin/sh", "-c", 'exec /init "$@"', "sh", win32yank, "win32yank.exe" }
        or { win32yank }
    local function command(...)
        return vim.list_extend(vim.deepcopy(launcher), { ... })
    end
    vim.g.clipboard = {
        name = "win32yank-wsl",
        copy = {
            ["+"] = command("-i", "--crlf"),
            ["*"] = command("-i", "--crlf")
        },
        paste = {
            ["+"] = command("-o", "--lf"),
            ["*"] = command("-o", "--lf")
        },
        cache_enabled = 0
    }
end

vim.opt.clipboard = "unnamedplus"
