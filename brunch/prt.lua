
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
		for key, value in pairs(var) do
			var[key] =
				substituteVariables(value, recipe, defaults)
		end
	end

	return var
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
				slot = slot
			}
		end

		return t
	else
		t = {{
			name = self.name,
			version = self.version,
			release = self.release,
			slot = self.slot -- Can be nil, be warned.
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

	for i = 1, #slotss do
		atoms[#atoms+1] = self:getTargetAtom(slots[i])
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

-- FIXME: Rewrite it all.
function _M:build(opt, slot)
	local oldDir = lfs.currentdir()

	local pkgdir = opt.packagesDirectory or oldDir
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

	local srcdir = opt.sourcesDirectory or oldDir

	local builddir = fs.mktemp(true)

	self.workingDirectory = builddir

	self.fakeRoot = builddir .. "/pkg"
	fs.mkdir(self.fakeRoot)

	lfs.chdir(builddir)

	local sources = self.recipe.sources
	if sources then
		for i = 1, #sources do
			local source = sources[i]

			if source.filename:match(".tar.*$") then
				ui.info("Extracting '", source.filename, "'")
				os.execute(("tar xf '%s/%s'"):format(
					srcdir, source.filename
				))
			else
				ui.info("Copying '", source.filename, "'.")

				fs.cp(("%s/%s"):format(
					srcdir, source.filename
				), ".")
			end
		end
	end

	local env = ""
	for key, value in pairs(self.recipe.exports or {}) do
		env = env .. ";" .. key .. "=\"" .. value .. "\""
	end

	-- Okay, that part is even uglier.
	local r, e
	if self.recipe.build then
		local build = substituteVariables(self.recipe.build, {
			version = self.version, name = self.name, slot = slot.slot
		}, defaults)
		r, e = os.execute("set -x -e; PKG='"
			.. self.fakeRoot .. "' "
			.. env .. ";"
			.. build
		)
	else
		r, e = os.execute("set -x -e; PKG='"
			.. self.fakeRoot .. "' "
			.. env .. ";" .. substituteVariables([[

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

		]], self.recipe, defaults)
		)
	end

	if not r then
		return nil, "building failed"
	end

	local t = type(self.recipe.install)
	if t == "nil" then
		r, e = os.execute("set -x -e; PKG='"
			.. self.fakeRoot .. "'; " .. substituteVariables([[

test -d %{name}-%{version} && cd %{name}-%{version}

test -f Makefile && {
	make DESTDIR="$PKG" install
}

			]], self.recipe, defaults))
	elseif t == "string" then
		local install = substituteVariables(self.recipe.build, {
			version = self.version, name = self.name, slot = slot.slot
		}, defaults)

		r, e = os.execute("set -x -e; PKG='"
			.. self.fakeRoot .. "'; " ..
			install)
	elseif t == "table" then
		r = true

		for bin, dir in pairs(self.recipe.install) do
			fs.mkdir(self.fakeRoot .. "/" .. dir)
			r = r and fs.cp(bin, self.fakeRoot .. "/" .. dir)
		end
	end

	if not r then
		return nil, "fake-installation failed"
	end

	lfs.chdir(oldDir)

	return self:package(opt, slot)
end

function _M:package(opt, slot)
	local pkgdir = opt.packagesDirectory or lfs.currentdir()

	-- FIXME: Also check write permissions in it.
	local attr = lfs.attributes(pkgdir)
	if not attr then
		return nil, "packages directory cannot be accessed"
	elseif attr.mode ~= "directory" then
		return nil, "packages directory is not a directory"
	end

	local pkgname = self:getPackageName(opt, slot)
	local pkgfilename = ("%s/%s"):format(pkgdir, pkgname)

	if lfs.attributes(pkgfilename) and not opt.force then
		ui.warning(("Package already built: '%s'."):format(pkgname))

		return pkgname, "package already built"
	end

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
			slot = self.slot,

			architecture = opt.architecture,
			kernel = opt.kernel,
			libc = opt.libc,

			prefixes = defaults
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

			recipe.sources[key] = {
				url = value,
				filename = value:gsub("^.*/", ""),
				protocol = value:gsub(":.*$", "")
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

