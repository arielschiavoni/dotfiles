local rest_nvim = require("rest-nvim")
local utils = require("ariel.utils")
local Remap = require("ariel.keymap")
local nnoremap = Remap.nnoremap

local create_autocmd = vim.api.nvim_create_autocmd
local create_augroup = vim.api.nvim_create_augroup

-- temporarly highlight yankend region.
-- it helps to visualise what was yanked after running commands like: ya{
create_autocmd("TextYankPost", {
  group = create_augroup("HighlightYank", {}),
  pattern = "*",
  callback = function()
    vim.highlight.on_yank({
      higroup = "IncSearch",
      timeout = 150,
    })
  end,
})

-- automatically sync packages when the packer config is saved
create_autocmd("BufWritePost", {
  group = create_augroup("PackerSyncOnPluginsSave", {}),
  pattern = "packer.lua",
  callback = function()
    -- reload_modules so packer picks up the new configuration
    utils.reload_modules()
    -- source the new packer file
    vim.cmd("source <afile>")
    require("packer").sync()
  end,
})

-- add keymap to .http files to run request in vim
create_autocmd("FileType", {
  group = create_augroup("HttpRestKeymap", {}),
  pattern = "http",
  callback = function()
    local buff = tonumber(vim.fn.expand("<abuf>"), 10)
    nnoremap("<leader>rn", rest_nvim.run, { buffer = buff, desc = "rest: run the request under the cursor" })
    nnoremap("<leader>rl", rest_nvim.last, { buffer = buff, desc = "rest: re-run the last request" })
    nnoremap("<leader>rp", function()
      rest_nvim.run(true)
    end, { buffer = buff, desc = "rest: preview the request cURL command" })
  end,
})

-- Automatically reload the file if it is changed outside of Nvim, see https://unix.stackexchange.com/a/383044/221410.
-- It seems that `checktime` does not work in command line. We need to check if we are in command
-- line before executing this command, see also https://vi.stackexchange.com/a/20397/15292 .
create_augroup("auto_read", { clear = true })

create_autocmd({ "FileChangedShellPost" }, {
  pattern = "*",
  group = "auto_read",
  callback = function()
    vim.notify("File changed on disk. Buffer reloaded!", vim.log.levels.WARN, { title = "nvim-config" })
  end,
})

create_autocmd({ "FocusGained", "CursorHold" }, {
  pattern = "*",
  group = "auto_read",
  callback = function()
    -- exec the checktime command to see if the buffer was changed outside of vim
    -- if the file was changed then the FileChangedShellPost will be trigger
    -- which is handled in the previous autocmd to print a notification message
    vim.cmd("checktime")
  end,
})
