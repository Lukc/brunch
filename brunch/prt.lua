
local ui = require "brunch.ui"
local ltin = require "brunch.ltin"
local fs = require "brunch.fs"

local lfs = require "lfs"

local _M = {}

local defaults = {
	prefix = "/usr",
	bindir = "/usr/bin",
	libdir = "/usr/lib",
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

function _M:getAtoms()
	local recipe = self.recipe

	return {
		("%s %s-%s"):format(
			recipe.name,
			recipe.version,
			recipe.release
		)
	}
end

function _M:getPackageName(opt)
	return ("%s-%s-%s@%s-%s-%s.brunch"):format(
		self.name, self.recipe.version, self.release,
		opt.kernel, opt.libc, opt.architecture
	)
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
function _M:build(opt)
	local oldDir = lfs.currentdir()

	local pkgdir = opt.packagesDirectory or oldDir
	local pkgname = self:getPackageName(opt)
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

	local builddir = io.popen("mktemp -d"):read("*a"):gsub("\n$", "")

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
		r, e = os.execute("set -x -e; PKG='"
			.. self.fakeRoot .. "' "
			.. env .. ";"
			.. self.recipe.build
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
		r, e = os.execute("set -x -e; PKG='"
			.. self.fakeRoot .. "'; " ..
			self.recipe.install)
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

	return r
end

function _M:package(opt)
	local pkgdir = opt.packagesDirectory or lfs.currentdir()

	-- FIXME: Also check write permissions in it.
	local attr = lfs.attributes(pkgdir)
	if not attr then
		return nil, "packages directory cannot be accessed"
	elseif attr.mode ~= "directory" then
		return nil, "packages directory is not a directory"
	end

	local pkgname = self:getPackageName(opt)
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

		os.execute(("tar cf '%s' meta.ltin content.tar.xz"):format(
			pkgfilename
		))
	end)

	if r then
		return pkgname
	end
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
			value = value:gsub("%%{version}", recipe.version or "")

			recipe.sources[key] = {
				url = value,
				filename = value:gsub("^.*/", ""),
				protocol = value:gsub(":.*$", "")
			}
		end
	end

	recipe = substituteVariables(recipe, recipe, defaults)

	local _O = {
		recipe = recipe,
		name = recipe.name,
		version = recipe.version,
		release = recipe.release or 1,
		slot = recipe.slot,
		dependencies = recipe.depends
	}

	setmetatable(_O, {
		__index = _M
	})

	return _O
end

return _M

