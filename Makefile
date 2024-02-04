SUBDIRS=rx-unix

all: $(SUBDIRS) tx-msdos

$(SUBDIRS):
	$(MAKE) -C $@
tx-msdos: tx-msdos-extract
	dosbox --conf dosbox.conf
	cat tx-msdos/BUILD.LOG

tx-msdos-extract:
	cd tx-msdos/build; tar --skip-old-files -xf watcom-11.tar.xz

clean:
	rm -rf rx-unix/build
	rm -f tx-msdos/*.OBJ
	rm -f tx-msdos/*.EXE
	rm -f tx-msdos/*.MAP
	rm -f tx-msdos/*.LK1

format:
	cd tx-msdos/src; clang-format -i -style=WebKit *.c *.h
	cd rx-unix/src; clang-format -i -style=WebKit *.c *.h

.PHONY: all $(SUBDIRS) tx-msdos
