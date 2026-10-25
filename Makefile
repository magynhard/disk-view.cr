.PHONY: setup build run test format clean install uninstall

PREFIX ?= /usr/local
DESTDIR ?=
APP_ID = de.magynhard.DiskView

setup:
	shards install
	./bin/gi-crystal

data/disk-view.gresource: data/disk-view.gresource.xml data/icons/de.magynhard.DiskView.svg
	glib-compile-resources --sourcedir=data --target=$@ $<

build: data/disk-view.gresource
	mkdir -p bin
	crystal build src/disk-view.cr -o bin/disk-view

run: build
	./bin/disk-view

test:
	crystal spec

format:
	crystal tool format src/ spec/

clean:
	rm -f bin/disk-view data/disk-view.gresource

install: build
	install -Dm755 bin/disk-view "$(DESTDIR)$(PREFIX)/bin/disk-view"
	install -Dm644 data/$(APP_ID).desktop "$(DESTDIR)$(PREFIX)/share/applications/$(APP_ID).desktop"
	install -Dm644 data/icons/$(APP_ID).svg "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/$(APP_ID).svg"
	install -Dm644 LICENSE "$(DESTDIR)$(PREFIX)/share/licenses/disk-view/LICENSE"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/disk-view" "$(DESTDIR)$(PREFIX)/share/applications/$(APP_ID).desktop" "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/$(APP_ID).svg" "$(DESTDIR)$(PREFIX)/share/licenses/disk-view/LICENSE"
