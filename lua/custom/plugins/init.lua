-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {
	"tpope/vim-dadbod",
	"kristijanhusak/vim-dadbod-ui",
	"kristijanhusak/vim-dadbod-completion",
	{
		"ibhagwan/fzf-lua",
		cmd = "FzfLua",
		opts = {
			winopts = {
				width = 0.98,
				height = 0.95,
				preview = {
					layout = "horizontal",
					horizontal = "right:35%",
				},
			},
		},
	},
	{
		"siawkz/nvim-cheatsh",
		dependencies = {
			"ibhagwan/fzf-lua",
		},
		opts = {},
	},
	{
		-- Install markdown preview, use npx if available.
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		ft = { "markdown" },
		build = function(plugin)
			if vim.fn.executable("npx") then
				vim.cmd("!cd " .. plugin.dir .. " && cd app && npx --yes yarn install")
			else
				vim.cmd([[Lazy load markdown-preview.nvim]])
				vim.fn["mkdp#util#install"]()
			end
		end,
		init = function()
			if vim.fn.executable("npx") then
				vim.g.mkdp_filetypes = { "markdown" }
			end
		end,
	},
}
