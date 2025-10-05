return {
  -- package manager, UI to discover, install and update lsp servers
  -- even though instalation can be done with its UI it is recommended define the list of LSPs and formattes
  -- in the ensure_installed configuration above
  "williamboman/mason.nvim",
  build = ":MasonUpdate",
  -- only load this package on demand when its command o keymap is invoqued.
  -- it does not make sense to bound this plugins with lsp configuration which
  -- needs to be loaded when any buffer is opened
  cmd = "Mason",
  keys = {
    { "<leader>ms", ":Mason<CR>", desc = "open Mason LSP package manager" },
  },
  opts = {
    -- https://github.com/williamboman/mason-lspconfig.nvim/blob/main/doc/server-mapping.md
    ensure_installed = {
      "js-debug-adapter",
      "lua-language-server",
      "typescript-language-server",
      "graphql-language-service-cli",
      "yaml-language-server",
      "json-lsp",
      "tailwindcss-language-server",
      "terraform-ls",
      "gopls",
      "bash-language-server",
      "html-lsp",
      "mmdc",
      "ruff",
      "pyright",
      "marksman",
    },
  },
  ---@param opts MasonSettings | {ensure_installed: string[]}
  config = function(_, opts)
    require("mason").setup(opts)
    local mr = require("mason-registry")
    for _, tool in ipairs(opts.ensure_installed) do
      local p = mr.get_package(tool)
      if not p:is_installed() then
        p:install()
      end
    end
  end,
}
