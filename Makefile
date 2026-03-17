PACKAGE  := immutable-ubuntu
VERSION  := $(shell dpkg-parsechangelog -S Version)
DEB      := target/$(PACKAGE)_$(VERSION)_all.deb

SCRIPTS  := data/usr/sbin/immutable-update \
            data/usr/sbin/immutable-ubuntu-setup \
            data/usr/lib/dracut/modules.d/90immutable-ubuntu/module-setup.sh \
            data/usr/lib/dracut/modules.d/90immutable-ubuntu/immutable-ubuntu-setup.sh \
            data/usr/lib/dracut/modules.d/90immutable-ubuntu/immutable-ubuntu-generator \
            data/etc/grub.d/06_immutable

.PHONY: build clean lint

build: $(DEB)

$(DEB):
	dpkg-buildpackage -us -uc -b
	mkdir -p target
	mv ../$(PACKAGE)_$(VERSION)_all.deb target/
	mv ../$(PACKAGE)_$(VERSION)_*.buildinfo target/ 2>/dev/null || true
	mv ../$(PACKAGE)_$(VERSION)_*.changes target/ 2>/dev/null || true

lint:
	shellcheck -s bash $(SCRIPTS)

clean:
	rm -rf target
	rm -f debian/debhelper-build-stamp debian/files
	rm -rf debian/.debhelper debian/$(PACKAGE)
	rm -f debian/*.substvars debian/*.log
