
local ltin = require "brunch.ltin"
local fs = require "brunch.fs"

local lfs = require "lfs"

local _M = {}

function _M.open(filename)
	local oldDir = lfs.currentdir()

	local directory = io.popen("mktemp -d"):read("*a"):gsub("\n$", "")

	fs.mkdir(directory .. "/root")

	os.execute(("tar -C '%s' -xf '%s'"):format(
		directory, filename
	))

	os.execute(("tar -C '%s/root' -xf '%s/content.tar.xz'"):format(
		directory, directory
	))

	local metaFile = io.open(("%s/meta.ltin"):format(directory), "r")
	local meta = ltin.parse(metaFile:read("*a"))
	metaFile:close()

	local _O = {
		directory = directory,
		name = meta.name,
		version = meta.version,
		release = meta.release,
		slot = meta.slot,

		dependencies = meta.dependencies,

		-- Just in case.
		meta = meta,

		close = _M.close
	}

	setmetatable(_O, {
		__index = _M
	})

	return _O
end

function _M:close()
	os.execute("rm -rf '" .. self.directory .. "'")
end

return _M

