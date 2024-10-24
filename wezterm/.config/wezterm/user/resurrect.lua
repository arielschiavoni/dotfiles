local wezterm = require("wezterm")
local resurrect = wezterm.plugin.require("https://github.com/MLFlexer/resurrect.wezterm")

local M = {}

function M.setup(_config)
	resurrect.periodic_save({
		-- save every 10 minutes
		interval_seconds = 600,
		save_workspaces = true,
		save_windows = false,
		save_tabs = false,
	})

	local resurrect_event_listeners = {
		"resurrect.error",
		"resurrect.save_state.finished",
	}

	local is_periodic_save = false

	wezterm.on("resurrect.periodic_save", function()
		is_periodic_save = true
	end)
	for _, event in ipairs(resurrect_event_listeners) do
		wezterm.on(event, function(...)
			if event == "resurrect.save_state.finished" and is_periodic_save then
				is_periodic_save = false
				wezterm.log_info("Wezterm - resurrect: periodic_save")
				return
			end
			local args = { ... }
			local msg = event
			for _, v in ipairs(args) do
				msg = msg .. " " .. tostring(v)
			end
			-- wezterm.gui.gui_windows()[1]:toast_notification("Wezterm - resurrect", msg, nil, 4000)
			-- window:toast_notification("Wezterm - resurrect", msg, nil, 4000)
			wezterm.log_info("Wezterm - resurrect: " .. msg)
		end)
	end
end

return M
