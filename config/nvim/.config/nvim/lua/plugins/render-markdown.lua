return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons" },
  ft = { "markdown", "codecompanion" },
  config = function()
    require("render-markdown").setup({
      file_types = { "markdown", "vimwiki", "codecompanion" },
      completions = {
        lsp = { enabled = true },
        blink = { enabled = true },
      },
      checkbox = {
        -- Turn on / off checkbox state rendering
        enabled = true,
        -- Determines how icons fill the available space:
        --  inline:  underlying text is concealed resulting in a left aligned icon
        --  overlay: result is left padded with spaces to hide any additional text
        position = "inline",
        unchecked = {
          -- Replaces '[ ]' of 'task_list_marker_unchecked'
          icon = "   󰄱 ",
          -- Highlight for the unchecked icon
          highlight = "RenderMarkdownUnchecked",
          -- Highlight for item associated with unchecked checkbox
          scope_highlight = nil,
        },
        checked = {
          -- Replaces '[x]' of 'task_list_marker_checked'
          icon = "   󰱒 ",
          -- Highlight for the checked icon
          highlight = "RenderMarkdownChecked",
          -- Highlight for item associated with checked checkbox
          scope_highlight = nil,
        },
      },
    })

    vim.keymap.set("n", "<leader>mp", ":RenderMarkdown buf_toggle<CR>", { desc = "Toggle markdown preview" })

    -- Custom toggle for checkboxes
    vim.keymap.set("n", "<leader>x", function()
      local line = vim.api.nvim_get_current_line()
      -- Toggle [ ] to [x] or [x] to [ ]
      if string.match(line, "%[ %]") then
        line = string.gsub(line, "%[ %]", "[x]")
      elseif string.match(line, "%[x%]") then
        line = string.gsub(line, "%[x%]", "[ ]")
      end
      vim.api.nvim_set_current_line(line)
    end, { desc = "Toggle checkbox" })
  end,
}
