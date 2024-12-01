return {
  "L3MON4D3/LuaSnip",
  -- this plugin is only loaded when needed from nvim-cmp
  lazy = true,
  config = function()
    local ls = require("luasnip")
    local types = require("luasnip.util.types")

    ls.config.set_config({
      -- This tells LuaSnip to remember to keep around the last snippet.
      -- You can jump back into it even if you move outside of the selection
      history = false,

      -- This one is cool cause if you have dynamic snippets, it updates as you type!
      updateevents = "TextChanged,TextChangedI",

      -- Autosnippets:
      enable_autosnippets = true,

      -- Crazy highlights!!
      -- #vid3
      -- ext_opts = nil,
      ext_opts = {
        [types.choiceNode] = {
          active = {
            virt_text = { { " « ", "NonTest" } },
          },
        },
      },
    })

    vim.keymap.set({ "i", "s" }, "<c-k>", function()
      if ls.jumpable(-1) then
        ls.jump(-1)
      end
    end, { desc = "Snippet: move to the previous item within the snippet", silent = true })

    vim.keymap.set({ "i", "s" }, "<c-j>", function()
      if ls.expand_or_jumpable() then
        ls.expand_or_jump()
      end
    end, { desc = "Snippet: expand the current item or jump to the next item within the snippet.", silent = true })

    -- This is useful for choice nodes
    vim.keymap.set("i", "<c-l>", function()
      if ls.choice_active() then
        ls.change_choice(1)
      end
    end, { desc = "Snippet: select within a list of options" })

    vim.keymap.set("i", "<c-u>", require("luasnip.extras.select_choice"))

    local function load_snippets()
      vim.cmd("source ~/.config/nvim/lua/ariel/snippets/init.lua")
    end

    load_snippets()

    local augroup_reload_snippets = vim.api.nvim_create_augroup("reload-snippets-group", { clear = true })
    vim.api.nvim_create_autocmd("BufWritePost", {
      -- only trigger for snippets files change!
      pattern = "**/ariel/snippets/**",
      group = augroup_reload_snippets,
      callback = function()
        load_snippets()
      end,
    })
  end,
}
