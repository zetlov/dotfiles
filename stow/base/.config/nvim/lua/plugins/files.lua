return {
	{
		"stevearc/oil.nvim",
		cond = function() return not vim.g.vscode end,
		cmd = "Oil",
		lazy = false,
		keys = {
			{ "-", "<cmd>Oil<cr>", desc = "Open parent directory" },
		},
		opts = {
			default_file_explorer = true,
			columns = { "icon" },
			view_options = {
				show_hidden = true,
				natural_order = "fast",
			},
			delete_to_trash = true,
			skip_confirm_for_simple_edits = true,

			lsp_file_methods = {
				enabled = true,
				autosave_changes = "unmodified",
			},
		},
		dependencies = { "nvim-tree/nvim-web-devicons" },
	},
	{
		"MagicDuck/grug-far.nvim",
		cond = function() return not vim.g.vscode end,
		cmd = "GrugFar",
		opts = {},
	},
}
