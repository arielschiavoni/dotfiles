-- find all files, including hidden and ignored by .gitignore or ~/.config/fd/ignore
local function find_all_files()
  require("telescope.builtin").find_files({
    find_command = { "fd", "--type", "file", "--hidden", "--no-ignore", "--strip-cwd-prefix" },
  })
end

-- find all files, it includes hidden, ignored by .gitignore and ~/.config/fd/ignore but exclude node_modules
-- The 99% of the time node_modules are not relevant!
local function find_files()
  require("telescope.builtin").find_files({
    find_command = {
      "fd",
      "--type",
      "file",
      "--hidden",
      "--no-ignore",
      "--strip-cwd-prefix",
      "--exclude",
      "node_modules",
    },
  })
end

-- try to find files with git and if not found then fallback to find_files :-)
local function project_files()
  local ok = pcall(require("telescope.builtin").git_files, { show_untracked = true })
  if not ok then
    find_files()
  end
end

return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope-fzy-native.nvim",
    },
    event = { "VeryLazy" },
    keys = {
      { "<leader>to", ":Telescope<CR>", desc = "open telescope overwiew" },
      {
        "<leader>fa",
        find_all_files,
        desc = "find all files in the current working directory (includes node_modules)",
      },
      {
        "<leader>ff",
        find_files,
        desc = "find files in the current working directory (excludes node_modules)",
      },
      { "<leader>fp", project_files, desc = "find project git files (respects .gitignore)" },
      { "<leader>fb", ":Telescope buffers<CR>", desc = "find open buffers" },
      { "<leader>fl", ":Telescope current_buffer_fuzzy_find<CR>", desc = "search active buffer line" },
      { "<leader>fh", ":Telescope help_tags<CR>", desc = "list help entries" },
      {
        "<leader>fra",
        function()
          require("telescope.builtin").lsp_references({ show_line = false, file_ignore_patterns = { "test", "spec" } })
        end,
        desc = "Lists LSP references for word under the cursor (ignores tests)",
      },
      {
        "<leader>fri",
        function()
          require("telescope.builtin").lsp_incoming_calls({
            show_line = false,
            file_ignore_patterns = { "test", "spec" },
          })
        end,
        desc = "Lists LSP incoming calls for word under the cursor (ignores tests)",
      },
      {
        "<leader>fro",
        function()
          require("telescope.builtin").lsp_outgoing_calls()
        end,
        desc = "Lists LSP incoming calls for word under the cursor",
      },
    },
    config = function()
      local telescope = require("telescope")
      local sorters = require("telescope.sorters")
      local previewers = require("telescope.previewers")
      local actions = require("telescope.actions")
      local actions_layout = require("telescope.actions.layout")

      telescope.setup({
        defaults = {
          file_sorter = sorters.get_fzy_sorter,
          prompt_prefix = "> ",
          color_devicons = true,

          file_previewer = previewers.vim_buffer_cat.new,
          grep_previewer = previewers.vim_buffer_vimgrep.new,
          qflist_previewer = previewers.vim_buffer_qflist.new,

          mappings = {
            i = {
              ["<esc>"] = actions.close,
              ["<C-q>"] = actions.send_to_qflist,
              ["<C-j>"] = actions.cycle_previewers_next,
              ["<C-k>"] = actions.cycle_previewers_prev,
              ["<M-p>"] = actions_layout.toggle_preview,
            },
            n = {
              ["<M-p>"] = actions_layout.toggle_preview,
            },
          },
        },
        extensions = {
          fzy_native = {
            override_generic_sorter = false,
            override_file_sorter = true,
          },
        },
      })

      -- extensions
      telescope.load_extension("fzy_native")
    end,
  },
  {
    "nvim-telescope/telescope-file-browser.nvim",
    dependencies = {
      "nvim-telescope/telescope.nvim",
    },
    keys = {
      {
        "<leader>e",
        function()
          require("telescope").extensions.file_browser.file_browser({
            path = "%:p:h",
            hidden = true,
            respect_gitignore = false,
          })
        end,
        desc = "explore files in the folder of the active buffer",
      },
    },
    config = function()
      require("telescope").load_extension("file_browser")
    end,
  },
  {
    "nvim-telescope/telescope-live-grep-args.nvim",
    dependencies = {
      "nvim-telescope/telescope.nvim",
    },
    keys = {
      {
        "<leader>fs",
        function()
          require("telescope").extensions.live_grep_args.live_grep_args()
        end,
        desc = "[f]ind [s]tring across current working directory",
      },
    },
    config = function()
      local lga_actions = require("telescope-live-grep-args.actions")

      require("telescope").setup({
        extensions = {
          live_grep_args = {
            vimgrep_arguments = {
              "rg",
              "--color=never",
              "--no-heading",
              "--with-filename",
              "--line-number",
              "--column",
              "--smart-case",
              "--trim",
              "--hidden",
              "-g",
              "!node_modules/**",
              "-g",
              "!.git/**",
              "-g",
              "!package-lock.json",
              "-g",
              "!yarn.lock",
            },
            auto_quoting = true, -- enable/disable auto-quoting
            -- define mappings, e.g.
            mappings = { -- extend mappings
              i = {
                ["<C-k>"] = lga_actions.quote_prompt(),
                ["<C-i>"] = lga_actions.quote_prompt({ postfix = " --iglob " }),
              },
            },
          },
        },
      })

      require("telescope").load_extension("live_grep_args")
    end,
  },
  {
    "jemag/telescope-diff.nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
    keys = {
      {
        "<leader>fd2",
        function()
          require("telescope").extensions.diff.diff_files({ hidden = true })
        end,
        desc = "find 2 files to diff",
      },
      {
        "<leader>fd%",
        function()
          require("telescope").extensions.diff.diff_current({ hidden = true })
        end,
        desc = "find file to diff current buffer (%)",
      },
    },
    config = function()
      require("telescope").load_extension("diff")
    end,
  },
}
