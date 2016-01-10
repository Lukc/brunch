
local fs = require "brunch.fs"
local ltin = require "brunch.ltin"
local ui = require "brunch.ui"
local pkg = require "brunch.pkg"

local function has(e, a)
	for i = 1, #a do
		if a[i] == e then
			return true
		end
	end
end

local _M = {}

function _M.create(root, cf)
	local r

	r = os.execute("mkdir -p '" .. root .. "/var/lib/brunch'")
	if not r then return nil, "failed to create database directory" end

	r = os.execute("mkdir -p '" .. root .. "/var/lib/brunch/manifests'")
	if not r then return nil, "failed to create database directory" end

	r = os.execute("echo '{}' > '" .. root .. "/var/lib/brunch/installed.ltin'")
	if not r then
		return nil, "failed to create database's installed packages list"
	end

	return _M.open(root, cf)
end

function _M.open(root, configFile)
	local file = io.open(root .. "/var/lib/brunch/installed.ltin")

	if not file then
		return nil, "no valid DB at this location"
	end

	file:close()

	file = io.open(configFile, "r")

	local _O = {
		root = root,
		config = ltin.parse(file:read("*a"))
	}

	file:close()	

	if type(_O.config.architecture) ~= "string" then
		local p = io.popen("uname -m")
		local arch = p:read("*line")
		p:close()
		ui.warning("No “architecture” field in your configuration!")
		ui.warning("Using the default value: ", arch)

		_O.config.architecture = arch
	end

	if type(_O.config.kernel) ~= "string" then
		local p = io.popen("uname -s")
		local kernel = p:read("*line"):lower()
		p:close()
		ui.warning("No “kernel” field in your configuration!")
		ui.warning("Using the default value: ", kernel)

		_O.config.kernel = kernel
	end

	if type(_O.config.libc) ~= "string" then
		local libc = "gnu"
		ui.warning("No “libc” field in your configuration!")
		ui.warning("Using the default value: ", libc)

		_O.config.libc = libc
	end

	setmetatable(_O, {
		__index = _M
	})

	return _O
end

-- optional: port
function _M:getTargets(port)
	local config = self.config
	local t = {}

	if config.native then
		t[#t+1] = {
			kernel = config.kernel,
			libc = config.libc,
			architecture = config.architecture,
			exports = config.native
		}
	else
		ui.warning("No “native” target in your configuration!")
	end

	if config.noarch then
		local target = {
			kernel = "any",
			libc = "any",
			architecture = "any",
			exports = config.noarch
		}

		for key, value in pairs(config.native) do
			if not target.exports[key] then
				target.exports[key] = value
			end
		end

		if port then
			if port.noarch then
				return {target}
			end
		else
			t[#t+1] = target
		end
	else
		ui.warning("No “noarch” target in your configuration!")
	end

	for k,v in pairs(config) do
		local k, l, a = k:match("^([a-z_0-9]+)-([a-z_0-9]+)-([a-z_0-9]+)$")
		if k and l and a then
			local target = {
				kernel = k,
				libc = l,
				architecture = a,
				exports = v
			}

			for key, value in pairs(config.native) do
				if not target.exports[key] then
					target.exports[key] = value
				end
			end

			t[#t+1] = target
		end
	end

	return t
end

function _M:updateDBFile(filename, callback)
	local file =
		io.open(("%s/var/lib/brunch/%s"):format(self.root, filename), "r")

	if not file then
		return nil, "could not open file for reading", filename
	end

	local data = ltin.parse(file:read("*a"))

	file:close()

	callback(data)

	local file =
		io.open(("%s/var/lib/brunch/%s"):format(self.root, filename), "w")

	if not file then
		return nil, "could not open file for writing", filename
	end

	file:write(ltin.stringify(data))

	file:close()

	return true
end

function _M:listInstalled()
	local file, e = io.open(self.root .. "/var/lib/brunch/installed.ltin")

	if not file then
		return nil, e
	end

	local list = ltin.parse(file:read("*a"))

	file:close()

	return list
end

function _M:updateDBEntry(file, package, callback)
	self:updateDBFile("installed.ltin", function(data)
		local index = 1

		while index <= #data do
			local entry = data[index]
			local sameName = entry.name == package.name
			local sameSlot = (not entry.slot) or entry.slot == package.slot

			if sameName and sameSlot then
				data[index] = callback(data[index])

				return
			end

			index = index + 1
		end

		data[index] = callback(data)
	end)
end

local function installFile(self, filename, opt)
	local attr = lfs.symlinkattributes(filename)

	local dest = ("%s/%s"):format(self.root, filename)

	if lfs.attributes(dest) and not (opt.force or opt.update) then
		-- File exists. Some special files are ignored.
		if attr.mode == "directory" then
		elseif attr.mode == "link" then
		else
			print(dest)
			error("would overwrite file", 0)
		end
	else
		if opt.verbose then
			io.write("<IN>  ", attr.permissions, "  ", filename, "\n")
		end

		if attr.mode == "directory" then
			-- FIXME: Give it the same permissions…
			fs.mkdir(dest)
		elseif attr.mode == "file" then
			fs.cp(filename, dest)
		elseif attr.mode == "link" then
			fs.cp(filename, dest)
		else
			error("unsupported mode: " .. attr.mode, 0)
		end
	end
end

local function removeFile(file, opt)
	local attr = lfs.symlinkattributes(file)

	if not attr then
		ui.warning("Could not remove non-existant file: ", file)
	else
		if attr.mode == "file" or attr.mode == "link" then
			if opt.verbose then
				io.write("<RM>  ", attr.permissions, "  ", file, "\n")
			end

			if not fs.rm(file) then
				error("error while removing file", 0)
			end
		elseif attr.mode == "directory" then
		else
			error("unsupported mode: " .. attr.mode, 0)
		end
	end
end

function _M:isInstalled(package)
	local installed = self:listInstalled()

	for i = 1, #installed do
		local data = installed[i]

		local sameName = data.name == package.name
		local sameSlot = (not data.slot) or data.slot == package.slot
		local sameTriplet =
			data.kernel == package.kernel and
			data.libc == package.libc and
			data.architecture == package.architecture

		if sameName and sameSlot and sameTriplet then
			return true
		end
	end
end

function _M:install(package, opt)
	if not opt then
		opt = {}
	end

	if not (opt.force or opt.update) then
		if self:isInstalled(package) then
			return nil, "package already installed"
		end
	end

	local installedFiles = {}

	local _, e = pcall(fs.cd, package.directory, function()
		local metaFile = io.open("meta.ltin", "r")
		local meta = ltin.parse(metaFile:read("*a"))
		metaFile:close()

		local manifest =
			io.open(("%s/var/lib/brunch/manifests/%s@%s-%s"):format(
				self.root, package.name, package.version, package.release
			), "w")

		if not manifest then
			error("could not open manifest", 0)
		end

		fs.cd("root", function()
			fs.find(".", function(filename)
				-- Let’s remove that confusing “./” prefix.
				filename = filename:sub(3, #filename)

				installFile(self, filename, opt)
				installedFiles[#installedFiles+1] = filename

				manifest:write(filename, "\n")
			end)
		end)

		manifest:close()

		self:updateDBEntry("installed.ltin", package,
			function(data)
				return meta
			end)
	end)

	if e then
		return nil, e
	end

	return {
		name = package.name,
		version = package.version,
		release = package.release,
		slot = package.slot
	}, installedFiles
end

function _M:getDBFileName(name)
	return ("%s/var/lib/brunch/%s"):format(self.root, name)
end

function _M:info(name)
	local file = io.open(self:getDBFileName("installed.ltin"))
	local data = ltin.parse(file:read("*a"))

	file:close()

	for i = 1, #data do
		if data[i].name == name then
			-- Will be of use for things like :getAtom().
			setmetatable(data[i], {
				__index = pkg
			})
			return data[i]
		end
	end
end

function _M:remove(name, opt)
	if not opt then
		opt = {}
	end

	local entry = self:info(name)

	if not entry then
		return nil, "package is not installed"
	end

	local manifestFileName = self:getDBFileName(("manifests/%s@%s-%s"):format(
		entry.name, entry.version, entry.release
	))

	-- We’re using r+ because if we can’t get write permissions, we’ll be
	-- in trouble to remove the file later on.
	local manifestFile = io.open(manifestFileName, "r+")

	if not manifestFile then
		return nil, "could not open manifest"
	end

	-- Hey, let’s use this!
	local _, e = pcall(fs.cd, self.root, function()
		for file in manifestFile:lines() do
			removeFile(file, opt)
		end
	end)

	if e then
		return nil, e
	end

	local _, e = self:updateDBFile("installed.ltin", function(data)
		for i = 1, #data do
			if data[i].name == entry.name then
				data[i] = data[#data]
				data[#data] = nil
			end
		end
	end)

	if e then
		return nil, e
	end

	fs.rm(manifestFileName)

	return entry
end

function _M:update(package, opt)
	if not opt then
		opt = {}
	end

	local meta

	local _, e = pcall(fs.cd, package.directory, function()
		local entry = self:info(package.name)

		if not entry then
			error("package is not installed", 0)
		end

		local manifestFileName =
			self:getDBFileName(("manifests/%s@%s-%s"):format(
				entry.name, entry.version, entry.release
			))

		local oldManifest = io.open(manifestFileName, "r")

		if not oldManifest then
			return nil, "could not open old manifest"
		end

		oldFiles = oldManifest:read("*a")
		oldManifest:close()

		fs.rm(manifestFileName)

		local newManifest =
			io.open(("%s/var/lib/brunch/manifests/%s@%s-%s"):format(
				self.root, package.name, package.version, package.release
			), "w")

		if not newManifest then
			error("could not open new manifest", 0)
		end


		local _, installedFiles = self:install(package, opt)

		fs.cd(self.root, function()
			for file in oldFiles:gmatch("[^\n][^\n]*") do
				if not has(file, installedFiles) then
					removeFile(file, opt)
				end
			end
		end)
	end)

	if e then
		return nil, e
	end

	return {
		name = package.name,
		version = package.version,
		release = package.release,
		slot = package.slot
	}
end

return _M

