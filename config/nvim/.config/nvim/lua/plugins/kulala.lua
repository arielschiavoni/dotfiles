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
      -- 2Mb
      max_response_size = 4000000,
    },
    default_env = "emea_stage",
    additional_curl_options = { "--compressed" },
  },
}
