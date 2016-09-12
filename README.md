
Installation
============

`make LUA_VERSION=5.3  install`

See `Makefile` for a list of variables you can edit from the command line.

With MoonBox
------------

```bash
moonbox install
source moonbox env enter
PREFIX=.moonbox make LUA_VERSION=5.3 install
```

Dependencies
============

For now, we need the following Lua libraries:

  - argparse
  - lfs (LuaFileSystem)

Should work on any Lua version, but was tested mostly under 5.2.

Usage
=====

When launched for the first time, `brunch` will try to create its database. It
will likely require root permissions to do so, unless you decide to use the
`-r` or `--root` option.

`brunch install` will install a package.

`brunch remove` will remove a package.

`brunch build` will create a package from a `package.ltin` file.

