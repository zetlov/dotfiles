local insert_keymaps_path = assert(arg[1], "Insert keymaps path is required")
local keymaps_init_path = assert(arg[2], "Keymaps init path is required")
local captured_mapping

local insert_keymaps = dofile(insert_keymaps_path)
insert_keymaps.setup({
  imap = function(lhs, rhs, opts)
    captured_mapping = { lhs = lhs, rhs = rhs, opts = opts }
  end,
})

assert(captured_mapping, "Insert keymap setup should define a mapping")
assert(captured_mapping.lhs == "jj", "Insert mode should map jj")
assert(captured_mapping.rhs == "<Esc>", "jj should leave insert mode")
assert(captured_mapping.opts.desc == "Exit insert mode", "jj should have a descriptive label")

local keymaps_init = assert(io.open(keymaps_init_path, "r"))
local keymaps_init_content = keymaps_init:read("*a")
keymaps_init:close()

assert(
  keymaps_init_content:match('require%("keymaps%.insert"%)%.setup%(u%)'),
  "Keymap initialization should load insert mappings"
)
