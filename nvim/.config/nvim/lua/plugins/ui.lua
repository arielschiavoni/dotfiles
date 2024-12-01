return {
  -- icons
  {
    "echasnovski/mini.icons",
    lazy = true,
    opts = {},
    init = function()
      package.preload["nvim-web-devicons"] = function()
        require("mini.icons").mock_nvim_web_devicons()
        return package.loaded["nvim-web-devicons"]
      end
    end,
  },
  {
    -- +-------------------------------------------------+
    -- | A | B | C                             X | Y | Z |
    -- +-------------------------------------------------+
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    config = function()
      require("lualine").setup({
        sections = {
          -- https://github.com/nvim-lualine/lualine.nvim#filename-component-options
          lualine_a = { "mode" },
          lualine_b = { "branch", "diff", "diagnostics" },
          lualine_c = { { "filename", path = 3 } },
          lualine_x = { "encoding", "fileformat", "filetype", "filesize" },
          lualine_y = { "progress" },
          lualine_z = { "location" },
        },
        extensions = { "quickfix", "man", "fugitive", "oil", "nvim-dap-ui" },
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
        ["<C-l>"] = false,
        ["gs"] = false,
        ["<C-r>"] = "actions.refresh",
        ["<CR>"] = {
          desc = "Open file",
          callback = function()
            local oil = require("oil")
            local entry = oil.get_cursor_entry()

            local function is_imag_file(file_name)
              -- Extracting the file extension
              local extension = file_name:match("^.+(%..+)$")

              if extension then
                -- Removing the dot from the extension
                extension = extension:sub(2)

                -- Table of allowed extensions
                local allowedExtensions = { "png", "jpeg", "jpg", "bmp", "gif" }

                -- Checking if the extension is in the list of allowed extensions
                for _, ext in ipairs(allowedExtensions) do
                  if ext == extension then
                    return true
                  end
                end
              end

              return false
            end

            if entry["type"] == "file" then
              local dir = oil.get_current_dir()
              local file_name = entry["name"]
              local full_name = dir .. file_name

              -- image files can't be opened in neovim open them with wezterm in a pane
              if is_imag_file(full_name) then
                local cmd = "silent !wezterm cli split-pane --right -- bash -c 'wezterm imgcat "
                  .. full_name
                  .. " ; read'"
                vim.cmd(cmd)
                return
              else
              end
            end

            -- call default selection
            oil.select()
          end,
        },
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
        ["<leader>p"] = {
          desc = "Preview image",
          callback = function()
            local oil = require("oil")
            local entry = oil.get_cursor_entry()

            local function is_imag_file(file_name)
              -- Extracting the file extension
              local extension = file_name:match("^.+(%..+)$")

              if extension then
                -- Removing the dot from the extension
                extension = extension:sub(2)

                -- Table of allowed extensions
                local allowedExtensions = { "png", "jpeg", "jpg", "bmp", "gif" }

                -- Checking if the extension is in the list of allowed extensions
                for _, ext in ipairs(allowedExtensions) do
                  if ext == extension then
                    return true
                  end
                end
              end

              return false
            end

            if entry["type"] == "file" then
              local dir = oil.get_current_dir()
              local file_name = entry["name"]
              local full_name = dir .. file_name
              if is_imag_file(full_name) then
                local cmd = "silent !wezterm cli split-pane --right -- bash -c 'wezterm imgcat "
                  .. full_name
                  .. " ; read'"
                vim.cmd(cmd)
              end
            end
          end,
        },
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
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    cmd = "Neotree",
    keys = {
      {
        "<leader>fE",
        function()
          require("neo-tree.command").execute({ toggle = true, dir = vim.loop.cwd() })
        end,
        desc = "Explorer NeoTree (cwd)",
      },
    },
    opts = {
      enable_git_status = false,
      enable_diagnostics = false,
      source_selector = {
        winbar = false,
        statusline = false,
      },
      filesystem = {
        follow_current_file = {
          enabled = true,
        },
        filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = false,
          hide_by_name = {
            ".DS_Store",
            --"node_modules",
          },
        },
      },
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
      "MunifTanjim/nui.nvim",
    },
  },
  {
    -- show keymaps on the go
    "folke/which-key.nvim",
    event = "VeryLazy",
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer Local Keymaps (which-key)",
      },
      {
        "<leader>/",
        function()
          require("which-key").show({ global = true })
        end,
        desc = "Global Keymaps (which-key)",
      },
    },
    opts = {
      -- show a warning when issues were detected with your mappings
      notify = true,
      --- You can add any mappings here, or use `require('which-key').add()` later
      ---@type wk.Spec
      spec = {
        {
          mode = { "n", "v" },
          { "<leader>d", group = "debug" },
          { "<leader>f", group = "file/find" },
          { "<leader>g", group = "git" },
          { "[", group = "prev" },
          { "]", group = "next" },
          { "g", group = "goto" },
        },
      },
    },
  },
}
