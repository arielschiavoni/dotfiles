-- Pull in the wezterm API
local wezterm = require("wezterm")
local events = require("user.events")
local keys = require("user.keys")
-- CTRL + D to show debug overlay, then type -> wezterm.plugin.list() to see where the plugins are installed
-- git pull to update them
-- wezterm.plugin.update_all()
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
config.pane_focus_follows_mouse = true
config.scrollback_lines = 5000

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

-- events
events.setup(config)

-- Use the defaults as a base
config.hyperlink_rules = wezterm.default_hyperlink_rules()

-- make task numbers clickable
-- the first matched regex group is captured in $1.
table.insert(config.hyperlink_rules, {
	regex = [[(WEBART-\d+)]],
	format = "https://collaboration.msi.audi.com/jira/browse/$1",
})

-- and finally, return the configuration to wezterm
return config
