local wezterm = require("wezterm")
local action_callback = wezterm.action_callback
local utils = require("user.utils")

local session_file = wezterm.home_dir .. "/.local/share/wezterm/session.json"
local session_file_parsed = wezterm.home_dir .. "/.local/share/wezterm/session-parsed.json"

local M = {}

function M.create()
	return action_callback(function(window, pane)
		local home = os.getenv("HOME")
		local fd_ignore_file = home .. "/.local/bin/.sessionizer-ignore"
		local base_directory = home

		local success, stdout, stderr = wezterm.run_child_process({
			"/opt/homebrew/bin/fd",
			"--max-depth",
			"3",
			"--type",
			"directory",
			"--ignore-file",
			fd_ignore_file,
			"--base-directory",
			base_directory,
		})

		local directories = {}
		if success then
			for _, directory in ipairs(wezterm.split_by_newlines(stdout)) do
				table.insert(directories, { label = directory })
			end
		else
			wezterm.log_error(stderr)
		end

		window:perform_action(
			wezterm.action.InputSelector({
				choices = directories,
				fuzzy = true,
				action = action_callback(function(inner_window, inner_pane, _id, directory)
					if not directory then
						wezterm.log_info("cancelled")
					else
						local cwd = base_directory .. "/" .. directory
						local lastDirectoryName = string.gsub(directory, ".+/(.-)/$", "%1")

						inner_window:perform_action(
							wezterm.action.SwitchToWorkspace({
								name = lastDirectoryName,
								spawn = {
									cwd = cwd,
									-- disable due it does not automatically load environment variables
									-- args = { "nvim", "." },
								},
							}),
							inner_pane
						)
					end
				end),
			}),
			pane
		)
	end)
end

M.save = function()
	return action_callback(function(window)
		-- get list of workspaces -> windows -> tabs -> panes
		local success, stdout, stderr = wezterm.run_child_process({
			"/opt/homebrew/bin/wezterm",
			"cli",
			"list",
			"--format",
			"json",
		})

		if success then
			-- save it to file to restore it later
			local f = assert(io.open(session_file, "w"))
			f:write(stdout)
			f:close()
			wezterm.log_info("Saved session in " .. session_file)
		else
			wezterm.log_error(stderr)
		end
	end)
end

local function format_cwd(pane)
	local cwd = string.gsub(pane.cwd, "^file://[^/]+(/.*)$", "%1")
	return string.gsub(cwd, "file://", "")
end

local function create_pane(pane, cwd)
	return {
		title = pane.tab_title,
		cwd = cwd,
		panes = {
			[pane.pane_id] = {
				cwd = cwd,
				size = pane.size,
				is_zoomed = pane.is_zoomed,
			},
		},
	}
end

local function create_tab(pane, cwd)
	return {
		title = pane.tab_title,
		cwd = cwd,
		panes = {
			[pane.pane_id] = create_pane(pane, cwd),
		},
	}
end

local function create_window(pane, cwd)
	return {
		title = pane.window_title,
		cwd = cwd,
		tabs = {
			[pane.tab_id] = create_tab(pane, cwd),
		},
	}
end

M.restore = function()
	wezterm.log_info("Restoring session from .." .. session_file)

	local session = utils.load_json(session_file)
	if session == nil then
		return
	end

	local workspaces = {}
	for index, pane in ipairs(session) do
		local workspace = workspaces[pane.workspace]
		local cwd = format_cwd(pane)

		if workspace == nil then
			workspaces[pane.workspace] = {
				[pane.window_id] = create_window(pane, cwd),
			}
		else
			local window = workspace[pane.window_id]

			if window == nil then
				workspace[pane.window_id] = create_window(pane, cwd)
			else
				local tab = window.tabs[pane.tab_id]

				if tab == nil then
					window.tabs[pane.tab_id] = create_tab(pane, cwd)
				else
					tab.panes[pane.pane_id] = create_pane(pane, cwd)
				end
			end
		end
	end

	wezterm.log_info(workspaces)
	utils.save_json(workspaces, session_file_parsed)

	local last_workspace = nil

	for workspace_name, workspace in pairs(workspaces) do
		last_workspace = workspace_name

		for window_id, window_data in pairs(workspace) do
			wezterm.log_info(workspace_name, window_data.title)

			local window = nil
			for tab_id, tab_data in pairs(window_data.tabs) do
				if window == nil then
					-- create window with the path of the first tab and store it for the next tabs
					-- creating a window creates a tab automatically
					local t, p, w = wezterm.mux.spawn_window({
						workspace = workspace_name,
						cwd = tab_data.cwd,
					})
					window = w
				else
					window:spawn_tab({ cwd = tab_data.cwd })
				end
			end
		end
	end

	if last_workspace ~= nil then
		wezterm.mux.set_active_workspace(last_workspace)
	end
end

return M
