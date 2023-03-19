return {
  -- Performance
  "nathom/filetype.nvim",

  -- Common dependencies required by several packages
  "nvim-lua/plenary.nvim",
  "nvim-lua/popup.nvim",
  "kyazdani42/nvim-web-devicons",

  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
  },

  {
    "nvim-treesitter/playground",
    cmd = "TSPlaygroundToggle",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
  },

  -- LSP
  "williamboman/mason.nvim",
  "williamboman/mason-lspconfig.nvim",
  "neovim/nvim-lspconfig",
  "jose-elias-alvarez/null-ls.nvim",
  "b0o/schemastore.nvim",

  -- others
  "tpope/vim-surround",
  "tpope/vim-unimpaired",
  "tpope/vim-fugitive",

  -- git
  "ThePrimeagen/git-worktree.nvim",
}
