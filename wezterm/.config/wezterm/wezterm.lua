-- Pull in the wezterm API
local wezterm = require("wezterm")
local events = require("user.events")
local keys = require("user.keys")
local os = require("os")
local os = require("os")

-- This table will hold the configuration.
local config = {}

-- In newer versions of wezterm, use the config_builder which will
-- help provide clearer error messages
if wezterm.config_builder then
	config = wezterm.config_builder()
end

config.color_scheme = "tokyonight_moon"
config.term = "wezterm"
config.set_environment_variables = {
	PATH = "/opt/homebrew/bin:" .. os.getenv("PATH"),
	HOME = wezterm.home_dir,
}
config.default_cursor_style = "BlinkingBlock"
config.cursor_blink_rate = 800

-- window
config.window_decorations = "RESIZE"
config.window_padding = {
	left = 0,
	right = 0,
	top = 10,
	bottom = 0,
}
config.window_close_confirmation = "NeverPrompt"
config.window_background_opacity = 1.0
config.check_for_updates = true
config.font = wezterm.font_with_fallback({
	{ family = "JetBrains Mono", weight = "Medium", harfbuzz_features = { "calt=0", "clig=0", "liga=0" } },
	{ family = "Symbols Nerd Font Mono", scale = 0.9 },
})
config.font_size = 12
config.tab_max_width = 32
config.scrollback_lines = 5000

-- events
wezterm.on("window-config-reloaded", events.window_config_reloaded)
wezterm.on("update-status", events.update_status)
wezterm.on("format-tab-title", events.format_tab_title)
wezterm.on("user-var-changed", events.user_var_changed)
wezterm.on("trigger-nvim-with-scrollback", function(window, pane)
	-- Retrieve the text from the pane
	local text = pane:get_lines_as_text(pane:get_dimensions().scrollback_rows)

	-- Create a temporary file to pass to vim
	local name = os.tmpname()
	local f = io.open(name, "w+")
	f:write(text)
	f:flush()
	f:close()

	-- Open a new window running vim and tell it to open the file
	window:perform_action(
		wezterm.action.SpawnCommandInNewTab({
			args = { "nvim", name },
		}),
		pane
	)

	-- Wait "enough" time for vim to read the file before we remove it.
	-- The window creation and process spawn are asynchronous wrt. running
	-- this script and are not awaitable, so we just pick a number.
	--
	-- Note: We don't strictly need to remove this file, but it is nice
	-- to avoid cluttering up the temporary directory.
	wezterm.sleep_ms(1000)
	os.remove(name)
end)

-- tab bar
config.use_fancy_tab_bar = false
config.status_update_interval = 1000
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = false
config.show_new_tab_button_in_tab_bar = false

-- keys
config.leader = { key = "a", mods = "CTRL" }
config.keys = keys.create_keys()
config.key_tables = keys.create_key_tables()

-- Use the defaults as a base
config.hyperlink_rules = wezterm.default_hyperlink_rules()

-- make task numbers clickable
-- the first matched regex group is captured in $1.
table.insert(config.hyperlink_rules, {
	regex = [[(SHAPESHIFT|WEBSUPPORT)-(\d+)]],
	format = "https://collaboration.msi.audi.com/jira/browse/$1-$2",
})

-- make username/project paths clickable. this implies paths like the following are for github.
-- ( "nvim-treesitter/nvim-treesitter" | wbthomason/packer.nvim | wez/wezterm | "wez/wezterm.git" )
-- as long as a full url hyperlink regex exists above this it should not match a full url to
-- github or gitlab / bitbucket (i.e. https://gitlab.com/user/project.git is still a whole clickable url)
table.insert(config.hyperlink_rules, {
	regex = [[["]?([\w\d]{1}[-\w\d]+)(/){1}([-\w\d\.]+)["]?]],
	format = "https://www.github.com/$1/$3",
})

-- and finally, return the configuration to wezterm
return config
