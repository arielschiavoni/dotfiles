-- https://github.com/ryanburda/config/blob/45b6920b9f45d566cfb10e6ebfa53c9329856090/dotfiles/nvim/lua/plugins/configs/telescope.lua#L108-L137
return {
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  config = function()
    require("diffview").setup({
      enhanced_diff_hl = true,
      file_panel = {
        listing_style = "tree",
        tree_options = {
          flatten_dirs = true,
          folder_statuses = "only_folded",
        },
        win_config = {
          position = "bottom",
          height = 20,
        },
      },
    })
  end,
}
