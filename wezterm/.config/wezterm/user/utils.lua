local wezterm = require("wezterm")
local io = require("io")

local M = {}
-- Equivalent to POSIX basename(3)
-- Given "/foo/bar" returns "bar"
-- Given "c:\\foo\\bar" returns "bar"
function M.basename(s)
	return s and string.gsub(s, "(.*[/\\])(.*)", "%2") or ""
end

-- Deep copy a table
local function deepcopy(tbl)
	if type(tbl) == "table" then
		local copy = {}
		for k, v in pairs(tbl) do
			copy[tostring(k)] = deepcopy(v)
		end
		return copy
	end
	return tbl
end

-- Load JSON data from a file
function M.load_json(file)
	local f = assert(io.open(file, "r"))
	local text = assert(f:read("*a"))
	f:close()
	local ok, val = pcall(wezterm.json_parse, text)
	if not ok then
		print("Error parsing json")
		print(val)
		return nil
	end
	return val
end

-- Save JSON data a file
function M.save_json(data, file)
	local f = assert(io.open(file, "w"))
	f:write(wezterm.json_encode(deepcopy(data)))
	f:close()
end

function M.is_vim(pane)
	local process_info = pane:get_foreground_process_info()
	local process_name = process_info and process_info.name

	return process_name == "nvim" or process_name == "vim"
end

return M
