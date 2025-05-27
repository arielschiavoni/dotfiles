return {
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "j-hui/fidget.nvim",
  },
  event = "VeryLazy",
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
          keymaps = {
            close = {
              modes = { n = "<C-q>", i = "<C-q" },
            },
            -- Add further custom keymaps here
          },
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
                -- default = "gemini-2.0-flash",
                default = "gemini-2.5-flash-preview-05-20",
                -- https://github.com/olimorris/codecompanion.nvim/discussions/1337
              },
            },
          })
        end,
      },
    })

    local progress = require("fidget.progress")
    local handles = {}
    local group = vim.api.nvim_create_augroup("CodeCompanionFidget", {})

    vim.api.nvim_create_autocmd("User", {
      pattern = "CodeCompanionRequestStarted",
      group = group,
      callback = function(e)
        handles[e.data.id] = progress.handle.create({
          title = "CodeCompanion",
          message = "Thinking...",
          lsp_client = { name = e.data.adapter.formatted_name },
        })
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      pattern = "CodeCompanionRequestFinished",
      group = group,
      callback = function(e)
        local h = handles[e.data.id]
        if h then
          h.message = e.data.status == "success" and "Done" or "Failed"
          h:finish()
          handles[e.data.id] = nil
        end
      end,
    })
  end,
}
