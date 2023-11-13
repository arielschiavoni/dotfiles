local M = {}
-- Equivalent to POSIX basename(3)
-- Given "/foo/bar" returns "bar"
-- Given "c:\\foo\\bar" returns "bar"
function M.basename(s)
	return s and string.gsub(s, "(.*[/\\])(.*)", "%2") or ""
end

return M
