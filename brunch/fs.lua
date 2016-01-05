
local lfs = require "lfs"

local _M = {}

-- Isolating the madness in that single file would be awesomely great.

function _M.cp(a, b)
	return os.execute(("cp '%s' '%s'"):format(a, b))
end

function _M.mkdir(dirname)
	return os.execute(("mkdir -p '%s'"):format(dirname))
end

-- Better be careful with that one.
function _M.rm(dirname)
	return os.execute(("rm -rf '%s'"):format(dirname))
end

function _M.cd(directory, cb)
	local oldDir = lfs.currentdir()

	-- FIXME: errors management.
	lfs.chdir(directory)

	cb()

	lfs.chdir(oldDir)
end

function _M.find(directory, callback)
	for f in lfs.dir(directory) do
		if f ~= "." and f ~= ".." then
			local filename = ("%s/%s"):format(directory, f)

			callback(filename)

			if lfs.attributes(filename).mode == "directory" then
				_M.find(filename, callback)
			end
		end
	end
end

function _M.chmod(file, mode)
	os.execute(("chmod '%s' '%s'"):format(mode, file))
end

return _M

