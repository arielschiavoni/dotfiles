return {
  {
    -- package manager, UI to discover, install and update lsp servers
    -- even though instalation can be done with its UI it is recommended define the list of LSPs and formattes
    -- in the ensure_installed configuration above
    "williamboman/mason.nvim",
    build = ":MasonUpdate",
    -- only load this package on demand when its command o keymap is invoqued.
    -- it does not make sense to bound this plugins with lsp configuration which
    -- needs to be loaded when any buffer is opened
    cmd = "Mason",
    keys = {
      { "<leader>ms", ":Mason<CR>", desc = "open Mason LSP package manager" },
    },
    opts = {
      -- https://github.com/williamboman/mason-lspconfig.nvim/blob/main/doc/server-mapping.md
      ensure_installed = {
        "eslint-lsp",
        "js-debug-adapter",
        "lua-language-server",
        "typescript-language-server",
        "graphql-language-service-cli",
        "yaml-language-server",
        "json-lsp",
        "tailwindcss-language-server",
        "terraform-ls",
        "gopls",
        "ocaml-lsp",
        "bash-language-server",
        "html-lsp",
        "nil",
      },
    },
    ---@param opts MasonSettings | {ensure_installed: string[]}
    config = function(_, opts)
      require("mason").setup(opts)
      local mr = require("mason-registry")
      for _, tool in ipairs(opts.ensure_installed) do
        local p = mr.get_package(tool)
        if not p:is_installed() then
          p:install()
        end
      end
    end,
  },
  {
    -- formatting
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    config = function()
      local prettier_filetypes = {
        "css",
        "graphql",
        "html",
        "javascript",
        "javascriptreact",
        "json",
        "jsonc",
        "markdown",
        "typescript",
        "typescriptreact",
        "yaml",
      }

      local formatters_by_ft = {
        lua = { "stylua" },
        ocaml = { "ocamlformat" },
        go = { "gofmt" },
        ["*"] = { "trim_whitespace" },
      }

      for _, prettier_filetype in ipairs(prettier_filetypes) do
        formatters_by_ft[prettier_filetype] = { "prettier" }
      end

      require("conform").setup({
        -- If this is set, Conform will run the formatter on save.
        -- It will pass the table to conform.format().
        format_on_save = function(bufnr)
          -- Disable with a global or buffer-local variable
          if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
            return
          end
          -- Disable autoformat for files in a certain path
          local bufname = vim.api.nvim_buf_get_name(bufnr)
          if bufname:match("/node_modules/") then
            return
          end

          return { timeout_ms = 2000, lsp_format = "fallback", stop_after_first = true }
        end,
        formatters_by_ft = formatters_by_ft,
        -- Set the log level. Use `:ConformInfo` to see the location of the log file.
        log_level = vim.log.levels.ERROR,
        -- Conform will notify you when a formatter errors
        notify_on_error = true,
      })

      vim.api.nvim_create_user_command("FormatDisable", function(args)
        if args.bang then
          -- FormatDisable! will disable formatting just for this buffer
          vim.b.disable_autoformat = true
        else
          vim.g.disable_autoformat = true
        end
      end, {
        desc = "Disable autoformat-on-save",
        bang = true,
      })

      vim.api.nvim_create_user_command("FormatEnable", function()
        vim.b.disable_autoformat = false
        vim.g.disable_autoformat = false
      end, {
        desc = "Re-enable autoformat-on-save",
      })

      vim.keymap.set(
        "n",
        "<leader>fd%",
        ":FormatDisable!<CR>",
        { desc = "disable auto format on save for the current buffer" }
      )
      vim.keymap.set("n", "<leader>fda", ":FormatDisable<CR>", { desc = "disable auto format on save" })
      vim.keymap.set("n", "<leader>fe", ":FormatEnable<CR>", { desc = "enable auto format on save" })
    end,
  },
  {
    "epwalsh/obsidian.nvim",
    version = "*", -- recommended, use latest release instead of latest commit
    dependencies = {
      -- Required.
      "nvim-lua/plenary.nvim",
    },
    keys = {
      { "<leader>ow", ":ObsidianWorkspace work<CR>", desc = "open obsidian work workspace" },
      { "<leader>op", ":ObsidianWorkspace personal<CR>", desc = "open obsidian personal workspace" },
      {
        "<leader>oq",
        ":ObsidianQuickSwitch<CR>",
        desc = "obsidian quickly switch to (or open) another note in your vault, searching by its name",
      },
      { "<leader>os", ":ObsidianSearch<CR>", desc = "obsidian search for (or create) notes in your vault" },
      { "<leader>ot", ":ObsidianToday<CR>", desc = "obsidian open/create a new daily note" },
      {
        "<leader>oy",
        ":ObsidianYesterday<CR>",
        desc = "obsidian open/create the daily note for the previous working day.",
      },
      {
        "<leader>om",
        ":ObsidianTomorrow<CR>",
        desc = "obsidian open/create the daily note for the next working day (Morgen)",
      },
      {
        "<leader>of",
        ":ObsidianFollowLink<CR>",
        desc = "obsidian follow a note reference under the cursor",
      },
      {
        "<leader>ob",
        ":ObsidianBacklinks<CR>",
        desc = "obsidian get a location list of references to the current buffer",
      },
      {
        "<leader>oe",
        ":ObsidianTemplate<CR>",
        desc = "obsidian insert a template from the templates folder, selecting from a list",
      },
      {
        "<leader>oi",
        ":ObsidianPasteImg<CR>",
        desc = "obsidian paste an image from the clipboard into the note at the cursor position",
      },
      {
        "<leader>on",
        ":ObsidianLinkNew<CR>",
        desc = "obsidian create a new note and link it to an inline visual selection of text",
        mode = "v",
      },
      {
        "<leader>ol",
        ":ObsidianLink<CR>",
        desc = "obsidian link an inline visual selection of text to a note",
        mode = "v",
      },
    },
    opts = {
      workspaces = {
        {
          name = "work",
          path = "~/Documents/work/notes",
        },
        {
          name = "personal",
          path = "~/Documents/personal/notes",
        },
      },
      follow_url_func = function(url)
        -- Open the URL in the default web browser.
        vim.fn.jobstart({ "open", url }) -- Mac OS
      end,
      templates = {
        subdir = "templates",
        date_format = "%Y-%m-%d",
        time_format = "%H:%M",
        -- A map for custom variables, the key should be the variable and the value a function
        substitutions = {
          yesterday = function()
            return os.date("%Y-%m-%d", os.time() - 86400)
          end,
        },
      },
      attachments = {
        -- The default folder to place images in via `:ObsidianPasteImg`.
        -- If this is a relative path it will be interpreted as relative to the vault root.
        -- You can always override this per image by passing a full path to the command instead of just a filename.
        img_folder = "assets/imgs", -- This is the default
        -- A function that determines the text to insert in the note when pasting an image.
        -- It takes two arguments, the `obsidian.Client` and a plenary `Path` to the image file.
        -- This is the default implementation.
        ---@param client obsidian.Client
        ---@param path Path the absolute path to the image file
        ---@return string
        img_text_func = function(client, path)
          local link_path
          local vault_relative_path = client:vault_relative_path(path)
          if vault_relative_path ~= nil then
            -- Use relative path if the image is saved in the vault dir.
            link_path = vault_relative_path
          else
            -- Otherwise use the absolute path.
            link_path = tostring(path)
          end
          local display_name = vim.fs.basename(link_path)
          return string.format("![%s](%s)", display_name, link_path)
        end,
      },
      ui = {
        enable = false,
        checkboxes = {
          -- NOTE: the 'char' value has to be a single character, and the highlight groups are defined below.
          [" "] = { char = "󰄱", hl_group = "ObsidianTodo" },
          ["x"] = { char = "", hl_group = "ObsidianDone" },
          -- [">"] = { char = "", hl_group = "ObsidianRightArrow" },
          -- ["~"] = { char = "󰰱", hl_group = "ObsidianTilde" },
          -- Replace the above with this if you don't have a patched font:
          -- [" "] = { char = "☐", hl_group = "ObsidianTodo" },
          -- ["x"] = { char = "✔", hl_group = "ObsidianDone" },

          -- You can also add more custom ones...
        },
      },
    },
  },
  {
    "iamcco/markdown-preview.nvim",
    ft = { "markdown" },
    keys = {
      {
        "<leader>mp",
        ":MarkdownPreview<CR>",
        ft = "markdown",
        desc = "Markdown Preview",
      },
    },
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = "cd app && yarn install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
      vim.cmd([[
      function OpenMarkdownPreview (url)
        execute "silent ! chrome --args --new-window " . a:url
      endfunction
       ]])
      -- a custom Vim function name to open preview page, this function will receive URL as param
      vim.g.mkdp_browserfunc = "OpenMarkdownPreview"
      -- nvim will auto close current preview window when changing from Markdown buffer to another buffer
      vim.g.mkdp_auto_close = 1
    end,
  },
  {
    "jellydn/hurl.nvim",
    branch = "main",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    ft = "hurl",
    keys = {
      -- Run API request
      { "<leader>hA", "<cmd>HurlRunner<CR>", ft = "hurl", desc = "Run All requests" },
      { "<leader>ha", "<cmd>HurlRunnerAt<CR>", ft = "hurl", desc = "Run Api request" },
      { "<leader>he", "<cmd>HurlRunnerToEntry<CR>", ft = "hurl", desc = "Run Api request to entry" },
      { "<leader>hE", "<cmd>HurlRunnerToEnd<CR>", ft = "hurl", desc = "Run Api request from current entry to end" },
      { "<leader>hv", "<cmd>HurlVerbose<CR>", ft = "hurl", desc = "Run Api in verbose mode" },
      { "<leader>hV", "<cmd>HurlVeryVerbose<CR>", ft = "hurl", desc = "Run Api in very verbose mode" },
      { "<leader>hr", "<cmd>HurlRerun<CR>", ft = "hurl", desc = "Rerun last command" },
      -- Run Hurl request in visual mode
      { "<leader>hh", ":HurlRunner<CR>", ft = "hurl", desc = "Hurl Runner", mode = "v" },
      -- Show last response
      { "<leader>hh", "<cmd>HurlShowLastResponse<CR>", ft = "hurl", desc = "History", mode = "n" },
      -- Manage variable
      { "<leader>hg", ":HurlSetVariable", ft = "hurl", desc = "Add global variable" },
      { "<leader>hG", "<cmd>HurlManageVariable<CR>", ft = "hurl", desc = "Manage global variable" },
      -- Toggle
      { "<leader>tH", "<cmd>HurlToggleMode<CR>", ft = "hurl", desc = "Toggle Hurl Split/Popup" },
    },
    config = function()
      require("hurl").setup({
        -- Show debugging info
        debug = false,
        -- Show notification on run
        show_notification = false,
        auto_close = false,
        -- Show response in popup or split
        mode = "split",
        -- Default formatter
        formatters = {
          json = { "jq" }, -- Make sure you have install jq in your system, e.g: brew install jq
          html = {
            "prettier", -- Make sure you have install prettier in your system, e.g: npm install -g prettier
            "--parser",
            "html",
          },
        },
        fixture_vars = {
          {
            name = "random_int_number",
            callback = function()
              return math.random(1, 1000)
            end,
          },
          {
            name = "random_float_number",
            callback = function()
              local result = math.random() * 10
              return string.format("%.2f", result)
            end,
          },
          {
            name = "now",
            callback = function()
              return os.date("%d/%m/%Y")
            end,
          },
        },
      })
    end,
  },
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = "VeryLazy",
    config = function()
      local harpoon = require("harpoon")

      ---@diagnostic disable-next-line: missing-parameter
      harpoon.setup()

      -- keymaps
      vim.keymap.set("n", "<leader>a", function()
        harpoon:list():add()
      end, { desc = "append file to harpoon list" })

      vim.keymap.set("n", "<leader>z", function()
        harpoon.ui:toggle_quick_menu(harpoon:list())
      end, { desc = "toggle harpoon UI" })

      for index = 1, 5 do
        vim.keymap.set("n", string.format("<leader>%d", index), function()
          harpoon:list():select(index)
        end, { desc = string.format("navigate to harpoon file %d", index) })
      end

      -- Toggle previous & next buffers stored within Harpoon list
      vim.keymap.set("n", "<C-S-P>", function()
        harpoon:list():prev()
      end)
      vim.keymap.set("n", "<C-S-N>", function()
        harpoon:list():next()
      end)

      -- Toggle previous & next buffers stored within Harpoon listharpooharpoo
      vim.keymap.set("n", "<C-p>", function()
        harpoon:list():prev()
      end)
      vim.keymap.set("n", "<C-n>", function()
        harpoon:list():next()
      end)
    end,
  },
  {
    "2nthony/sortjson.nvim",
    cmd = {
      "SortJSONByAlphaNum",
      "SortJSONByAlphaNumReverse",
      "SortJSONByKeyLength",
      "SortJSONByKeyLengthReverse",
    },
    config = true,
  },
  {
    "riddlew/asciitree.nvim",
    cmd = {
      "AsciiTree",
    },
    config = function()
      -- Default values
      require("asciitree").setup({
        -- Characters used to represent the tree.
        symbols = {
          child = "├",
          last = "└",
          parent = "│",
          dash = "─",
          blank = " ",
        },

        -- How deep each level should be drawn. This value can be overridden by
        -- calling the AsciiTree command with a number, such as :AsciiTree 4.
        depth = 2,

        -- The delimiter to look for when converting to a tree. By default, this
        -- looks for a tree that looks like:
        -- # Level 1
        -- ## Level 2
        -- ### Level 3
        -- #### Level 4
        --
        -- Changing it to "+" would look for the following:
        -- + Level 1
        -- ++ Level 2
        -- +++ Level 3
        -- ++++ Level 4
        delimiter = "#",
      })
    end,
  },
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      { "<C-g>a", "<cmd>CodeCompanionActions<cr>", desc = "Open the Action Palette", mode = { "n", "v" } },
      { "<C-g>t", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle a chat buffer", mode = { "n", "v" } },
      {
        "ga",
        "<cmd>CodeCompanionChat Add<cr>",
        desc = "Add visually selected chat to the current chat buffer",
        mode = { "v" },
      },
    },
    config = function()
      -- Expand 'cc' into 'CodeCompanion' in the command line
      vim.cmd([[cab cc CodeCompanion]])

      require("codecompanion").setup({
        display = {
          chat = {
            show_settings = false, -- I'm using this to prove that the default model is not changed.
          },
        },
        -- opts = { log_level = "TRACE" },
        strategies = {
          chat = {
            adapter = "gemini",
          },
          inline = {
            adapter = "gemini",
          },
        },
        adapters = {
          openai = function()
            return require("codecompanion.adapters").extend("openai", {
              env = {
                api_key = "cmd:op read op://Personal/OpenAI/API_KEY --no-newline",
              },
              schema = {
                -- https://platform.openai.com/docs/models
                model = {
                  -- default = "o3-mini-2025-01-31", -- only support via API for tier 4 users (i am tier 1)
                  -- default = "o1-mini",
                  default = "gpt-4o-mini",
                },
              },
            })
          end,
          gemini = function()
            return require("codecompanion.adapters").extend("gemini", {
              env = {
                api_key = "cmd:op read op://Personal/Gemini/credential --no-newline",
              },
              schema = {
                model = {
                  default = "gemini-2.0-flash",
                },
              },
            })
          end,
        },
      })
    end,
  },
  {
    "letieu/wezterm-move.nvim",
    keys = {
      {
        "<C-h>",
        function()
          require("wezterm-move").move("h")
        end,
      },
      {
        "<C-j>",
        function()
          require("wezterm-move").move("j")
        end,
      },
      {
        "<C-k>",
        function()
          require("wezterm-move").move("k")
        end,
      },
      {
        "<C-l>",
        function()
          require("wezterm-move").move("l")
        end,
      },
    },
  },
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    ---@type Flash.Config
    opts = {},
    -- stylua: ignore
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
      { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
      { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
    },
  },
  {
    "christoomey/vim-tmux-navigator",
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
      "TmuxNavigatorProcessList",
    },
    keys = {
      { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>" },
      { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>" },
      { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>" },
      { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>" },
      { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>" },
    },
  },
}
