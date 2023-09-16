return {
  {
    -- +-------------------------------------------------+
    -- | A | B | C                             X | Y | Z |
    -- +-------------------------------------------------+
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    config = function()
      require("lualine").setup({
        options = {
          theme = "tokyonight",
        },
        sections = {
          -- https://github.com/nvim-lualine/lualine.nvim#filename-component-options
          -- disable filename, it is shown top right in the winbar
          lualine_c = {},
          lualine_y = { "filetype", "filesize" },
        },
      })
    end,
  },
  {
    -- nicer vim.input and vim.select UI elements
    "stevearc/dressing.nvim",
    event = "VeryLazy",
  },
  {
    -- file manager in vim
    "stevearc/oil.nvim",
    event = "VeryLazy",
    keys = {
      {
        "-",
        function()
          require("oil").open()
        end,
        desc = "open parent directory",
      },
    },
    opts = {
      columns = {
        "icon",
        -- "permissions",
        -- "size",
        -- "mtime",
      },
      -- https://github.com/stevearc/oil.nvim#options
      view_options = {
        -- Show files and directories that start with "."
        show_hidden = true,
      },
      keymaps = {
        -- deactivate undesired keymaps
        ["<C-s>"] = false,
        ["<C-h>"] = false,
        ["<C-t>"] = false,
        ["<C-p>"] = false,
        ["gs"] = false,
      },
    },
    config = function(_, opts)
      require("oil").setup(opts)
    end,
  },
  {
    "mbbill/undotree",
    event = "VeryLazy",
    config = function()
      vim.o.undofile = true
      vim.g.undotree_SplitWidth = 50
      vim.keymap.set("n", "<leader>u", vim.cmd.UndotreeToggle, { desc = "toggle undotree" })
    end,
  },
  {
    -- show keymaps on the go
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      plugins = { spelling = true },
      defaults = {
        mode = { "n", "v" },
        ["g"] = { name = "+goto" },
        ["]"] = { name = "+next" },
        ["["] = { name = "+prev" },
        ["<leader>f"] = { name = "+file/find" },
        ["<leader>g"] = { name = "+git" },
        ["<leader>d"] = { name = "+debug" },
      },
    },
    config = function(_, opts)
      vim.o.timeout = true
      vim.o.timeoutlen = 300
      local wk = require("which-key")
      wk.setup(opts)
      wk.register(opts.defaults)
    end,
  },
}
