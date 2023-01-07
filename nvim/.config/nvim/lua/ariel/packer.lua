require("packer").startup(function(use)
  use("wbthomason/packer.nvim")
  -- Performance
  use("nathom/filetype.nvim")
  use("lewis6991/impatient.nvim")

  -- TJ created lodash of neovim
  use("nvim-lua/plenary.nvim")
  use("nvim-lua/popup.nvim")

  use("kyazdani42/nvim-web-devicons")

  -- Colorscheme section
  use("gruvbox-community/gruvbox")
  -- use("folke/tokyonight.nvim")

  -- Status line
  use("nvim-lualine/lualine.nvim")

  -- Telescope
  use("nvim-telescope/telescope-fzy-native.nvim")
  use("nvim-telescope/telescope-file-browser.nvim")
  use("nvim-telescope/telescope.nvim")
  use("nvim-telescope/telescope-ui-select.nvim")

  use({
    "nvim-treesitter/nvim-treesitter",
    run = ":TSUpdate",
  })
  use("nvim-treesitter/playground")

  -- LSP
  use("williamboman/mason.nvim")
  use("williamboman/mason-lspconfig.nvim")
  use("neovim/nvim-lspconfig")
  use("onsails/lspkind.nvim")
  use("jose-elias-alvarez/null-ls.nvim")
  use("b0o/schemastore.nvim")

  -- Completion
  use("hrsh7th/cmp-nvim-lsp")
  use("hrsh7th/cmp-cmdline")
  use("hrsh7th/cmp-emoji")
  use("hrsh7th/cmp-buffer")
  use("hrsh7th/cmp-path")
  use("hrsh7th/cmp-nvim-lua")
  use("dmitmel/cmp-cmdline-history")
  use("hrsh7th/nvim-cmp")

  -- snippets
  use("L3MON4D3/LuaSnip")
  use("saadparwaiz1/cmp_luasnip")
  use("rafamadriz/friendly-snippets")

  -- comments
  use("JoosepAlviste/nvim-ts-context-commentstring")
  use("numToStr/Comment.nvim")

  -- others
  use("tpope/vim-surround")
  use("ThePrimeagen/git-worktree.nvim")
  use("NTBBloodbath/rest.nvim")
  use({
    "iamcco/markdown-preview.nvim",
    run = "cd app && npm install",
    ft = { "markdown" },
  })
  use("milisims/nvim-luaref")
  use("lewis6991/gitsigns.nvim")
  use("tpope/vim-unimpaired")
  use({ "akinsho/git-conflict.nvim", tag = "*" })
  use("ThePrimeagen/harpoon")
  use({ "michaelb/sniprun", run = "bash ./install.sh" })
  use({
    "ThePrimeagen/refactoring.nvim",
    requires = {
      { "nvim-lua/plenary.nvim" },
      { "nvim-treesitter/nvim-treesitter" },
    },
  })
end)
