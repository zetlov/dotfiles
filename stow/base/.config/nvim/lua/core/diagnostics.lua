vim.o.updatetime = 300

vim.diagnostic.config({
	underline = true,
	signs = true,
	virtual_text = { spacing = 4, prefix = "●" },
	update_in_insert = false,
	severity_sort = true,
	float = {
		border = "rounded",
		source = "if_many",
		focusable = false,
	},
})

vim.api.nvim_create_autocmd("CursorHold", {
	callback = function()
		if vim.fn.mode() ~= "n" then
			return
		end
		local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
		local diags = vim.diagnostic.get(0, { lnum = lnum })
		if #diags == 0 then
			return
		end
		vim.diagnostic.open_float(nil, {
			scope = "line",
			focus = false,
			close_events = { "CursorMoved", "InsertEnter", "BufHidden", "BufLeave" },
		})
	end,
})
