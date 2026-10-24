return {
  "mistweaverco/kulala.nvim",
  enabled = true,
  ft = { "http", "rest" },
  opts = {
    -- your configuration comes here
    global_keymaps = true,
    -- <c-h>/<c-l> belong to vim-tmux-navigator
    kulala_keymaps = {
      ["Previous tab"] = false,
      ["Next tab"] = false,
    },
    ui = {
      pickers = {
        snacks = {
          layout = {
            preset = "ivy",
          },
        },
      },
      -- 2Mb
      max_response_size = 4000000,
    },
    default_env = "emea_stage",
  },
}
