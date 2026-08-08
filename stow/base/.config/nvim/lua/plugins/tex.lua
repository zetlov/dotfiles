return {
	{
		"lervag/vimtex",
		cond = function() return not vim.g.vscode end,
		ft = { "tex", "plaintex", "bib" },
		init = function()
			local is_wsl = vim.fn.has("wsl") == 1 or vim.env.WSL_DISTRO_NAME ~= nil
			if is_wsl then
				vim.g.vimtex_view_method = "general"
				vim.g.vimtex_view_general_viewer = "SumatraPDF.exe"
				vim.g.vimtex_view_general_options =
					[[-reuse-instance -forward-search @tex @line @pdf]]
			else
				vim.g.vimtex_view_method = "zathura"
			end
			vim.g.vimtex_compiler_latexmk = {
				out_dir = "out",
			}
			vim.g.vimtex_compiler_latexmk_engines = {
				_ = "-lualatex",
			}
		end,
	},
}
