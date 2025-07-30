return {
  "obsidian-nvim/obsidian.nvim",
  version = "*", -- recommended, use latest release instead of latest commit
  keys = {
    { "<leader>ow", ":Obsidian workspace work<CR>", desc = "open obsidian work workspace" },
    { "<leader>op", ":Obsidian workspace personal<CR>", desc = "open obsidian personal workspace" },
    {
      "<leader>oq",
      ":Obsidian quick_switch<CR>",
      desc = "obsidian quickly switch to (or open) another note in your vault, searching by its name",
    },
    { "<leader>os", ":Obsidian search<CR>", desc = "obsidian search for (or create) notes in your vault" },
    { "<leader>ot", ":Obsidian today<CR>", desc = "obsidian open/create a new daily note" },
    {
      "<leader>oy",
      ":Obsidian yesterday<CR>",
      desc = "obsidian open/create the daily note for the previous working day.",
    },
    {
      "<leader>om",
      ":Obsidian tomorrow<CR>",
      desc = "obsidian open/create the daily note for the next working day (Morgen)",
    },
    {
      "<leader>of",
      ":Obsidian follow_link<CR>",
      desc = "obsidian follow a note reference under the cursor",
    },
    {
      "<leader>ob",
      ":Obsidian backlinks<CR>",
      desc = "obsidian get a location list of references to the current buffer",
    },
    {
      "<leader>oe",
      ":Obsidian template<CR>",
      desc = "obsidian insert a template from the templates folder, selecting from a list",
    },
    {
      "<leader>oi",
      ":Obsidian paste_img<CR>",
      desc = "obsidian paste an image from the clipboard into the note at the cursor position",
    },
    {
      "<leader>on",
      ":Obsidian link_new<CR>",
      desc = "obsidian create a new note and link it to an inline visual selection of text",
      mode = "v",
    },
    {
      "<leader>ol",
      ":Obsidian link<CR>",
      desc = "obsidian link an inline visual selection of text to a note",
      mode = "v",
    },
    {
      "<C-space>",
      ":Obsidian toggle_checkbox<CR>",
      desc = "obsidian link an inline visual selection of text to a note",
    },
  },
  opts = {
    legacy_commands = false,
    picker = {
      -- Set your preferred picker. Can be one of 'telescope.nvim', 'fzf-lua', 'mini.pick' or 'snacks.pick'.
      name = "snacks.pick",
    },
    workspaces = {
      {
        name = "work",
        path = "~/Documents/work/notes",
      },
      {
        name = "personal",
        path = "~/Documents/personal/notes",
      },
    },
    follow_url_func = function(url)
      -- Open the URL in the default web browser.
      vim.fn.jobstart({ "open", url }) -- Mac OS
    end,
    templates = {
      subdir = "templates",
      date_format = "%Y-%m-%d",
      time_format = "%H:%M",
      -- A map for custom variables, the key should be the variable and the value a function
      substitutions = {
        yesterday = function()
          return os.date("%Y-%m-%d", os.time() - 86400)
        end,
      },
    },
    attachments = {
      -- The default folder to place images in via `:ObsidianPasteImg`.
      -- If this is a relative path it will be interpreted as relative to the vault root.
      -- You can always override this per image by passing a full path to the command instead of just a filename.
      img_folder = "assets/imgs", -- This is the default
      -- A function that determines the text to insert in the note when pasting an image.
      -- It takes two arguments, the `obsidian.Client` and a plenary `Path` to the image file.
      -- This is the default implementation.
      ---@param client obsidian.Client
      ---@param path Path the absolute path to the image file
      ---@return string
      img_text_func = function(client, path)
        local link_path
        local vault_relative_path = client:vault_relative_path(path)
        if vault_relative_path ~= nil then
          -- Use relative path if the image is saved in the vault dir.
          link_path = vault_relative_path
        else
          -- Otherwise use the absolute path.
          link_path = tostring(path)
        end
        local display_name = vim.fs.basename(link_path)
        return string.format("![%s](%s)", display_name, link_path)
      end,
    },
    checkbox = {
      order = { " ", ">", "x" },
    },
    ui = {
      enable = false,
    },
  },
}
