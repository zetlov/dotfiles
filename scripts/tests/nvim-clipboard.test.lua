local config = assert(arg[1])
local original_getenv = os.getenv

local function check(wsl, win32yank, init)
  os.getenv = function(name)
    if name == "WSL_DISTRO_NAME" then return wsl and "archlinux" or nil end
    if name == "WSL_INTEROP" then return nil end
    return original_getenv(name)
  end
  vim = {
    g = {}, opt = {},
    deepcopy = function(values)
      local result = {}
      for i, value in ipairs(values) do result[i] = value end
      return result
    end,
    list_extend = function(values, extra)
      for _, value in ipairs(extra) do values[#values + 1] = value end
      return values
    end,
    fn = {
      executable = function(name)
        return ((name == "win32yank.exe" and win32yank)
          or (name == "/init" and init)) and 1 or 0
      end,
      exepath = function() return "/fixture/bin/win32yank.exe" end,
    },
  }
  dofile(config)
  assert(vim.opt.clipboard == "unnamedplus")
  if not (wsl and win32yank) then
    assert(vim.g.clipboard == nil)
    return
  end
  local prefix = init and {
    "/bin/sh", "-c", 'exec /init "$@"', "sh", "/fixture/bin/win32yank.exe", "win32yank.exe",
  }
    or { "/fixture/bin/win32yank.exe" }
  for _, register in ipairs({ "+", "*" }) do
    for operation, args in pairs({ copy = { "-i", "--crlf" }, paste = { "-o", "--lf" } }) do
      local command = vim.g.clipboard[operation][register]
      assert(#command == #prefix + #args)
      for i, value in ipairs(prefix) do assert(command[i] == value) end
      for i, value in ipairs(args) do assert(command[#prefix + i] == value) end
    end
  end
  assert(vim.g.clipboard.cache_enabled == 0)
end

check(true, true, true)
check(true, true, false)
check(true, false, true)
check(false, true, true)
os.getenv = original_getenv
