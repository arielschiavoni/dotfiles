return {
  -- Performance
  "nathom/filetype.nvim",

  "nvim-lua/plenary.nvim",
  "nvim-lua/popup.nvim",
  "kyazdani42/nvim-web-devicons",

  -- Colorscheme section
  "gruvbox-community/gruvbox",

  -- Telescope
  "nvim-telescope/telescope-fzy-native.nvim",
  "nvim-telescope/telescope-file-browser.nvim",
  "nvim-telescope/telescope.nvim",
  "nvim-telescope/telescope-ui-select.nvim",

  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
  },
  "nvim-treesitter/playground",

  -- LSP
  "williamboman/mason.nvim",
  "williamboman/mason-lspconfig.nvim",
  "neovim/nvim-lspconfig",
  "onsails/lspkind.nvim",
  "jose-elias-alvarez/null-ls.nvim",
  "b0o/schemastore.nvim",

  -- Completion
  "hrsh7th/cmp-nvim-lsp",
  "hrsh7th/cmp-cmdline",
  "hrsh7th/cmp-emoji",
  "hrsh7th/cmp-buffer",
  "hrsh7th/cmp-path",
  "hrsh7th/cmp-nvim-lua",
  "dmitmel/cmp-cmdline-history",
  "hrsh7th/nvim-cmp",

  -- snippets
  "L3MON4D3/LuaSnip",
  "saadparwaiz1/cmp_luasnip",
  "rafamadriz/friendly-snippets",

  -- comments
  "JoosepAlviste/nvim-ts-context-commentstring",
  "numToStr/Comment.nvim",

  -- others
  "tpope/vim-surround",
  "ThePrimeagen/git-worktree.nvim",
  "NTBBloodbath/rest.nvim",
  {
    "iamcco/markdown-preview.nvim",
    build = "cd app && npm install",
    ft = { "markdown" },
  },
  "milisims/nvim-luaref",
  "lewis6991/gitsigns.nvim",
  "tpope/vim-unimpaired",
  { "akinsho/git-conflict.nvim", tag = "v1.0.0" },
  "ThePrimeagen/harpoon",
  { "michaelb/sniprun", build = "bash ./install.sh" },
  {
    "ThePrimeagen/refactoring.nvim",
    dependencies = {
      { "nvim-lua/plenary.nvim" },
      { "nvim-treesitter/nvim-treesitter" },
    },
  },
}
