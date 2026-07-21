return {
	{
		"tpope/vim-fugitive",
		cmd = { "Git", "G", "Gdiffsplit", "Gvdiffsplit" },
		keys = {
			{ "<leader>gs", "<cmd>Git<cr>", desc = "[G]it [S]tatus" },
			{ "<leader>gb", "<cmd>Git blame<cr>", desc = "[G]it [B]lame" },
			{ "<leader>gl", "<cmd>Git log<cr>", desc = "[G]it [L]og" },
			{ "<leader>gp", "<cmd>Git push<cr>", desc = "[G]it [P]ush" },
		},
	},
	{
		"sindrets/diffview.nvim",
		cmd = {
			"DiffviewClose",
			"DiffviewFileHistory",
			"DiffviewFocusFiles",
			"DiffviewOpen",
			"DiffviewToggleFiles",
		},
		keys = {
			{ "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "[G]it [D]iff working tree" },
			{ "<leader>gD", ":DiffviewOpen ", desc = "[G]it [D]iff refs" },
			{ "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "[G]it file [H]istory" },
		},
		opts = {},
	},
}
