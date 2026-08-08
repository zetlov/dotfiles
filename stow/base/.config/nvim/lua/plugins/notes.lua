return {
	{
		"epwalsh/obsidian.nvim",
		cond = function() return not vim.g.vscode end,
		version = "*",
		lazy = true,
		cmd = { "ObsidianToday", "ObsidianSearch", "ObsidianQuickSwitch" },
		ft = "markdown",
		dependencies = {
			-- Required
			"nvim-lua/plenary.nvim",
			"hrsh7th/nvim-cmp",
		},
		opts = {
			workspaces = {
				{
					name = "main",
					path = "~/Obsidian/main/",
				},
			},
			daily_notes = {
				folder = "20_Journal/Daily/2026",
				template = "99_Extra/Templates/journal-daily.md",
			},
			mappings = {
				["gf"] = {
					action = function()
						return require("obsidian").util.gf_passthrough()
					end,
					opts = { noremap = false, expr = true, buffer = true },
				},
				["<leader>ch"] = {
					action = function()
						return require("obsidian").util.toggle_checkbox()
					end,
					opts = { buffer = true },
				},
				["<CR>"] = {
					action = function()
						return require("obsidian").util.smart_action()
					end,
					opts = { buffer = true, expr = true },
				},
			},
			disable_frontmatter = true,
			note_id_func = function(title)
				return title
			end,
			wiki_link_func = function(opts)
				return require("obsidian").util.wiki_link_id_prefix(opts)
			end,

			ui = {
				enable = false,
				-- checkboxes = {
				-- 	[" "] = { char = "󰄱", hl_group = "ObsidianTodo" },
				-- 	["x"] = { char = "", hl_group = "ObsidianDone" },
				-- 	[">"] = { char = "", hl_group = "ObsidianRightArrow" },
				-- 	["~"] = { char = "󰰱", hl_group = "ObsidianTilde" },
				-- 	["!"] = { char = "", hl_group = "ObsidianImportant" },
				-- },
			},

			attachments = {
				img_folder = "99_Extra/Attachments",
			},
		},
	},
	{
		"MeanderingProgrammer/render-markdown.nvim",
		cond = function()
			return not vim.g.vscode
		end,
		ft = "markdown",
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			"nvim-mini/mini.icons",
		},
		opts = {
			render_modes = { "n" },
			max_file_size = 5.0, -- in MB
			latex = {
				enabled = true,
				position = "center",
				converter = { "utftex", "latex2text" },
			},
		},
	},
}
