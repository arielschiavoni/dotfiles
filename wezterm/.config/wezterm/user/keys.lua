local wezterm = require("wezterm")
local action = wezterm.action
local session = require("user.session")

local M = {}

-- this keys include native wezterm multiplexer functionality
function M.create_keys()
	local keys = {
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
		{ key = "t", mods = "LEADER", action = action.ShowTabNavigator },
		{ key = "m", mods = "LEADER", action = action.ActivateKeyTable({ name = "move_tab", one_shot = false }) },

		-- workspaces
		{
			-- create new session/workspace
			key = "f",
			mods = "CTRL",
			action = session.create(),
		},
		{ key = "s", mods = "CTRL", action = action.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },
		{ key = "s", mods = "LEADER", action = session.save() },
		{
			key = "w",
			mods = "LEADER",
			action = action.ActivateKeyTable({ name = "switch_workspace", one_shot = false }),
		},

		-- others
		{ key = "^", mods = "SHIFT|CTRL", action = action.DisableDefaultAssignment }, -- don't interfeer with alternate file in nvim
		{ key = "PageUp", mods = "SHIFT", action = action.ScrollByPage(-0.5) },
		{ key = "PageDown", mods = "SHIFT", action = action.ScrollByPage(0.5) },
		{ key = "f", mods = "LEADER", action = action.Search({ CaseSensitiveString = "" }) },
		{ key = "F", mods = "LEADER", action = action.Search({ CaseInSensitiveString = "" }) },
		{ key = "[", mods = "LEADER", action = wezterm.action.ActivateCopyMode },
		{ key = "q", mods = "LEADER", action = wezterm.action.QuickSelect },
		{
			key = "o",
			mods = "LEADER",
			action = wezterm.action.QuickSelectArgs({
				label = "open url",
				patterns = {
					"https?://\\S+",
				},
				action = wezterm.action_callback(function(window, pane)
					local url = window:get_selection_text_for_pane(pane)
					wezterm.log_info("opening: " .. url)
					wezterm.open_with(url)
				end),
			}),
		},

		-- search for things that look like git hashes
		{
			key = "H",
			mods = "LEADER",
			action = wezterm.action.Search({ Regex = "[a-f0-9]{6,}" }),
		},
		{
			-- rename tab/window
			key = ",",
			mods = "LEADER",
			action = action.PromptInputLine({
				description = "Enter new name for tab",
				action = wezterm.action_callback(function(window, _, line)
					if line then
						window:active_tab():set_title(line)
					end
				end),
			}),
		},
		{
			-- rename workspace/session
			key = "$",
			mods = "LEADER",
			action = action.PromptInputLine({
				description = "Enter new name for worspace",
				action = wezterm.action_callback(function(_window, _, line)
					if line then
						wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
					end
				end),
			}),
		},
	}

	-- extend keys with keybindngs for tab navigation from 1 to 9
	-- { key = "1", mods = "LEADER", action = action.ActivateTab(0) },
	-- ...
	-- { key = "9", mods = "LEADER", action = action.ActivateTab(9) },
	for i = 1, 9 do
		table.insert(keys, {
			key = tostring(i),
			mods = "LEADER",
			action = action.ActivateTab(i - 1),
		})
	end

	return keys
end

-- this keys don't include keybindings that interfeer with multiplexers like tmux
function M.create_keys_without_multiplexer()
	-- https://wezfurlong.org/wezterm/config/default-keys.html
	local keys = {
		{ key = "^", mods = "SHIFT|CTRL", action = action.DisableDefaultAssignment }, -- don't interfeer with alternate file in nvim
	}

	return keys
end

function M.create_key_tables()
	return {
		move_tab = {
			{ key = "p", action = action.MoveTabRelative(-1) },
			{ key = "n", action = action.MoveTabRelative(1) },
			-- Cancel the mode by pressing escape
			{ key = "Escape", action = "PopKeyTable" },
		},
		resize_pane = {
			{ key = "h", action = action.AdjustPaneSize({ "Left", 5 }) },
			{ key = "j", action = action.AdjustPaneSize({ "Down", 5 }) },
			{ key = "k", action = action.AdjustPaneSize({ "Up", 5 }) },
			{ key = "l", action = action.AdjustPaneSize({ "Right", 5 }) },
			{ key = "Escape", action = "PopKeyTable" },
		},
		switch_workspace = {
			{ key = "p", action = action.SwitchWorkspaceRelative(-1) },
			{ key = "n", action = action.SwitchWorkspaceRelative(1) },
			{ key = "Escape", action = "PopKeyTable" },
		},
	}
end

return M
