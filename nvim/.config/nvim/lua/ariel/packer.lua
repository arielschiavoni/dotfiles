require("packer").startup(function(use)
  use("wbthomason/packer.nvim")

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

  use({
    "nvim-treesitter/nvim-treesitter",
    run = ":TSUpdate",
  })

  -- LSP
  use("williamboman/nvim-lsp-installer")
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
  use("lewis6991/impatient.nvim")
  use("dstein64/vim-startuptime")
  use("tpope/vim-surround")
  use("ThePrimeagen/git-worktree.nvim")
  use("NTBBloodbath/rest.nvim")
end)