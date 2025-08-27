return {
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "j-hui/fidget.nvim",
    "ravitemer/codecompanion-history.nvim",
  },
  event = "VeryLazy",
  keys = {
    { "<C-g>a", "<cmd>CodeCompanionActions<cr>", desc = "Open the Action Palette", mode = { "n", "v" } },
    { "<C-g>t", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle a chat buffer", mode = { "n", "v" } },
    {
      "ga",
      "<cmd>CodeCompanionChat Add<cr>",
      desc = "Add visually selected chat to the current chat buffer",
      mode = { "x" },
    },
  },
  config = function()
    -- Expand 'cc' into 'CodeCompanion' in the command line
    vim.cmd([[cab cc CodeCompanion]])

    require("codecompanion").setup({
      display = {
        chat = {
          auto_scroll = false,
        },
      },
      strategies = {
        chat = {
          adapter = "xai",
        },
        inline = {
          adapter = "xai",
        },
      },
      adapters = {
        openai = function()
          return require("codecompanion.adapters").extend("openai", {
            env = {
              api_key = os.getenv("OPENAI_API_KEY"),
            },
            schema = {
              model = {
                default = "gpt-5-mini",
              },
            },
          })
        end,
        gemini = function()
          return require("codecompanion.adapters").extend("gemini", {
            env = {
              api_key = os.getenv("GEMINI_API_KEY"),
            },
            schema = {
              model = {
                default = "gemini-2.5-flash",
              },
              reasoning_effort = {
                default = "high",
              },
            },
          })
        end,
        xai = function()
          return require("codecompanion.adapters").extend("xai", {
            env = {
              api_key = os.getenv("XAI_API_KEY"),
            },
            schema = {
              model = {
                default = "grok-3-mini",
                choices = {
                  "grok-3-mini",
                  "grok-4",
                },
              },
            },
          })
        end,
      },
      extensions = {
        history = {
          enabled = true,
          opts = {
            -- Keymap to open history from chat buffer (default: gh)
            keymap = "gh",
            -- Keymap to save the current chat manually (when auto_save is disabled)
            save_chat_keymap = "sc",
            -- Save all chats by default (disable to save only manually using 'sc')
            auto_save = true,
            -- Number of days after which chats are automatically deleted (0 to disable)
            expiration_days = 0,
            -- Picker interface (auto resolved to a valid picker)
            picker = "snacks", --- ("telescope", "snacks", "fzf-lua", or "default")
            ---Optional filter function to control which chats are shown when browsing
            chat_filter = nil, -- function(chat_data) return boolean end
            -- Customize picker keymaps (optional)
            picker_keymaps = {
              rename = { n = "r", i = "<M-r>" },
              delete = { n = "d", i = "<M-d>" },
              duplicate = { n = "<C-y>", i = "<C-y>" },
            },
            ---Automatically generate titles for new chats
            auto_generate_title = true,
            title_generation_opts = {
              ---Adapter for generating titles (defaults to current chat adapter)
              adapter = nil, -- "copilot"
              ---Model for generating titles (defaults to current chat model)
              model = nil, -- "gpt-4o"
              ---Number of user prompts after which to refresh the title (0 to disable)
              refresh_every_n_prompts = 0, -- e.g., 3 to refresh after every 3rd user prompt
              ---Maximum number of times to refresh the title (default: 3)
              max_refreshes = 3,
              format_title = function(original_title)
                -- this can be a custom function that applies some custom
                -- formatting to the title.
                return original_title
              end,
            },
            ---On exiting and entering neovim, loads the last chat on opening chat
            continue_last_chat = false,
            ---When chat is cleared with `gx` delete the chat from history
            delete_on_clearing_chat = false,
            ---Directory path to save the chats
            dir_to_save = vim.fn.stdpath("data") .. "/codecompanion-history",
            ---Enable detailed logging for history extension
            enable_logging = false,

            -- Summary system
            summary = {
              -- Keymap to generate summary for current chat (default: "gcs")
              create_summary_keymap = "gcs",
              -- Keymap to browse summaries (default: "gbs")
              browse_summaries_keymap = "gbs",

              generation_opts = {
                adapter = nil, -- defaults to current chat adapter
                model = nil, -- defaults to current chat model
                context_size = 90000, -- max tokens that the model supports
                include_references = true, -- include slash command content
                include_tool_outputs = true, -- include tool execution results
                system_prompt = nil, -- custom system prompt (string or function)
                format_summary = nil, -- custom function to format generated summary e.g to remove <think/> tags from summary
              },
            },
          },
        },
      },
      prompt_library = {
        ["Translator"] = {
          strategy = "chat",
          description = "Custom prompt to translate from English to German",
          opts = {
            ignore_system_prompt = true,
          },
          prompts = {
            {
              role = "system",
              content = [[
You are a Translator assistant named "Translator" with a strong background in Software Engineering. You translate with an informal tone directed to colleagues who 
are also working in software-related activities. Only use "Denglish" words when appropiated. You are currently plugged into the Neovim text editor on a user's machine.

Your core tasks include:
- Interpreting the given command as the text to translate
- Translating general paragraphs from English to German.
- Proposing fixes to mistakes if the given text is in German.
- Explaining grammatical errors but keep the explanation concise not too verbose.
- Presenting the translated response in a new paragraph with a new line above and below.
- Ending your response with a short suggestion for the next user turn that directly supports continuing the conversation.
- Providing exactly one complete reply per conversation turn.
    ]],
            },
          },
        },
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
