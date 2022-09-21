local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local utils = require("telescope.utils")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")
local make_entry = require("telescope.make_entry")

local ls = require("luasnip")
-- print(vim.inspect(conf))

local M = {}

M.snippets = function(opts)
  local available_snippets = {}

  local max_length_trigger = 0
  local max_length_name = 0
  for _, file_type_snippets in pairs(ls.available()) do
    for _, snippet in pairs(file_type_snippets) do
      table.insert(available_snippets, snippet)
      max_length_trigger = math.max(max_length_trigger, #utils.display_termcodes(snippet.trigger))
      max_length_name = math.max(max_length_name, #utils.display_termcodes(snippet.name))
    end
  end
  print(max_length_trigger)
  print(max_length_name)

  -- print(vim.inspect(snippets))
  -- {
  --   description = { "GPLv3 License" },
  --   name = "GPL3",
  --   regTrig = false,
  --   trigger = "GPL3",
  --   wordTrig = true
  -- }

  opts = opts or {}
  pickers
    .new(opts, {
      prompt_title = "Snippets",
      finder = finders.new_table({
        results = available_snippets,
        entry_maker = function(entry)
          -- local displayer = entry_display.create({
          --   separator = "▏",
          --   items = {
          --     { width = max_length_trigger },
          --     { width = max_length_name },
          --     { remaining = true },
          --   },
          -- })
          --
          -- local make_display = function(entry)
          --   return displayer({
          --     entry.trigger,
          --     entry.name,
          --     entry.description[1],
          --   })
          -- end
          --
          -- return make_entry.set_default_entry_mt({
          --   valid = entry ~= "",
          --   value = entry,
          --   ordinal = entry.trigger .. " " .. entry.name .. " " .. entry.description[1],
          --   display = make_display(entry),
          -- }, opts)
          -- end
          return {
            value = entry,
            -- display trigger and name
            display = entry.trigger .. " -> " .. entry.description[1],
            -- search for trigger, name and description
            ordinal = entry.trigger .. " " .. entry.name .. " " .. entry.description[1],
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          -- print(vim.inspect(selection))
          vim.api.nvim_put({ selection[1] }, "", false, true)
        end)
        return true
      end,
    })
    :find()
end

return M
-- snippets()
