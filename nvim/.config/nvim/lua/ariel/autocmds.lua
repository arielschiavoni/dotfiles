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
