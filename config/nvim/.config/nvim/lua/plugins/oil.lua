return {
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
      ["<C-l>"] = false,
      ["gs"] = false,
      ["<C-r>"] = "actions.refresh",
      ["<CR>"] = "actions.select",
      ["gd"] = {
        desc = "toggle detail view",
        callback = function()
          local oil = require("oil")
          local config = require("oil.config")
          if #config.columns == 1 then
            oil.set_columns({ "icon", "size", "mtime" })
          else
            oil.set_columns({ "icon" })
          end
        end,
      },
      ["gm"] = {
        desc = "Go to ~/Documents/media",
        callback = function()
          vim.cmd("edit $HOME/Documents/media")
          local oil = require("oil")
          oil.set_sort({ { "mtime", "desc" } })
        end,
      },
      ["<leader>sc"] = {
        desc = "Change files sorting",
        callback = "actions.change_sort",
      },
      ["<leader>ss"] = {
        desc = "Sort files by size",
        callback = function()
          local oil = require("oil")
          oil.set_sort({ { "size", "desc" } })
        end,
      },
      ["<leader>sm"] = {
        desc = "Sort files by modified date",
        callback = function()
          local oil = require("oil")
          oil.set_sort({ { "mtime", "desc" } })
        end,
      },
      ["<leader>sn"] = {
        desc = "Sort files by name",
        callback = function()
          local oil = require("oil")
          oil.set_sort({ { "name", "asc" } })
        end,
      },
      ["<leader>st"] = {
        desc = "Sort files by type",
        callback = function()
          local oil = require("oil")
          oil.set_sort({ { "type", "asc" }, { "name", "asc" } })
        end,
      },
    },
  },
  config = function(_, opts)
    require("oil").setup(opts)
  end,
}
