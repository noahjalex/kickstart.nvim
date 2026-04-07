return {
	"tpope/vim-fugitive",
	cmd = { "Git", "G", "Gdiffsplit", "Gvdiffsplit" },
	keys = {
		{ "<leader>gs", "<cmd>Git<cr>", desc = "[G]it [S]tatus" },
		{ "<leader>gd", "<cmd>Gdiffsplit<cr>", desc = "[G]it [D]iff" },
		{ "<leader>gb", "<cmd>Git blame<cr>", desc = "[G]it [B]lame" },
		{ "<leader>gl", "<cmd>Git log<cr>", desc = "[G]it [L]og" },
		{ "<leader>gp", "<cmd>Git push<cr>", desc = "[G]it [P]ush" },
	},
}
