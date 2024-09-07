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
      ui = { enable = false },
    },
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = "markdown",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<leader>rmt", "<cmd>RenderMarkdown toggle<CR>", ft = "markdown", desc = "Render markdown toggle" },
    },
  },
  {
    "toppair/peek.nvim",
    build = "deno task --quiet build:fast",
    keys = {
      {
        "<leader>mp",
        function()
          local peek = require("peek")
          if peek.is_open() then
            peek.close()
          else
            peek.open()
          end
        end,
        ft = "markdown",
        desc = "Peek (Markdown Preview)",
      },
    },
    config = function()
      require("peek").setup({
        auto_load = true, -- whether to automatically load preview when entering another markdown buffer
        close_on_bdelete = true, -- close preview window on buffer delete

        syntax = true, -- enable syntax highlighting, affects performance

        theme = "light", -- 'dark' or 'light'

        update_on_change = true,

        -- app = "webview", -- 'webview', 'browser', string or a table of strings
        app = "webview",
        -- app = { "Google Chrome", "--args", "--new-window" },

        filetype = { "markdown" }, -- list of filetypes to recognize as markdown

        -- relevant if update_on_change is true
        throttle_at = 200000, -- start throttling when file exceeds this
        -- amount of bytes in size
        throttle_time = "auto", -- minimum amount of time in milliseconds
        -- that has to pass before starting new render
      })
    end,
  },
  {
    "jellydn/hurl.nvim",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    ft = "hurl",
    keys = {
      -- Run API request
      { "<leader>hR", "<cmd>HurlRunner<CR>", ft = "hurl", desc = "Run All requests" },
      { "<leader>hr", "<cmd>HurlRunnerAt<CR>", ft = "hurl", desc = "Run Api request" },
      -- { "<leader>te", "<cmd>HurlRunnerToEntry<CR>", ft = "hurl", desc = "Run Api request to entry" },
      { "<leader>ht", "<cmd>HurlToggleMode<CR>", ft = "hurl", desc = "Hurl Toggle Mode" },
      { "<leader>hv", "<cmd>HurlVerbose<CR>", ft = "hurl", desc = "Run Api in verbose mode" },
      -- Run Hurl request in visual mode
      { "<leader>h", ":HurlRunner<CR>", ft = "hurl", desc = "Hurl Runner", mode = "v" },
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
    "jackMort/ChatGPT.nvim",
    keys = {
      { "<leader>Cc", ":ChatGPT<CR>", desc = "ChatGPT" },
      { "<leader>Ce", ":ChatGPTEditWithInstruction<CR>", desc = "Edit with instruction", mode = { "n", "v" } },
      { "<leader>Cg", ":ChatGPTRun grammar_correction<CR>", desc = "Grammar Correction", mode = { "n", "v" } },
      { "<leader>Ct", ":ChatGPTRun translate<CR>", desc = "Translate", mode = { "n", "v" } },
      { "<leader>Ck", ":ChatGPTRun keywords<CR>", desc = "Keywords", mode = { "n", "v" } },
      { "<leader>Cd", ":ChatGPTRun docstring<CR>", desc = "Docstring", mode = { "n", "v" } },
      { "<leader>Ca", ":ChatGPTRun add_tests<CR>", desc = "Add Tests", mode = { "n", "v" } },
      { "<leader>Co", ":ChatGPTRun optimize_code<CR>", desc = "Optimize Code", mode = { "n", "v" } },
      { "<leader>Cs", ":ChatGPTRun summarize<CR>", desc = "Summarize", mode = { "n", "v" } },
      { "<leader>Cf", ":ChatGPTRun fix_bugs<CR>", desc = "Fix Bugs", mode = { "n", "v" } },
      { "<leader>Cx", ":ChatGPTRun explain_code<CR>", desc = "Explain Code", mode = { "n", "v" } },
      { "<leader>Cr", ":ChatGPTRun roxygen_edit<CR>", desc = "Roxygen Edit", mode = { "n", "v" } },
      {
        "<leader>Cl",
        ":ChatGPTRun code_readability_analysis<CR>",
        desc = "Code Readability Analysis",
        mode = { "n", "v" },
      },
    },
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "folke/trouble.nvim",
      "nvim-telescope/telescope.nvim",
    },
    config = function()
      -- https://github.com/jackMort/ChatGPT.nvim?tab=readme-ov-file#configuration
      require("chatgpt").setup({
        api_key_cmd = "op read op://Personal/OpenAI/API_KEY --no-newline",
        -- this config assumes you have OPENAI_API_KEY environment variable set
        openai_params = {
          model = "gpt-4o-mini",
          -- The maximum number of tokens that can be generated in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.
          max_tokens = 16384,
          -- The sampling temperature, between 0 and 1. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic.
          -- If set to 0, the model will use log probability to automatically increase the temperature until certain thresholds are hit.
          -- @default 1
          temperature = 1,
          -- Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim.
          -- @default 0
          frequency_penalty = 0,
          -- Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics.
          -- @default 0
          presence_penalty = 0,
          -- An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered.
          -- We generally recommend altering this or temperature but not both.
          -- @default 1
          top_p = 1,
          -- How many chat completion choices to generate for each input message. Note that you will be charged based on the number of generated tokens across all of the choices. Keep n as 1 to minimize costs.
          -- @default 1
          n = 1,
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
}
