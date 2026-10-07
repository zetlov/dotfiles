local lsp_config = assert(arg[1], "Neovim LSP config path is required")
local debug_config = assert(arg[2], "Neovim debug config path is required")

local function find_spec(specs, name)
  for _, spec in ipairs(specs) do
    if spec[1] == name then
      return spec
    end
  end
  error(name .. " plugin spec is missing")
end

local function contains(values, expected)
  for _, value in ipairs(values or {}) do
    if value == expected then
      return true
    end
  end
  return false
end

local lsp_spec = find_spec(dofile(lsp_config), "neovim/nvim-lspconfig")
local found_mason_lspconfig = false
local found_mason_tool_installer = false
for _, dependency in ipairs(lsp_spec.dependencies) do
  if type(dependency) == "table" and dependency[1] == "mason-org/mason-lspconfig.nvim" then
    found_mason_lspconfig = true
    assert(not contains(dependency.opts.ensure_installed, "clangd"), "clangd should be OS-managed, not Mason-managed")
  end
  if type(dependency) == "table" and dependency[1] == "WhoIsSethDaniel/mason-tool-installer.nvim" then
    found_mason_tool_installer = true
    assert(not contains(dependency.opts.ensure_installed, "clangd"), "clangd should not be duplicated in Mason tools")
    assert(not contains(dependency.opts.ensure_installed, "clang-format"), "clang-format should be OS-managed")
  end
end
assert(found_mason_lspconfig, "mason-lspconfig dependency is missing")
assert(found_mason_tool_installer, "Mason tool installer dependency is missing")

local dap = {
  adapters = {},
  configurations = {},
  listeners = {
    after = { event_initialized = {} },
    before = { event_terminated = {}, event_exited = {} },
  },
}

package.preload.dap = function()
  return dap
end
package.preload["dap.utils"] = function()
  return { pick_process = function() return 1 end }
end
package.preload.dapui = function()
  return { setup = function() end, open = function() end, close = function() end }
end
package.preload["nvim-dap-virtual-text"] = function()
  return { setup = function() end }
end
package.preload["mason-nvim-dap"] = function()
  return { setup = function() end }
end

vim = {
  fn = {
    sign_define = function() end,
    getcwd = function() return "/workspace" end,
    input = function() return "/workspace/app" end,
  },
}

local debug_spec = find_spec(dofile(debug_config), "mfussenegger/nvim-dap")
debug_spec.config()

assert(dap.adapters.gdb, "GDB DAP adapter should be configured")
assert(dap.adapters.gdb.command == "gdb", "GDB DAP adapter should use the OS-managed GDB")
assert(contains(dap.adapters.gdb.args, "--interpreter=dap"), "GDB should use its built-in DAP interpreter")
assert(dap.configurations.cpp and #dap.configurations.cpp > 0, "C++ launch configuration should be available")
assert(dap.configurations.c and #dap.configurations.c > 0, "C launch configuration should be available")
assert(dap.configurations.cpp[1].type == "gdb", "C++ launch configuration should use GDB DAP")
assert(dap.configurations.cpp[1].request == "launch", "C++ should have a launch configuration")
assert(dap.configurations.cpp[2].request == "attach", "C++ should have an attach configuration")
assert(type(dap.configurations.cpp[2].program) == "function", "C++ attach should load executable symbols")
