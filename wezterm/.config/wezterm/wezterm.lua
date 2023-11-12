-- Pull in the wezterm API
local wezterm = require("wezterm")
local action = wezterm.action

-- This table will hold the configuration.
local config = {}

-- In newer versions of wezterm, use the config_builder which will
-- help provide clearer error messages
if wezterm.config_builder then
	config = wezterm.config_builder()
end

config.color_scheme = "tokyonight_moon"

-- window
config.window_decorations = "RESIZE"
config.window_padding = {
	left = 0,
	right = 0,
	top = 0,
	bottom = 0,
}
config.window_close_confirmation = "NeverPrompt"
config.font = wezterm.font_with_fallback({
	{ family = "JetBrains Mono", weight = "Medium", harfbuzz_features = { "calt=0", "clig=0", "liga=0" } },
	{ family = "Symbols Nerd Font Mono", scale = 0.9 },
})

-- tab bar
config.use_fancy_tab_bar = false
config.status_update_interval = 1000
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = false

-- define how to update tab bar right status
wezterm.on("update-right-status", function(window, pane)
	-- workspace name
	local status = window:active_workspace()

	-- active key
	if window:active_key_table() then
		status = window:active_key_table()
	end
	if window:leader_is_active() then
		status = "LEADER"
	end

	-- cwd
	function basename(s)
		return string.gsub(s, "(.*[/\\])(.*)", "%2")
	end

	local cwd = basename(pane:get_current_working_dir())

	-- cmd
	local cmd = basename(pane:get_foreground_process_name())

	-- time
	local time = wezterm.strftime("%H:%M")

	window:set_right_status(wezterm.format({
		{ Text = wezterm.nerdfonts.oct_table .. " " .. status },
		{ Text = " | " },
		{ Text = wezterm.nerdfonts.md_folder .. " " .. cwd },
		{ Text = " | " },
		{ Foreground = { Color = "FFB86C" } },
		{ Text = wezterm.nerdfonts.fa_code .. " " .. cmd },
		"ResetAttributes",
		{ Text = " | " },
		{ Text = wezterm.nerdfonts.md_clock .. " " .. time },
		{ Text = " |" },
	}))
end)

-- keys
config.leader = { key = "a", mods = "CTRL" }
config.keys = {
	-- panes
	{ key = "-", mods = "LEADER", action = action.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "|", mods = "LEADER", action = action.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "x", mods = "LEADER", action = action.CloseCurrentPane({ confirm = true }) },
	{ key = "z", mods = "LEADER", action = action.TogglePaneZoomState },
	{ key = "r", mods = "LEADER", action = action.ActivateKeyTable({ name = "resize_pane", one_shot = false }) },
	{ key = "h", mods = "LEADER", action = action.ActivatePaneDirection("Left") },
	{ key = "j", mods = "LEADER", action = action.ActivatePaneDirection("Down") },
	{ key = "k", mods = "LEADER", action = action.ActivatePaneDirection("Up") },
	{ key = "l", mods = "LEADER", action = action.ActivatePaneDirection("Right") },
	{ key = ">", mods = "LEADER|SHIFT", action = action.RotatePanes("Clockwise") },
	{ key = "<", mods = "LEADER|SHIFT", action = action.RotatePanes("CounterClockwise") },

	-- tabs
	{ key = "a", mods = "LEADER", action = action.ActivateLastTab },
	{ key = "c", mods = "LEADER", action = action.SpawnTab("CurrentPaneDomain") },
	{ key = "&", mods = "LEADER|SHIFT", action = action.CloseCurrentTab({ confirm = true }) },
	{ key = "[", mods = "LEADER", action = action.ActivateTabRelative(-1) },
	{ key = "]", mods = "LEADER", action = action.ActivateTabRelative(1) },
	{ key = "t", mods = "LEADER", action = action.ShowTabNavigator },
	{ key = "m", mods = "LEADER", action = action.ActivateKeyTable({ name = "move_tab", one_shot = false }) },

	-- workspaces
	{ key = "i", mods = "LEADER", action = action.SwitchToWorkspace },
	{ key = "s", mods = "LEADER", action = action.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },
	{ key = "n", mods = "LEADER", action = action.SwitchWorkspaceRelative(1) },
	{ key = "p", mods = "LEADER", action = action.SwitchWorkspaceRelative(-1) },

	{ key = "n", mods = "SHIFT|CTRL", action = wezterm.action.ToggleFullScreen },
	{ key = "^", mods = "SHIFT|CTRL", action = wezterm.action.DisableDefaultAssignment }, -- don't interfeer with alternate file in nvim
}

-- extend keys with keybindngs for tab navigation from 1 to 9
-- { key = "1", mods = "LEADER", action = action.ActivateTab(0) },
-- ...
-- { key = "9", mods = "LEADER", action = action.ActivateTab(9) },
for i = 1, 9 do
	table.insert(config.keys, {
		key = tostring(i),
		mods = "LEADER",
		action = action.ActivateTab(i - 1),
	})
end

config.key_tables = {
	move_tab = {
		{ key = "h", action = action.MoveTabRelative(-1) },
		{ key = "j", action = action.MoveTabRelative(-1) },
		{ key = "k", action = action.MoveTabRelative(1) },
		{ key = "l", action = action.MoveTabRelative(1) },
		-- Cancel the mode by pressing escape
		{ key = "Escape", action = "PopKeyTable" },
	},
	resize_pane = {
		{ key = "h", action = action.AdjustPaneSize({ "Left", 5 }) },
		{ key = "j", action = action.AdjustPaneSize({ "Down", 5 }) },
		{ key = "k", action = action.AdjustPaneSize({ "Up", 5 }) },
		{ key = "l", action = action.AdjustPaneSize({ "Right", 5 }) },
		-- Cancel the mode by pressing escape
		{ key = "Escape", action = "PopKeyTable" },
	},
}

-- and finally, return the configuration to wezterm
return config
