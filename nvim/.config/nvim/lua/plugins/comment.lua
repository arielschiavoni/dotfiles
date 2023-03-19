return {
  "numToStr/Comment.nvim",
  dependencies = {
    "JoosepAlviste/nvim-ts-context-commentstring",
  },
  config = {
    pre_hook = function(ctx)
      -- Only calculate commentstring for tsx filetypes
      if vim.bo.filetype == "typescriptreact" then
        local comment_utils = require("Comment.utils")
        local ts_context_utils = require("ts_context_commentstring.utils")

        -- Detemine whether to use linewise or blockwise commentstring
        local type = ctx.ctype == comment_utils.ctype.line and "__default" or "__multiline"

        -- Determine the location where to calculate commentstring from
        local location = nil
        if ctx.ctype == comment_utils.ctype.block then
          location = ts_context_utils.get_cursor_location()
        elseif ctx.cmotion == comment_utils.cmotion.v or ctx.cmotion == comment_utils.cmotion.V then
          location = ts_context_utils.get_visual_start_location()
        end

        return require("ts_context_commentstring.internal").calculate_commentstring({
          key = type,
          location = location,
        })
      end
    end,
  },
}
