#!/usr/bin/env lua

local ui = require "brunch.ui"
local database = require "brunch.db"
local package = require "brunch.pkg"
local port = require "brunch.prt"
local ltin = require "brunch.ltin"

local lfs = require "lfs"
local argparse = require "argparse"

local function has(element, array)
	for i = 1, #array do
		if array[i] == element then
			return true
		end
	end
end


local parser = argparse(arg[0], "Brunch Package Manager")
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
command:flag(
	"-f --force", "Overwrites existing files and reinstalls if needed.")

command = parser:command("update", "Updates a package.")
command:argument("package", "A brunch package to install."):args(1)
command:flag(
	"-f --force", "Overwrites existing files and reinstalls if needed.")

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

if type(config.architecture) ~= "string" then
	local p = io.popen("uname -m")
	local arch = p:read("*line")
	p:close()
	ui.warning("No “architecture” field in your configuration!")
	ui.warning("Using the default value: ", arch)

	config.architecture = arch
end

if type(config.kernel) ~= "string" then
	local p = io.popen("uname -s")
	local kernel = p:read("*line"):lower()
	p:close()
	ui.warning("No “kernel” field in your configuration!")
	ui.warning("Using the default value: ", kernel)

	config.kernel = kernel
end

if type(config.libc) ~= "string" then
	local libc = "gnu"
	ui.warning("No “libc” field in your configuration!")
	ui.warning("Using the default value: ", libc)

	config.libc = libc
end

for key, value in pairs(config) do
	opt[key] = opt[key] or value
end

if opt.show then
	local prt, e = port.open(opt.port)

	if not prt then
		ui.error(e)
		os.exit(1)
	end

	for _, slot in ipairs(prt:getSlots()) do
		local atom = prt:getSlotAtom(slot)
		-- FIXME: Show status.
		ui.info(atom)
		ui.rinfo(("%s[%s]"):format(
			ui.colors.red,
			db:isInstalled(slot) and "I" or " "
		))

		if prt.dependencies then
			ui.header("Dependencies")
			for _, name in ipairs(slot.dependencies or {}) do
				-- FIXME: Add the status of those dependencies.
				ui.list(name)
			end
		end
	end
elseif opt.build then
	local prt, e = port.open(opt.port)

	if not prt then
		ui.error(e)
		os.exit(1)
	end

	local slots = prt:getSlots()
	if not slots then
		ui.error("Could not generate the port’s virtual slots list.")
		os.exit(1)
	end

	local r, e = prt:fetch(opt)
	if not r then
		ui.error(e)
		os.exit(1)
	end

	for i = 1, #slots do
		local slot = slots[i]

		ui.info("Building ", prt:getSlotAtom(slot), ".")
		local r, e = prt:build(opt, slot)

		if r then
			if not e then
				prt:clean()
			end
		else
			ui.error(e)
			os.exit(1)
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
		ui.info(("%s installed"):format(pkg:getAtom()))
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
		ui.info(("%s updated"):format(pkg:getAtom()))
	end

	pkg:close()
elseif opt.remove then
	local r, e = db:remove(opt.package, opt)

	if e then
		ui.error(e)
		os.exit(1)
	else
		ui.info(("%s removed"):format(r:getAtom()))
	end
elseif opt["list-installed"] then
	for _, package in ipairs(db:listInstalled()) do
		local s = ("%s %s-%s"):format(
			package.name, package.version, package.release
		)

		if package.slot then
			s = ("%-26s :%s"):format(s, package.slot)
		end

		ui.list(s)
	end
else
	ui.error("see usage")
	os.exit(1)
end

