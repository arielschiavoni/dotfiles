require("gitsigns").setup({
  signs = {
    add = { hl = "GitSignsAdd", text = "│", numhl = "GitSignsAddNr", linehl = "GitSignsAddLn" },
    change = { hl = "GitSignsChange", text = "│", numhl = "GitSignsChangeNr", linehl = "GitSignsChangeLn" },
    delete = { hl = "GitSignsDelete", text = "_", numhl = "GitSignsDeleteNr", linehl = "GitSignsDeleteLn" },
    topdelete = { hl = "GitSignsDelete", text = "‾", numhl = "GitSignsDeleteNr", linehl = "GitSignsDeleteLn" },
    changedelete = { hl = "GitSignsChange", text = "~", numhl = "GitSignsChangeNr", linehl = "GitSignsChangeLn" },
  },
  signcolumn = true, -- Toggle with `:Gitsigns toggle_signs`
  numhl = false, -- Toggle with `:Gitsigns toggle_numhl`
  linehl = false, -- Toggle with `:Gitsigns toggle_linehl`
  word_diff = false, -- Toggle with `:Gitsigns toggle_word_diff`
  watch_gitdir = {
    interval = 1000,
    follow_files = true,
  },
  attach_to_untracked = true,
  current_line_blame = false, -- Toggle with `:Gitsigns toggle_current_line_blame`
  current_line_blame_opts = {
    virt_text = true,
    virt_text_pos = "eol", -- 'eol' | 'overlay' | 'right_align'
    delay = 1000,
    ignore_whitespace = false,
  },
  current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",
  sign_priority = 6,
  update_debounce = 100,
  status_formatter = nil, -- Use default
  max_file_length = 40000,
  preview_config = {
    -- Options passed to nvim_open_win
    border = "single",
    style = "minimal",
    relative = "cursor",
    row = 0,
    col = 1,
  },
  yadm = {
    enable = false,
  },
  on_attach = function(bufnr)
    local u = require("user.core.utils")
    local gs = package.loaded.gitsigns

    -- Navigation
    u.buf_map(bufnr, "n", "]c", "&diff ? ']c' : '<cmd>Gitsigns next_hunk<CR>'", { expr = true })
    u.buf_map(bufnr, "n", "[c", "&diff ? '[c' : '<cmd>Gitsigns prev_hunk<CR>'", { expr = true })

    -- Actions
    u.buf_map(bufnr, "n", "<leader>cs", ":Gitsigns stage_hunk<CR>")
    u.buf_map(bufnr, "v", "<leader>cs", ":Gitsigns stage_hunk<CR>")
    u.buf_map(bufnr, "n", "<leader>cr", ":Gitsigns reset_hunk<CR>")
    u.buf_map(bufnr, "v", "<leader>cr", ":Gitsigns reset_hunk<CR>")
    u.buf_map(bufnr, "n", "<leader>cS", "<cmd>Gitsigns stage_buffer<CR>")
    u.buf_map(bufnr, "n", "<leader>cu", "<cmd>Gitsigns undo_stage_hunk<CR>")
    u.buf_map(bufnr, "n", "<leader>cR", "<cmd>Gitsigns reset_buffer<CR>")
    u.buf_map(bufnr, "n", "<leader>cp", "<cmd>Gitsigns preview_hunk<CR>")
    u.buf_map(bufnr, "n", "<leader>cb", '<cmd>lua require"gitsigns".blame_line{full=true}<CR>')
    u.buf_map(bufnr, "n", "<leader>ctb", "<cmd>Gitsigns toggle_current_line_blame<CR>")
    u.buf_map(bufnr, "n", "<leader>cd", "<cmd>Gitsigns diffthis<CR>")
    u.buf_map(bufnr, "n", "<leader>cD", '<cmd>lua require"gitsigns".diffthis("~")<CR>')
    u.buf_map(bufnr, "n", "<leader>ctd", "<cmd>Gitsigns toggle_deleted<CR>")

    -- Text object
    u.buf_map(bufnr, "o", "ih", ":<C-U>Gitsigns select_hunk<CR>")
    u.buf_map(bufnr, "x", "ih", ":<C-U>Gitsigns select_hunk<CR>")
  end,
})
