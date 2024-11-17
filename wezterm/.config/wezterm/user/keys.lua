local wezterm = require("wezterm")
local action = wezterm.action
local utils = require("user.utils")
local workspace_switcher = wezterm.plugin.require("https://github.com/MLFlexer/smart_workspace_switcher.wezterm")
local resurrect = wezterm.plugin.require("https://github.com/MLFlexer/resurrect.wezterm")

local M = {}

local direction_keys = {
	Left = "h",
	Down = "j",
	Up = "k",
	Right = "l",
	-- reverse lookup
	h = "Left",
	j = "Down",
	k = "Up",
	l = "Right",
}

-- create keymap to move between panes or resize them.
-- if the action takes place within vim or neovim it sends the key to it
local function create_resize_or_move_pane_key(resize_or_move, key)
	return {
		key = key,
		mods = resize_or_move == "resize" and "CTRL | SHIFT" or "CTRL",
		action = wezterm.action_callback(function(win, pane)
			if utils.is_vim(pane) then
				-- pass the keys through to vim/nvim
				win:perform_action({
					SendKey = { key = key, mods = resize_or_move == "resize" and "CTRL | SHIFT" or "CTRL" },
				}, pane)
			else
				if resize_or_move == "resize" then
					win:perform_action({ AdjustPaneSize = { direction_keys[key], 3 } }, pane)
				else
					win:perform_action({ ActivatePaneDirection = direction_keys[key] }, pane)
				end
			end
		end),
	}
end

-- this keys include native wezterm multiplexer functionality
function M.create_keys()
	local keys = {
		{ key = "D", mods = "CTRL", action = action.ShowDebugOverlay },

		-- panes
		{ key = "-", mods = "LEADER", action = action.SplitVertical({ domain = "CurrentPaneDomain" }) },
		{ key = "|", mods = "LEADER", action = action.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
		{ key = "x", mods = "LEADER", action = action.CloseCurrentPane({ confirm = true }) },
		{ key = "z", mods = "LEADER", action = action.TogglePaneZoomState },
		{ key = ">", mods = "LEADER|SHIFT", action = action.RotatePanes("Clockwise") },
		{ key = "<", mods = "LEADER|SHIFT", action = action.RotatePanes("CounterClockwise") },
		-- move between split panes CTRL + hjkl
		create_resize_or_move_pane_key("move", "h"),
		create_resize_or_move_pane_key("move", "j"),
		create_resize_or_move_pane_key("move", "k"),
		create_resize_or_move_pane_key("move", "l"),
		-- resize panes META + hjkl
		create_resize_or_move_pane_key("resize", "h"),
		create_resize_or_move_pane_key("resize", "j"),
		create_resize_or_move_pane_key("resize", "k"),
		create_resize_or_move_pane_key("resize", "l"),
		-- tabs
		{ key = "a", mods = "LEADER", action = action.ActivateLastTab },
		{ key = "c", mods = "LEADER", action = action.SpawnTab("CurrentPaneDomain") },
		{ key = "&", mods = "LEADER|SHIFT", action = action.CloseCurrentTab({ confirm = true }) },
		{ key = "t", mods = "LEADER", action = action.ShowTabNavigator },
		{ key = "m", mods = "LEADER", action = action.ActivateKeyTable({ name = "move_tab", one_shot = false }) },

		-- workspaces
		{
			key = "s",
			mods = "CTRL",
			action = workspace_switcher.switch_workspace({}),
		},
		{
			key = "^",
			mods = "LEADER",
			action = workspace_switcher.switch_to_prev_workspace(),
		},
		{
			key = "s",
			mods = "SHIFT|CTRL",
			action = wezterm.action_callback(function(win, pane)
				resurrect.save_state(resurrect.workspace_state.get_workspace_state())
				-- resurrect.window_state.save_window_action()
			end),
		},
		{
			key = "f",
			mods = "CTRL",
			action = workspace_switcher.switch_workspace({ create_workspace = true }),
		},

		-- others
		{ key = "^", mods = "SHIFT|CTRL", action = action.DisableDefaultAssignment }, -- don't interfeer with alternate file in nvim
		{ key = "PageUp", mods = "SHIFT", action = action.ScrollByPage(-0.5) },
		{ key = "PageDown", mods = "SHIFT", action = action.ScrollByPage(0.5) },
		{ key = "f", mods = "LEADER", action = action.Search({ CaseSensitiveString = "" }) },
		{ key = "F", mods = "LEADER", action = action.Search({ CaseInSensitiveString = "" }) },
		{ key = "[", mods = "LEADER", action = action.ActivateCopyMode },
		{ key = "q", mods = "LEADER", action = action.QuickSelect },
		{
			key = "f",
			mods = "SHIFT|CTRL",
			action = action.ToggleFullScreen,
		},
		{
			key = "u",
			mods = "LEADER",
			action = action.QuickSelectArgs({
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
		{
			key = "N",
			mods = "SHIFT|CTRL",
			action = action.EmitEvent("trigger-nvim-with-scrollback"),
		},
		-- Clears the scrollback and viewport, and then sends CTRL-L to ask the
		-- shell to redraw its prompt
		{
			key = "K",
			mods = "CTRL|SHIFT",
			action = action.Multiple({
				action.ClearScrollback("ScrollbackAndViewport"),
				action.SendKey({ key = "L", mods = "CTRL" }),
			}),
		},

		-- search for things that look like git hashes
		{
			key = "H",
			mods = "LEADER",
			action = action.Search({ Regex = "[a-f0-9]{6,}" }),
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
	}
end

return M
