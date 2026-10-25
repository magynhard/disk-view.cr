.PHONY: setup build run test format clean install uninstall locales generate_locales

PREFIX ?= /usr/local
DESTDIR ?=
CRYSTAL_FLAGS ?=
APP_ID = de.magynhard.DiskView
LANGUAGES = $(strip $(file <po/LINGUAS))
MO_FILES = $(foreach lang,$(LANGUAGES),po/$(lang)/LC_MESSAGES/$(APP_ID).mo)

setup:
	shards install
	./bin/gi-crystal

data/disk-view.gresource: data/disk-view.gresource.xml data/icons/de.magynhard.DiskView.svg
	glib-compile-resources --sourcedir=data --target=$@ $<

build: locales data/disk-view.gresource
	mkdir -p bin
	crystal build $(CRYSTAL_FLAGS) src/disk-view.cr -o bin/disk-view

run: build
	./bin/disk-view

test: locales
	crystal spec

format:
	crystal tool format src/ spec/

clean:
	rm -f bin/disk-view data/disk-view.gresource $(MO_FILES)

locales: $(MO_FILES)

po/%/LC_MESSAGES/$(APP_ID).mo: po/%/LC_MESSAGES/$(APP_ID).po
	msgfmt --check --check-format $< -o $@

generate_locales:
	xgettext --from-code=UTF-8 --language=C --keyword=translate --keyword=translate_count:1,2 --package-name="Disk View" --msgid-bugs-address="https://github.com/magynhard/disk-view.cr/issues" --copyright-holder="Matthäus J. N. Beyrle" --files-from=po/POTFILES -o po/$(APP_ID).pot
	@for lang in $(LANGUAGES); do \
		msgmerge --update --backup=none --no-fuzzy-matching "po/$$lang/LC_MESSAGES/$(APP_ID).po" "po/$(APP_ID).pot" || exit $$?; \
	done

install: build
	install -Dm755 bin/disk-view "$(DESTDIR)$(PREFIX)/bin/disk-view"
	install -Dm644 data/$(APP_ID).desktop "$(DESTDIR)$(PREFIX)/share/applications/$(APP_ID).desktop"
	install -Dm644 data/icons/$(APP_ID).svg "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/$(APP_ID).svg"
	install -Dm644 LICENSE "$(DESTDIR)$(PREFIX)/share/licenses/disk-view/LICENSE"
	@for lang in $(LANGUAGES); do \
		install -Dm644 "po/$$lang/LC_MESSAGES/$(APP_ID).mo" "$(DESTDIR)$(PREFIX)/share/locale/$$lang/LC_MESSAGES/$(APP_ID).mo" || exit $$?; \
	done

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/disk-view" "$(DESTDIR)$(PREFIX)/share/applications/$(APP_ID).desktop" "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/$(APP_ID).svg" "$(DESTDIR)$(PREFIX)/share/licenses/disk-view/LICENSE"
	@for lang in $(LANGUAGES); do \
		rm -f "$(DESTDIR)$(PREFIX)/share/locale/$$lang/LC_MESSAGES/$(APP_ID).mo" || exit $$?; \
	done
