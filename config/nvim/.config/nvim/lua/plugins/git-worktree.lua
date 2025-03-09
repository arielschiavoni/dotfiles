return {
  "polarmutex/git-worktree.nvim",
  version = "^2",
  dependencies = { "nvim-lua/plenary.nvim" },
  keys = {
    {
      "<leader>fw",
      function()
        Snacks.picker({
          title = "Git Worktrees",
          finder = function(opts, _ctx)
            local command = "git worktree list"
            local output = vim.fn.system(command)
            local lines = vim.split(output, "\n")

            local worktrees = {}

            for idx, line in ipairs(lines) do
              -- skip the first line as it is the (bare) default worktree
              if line ~= "" and idx > 1 then
                local path, commit, name = string.match(line, "^(%S+)%s*(%x+)%s*%[(%S+)%]$")
                if name and commit and path then
                  table.insert(worktrees, { text = name, name = name, path = path, commit = commit })
                end
              end
            end

            return worktrees
          end,
          format = "text",
          preview = "none",
          layout = {
            preset = "vscode",
          },
          confirm = function(picker, item)
            picker:close()
            require("git-worktree").switch_worktree(item.path)
          end,
        })
      end,
      desc = "Find git worktrees",
    },
  },
  config = function()
    local Hooks = require("git-worktree.hooks")

    Hooks.register(Hooks.type.SWITCH, function(path, prev_path)
      local relativePath = path:gsub("^" .. os.getenv("HOME"), "")
      vim.notify(" Switched to worktree " .. relativePath)

      local bufnr = vim.api.nvim_get_current_buf()
      local filetype = vim.api.nvim_get_option_value("ft", { buf = bufnr })
      if filetype == "oil" then
        local ok, oil = pcall(require, "oil")
        if ok then
          oil.open(path)
        else
          vim.notify("Oil is not ready to be used by git_worktree", vim.log.levels.ERROR)
        end
      else
        Hooks.builtins.update_current_buffer_on_switch(path, prev_path)
      end
    end)
  end,
}
