#!/usr/bin/env lua

local ui = require "brunch.ui"
local database = require "brunch.db"
local package = require "brunch.pkg"
local port = require "brunch.prt"

local lfs = require "lfs"
local argparse = require "argparse"

local function has(element, array)
	for i = 1, #array do
		if array[i] == element then
			return true
		end
	end
end


local parser = argparse(arg[0], "Lukc’s Package Manager")
local command

parser:option("-r --root", "Change the system’s root directory.", "/")
parser:flag("-v --verbose", "Be more talkative.")

command = parser:command("show", "Prints the available data on a port.")
command:argument("port", "A package.ltin file.", "package.ltin")

command = parser:command("build", "Builds a package from a port.")
command:argument("port", "A package.ltin file.", "package.ltin")
command:flag("-f --force", "Ignores already built packages.")

command = parser:command("install", "Installs a package.")
command:argument("package", "A brunch package to install."):args(1)
command:flag
	("-f --force", "Overwrites existing files and reinstalls if needed.")

command = parser:command("update", "Updates a package.")
command:argument("package", "A brunch package to install."):args(1)
command:flag
	("-f --force", "Overwrites existing files and reinstalls if needed.")

command = parser:command("remove", "Uninstalls a package.")
command:argument("package", "A brunch package to install."):args(1)

command = parser:command("list-installed", "List all installed packages.")

local opt = parser:parse(arg)

if not opt.root:match("^/") then
	opt.root = lfs.currentdir() .. "/" .. opt.root
end

local db = database.open(opt.root)

if not db then
	ui.info("No package database found. Creating one.")

	local e
	db, e = database.create(opt.root)

	if e then
		ui.error(e)
		os.exit(1)
	end
end

local config = {}
local userConf = ("%s/.config/brunch/config.ltin"):format(os.getenv("HOME"))
for _, filename in ipairs {"/etc/brunch.ltin", userConf} do
	local file = io.open(filename, "r")

	if file then
		local content = ltin.parse(file:read("*a"))

		if content then
			for key, value in pairs(content) do
				config[key] = config[key] or value
			end
		end

		file:close()
	end
end

if opt.show then
	local prt, e = port.open(opt.port)

	if not prt then
		ui.error(e)
		os.exit(1)
	end

	for _, atom in ipairs(prt:getAtoms()) do
		-- FIXME: Show status.
		ui.info(atom)
		ui.rinfo(("%s[?]"):format(ui.colors.red))
	end

	ui.header("Dependencies")
	for _, name in ipairs(prt.dependencies or {}) do
		-- FIXME: Add the status of those dependencies.
		ui.list(name)
	end
elseif opt.build then
	local prt, e = port.open(opt.port)

	if not prt then
		ui.error(e)
		os.exit(1)
	end

	prt:fetch(opt)

	local r, e = prt:build(opt)
	if not e then
		ui.info "Packaging..."

		local package = prt:package(opt)
		if package then
			ui.info(("Package built: '%s'"):format(package))

			prt:clean {}
		end
	else
		if not r then
			ui.error(e)
		end
	end
elseif opt.install then
	local pkg, e = package.open(opt.package)

	if not pkg then
		ui.error(e)
		os.exit(1)
	end

	local r, e = db:install(pkg, opt)

	if not r then
		ui.error(e)
		pkg:close()
		os.exit(1)
	else
		ui.info(("%s@%s-%s installed"):format(r.name, r.version, r.release))
	end

	pkg:close()
elseif opt.update then
	local pkg, e = package.open(opt.package)

	if not pkg then
		ui.error(e)
		os.exit(1)
	end

	local r, e = db:update(pkg, opt)

	if e then
		ui.error(e)
		pkg:close()
		os.exit(1)
	else
		ui.info(("%s@%s-%s updated"):format(r.name, r.version, r.release))
	end

	pkg:close()
elseif opt.remove then
	local r, e = db:remove(opt.package, opt)

	if e then
		ui.error(e)
		os.exit(1)
	else
		ui.info(("%s@%s-%s removed"):format(r.name, r.version, r.release))
	end
elseif opt["list-installed"] then
	for _, package in ipairs(db:listInstalled()) do
		ui.list(package.name, " ", package.version, "-", package.release)
	end
else
	ui.error("see usage")
	os.exit(1)
end

