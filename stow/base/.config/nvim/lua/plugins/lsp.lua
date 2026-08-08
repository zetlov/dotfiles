return {
	{
		"neovim/nvim-lspconfig",
		cond = function()
			return not vim.g.vscode
		end,
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			{ "mason-org/mason.nvim", opts = { ui = { border = "rounded" } } },
			{
				"mason-org/mason-lspconfig.nvim",
				opts = {
					ensure_installed = { "lua_ls", "clangd", "pyright", "texlab" },
					automatic_installation = true,
				},
			},
			{
				"WhoIsSethDaniel/mason-tool-installer.nvim",
				opts = {
					-- ここは「masonのパッケージ名」
					ensure_installed = {
						"pyright",
						"clangd",
						"texlab",
						"lua-language-server",
						"ruff",
						"stylua",
						"clang-format",
						"latexindent",
						"luacheck",
					},
					auto_update = false,
					run_on_start = true,
				},
			},
			{ "folke/lazydev.nvim", ft = "lua" },
			"folke/trouble.nvim",
			{ "hrsh7th/cmp-nvim-lsp", lazy = true },
		},
		config = function()
			local capabilities = vim.lsp.protocol.make_client_capabilities()
			local ok, cmp_lsp = pcall(require, "cmp_nvim_lsp")
			if ok then
				capabilities = cmp_lsp.default_capabilities(capabilities)
			end

			-- Apply shared capabilities to all servers
			vim.lsp.config("*", {
				capabilities = capabilities,
			})

			-- Python
			vim.lsp.config("pyright", {
				root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
				settings = {
					python = {
						analysis = {
							typeCheckingMode = "standard",
							autoSearchPaths = true,
							useLibraryCodeForTypes = true,
						},
					},
				},
			})
			vim.lsp.config("ruff", {
				root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
				cmd = { "ruff", "server" },
				filetypes = { "python" },
			})

			-- C/C++
			vim.lsp.config("clangd", {
				root_markers = { "compile_commands.json", "compile_flags.txt", ".git" },
				cmd = { "clangd", "--background-index", "--clang-tidy" },
			})

			-- LaTeX
			vim.lsp.config("texlab", {
				root_markers = { ".latexmkrc", "texlabroot", ".git" },
				settings = {
					texlab = {
						build = { onSave = true },
					},
				},
			})

			-- Lua
			vim.lsp.config("lua_ls", {
				root_markers = { ".luarc.json", ".luarc.jsonc", ".git" },
				settings = {
					Lua = {
						runtime = { version = "LuaJIT" },
						diagnostics = { globals = { "vim" } },
						workspace = {
							checkThirdParty = false,
							library = vim.api.nvim_get_runtime_file("", true),
						},
						telemetry = { enable = false },
					},
				},
			})

			vim.lsp.enable({ "pyright", "ruff", "clangd", "texlab", "lua_ls" })
			require("lazydev").setup()
		end,
	},
	{
		"folke/trouble.nvim",
		cmd = { "Trouble" },
		opts = {},
	},
	{
		"linux-cultist/venv-selector.nvim",
		branch = "regexp",
		cond = function() return not vim.g.vscode end,
		ft = "python",
		opts = {},
		keys = {
			{ "<leader>cv", "<cmd>VenvSelect<cr>", desc = "Select Python Venv" },
		},
	},
}
