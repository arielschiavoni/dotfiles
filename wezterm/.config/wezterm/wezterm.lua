-- Pull in the wezterm API
local wezterm = require("wezterm")
local events = require("user.events")
local keys = require("user.keys")
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
config.tab_max_width = 60
config.scrollback_lines = 10000

-- events
wezterm.on("gui-startup", events.gui_startup)
wezterm.on("window-config-reloaded", events.window_config_reloaded)
wezterm.on("update-status", events.update_status)
wezterm.on("format-tab-title", events.format_tab_title)
wezterm.on("user-var-changed", events.user_var_changed)

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
