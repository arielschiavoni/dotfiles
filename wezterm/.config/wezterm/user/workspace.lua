local wezterm = require("wezterm")
local action_callback = wezterm.action_callback

local M = {}

function M.create()
	return action_callback(function(window, pane)
		local home = os.getenv("HOME")
		local fd_ignore_file = home .. "/.local/bin/.sessionizer-ignore"
		local base_directory = home
		local directories = {}

		local zoxide_success, zoxide_stdout, zoxide_stderr = wezterm.run_child_process({
			"/opt/homebrew/bin/zoxide",
			"query",
			"--list",
		})

		if zoxide_success and base_directory then
			for _, directory in ipairs(wezterm.split_by_newlines(zoxide_stdout)) do
				table.insert(directories, { label = string.gsub(directory, base_directory, "~") })
			end
		else
			wezterm.log_error(zoxide_stderr)
		end

		local fd_success, fd_stdout, fd_stderr = wezterm.run_child_process({
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

		if fd_success then
			for _, directory in ipairs(wezterm.split_by_newlines(fd_stdout)) do
				table.insert(directories, { label = "~/" .. directory })
			end
		else
			wezterm.log_error(fd_stderr)
		end

		window:perform_action(
			wezterm.action.InputSelector({
				choices = directories,
				fuzzy = true,
				action = action_callback(function(inner_window, inner_pane, _id, directory)
					if not directory then
						wezterm.log_info("cancelled")
					else
						local base_name = directory:match("([^/]+)$")
						local cwd = string.gsub(directory, "~", base_directory)

						inner_window:perform_action(
							wezterm.action.SwitchToWorkspace({
								name = base_name,
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

return M
