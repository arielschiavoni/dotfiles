return {
  {
    -- mappings to easily delete, change and add such surroundings in pairs
    "tpope/vim-surround",
    event = "VeryLazy",
  },
  {
    -- complementary pairs of mappings (for quickfixlist [q, ]q, add spaces before or after line [<Space>)
    "tpope/vim-unimpaired",
    jevent = "VeryLazy",
  },
  {
    -- Advanced search/replace that allows to adjust plurals and preserve original case
    -- :%Subvert/facilit{y,ies}/building{,s}/g
    -- Want to turn fooBar into foo_bar? Press crs (coerce to snake_case). MixedCase (crm), camelCase (crc), UPPER_CASE (cru), dash-case (cr-), and dot.case (cr.) are all just 3 keystrokes away.
    "tpope/vim-abolish",
    event = "VeryLazy",
  },
  {
    "norcalli/nvim-colorizer.lua",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("colorizer").setup()
    end,
  },
  {
    -- comments
    "echasnovski/mini.comment",
    dependencies = { "JoosepAlviste/nvim-ts-context-commentstring" },
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      hooks = {
        pre = function()
          require("ts_context_commentstring.internal").update_commentstring({})
        end,
      },
    },
    config = function(_, opts)
      require("mini.comment").setup(opts)
    end,
  },
  {
    -- allows to keep registers (yanked, deleted text) in a history searcheable by telescope
    "AckslD/nvim-neoclip.lua",
    dependencies = { "nvim-telescope/telescope.nvim" },
    -- load also with VeryLazy to not miss the first yanked/deleted text
    event = { "VeryLazy" },
    keys = {
      { "<leader>fy", ":Telescope neoclip<CR>", desc = "find yanked text over time" },
    },
    config = function()
      require("neoclip").setup()
      require("telescope").load_extension("neoclip")
    end,
  },
}
