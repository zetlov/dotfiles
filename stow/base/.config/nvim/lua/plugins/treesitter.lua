return {
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		event = { "BufReadPost", "BufNewFile" },
		opts = {
			highlight = { enable = true },
			indent = { enable = false },
			incremental_selection = { enable = true },
			ensure_installed = {
				"bash",
				"c",
				"cpp",
				"css",
				"html",
				"javascript",
				"json",
				"latex",
				"lua",
				"markdown",
				"markdown_inline",
				"python",
				"rust",
				"typescript",
				"tsx",
				"yaml",
			},
		},
		config = function(_, opts)
			if vim.g.vscode then
				opts.highlight = { enable = false }
			end
			require("nvim-treesitter").setup(opts)
			if not vim.g.vscode then
				-- プラグイン読み込み後に既存バッファへ適用（BufReadPost取りこぼし対策）
				vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
					group = vim.api.nvim_create_augroup("treesitter_highlight", { clear = true }),
					callback = function(args)
						pcall(vim.treesitter.start, args.buf)
					end,
				})
				vim.schedule(function() pcall(vim.treesitter.start) end)
			end
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		dependencies = { "nvim-treesitter/nvim-treesitter" },
	},
	{
		"windwp/nvim-ts-autotag",
		ft = { "html", "xml", "javascript", "typescript", "tsx", "jsx", "svelte", "vue" },
		opts = {},
	},
}
