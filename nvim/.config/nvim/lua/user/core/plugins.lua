local fn = vim.fn
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

require("packer").startup(function(use)
  -- Packer
  use("wbthomason/packer.nvim")

  -- Themes
  use("ellisonleao/gruvbox.nvim")
  use("rebelot/kanagawa.nvim")

  -- Status line
  use({
    "nvim-lualine/lualine.nvim",
    requires = {
      "kyazdani42/nvim-web-devicons",
      opt = true,
    },
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
      -- the telescope setup increases the startup by +50% (~60ms), the first command will do the setup
      -- TODO: find a better way to fix this issue
      -- require("user.plugins.telescope")
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
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
    },
    config = function()
      require("user.plugins.nvim-cmp")
    end,
  })

  use({
    "JoosepAlviste/nvim-ts-context-commentstring",
  })

  use({
    "numToStr/Comment.nvim",
    config = function()
      require("user.plugins.comment")
    end,
  })

  use({
    "ThePrimeagen/git-worktree.nvim",
  })

  use({
    "jose-elias-alvarez/null-ls.nvim",
    config = function()
      require("user.plugins.null-ls")
    end,
  })

  use({
    "L3MON4D3/LuaSnip",
    config = function()
      require("user.plugins.luasnip")
    end,
  })

  use("dstein64/vim-startuptime")

  -- Automatically set up your configuration after cloning packer.nvim
  -- Put this at the end after all plugins
  if PACKER_BOOTSTRAP then
    require("packer").sync()
  end
end)
