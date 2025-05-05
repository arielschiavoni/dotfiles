return {
  "mistweaverco/kulala.nvim",
  ft = { "http", "rest" },
  opts = {
    -- your configuration comes here
    global_keymaps = true,
    ui = {
      pickers = {
        snacks = {
          layout = {
            preset = "ivy",
          },
        },
      },
    },
    default_env = "emea_stage",
    additional_curl_options = { "--compressed" },
  },
}
