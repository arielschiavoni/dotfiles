return {
  "lewis6991/gitsigns.nvim",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    require("gitsigns").setup({
      on_attach = function(bufnr)
        local gs = require("gitsigns")

        local map = require("ariel.utils").create_buffer_keymaper(bufnr)
        -- Navigation
        map("n", "]c", function()
          if vim.wo.diff then
            vim.cmd.normal({ "]c", bang = true })
          else
            gs.nav_hunk("next")
          end
        end)

        map("n", "[c", function()
          if vim.wo.diff then
            vim.cmd.normal({ "[c", bang = true })
          else
            gs.nav_hunk("prev")
          end
        end)

        -- Actions
        map({ "n", "v" }, "<leader>hs", ":Gitsigns stage_hunk<CR>", { desc = "git stage hunk" })
        map({ "n", "v" }, "<leader>hr", ":Gitsigns reset_hunk<CR>", { desc = "git reset hunk" })
        map("n", "<leader>hS", gs.stage_buffer, { desc = "git stage buffer" })
        map("n", "<leader>hu", gs.undo_stage_hunk, { desc = "git undo stage hunk" })
        map("n", "<leader>hR", gs.reset_buffer, { desc = "git reset buffer" })
        map("n", "<leader>hp", gs.preview_hunk, { desc = "git preview hunk" })
        map("n", "<leader>hb", function()
          gs.blame_line({ full = true })
        end, { desc = "git blame line" })
        map("n", "<leader>tb", gs.toggle_current_line_blame, { desc = "git toggle current line blame" })
        map("n", "<leader>hd", gs.diffthis, { desc = "git diff this" })
        map("n", "<leader>hD", function()
          gs.diffthis("~")
        end, { desc = "git diff this against ~" })
        map("n", "<leader>td", gs.toggle_deleted, { desc = "git toggle deleted" })

        -- Text object (in visual mode (x) you can can select the hunk. vih -> select inside hunk, similar to selecting a word or paragraph
        map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", { desc = "git select hunk" })
      end,
    })
  end,
}
