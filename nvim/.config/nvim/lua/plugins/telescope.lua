-- find all files, including hidden and ignored by .gitignore or ~/.config/fd/ignore
local function find_all_files()
  require("telescope.builtin").find_files({
    find_command = { "fd", "--type", "file", "--hidden", "--no-ignore", "--strip-cwd-prefix" },
  })
end

local find_command = {
  "fd",
  "--type",
  "file",
  "--hidden",
  "--no-ignore",
  "--strip-cwd-prefix",
  "--exclude",
  "node_modules",
}
-- find all files, it includes hidden, ignored by .gitignore and ~/.config/fd/ignore but exclude node_modules
-- The 99% of the time node_modules are not relevant!
local function find_files()
  require("telescope.builtin").find_files({
    find_command = find_command,
  })
end

-- try to find files with git and if not found then fallback to find_files :-)
local function project_files()
  local ok = pcall(require("telescope.builtin").git_files, { show_untracked = true })
  if not ok then
    find_files()
  end
end

local function delete_git_stash(prompt_bufnr)
  local utils = require("telescope.utils")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local selection = action_state.get_selected_entry()
  local cwd = action_state.get_current_picker(prompt_bufnr).cwd

  if selection == nil then
    utils.__warn_no_selection("delete_git_stash")
    return
  end

  actions.close(prompt_bufnr)

  local _, ret, stderr = utils.get_os_command_output({ "git", "stash", "drop", selection.value }, cwd)

  if ret == 0 then
    utils.notify("delete_git_stash", {
      msg = string.format("Deleted git stash '%s'", selection.value),
      level = "INFO",
    })
  else
    utils.notify("delete_git_stash", {
      msg = string.format("Delete git stash %s. Git returned: '%s'", selection.value, table.concat(stderr, " ")),
      level = "ERROR",
    })
  end
end

local function find_git_stash()
  require("telescope.builtin").git_stash({
    attach_mappings = function(_, map)
      map({ "i", "n" }, "<c-x>", delete_git_stash)

      return true
    end,
  })
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
      { "<leader>fl", ":Telescope current_buffer_fuzzy_find<CR>", desc = "find line in current buffer" },
      { "<leader>fh", ":Telescope help_tags<CR>", desc = "find help" },
      { "<leader>fgs", find_git_stash, desc = "find git stash" },
      {
        "<leader>fra",
        function()
          require("telescope.builtin").lsp_references({ show_line = false, file_ignore_patterns = { "test", "spec" } })
        end,
        desc = "find all references (ignores tests)",
      },
      {
        "<leader>fri",
        function()
          require("telescope.builtin").lsp_incoming_calls({
            show_line = false,
            file_ignore_patterns = { "test", "spec" },
          })
        end,
        desc = "find incoming call references (ignores tests)",
      },
      {
        "<leader>fro",
        function()
          require("telescope.builtin").lsp_outgoing_calls()
        end,
        desc = "find outgoing call references",
      },
      {
        "<leader>fiw",
        function()
          require("telescope.builtin").grep_string({
            find_command = "rg",
            prompt_title = "< word under cursor >",
          })
        end,
        desc = "find word under the cursor",
      },
      {
        "<leader>fws",
        function()
          require("telescope.builtin").lsp_workspace_symbols()
        end,
        desc = "find workspace symbols",
      },
    },
    config = function()
      local telescope = require("telescope")
      local sorters = require("telescope.sorters")
      local previewers = require("telescope.previewers")
      local actions = require("telescope.actions")
      local actions_layout = require("telescope.actions.layout")

      telescope.setup({
        -- help telescope.setup
        defaults = {
          prompt_prefix = "> ",
          selection_caret = "> ",
          entry_prefix = "  ",
          multi_icon = "<>",
          winblend = 0,
          selection_strategy = "reset",
          -- show results from top to bottom
          sorting_strategy = "descending",
          scroll_strategy = "cycle",
          layout_strategy = "horizontal",
          layout_config = {
            width = 0.95,
            height = 0.85,
            -- show prompt at the top, it makes sense to use sorting_strategy = ascending if the prompt is on the top
            prompt_position = "bottom",
            horizontal = {
              preview_width = function(_, cols, _)
                if cols > 200 then
                  return math.floor(cols * 0.6)
                else
                  return math.floor(cols * 0.5)
                end
              end,
            },
            vertical = {
              width = 0.9,
              height = 0.95,
              preview_height = 0.5,
            },
            flex = {
              horizontal = {
                preview_width = 0.9,
              },
            },
          },

          file_sorter = sorters.get_fzy_sorter,
          file_previewer = previewers.vim_buffer_cat.new,
          grep_previewer = previewers.vim_buffer_vimgrep.new,
          qflist_previewer = previewers.vim_buffer_qflist.new,

          mappings = {
            i = {
              ["<C-q>"] = actions.send_to_qflist,
              ["<C-j>"] = actions.cycle_previewers_next,
              ["<C-k>"] = actions.cycle_previewers_prev,
              ["<C-Down>"] = actions.cycle_history_next,
              ["<C-Up>"] = actions.cycle_history_prev,
              ["<M-p>"] = actions_layout.toggle_preview,
              ["<M-m>"] = actions_layout.toggle_mirror,
              ["<M-Down>"] = actions_layout.cycle_layout_next,
              ["<M-Up>"] = actions_layout.cycle_layout_prev,
            },
            n = {
              ["<M-p>"] = actions_layout.toggle_preview,
            },
          },
          preview = {
            mime_hook = function(filepath, bufnr, opts)
              local is_image = function(filepath)
                local image_extensions = { "png", "jpg" } -- Supported image formats
                local split_path = vim.split(filepath:lower(), ".", { plain = true })
                local extension = split_path[#split_path]
                return vim.tbl_contains(image_extensions, extension)
              end

              if is_image(filepath) then
                local term = vim.api.nvim_open_term(bufnr, {})
                local function send_output(_, data, _)
                  for _, d in ipairs(data) do
                    vim.api.nvim_chan_send(term, d .. "\r\n")
                  end
                end

                vim.fn.jobstart({
                  "catimg",
                  filepath,
                }, {
                  on_stdout = send_output,
                  on_stderr = function(data)
                    vim.notify(data, vim.log.levels.ERROR)
                  end,
                  stdout_buffered = true,
                  pty = true,
                  on_std,
                })
              else
                require("telescope.previewers.utils").set_preview_message(
                  bufnr,
                  opts.winid,
                  "Binary cannot be previewed"
                )
              end
            end,
          },
        },
        extensions = {
          fzy_native = {
            override_generic_sorter = true,
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
        desc = "find string across current working directory",
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
        "<leader>gd2",
        function()
          require("telescope").extensions.diff.diff_files({ find_command = find_command })
        end,
        desc = "find 2 files to diff",
      },
      {
        "<leader>gd%",
        function()
          require("telescope").extensions.diff.diff_current({ find_command = find_command })
        end,
        desc = "find file to diff current buffer (%)",
      },
    },
    config = function()
      require("telescope").load_extension("diff")
    end,
  },
  {
    "arielschiavoni/dir-telescope.nvim",
    branch = "live_grep_args",
    dependencies = { "nvim-telescope/telescope.nvim", "nvim-telescope/telescope-live-grep-args.nvim" },
    keys = {
      {
        "<leader>fds",
        function()
          require("telescope").extensions.dir.live_grep()
        end,
        desc = "find string in directory",
      },
      {
        "<leader>fdf",
        function()
          require("telescope").extensions.dir.find_files()
        end,
        desc = "find file in directory",
      },
    },
    config = function()
      require("dir-telescope").setup({
        -- these are the default options set
        hidden = true,
        no_ignore = false,
        show_preview = true,
        live_grep = require("telescope").extensions.live_grep_args.live_grep_args,
      })
    end,
  },
}
