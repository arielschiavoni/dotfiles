local fn = vim.fn

-- ~/.local/share/nvim
local install_path = fn.stdpath("data") .. "/site/pack/packer/start/packer.nvim"

if fn.empty(fn.glob(install_path)) > 0 then
  PACKER_BOOTSTRAP = fn.system({
    "git",
    "clone",
    "--depth",
    "1",
    "https://github.com/wbthomason/packer.nvim",
    install_path,
  })
end

-- Autocommand that reloads neovim whenever you save the plugins.lua file
vim.cmd([[
  augroup packer_user_config
    autocmd!
    autocmd BufWritePost plugins.lua source <afile> | PackerSync
  augroup end
]])

require("packer").startup(function(use)
  -- Packer
  use("wbthomason/packer.nvim")

  use("lewis6991/impatient.nvim")

  -- Themes
  use("ellisonleao/gruvbox.nvim")
  -- use("rebelot/kanagawa.nvim")

  use("kyazdani42/nvim-web-devicons")

  -- Utilities
  use("nvim-lua/plenary.nvim")

  -- Status line
  use({
    "nvim-lualine/lualine.nvim",
    config = function()
      require("user.plugins.lualine")
    end,
  })

  -- Telescope
  use({
    "nvim-telescope/telescope.nvim",
    requires = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope-fzy-native.nvim",
      "nvim-telescope/telescope-file-browser.nvim",
    },
    config = function()
      require("user.plugins.telescope")
    end,
  })

  -- Treesitter
  use({
    "nvim-treesitter/nvim-treesitter",
    run = ":TSUpdate",
    config = function()
      require("user.plugins.nvim-treesitter")
    end,
  })

  -- LSP
  use({
    "neovim/nvim-lspconfig",
    -- Config is done in nvim-lsp-installer
  })

  use({
    "williamboman/nvim-lsp-installer",
    config = function()
      require("user.plugins.nvim-lsp-installer")
    end,
  })

  -- Completion
  use({
    "hrsh7th/nvim-cmp",
    requires = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-cmdline",
      "hrsh7th/cmp-emoji",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-nvim-lua",
      "dmitmel/cmp-cmdline-history",
    },
    config = function()
      require("user.plugins.nvim-cmp")
    end,
  })

  use({
    "L3MON4D3/LuaSnip",
    config = function()
      require("user.plugins.luasnip")
    end,
  })

  use({ "saadparwaiz1/cmp_luasnip" })
  use({ "onsails/lspkind.nvim" })

  use({
    "rafamadriz/friendly-snippets",
  })

  use({
    "JoosepAlviste/nvim-ts-context-commentstring",
    after = "nvim-treesitter",
  })

  use({
    "numToStr/Comment.nvim",
    after = "nvim-treesitter",
    config = function()
      require("user.plugins.comment")
    end,
  })

  use({
    "ThePrimeagen/git-worktree.nvim",
    config = function()
      require("user.plugins.git-worktree")
    end,
  })

  use({
    "jose-elias-alvarez/null-ls.nvim",
    config = function()
      require("user.plugins.null-ls")
    end,
  })

  use("tpope/vim-surround")
  use("tpope/vim-fugitive")

  use({
    "lewis6991/gitsigns.nvim",
    requires = {
      "nvim-lua/plenary.nvim",
    },
    config = function()
      require("user.plugins.gitsigns")
    end,
  })

  use({
    "NTBBloodbath/rest.nvim",
    requires = { "nvim-lua/plenary.nvim" },
    config = function()
      require("user.plugins.rest")
    end,
  })

  use("dstein64/vim-startuptime")

  -- Automatically set up your configuration after cloning packer.nvim
  -- Put this at the end after all plugins
  if PACKER_BOOTSTRAP then
    require("packer").sync()
  end
end)
