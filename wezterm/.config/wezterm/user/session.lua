local wezterm = require("wezterm")
local action_callback = wezterm.action_callback
local utils = require("user.utils")

local layout_file = wezterm.home_dir .. "/.local/share/wezterm/layout.json"

local M = {}

M.save = function()
	return action_callback(function()
		-- check if it possible to use ❯ wezterm cli list --format json
		local layout = { workspaces = {} }

		wezterm.log_info("DEBUG: ", wezterm.mux.get_workspace_names())

		for _, window in ipairs(wezterm.mux.all_windows()) do
			local window_json = {
				-- id = window.window_id,
				tabs = {},
			}

			-- local workspace_name = window:get_workspace()
			--
			-- local workspace = workspaces[workspace_name] == nil and { [workspace_name] = { windows = {} } }
			-- 	or workspaces[workspace_name]

			-- store window
			layout.windows[#layout.windows + 1] = window_json

			for _, tab in ipairs(window:tabs_with_info()) do
				local tab_json = {
					id = tab.tab:tab_id(),
					title = tab.tab:get_title(),
					active = tab.is_active,
					panes = {},
				}

				-- add tab to window
				window_json.tabs[#window_json.tabs + 1] = tab_json

				local panes = tab.tab:panes_with_info()
				for _, pane in ipairs(panes) do
					local pane_dim = pane.pane:get_dimensions()
					local pane_json = {
						id = pane.pane:pane_id(),
						process = pane.pane:get_foreground_process_name(),
						cwd = pane.pane:get_current_working_dir(),
						title = pane.pane:get_title(),
						-- TODO: enabling generates a huge file because the whole scrollback of every
						-- pane is persisted, find a way to only save a few lines
						-- text = pane.pane:get_text_from_region(
						-- 	0,
						-- 	pane_dim.cols,
						-- 	pane_dim.scrollback_top,
						-- 	pane_dim.scrollback_top + pane_dim.scrollback_rows
						-- ),
						active = pane.is_active,
					}

					-- add pane to tab
					tab_json.panes[#tab_json.panes + 1] = pane_json
				end
			end
		end

		utils.save_json(layout, layout_file)
	end)
end

return M
