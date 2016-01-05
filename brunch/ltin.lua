
local _M = {}

function _M.parse(text)
	local code = "return" .. text

	if setfenv and loadstring then
		local f = assert(loadstring(code))
		setfenv(f, {})
		return f()
	else
		return assert(load(code, nil, "t", {}))()
	end
end

---
-- Import from https://github.com/luvit/ltin/blob/master/ltin.lua
function _M.stringify(value)
	local t = type(value)
	if t == "number" or t == "boolean" or t == "nil" then
		return tostring(value)
	end

	if t == "string" then
		return '"' .. value:gsub("\\", "\\\\")
			:gsub("%z", "\\0"):gsub("\a", "\\a"):gsub("\b", "\\b")
			:gsub("\f", "\\f"):gsub("\n", "\\n"):gsub("\r", "\\r")
			:gsub("\t", "\\t"):gsub("\v", "\\v"):gsub('"', '\\"') .. '"'
	end

	if t == 'table' then
		local parts = {}
		local index = 1

		for key, item in pairs(value) do
			local keyString
			if key == index then
				keyString = ""
			elseif type(key) == "string" and key:match("^[_%a][_%w]*$") then
				keyString = key .. "="
			else
				keyString = "[" .. _M.stringify(key) .. "]="
			end
			parts[index] = keyString .. _M.stringify(item)
			index = index + 1
		end

		return "{" .. table.concat(parts, ",") .. "}"
	end

	return "'" .. tostring(value):gsub("\\", "\\\\")
		:gsub("%z", "\\0"):gsub("\a", "\\a"):gsub("\b", "\\b")
		:gsub("\f", "\\f"):gsub("\n", "\\n"):gsub("\r", "\\r")
		:gsub("\t", "\\t"):gsub("\v", "\\v"):gsub("'", "\\'") .. "'"
end

return _M

