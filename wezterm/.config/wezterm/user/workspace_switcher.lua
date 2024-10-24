local wezterm = require("wezterm")
local colors = require("user.colors")
local utils = require("user.utils")

local M = {}

local workspace_switcher = wezterm.plugin.require("https://github.com/MLFlexer/smart_workspace_switcher.wezterm")
local resurrect = wezterm.plugin.require("https://github.com/MLFlexer/resurrect.wezterm")

local function get_fd_elements(choice_table, opts)
	local fd_ignore_file = wezterm.home_dir .. "/.local/bin/.sessionizer-ignore"
	local base_directory = wezterm.home_dir

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
		for _, path in ipairs(wezterm.split_by_newlines(fd_stdout)) do
			-- remove trailing slash
			path = path.gsub(path, "/+$", "")
			local full_path = base_directory .. "/" .. path
			local workspace_label = string.gsub(full_path, wezterm.home_dir, "~")

			if not opts.workspace_ids[workspace_label] then
				table.insert(choice_table, {
					id = full_path,
					label = workspace_label,
				})
			end
		end
	else
		wezterm.log_error(fd_stderr)
	end

	return choice_table
end

function M.setup(config)
	workspace_switcher.apply_to_config(config)

	workspace_switcher.workspace_formatter = function(label)
		return wezterm.format({
			{ Foreground = { Color = colors.ansi[3] } },
			{ Background = { Color = colors.background } },
			{ Text = "󱂬 " .. " " .. label },
		})
	end

	workspace_switcher.get_choices = function(opts)
		local choices = {}
		choices, opts.workspace_ids = workspace_switcher.choices.get_workspace_elements(choices)

		if opts.create_workspace then
			choices = get_fd_elements(choices, opts)
		end

		return choices
	end

	wezterm.on("smart_workspace_switcher.workspace_switcher.created", function(window, path, label)
		local workspace_state = resurrect.workspace_state

		workspace_state.restore_workspace(resurrect.load_state(label, "workspace"), {
			window = window,
			relative = true,
			restore_text = true,
			on_pane_restore = resurrect.tab_state.default_on_pane_restore,
		})
	end)

	wezterm.on("smart_workspace_switcher.workspace_switcher.selected", function(window, path, label)
		local workspace_state = resurrect.workspace_state
		resurrect.save_state(workspace_state.get_workspace_state())
	end)
end

return M
