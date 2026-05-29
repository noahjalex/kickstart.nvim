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
		-- Open-source, local AI syntax help/completions via Ollama.
		-- Recommended fast model: `ollama pull qwen2.5-coder:1.5b`.
		"David-Kunz/gen.nvim",
		cmd = "Gen",
		keys = {
			{ "<leader>at", "<cmd>Gen Chat<CR>", mode = "n", desc = "AI chat" },
			{ "<leader>ag", "<cmd>Gen Generate<CR>", mode = "n", desc = "AI generate" },
			{ "<leader>ag", ":Gen Generate<CR>", mode = "v", desc = "AI generate" },
			{ "<leader>aa", "<cmd>Gen Ask<CR>", mode = "n", desc = "AI ask about buffer" },
			{ "<leader>aa", ":Gen Ask<CR>", mode = "v", desc = "AI ask about selection" },
			{ "<leader>ar", ":Gen Change<CR>", mode = "v", desc = "AI rewrite selection" },
			{ "<leader>ah", "<cmd>Gen SyntaxHelp<CR>", mode = "n", desc = "AI syntax help" },
			{ "<leader>ah", ":Gen SyntaxHelp<CR>", mode = "v", desc = "AI syntax help" },
			{ "<leader>ac", ":Gen Complete_Code<CR>", mode = "v", desc = "AI complete selected code" },
		},
		opts = {
			model = "qwen2.5-coder:3b",
			display_mode = "float",
			win_config = {
				relative = "editor",
				width = math.floor(vim.o.columns * 0.9),
				height = math.floor(vim.o.lines * 0.75),
				row = math.floor(vim.o.lines * 0.1),
				col = math.floor(vim.o.columns * 0.05),
				border = "rounded",
			},
			show_prompt = false,
			show_model = true,
			prompts = {
				Complete_Code = {
					prompt = "Complete the following $filetype code. Only output the completed code in format ```$filetype\n...\n```:\n```$filetype\n$text\n```",
					replace = true,
					extract = "```$filetype\n(.-)```",
				},
				SyntaxHelp = {
					prompt = "Explain the syntax or idiom in this $filetype code briefly. Include the corrected form if something is wrong:\n```$filetype\n$text\n```",
				},
			},
		},
		config = function(_, opts)
			local gen = require("gen")
			local setup_opts = vim.deepcopy(opts)
			local prompts = setup_opts.prompts or {}

			setup_opts.prompts = nil
			gen.setup(setup_opts)

			for name, prompt in pairs(prompts) do
				gen.prompts[name] = prompt
			end
		end,
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
