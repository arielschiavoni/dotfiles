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
    branch = "canary",
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
    "robitx/gp.nvim",
    keys = {
      -- normal mode
      { "<C-g><C-t>", "<cmd>GpChatNew tabnew<cr>", desc = "New Chat tabnew", mode = { "n" } },
      { "<C-g><C-v>", "<cmd>GpChatNew vsplit<cr>", desc = "New Chat vsplit", mode = { "n" } },
      { "<C-g><C-x>", "<cmd>GpChatNew split<cr>", desc = "New Chat split", mode = { "n" } },
      { "<C-g>a", "<cmd>GpAppend<cr>", desc = "Append (after)", mode = { "n" } },
      { "<C-g>b", "<cmd>GpPrepend<cr>", desc = "Prepend (before)", mode = { "n" } },
      { "<C-g>c", "<cmd>GpChatNew<cr>", desc = "New Chat", mode = { "n" } },
      { "<C-g>f", "<cmd>GpChatFinder<cr>", desc = "Chat Finder", mode = { "n" } },
      { "<C-g>ge", "<cmd>GpEnew<cr>", desc = "GpEnew", mode = { "n" } },
      { "<C-g>gn", "<cmd>GpNew<cr>", desc = "GpNew", mode = { "n" } },
      { "<C-g>gp", "<cmd>GpPopup<cr>", desc = "Popup", mode = { "n" } },
      { "<C-g>gt", "<cmd>GpTabnew<cr>", desc = "GpTabnew", mode = { "n" } },
      { "<C-g>gv", "<cmd>GpVnew<cr>", desc = "GpVnew", mode = { "n" } },
      { "<C-g>n", "<cmd>GpNextAgent<cr>", desc = "Next Agent", mode = { "n" } },
      { "<C-g>r", "<cmd>GpRewrite<cr>", desc = "Inline Rewrite", mode = { "n" } },
      { "<C-g>s", "<cmd>GpStop<cr>", desc = "GpStop", mode = { "n" } },
      { "<C-g>t", "<cmd>GpChatToggle<cr>", desc = "Toggle Chat", mode = { "n" } },
      { "<C-g>x", "<cmd>GpContext<cr>", desc = "Toggle GpContext", mode = { "n" } },
      -- visual mode
      { "<C-g><C-t>", ":<C-u>'<,'>GpChatNew tabnew<cr>", desc = "ChatNew tabnew", mode = { "v" } },
      { "<C-g><C-v>", ":<C-u>'<,'>GpChatNew vsplit<cr>", desc = "ChatNew vsplit", mode = { "v" } },
      { "<C-g><C-x>", ":<C-u>'<,'>GpChatNew split<cr>", desc = "ChatNew split", mode = { "v" } },
      { "<C-g>a", ":<C-u>'<,'>GpAppend<cr>", desc = "Visual Append (after)", mode = { "v" } },
      { "<C-g>b", ":<C-u>'<,'>GpPrepend<cr>", desc = "Visual Prepend (before)", mode = { "v" } },
      { "<C-g>c", ":<C-u>'<,'>GpChatNew<cr>", desc = "Visual Chat New", mode = { "v" } },
      { "<C-g>ge", ":<C-u>'<,'>GpEnew<cr>", desc = "Visual GpEnew", mode = { "v" } },
      { "<C-g>gn", ":<C-u>'<,'>GpNew<cr>", desc = "Visual GpNew", mode = { "v" } },
      { "<C-g>gp", ":<C-u>'<,'>GpPopup<cr>", desc = "Visual Popup", mode = { "v" } },
      { "<C-g>gt", ":<C-u>'<,'>GpTabnew<cr>", desc = "Visual GpTabnew", mode = { "v" } },
      { "<C-g>gv", ":<C-u>'<,'>GpVnew<cr>", desc = "Visual GpVnew", mode = { "v" } },
      { "<C-g>i", ":<C-u>'<,'>GpImplement<cr>", desc = "Implement selection", mode = { "v" } },
      { "<C-g>n", "<cmd>GpNextAgent<cr>", desc = "Next Agent", mode = { "v" } },
      { "<C-g>p", ":<C-u>'<,'>GpChatPaste<cr>", desc = "Visual Chat Paste", mode = { "v" } },
      { "<C-g>r", ":<C-u>'<,'>GpRewrite<cr>", desc = "Visual Rewrite", mode = { "v" } },
      { "<C-g>s", "<cmd>GpStop<cr>", desc = "GpStop", mode = { "v" } },
      { "<C-g>t", ":<C-u>'<,'>GpChatToggle<cr>", desc = "Visual Toggle Chat", mode = { "v" } },
      { "<C-g>x", ":<C-u>'<,'>GpContext<cr>", desc = "Visual GpContext", mode = { "v" } },
      -- insert mode
      { "<C-g><C-t>", "<cmd>GpChatNew tabnew<cr>", desc = "New Chat tabnew", mode = { "i" } },
      { "<C-g><C-v>", "<cmd>GpChatNew vsplit<cr>", desc = "New Chat vsplit", mode = { "i" } },
      { "<C-g><C-x>", "<cmd>GpChatNew split<cr>", desc = "New Chat split", mode = { "i" } },
      { "<C-g>a", "<cmd>GpAppend<cr>", desc = "Append (after)", mode = { "i" } },
      { "<C-g>b", "<cmd>GpPrepend<cr>", desc = "Prepend (before)", mode = { "i" } },
      { "<C-g>c", "<cmd>GpChatNew<cr>", desc = "New Chat", mode = { "i" } },
      { "<C-g>f", "<cmd>GpChatFinder<cr>", desc = "Chat Finder", mode = { "i" } },
      { "<C-g>ge", "<cmd>GpEnew<cr>", desc = "GpEnew", mode = { "i" } },
      { "<C-g>gn", "<cmd>GpNew<cr>", desc = "GpNew", mode = { "i" } },
      { "<C-g>gp", "<cmd>GpPopup<cr>", desc = "Popup", mode = { "i" } },
      { "<C-g>gt", "<cmd>GpTabnew<cr>", desc = "GpTabnew", mode = { "i" } },
      { "<C-g>gv", "<cmd>GpVnew<cr>", desc = "GpVnew", mode = { "i" } },
      { "<C-g>n", "<cmd>GpNextAgent<cr>", desc = "Next Agent", mode = { "i" } },
      { "<C-g>r", "<cmd>GpRewrite<cr>", desc = "Inline Rewrite", mode = { "i" } },
      { "<C-g>s", "<cmd>GpStop<cr>", desc = "GpStop", mode = { "i" } },
      { "<C-g>t", "<cmd>GpChatToggle<cr>", desc = "Toggle Chat", mode = { "i" } },
      { "<C-g>x", "<cmd>GpContext<cr>", desc = "Toggle GpContext", mode = { "i" } },
    },
    -- https://github.com/Robitx/gp.nvim/blob/8b448c06651ebfc6b810bf37029d0a1ee43c237e/lua/gp/config.lua#L9-L602
    config = function()
      local openapi_prompt = [[
You are a professional Software Developer and Architect specializing in AWS services, TypeScript, AWS CDK, npm, and esbuild. Your responsibilities include:

- Designing and developing scalable, secure software solutions.
- Implementing and managing AWS cloud infrastructure.
- Maintaining TypeScript codebases.
- Using AWS CDK for infrastructure-as-code.
- Packaging with npm.
- Bundling and optimizing with esbuild.

**Technologies and Expertise:**
- **AWS Services:** CloudFormation, Lambda, S3, EC2, RDS, IAM.
- **TypeScript:** Advanced TypeScript skills.
- **AWS CDK:** Proficient in creating and managing infrastructure-as-code.
- **npm:** In-depth knowledge of package management and distribution.
- **esbuild:** Efficiently bundling and optimizing code.

**Requirements:**
- Ensure responses are concise and avoid repeating the provided context.
- Provide examples in TypeScript by default.

Using this persona, generate an OpenAPI definition for a service you might use or develop, including typical operations like creating, updating, and deleting resources, following best practices.
]]
      require("gp").setup({
        openai_api_key = { "op", "read", "op://Personal/OpenAI/API_KEY", "--no-newline" },
        -- default command agents (model + persona)
        -- name, model and system_prompt are mandatory fields
        -- to use agent for chat set chat = true, for command set command = true
        -- to remove some default agent completely set it like:
        -- agents = {  { name = "ChatGPT3-5", disable = true, }, ... },
        agents = {
          {
            provider = "openai",
            name = "ChatGPT4o-mini",
            chat = true,
            command = false,
            -- string with model name or table with model name and parameters
            model = { model = "gpt-4o-mini", temperature = 1.1, top_p = 1 },
            -- system prompt (use this to specify the persona/role of the AI)
            -- system_prompt = require("gp.defaults").chat_system_prompt,
            system_prompt = openapi_prompt,
          },
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
}
