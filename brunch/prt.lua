
local ui = require "brunch.ui"
local ltin = require "brunch.ltin"
local fs = require "brunch.fs"

local lfs = require "lfs"

local _M = {}

local defaults = {
	prefix = "/usr",
	bindir = "/usr/bin",
	libdir = "/usr/lib",
	includedir = "/usr/include",
	sharedir = "/usr/share",
	mandir = "/usr/share/man",
	confdir = "/usr/etc",
}

local function substituteVariables(var, recipe, defaults)
	local t = type(var)

	if t == "string" then
		local s = var:match("%%{[a-zA-Z0-9]+}")
		while s do
			local key = s:gsub("^%%{", ""):gsub("}$", "")

			var = var:gsub("%%{" .. key .. "}",
				tostring(recipe[key] or defaults[key]))

			s = var:match("%%{[a-zA-Z0-9]+}")
		end
	elseif t == "table" then
		local nt = {}
		for key, value in pairs(var) do
			nt[key] =
				substituteVariables(value, recipe, defaults)
		end
		return nt
	end

	return var
end

local defaultBuild = [[
test -d %{name}-%{version} && cd %{name}-%{version}

test -x configure && {
	./configure \
		--prefix=${prefix:-%{prefix}} \
		--libdir=${libdir:-%{libdir}} \
		--bindir=${bindir:-%{bindir}} \
		--mandir=${mandir:-%{mandir}} \
		--sysconfdir=${confdir:-%{confdir}}
}

test -f Makefile && {
	make
}
]]

local defaultInstall = [[
test -d %{name}-%{version} && cd %{name}-%{version}

test -f Makefile && {
	make DESTDIR="$PKG" install
}
]]


local function buildFunction(self, slot, default, recipeFunction)
	local env = ""
	for key, value in pairs(self.recipe.exports or {}) do
		env = env .. ";" .. key .. "=\"" .. value .. "\""
	end

	local f
	if recipeFunction then
		f = substituteVariables(recipeFunction, {
			version = self.version, name = self.name, slot = slot.slot
		}, defaults)
	else
		f = substituteVariables(default, self.recipe, defaults)
	end

	return os.execute("set -x -e; PKG='"
		.. self.fakeRoot .. "' "
		.. env .. ";"
		.. f
	)
end

function _M:getSlots()
	local t

	if self.slots then
		t = {}

		for i = 1, #self.slots do
			local slot = self.slots[i]

			t[#t+1] = {
				name = self.name,
				version = self.version,
				release = self.release,
				slot = slot,
				dependencies = substituteVariables(self.dependencies, {
					slot = slot
				})
			}
		end

		return t
	else
		t = {{
			name = self.name,
			version = self.version,
			release = self.release,
			slot = self.slot, -- Can be nil, be warned.
			dependencies = self.dependencies
		}}
	end

	return t
end

function _M:getSlotAtom(slot)
	if slot.slot then
		return ("%s %s-%s:%s"):format(
			slot.name,
			slot.version,
			slot.release,
			slot.slot
		)
	else
		return ("%s %s-%s"):format(
			slot.name,
			slot.version,
			slot.release
		)
	end
end

function _M:getAtoms()
	local slots = self:getSlots()
	local atoms = {}

	for i = 1, #slots do
		atoms[#atoms+1] = self:getSlotAtom(slots[i])
	end

	return atoms
end

function _M:getPackageName(opt, slot)
	if slot.slot then
		return ("%s-%s-%s:%s@%s-%s-%s.brunch"):format(
			slot.name, slot.version, slot.release, slot.slot,
			opt.kernel, opt.libc, opt.architecture
		)
	else
		return ("%s-%s-%s@%s-%s-%s.brunch"):format(
			slot.name, slot.version, slot.release,
			opt.kernel, opt.libc, opt.architecture
		)
	end
end

function _M:fetch(options)
	local srcdir = options.sourcesDirectory or "."
	local sources = self.recipe.sources

	-- FIXME: Also check write permissions in it.
	local attr = lfs.attributes(srcdir)
	if not attr then
		return nil, "sources directory cannot be accessed"
	elseif attr.mode ~= "directory" then
		return nil, "sources directory is not a directory"
	end

	local r = true
	local e

	if not sources then
		-- Nothing to download? Success!
		return true
	end

	for i = 1, #sources do
		local s = sources[i]

		local filename = ("%s/%s"):format(srcdir, s.filename)
		local f = io.open(filename, "r")

		if f then
			f:close()

			ui.info("Already downloaded '", s.filename, "'.")
		else
			ui.info("Downloading '", s.filename, "'.")

			r = r and os.execute(("wget '%s' -O '%s/%s'"):format(
				s.url, srcdir, s.filename
			))

			if not r then
				e = "could not download source"
			end
		end
	end

	return r, e
end

function _M:extract(opt, srcdir)
	local sources = self.recipe.sources
	if sources then
		for i = 1, #sources do
			local source = sources[i]
			local r

			if source.filename:match(".tar.*$") then
				ui.info("Extracting '", source.filename, "'")
				r = os.execute(("tar xf '%s/%s'"):format(
					srcdir, source.filename
				))
			else
				ui.info("Copying '", source.filename, "'.")

				r = fs.cp(("%s/%s"):format(
					srcdir, source.filename
				), ".")
			end

			if not r then
				return nil, "extraction or copy failed"
			end
		end
	end

	return true
end

function _M:package(opt, slot)
	local pkgdir = opt.packagesDirectory or lfs.currentdir()

	local pkgname = self:getPackageName(opt, slot)
	local pkgfilename = ("%s/%s"):format(pkgdir, pkgname)

	local r
	fs.cd(self.fakeRoot, function()
		local tarball = ("%s/content.tar.xz"):format(self.workingDirectory)

		r = os.execute(("tar cJf '%s' ."):format(tarball))
	end)

	if not r then
		return nil, "could not create content.tar.xz"
	end

	fs.cd(self.workingDirectory, function()
		local file = io.open("meta.ltin", "w")

		file:write(ltin.stringify {
			"Built with love. <3",
			name = self.name,
			version = self.version,
			release = self.release,
			slot = slot.slot,

			dependencies = slot.dependencies,

			architecture = opt.architecture,
			kernel = opt.kernel,
			libc = opt.libc,
		})

		file:close()

		r, e = os.execute(("tar cf '%s' meta.ltin content.tar.xz"):format(
			pkgfilename
		))
	end)

	if not r then
		return nil, "could not create package"
	end

	return pkgname
end

function _M:build(opt, slot)
	local pkgdir = opt.packagesDirectory or lfs.currentdir()
	local srcdir = opt.sourcesDirectory or lfs.currentdir()

	local pkgname = self:getPackageName(opt, slot)
	local pkgfilename = ("%s/%s"):format(pkgdir, pkgname)

	-- FIXME: Also check write permissions in it.
	local attr = lfs.attributes(pkgdir)
	if not attr then
		return nil, "packages directory cannot be accessed"
	elseif attr.mode ~= "directory" then
		return nil, "packages directory is not a directory"
	end

	if lfs.attributes(pkgfilename) and not opt.force then
		ui.warning(("Package already built: '%s'."):format(pkgname))

		return pkgname, "package already built"
	end

	local builddir = fs.mktemp(true)

	self.workingDirectory = builddir

	self.fakeRoot = builddir .. "/pkg"
	fs.mkdir(self.fakeRoot)

	local _, e = pcall(fs.cd, builddir, function()
		local r = self:extract(opt, srcdir)
		if not r then
			error("extraction failed", 0)
		end

		local r, e = buildFunction(self, slot, defaultBuild, self.recipe.build)
		if not r then
			error("building failed", 0)
		end

		local t = type(self.recipe.install)
		if t == "table" then
			r = true

			for bin, dir in pairs(self.recipe.install) do
				fs.mkdir(self.fakeRoot .. "/" .. dir)
				r = r and fs.cp(bin, self.fakeRoot .. "/" .. dir)
			end
		else
			r, e =
				buildFunction(self, slot, defaultInstall, self.recipe.install)
		end

		if not r then
			error("fake-installation failed", 0)
		end
	end)

	if e then
		return nil, e
	end

	return self:package(opt, slot)
end

function _M:clean()
	ui.info("Removing working directory.")
	fs.rm(self.workingDirectory)
end

function _M.open(recipe)
	local file, e = io.open(recipe, "r")

	if not file then
		return nil, e
	end

	local recipe = ltin.parse(file:read("*a"))

	if recipe.sources then
		for key, value in pairs(recipe.sources) do
			value = substituteVariables(value, {
				version = recipe.version,
				name = recipe.name
			})

			local url = value:gsub("%s+->%s.*", "")
			local filename

			-- If -> was found.
			if url ~= value then
				filename = value:gsub("^.*->%s*", "")
			else
				filename = url:gsub("^.*/", "")
			end

			recipe.sources[key] = {
				url = url,
				filename = filename,
				protocol = url:gsub(":.*$", "")
			}
		end
	end

	local _O = {
		recipe = recipe,
		name = recipe.name,
		version = recipe.version,
		release = recipe.release or 1,
		slot = recipe.slot,
		slots = recipe.slots,
		dependencies = recipe.depends
	}

	setmetatable(_O, {
		__index = _M
	})

	return _O
end

return _M

