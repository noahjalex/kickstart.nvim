return {
	{
		"vague2k/huez.nvim",
		branch = "stable",
		event = "UIEnter",
		cmd = { "Huez", "HuezFavorites", "HuezLive", "HuezEnsured" },
		dependencies = { "nvim-telescope/telescope.nvim" },
		import = "huez-manager.import",
		keys = {
			{ "<leader>cs", "<cmd>Huez<cr>", desc = "[C]olorscheme [S]elect" },
			{ "<leader>cl", "<cmd>HuezLive<cr>", desc = "[C]olorscheme [L]ive registry" },
			{ "<leader>cf", "<cmd>HuezFavorites<cr>", desc = "[C]olorscheme [F]avorites" },
			{ "<leader>ce", "<cmd>HuezEnsured<cr>", desc = "[C]olorscheme [E]nsured" },
		},
		config = function()
			require("huez").setup({
				fallback = "tokyonight-night",
			})
		end,
	},
	{
		"xiyaowong/transparent.nvim",
		lazy = false,
		keys = {
			{ "<leader>tt", "<cmd>TransparentToggle<cr>", desc = "[T]oggle [T]ransparency" },
		},
		opts = {
			extra_groups = {
				"NormalFloat",
				"FloatBorder",
				"FoldColumn",
				"WinSeparator",
			},
		},
	},
}
