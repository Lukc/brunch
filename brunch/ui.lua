
local _M = {}

function _M.info(...)
	io.write(" \027[01;32m> \027[01;37m")
	io.write(...)
	io.write("\027[00m\n")
end

function _M.header(...)
	io.write(" \027[01;34m>> \027[00;37m")
	io.write(...)
	io.write("\027[00m\n")
end

function _M.list(...)
	io.write(" \027[01;32m  - \027[00;37m")
	io.write(...)
	io.write("\027[00m\n")
end

function _M.rinfo(...)
	local str = table.concat(table.pack(...))
	io.write("\027[", tostring(72 - _M.len(str)), "G\027[01A")
	io.write(str)
	io.write("\027[00m\n")
end

function _M.warning(...)
	io.stderr:write(" \027[01;33m> ")
	io.stderr:write(...)
	io.stderr:write("\027[00m\n")
end

function _M.error(...)
	io.stderr:write(" \027[01;31m> ")
	io.stderr:write(...)
	io.stderr:write("\027[00m\n")
end

function _M.len(str)
	local len = #str

	for match in str:gmatch("\027%[[0-9;]+m") do
		len = len - #match
	end

	return len
end

_M.colors = {
	bright  = "\027[01m",
	red     = "\027[31m",
	blue    = "\027[34m",
	magenta = "\027[35m"
}

return _M

