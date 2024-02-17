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
        "prettierd",
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
        -- Use a sub-list to run only the first available formatter
        -- TODO: use prettierd by default as soon as https://github.com/fsouza/prettierd/issues/611 is fixed
        formatters_by_ft[prettier_filetype] = { { "prettier" } }
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

          return { timeout_ms = 2000, lsp_fallback = true }
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
    },
    opts = {
      workspaces = {
        {
          name = "work",
          path = "~/work/notes",
        },
        {
          name = "personal",
          path = "~/personal/notes",
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
    },
  },
  {
    "iamcco/markdown-preview.nvim",
    ft = { "markdown" },
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    keys = {
      {
        "<leader>mp",
        ":MarkdownPreview<CR>",
        desc = "Markdown Preview",
      },
    },
    build = function()
      vim.fn["mkdp#util#install"]()
    end,
    config = function()
      vim.api.nvim_exec(
        [[
          function OpenMarkdownPreview (url)
            execute "silent ! chrome --args --new-window " . a:url
          endfunction
      ]],
        false
      )
      -- a custom Vim function name to open preview page, this function will receive URL as param
      vim.g.mkdp_browserfunc = "OpenMarkdownPreview"
      -- nvim will auto close current preview window when changing from Markdown buffer to another buffer
      vim.g.mkdp_auto_close = 1
    end,
  },
  {
    "rest-nvim/rest.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    ft = "http",
    opts = {
      result = {
        -- toggle showing URL, HTTP info, headers at top the of result window
        show_url = true,
        show_http_info = true,
        show_headers = true,
        -- executables or functions for formatting response body [optional]
        -- set them to false if you want to disable them
        formatters = {
          json = "jq",
          html = function(body)
            return vim.fn.system({ "tidy", "-i", "-q", "-" }, body)
          end,
        },
      },
    },
    config = function(_, opts)
      vim.keymap.set("n", "<leader>rr", "<Plug>RestNvim", { desc = "run the request under the cursor" })
      vim.keymap.set("n", "<leader>rp", "<Plug>RestNvimPreview", { desc = "preview the request cURL command" })
      vim.keymap.set("n", "<leader>rl", "<Plug>RestNvimLast", { desc = "re-run the last request" })
      require("rest-nvim").setup(opts)
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
        harpoon:list():append()
      end, { desc = "append file to harpoon list" })
      vim.keymap.set("n", "<leader>z", function()
        harpoon.ui:toggle_quick_menu(harpoon:list())
      end, { desc = "toggle harpoon UI" })

      for index = 1, 5 do
        vim.keymap.set("n", string.format("<leader>%d", index), function()
          harpoon:list():select(index)
        end, { desc = string.format("navigate to harpoon file %d", index) })
      end
    end,
  },
  {
    "vinnymeller/swagger-preview.nvim",
    build = "npm install -g swagger-ui-watcher",
    keys = {
      { "<leader>sp", ":SwaggerPreviewToggle<CR>", desc = "open swagger preview" },
    },
    opts = {
      -- The port to run the preview server on
      port = 8000,
      -- The host to run the preview server on
      host = "localhost",
    },
    config = function(_, opts)
      require("swagger-preview").setup(opts)
    end,
  },
  {
    "postfen/clipboard-image.nvim",
    keys = {
      { "<leader>pi", ":PasteImg<CR>", desc = "paste image" },
    },
    opts = {
      default = {
        -- use the directory of your current file + img
        img_dir = { "%:p:h", "img" },
        img_name = function()
          vim.fn.inputsave()
          local name = vim.fn.input("Name: ")
          vim.fn.inputrestore()

          if name == nil or name == "" then
            return os.date("%y-%m-%d-%H-%M-%S")
          end
          return name
        end,
      },
    },
    config = function(_, opts)
      require("clipboard-image").setup(opts)
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
}
