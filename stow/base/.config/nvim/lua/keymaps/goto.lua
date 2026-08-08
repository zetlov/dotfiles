local M = {}

function M.setup()
	-- Go to definition
	vim.api.nvim_set_keymap(
		"n",
		"gd",
		"<cmd>lua vim.lsp.buf.definition()<CR>",
		{ desc = "Go to definition", noremap = true, silent = true }
	)
	-- Go to declaration
	vim.api.nvim_set_keymap(
		"n",
		"gD",
		"<cmd>lua vim.lsp.buf.declaration()<CR>",
		{ desc = "Go to declaration", noremap = true, silent = true }
	)
	-- Go to implementation
	vim.api.nvim_set_keymap(
		"n",
		"gi",
		"<cmd>lua vim.lsp.buf.implementation()<CR>",
		{ desc = "Go to implementation", noremap = true, silent = true }
	)
	-- Go to references
	vim.api.nvim_set_keymap(
		"n",
		"gr",
		"<cmd>lua vim.lsp.buf.references()<CR>",
		{ desc = "Go to references", noremap = true, silent = true }
	)
	-- Go to type definition
	vim.api.nvim_set_keymap(
		"n",
		"gt",
		"<cmd>lua vim.lsp.buf.type_definition()<CR>",
		{ desc = "Go to type definition", noremap = true, silent = true }
	)
end

return M
