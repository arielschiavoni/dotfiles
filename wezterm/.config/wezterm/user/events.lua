local wezterm = require("wezterm")
local utils = require("user.utils")
local colors = require("user.colors")

local function window_config_reloaded(window, pane)
	wezterm.log_info(string.format("[%s] was emitted by window: %s, pane: %s", "window-config-reloaded", window, pane))
end

local function update_status(window, pane)
	local active_key = "none"

	-- active key
	if window:active_key_table() then
		active_key = window:active_key_table()
	end
	if window:leader_is_active() then
		active_key = "LEADER"
	end

	-- workspace name
	local workspace_name = window:active_workspace()

	-- time
	local time = wezterm.strftime("%H:%M")

	window:set_left_status(wezterm.format({
		{ Text = "  " },
		{ Foreground = { Color = colors.ansi[3] } },
		{ Text = "󱂬 " .. " " .. workspace_name },
		{ Text = " " },
		"ResetAttributes",
	}))

	window:set_right_status(wezterm.format({
		{ Foreground = { Color = active_key ~= "none" and colors.tab_bar.active_tab.bg_color or colors.foreground } },
		{ Text = wezterm.nerdfonts.fa_keyboard_o .. " " .. active_key },
		"ResetAttributes",
		{ Text = " | " },
		{ Text = wezterm.nerdfonts.md_clock .. " " .. time },
		{ Text = " " },
	}))
end

local function format_tab_title(tab, tabs, panes, config, hover, max_width)
	local background = colors.background
	local foreground = colors.foreground

	if tab.is_active then
		background = colors.selection_bg
		foreground = colors.selection_fg
	end

	local index = tonumber(tab.tab_index) + 1
	-- if the tab title is explicitly set, take that
	local title
	if tab.tab_title and #tab.tab_title > 0 then
		title = tab.tab_title
	else
		-- falback to process name of the active pane
		local pane = tab.active_pane
		local process_name = utils.basename(pane.foreground_process_name)
		title = #process_name > 0 and process_name or "launcher"
	end

	local text = " " .. index .. ": " .. title .. " "

	if tab.active_pane.is_zoomed then
		text = " " .. " " .. text
	end

	local res = {
		{ Background = { Color = background } },
		{ Foreground = { Color = foreground } },
		{ Text = text },
	}

	return res
end

local function trigger_nvim_with_scrollback(window, pane)
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
end

local M = {}

function M.setup(_config)
	wezterm.on("window-config-reloaded", window_config_reloaded)
	wezterm.on("update-status", update_status)
	wezterm.on("format-tab-title", format_tab_title)
	wezterm.on("trigger-nvim-with-scrollback", trigger_nvim_with_scrollback)
end

return M
