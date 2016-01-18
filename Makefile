
PREFIX ?= /usr/local
LIBDIR ?= ${PREFIX}/lib
BINDIR ?= ${PREFIX}/bin
SHAREDIR ?= ${PREFIX}/share

LUA_VERSION ?= 5.2
LUA_SHAREDIR ?= ${SHAREDIR}/lua/${LUA_VERSION}

all:

install:
	mkdir -p "${DESTDIR}${BINDIR}"
	mkdir -p "${DESTDIR}${LUA_SHAREDIR}/brunch"
	install -m0755 brunch.lua "${DESTDIR}${BINDIR}/brunch"
	install -m0644 brunch/db.lua   ${DESTDIR}${LUA_SHAREDIR}/brunch/db.lua
	install -m0644 brunch/fs.lua   ${DESTDIR}${LUA_SHAREDIR}/brunch/fs.lua
	install -m0644 brunch/ltin.lua ${DESTDIR}${LUA_SHAREDIR}/brunch/ltin.lua
	install -m0644 brunch/pkg.lua  ${DESTDIR}${LUA_SHAREDIR}/brunch/pkg.lua
	install -m0644 brunch/prt.lua  ${DESTDIR}${LUA_SHAREDIR}/brunch/prt.lua
	install -m0644 brunch/ui.lua   ${DESTDIR}${LUA_SHAREDIR}/brunch/ui.lua

uninstall:
	rm -f "${DESTDIR}${BINDIR}/brunch"
	rm -f ${DESTDIR}${LUA_SHAREDIR}/brunch/db.lua
	rm -f ${DESTDIR}${LUA_SHAREDIR}/brunch/fs.lua
	rm -f ${DESTDIR}${LUA_SHAREDIR}/brunch/ltin.lua
	rm -f ${DESTDIR}${LUA_SHAREDIR}/brunch/pkg.lua
	rm -f ${DESTDIR}${LUA_SHAREDIR}/brunch/prt.lua
	rm -f ${DESTDIR}${LUA_SHAREDIR}/brunch/ui.lua
	rmdir "${DESTDIR}${LUA_SHAREDIR}/brunch"

