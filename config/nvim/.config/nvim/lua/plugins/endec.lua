return {
  "ovk/endec.nvim",
  event = "VeryLazy",
  opts = {
    -- https://github.com/ovk/endec.nvim/blob/main/lua/endec/config.lua
    -- Override default configuration here
    keymaps = {
      -- Set to `false` to disable all default mappings.
      defaults = false,

      -- Decode Base64 in-place (visual mode)
      vdecode_base64_inplace = "<leader>*yb",

      -- Decode Base64 in a popup (normal mode)
      decode_base64_popup = "<leader>*b",

      -- Decode Base64 in a popup (visual mode)
      vdecode_base64_popup = "<leader>*b",

      -- Encode Base64 in-place (normal mode)
      encode_base64_inplace = "<leader>*B",

      -- Encode Base64 in-place (visual mode)
      vencode_base64_inplace = "<leader>*B",

      -- Decode Base64URL in-place (normal mode)
      decode_base64url_inplace = "<leader>*ys",

      -- Decode Base64URL in-place (visual mode)
      vdecode_base64url_inplace = "<leader>*ys",

      -- Decode Base64URL in a popup (normal mode)
      decode_base64url_popup = "<leader>*s",

      -- Decode Base64URL in a popup (visual mode)
      vdecode_base64url_popup = "<leader>*s",

      -- Encode Base64URL in-place (normal mode)
      encode_base64url_inplace = "<leader>*S",

      -- Encode Base64URL in-place (visual mode)
      vencode_base64url_inplace = "<leader>*S",

      -- Decode URL in-place (normal mode)
      decode_url_inplace = "<leader>*yl",

      -- Decode URL in-place (visual mode)
      vdecode_url_inplace = "<leader>*yl",

      -- Decode URL in a popup (normal mode)
      decode_url_popup = "<leader>*l",

      -- Decode URL in a popup (visual mode)
      vdecode_url_popup = "<leader>*l",

      -- Encode URL in-place (normal mode)
      encode_url_inplace = "<leader>*L",

      -- Encode URL in-place (visual mode)
      vencode_url_inplace = "<leader>*L",
    },
  },
}
