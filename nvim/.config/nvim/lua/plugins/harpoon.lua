return {
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
}
