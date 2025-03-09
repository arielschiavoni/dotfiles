return {
  "jellydn/hurl.nvim",
  branch = "main",
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
}
