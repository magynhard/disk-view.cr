# Contributing to Disk View

## Development requirements

Building requires Linux, Crystal 1.21+, Shards, GTK4, libadwaita 1.5+, libudev,
GObject Introspection, GNU gettext tools and `glib-compile-resources` (provided by
the GLib development packages). A graphical session is required to run the app.
Mount/unmount actions additionally require UDisks2, a system D-Bus and a desktop
polkit authentication agent.

On Arch / Manjaro:

```sh
sudo pacman -S --needed base-devel crystal shards gtk4 libadwaita gobject-introspection gettext systemd-libs udisks2 polkit
```

On Debian / Ubuntu:

```sh
sudo apt install build-essential crystal shards libgtk-4-dev libadwaita-1-dev libgirepository1.0-dev gobject-introspection gir1.2-gtk-4.0 gir1.2-adw-1 gettext libudev-dev udisks2 polkitd
```

Your distribution may require installing a current Crystal compiler and Shards
separately.

## Build and run

```sh
make setup
make run
```

`make setup` downloads the Crystal bindings and generates them for your installed
GTK version. Run it again after updating the dependencies or system libraries.

```sh
make build                         # Creates bin/disk-view
./bin/disk-view
make test                          # Headless discovery/parser and usage tests
crystal tool format --check src/ spec/
```

Build an optimized executable with:

```sh
make build CRYSTAL_FLAGS="--release --no-debug"
```

To install the executable, desktop launcher and icon for your user:

```sh
make install PREFIX="$HOME/.local"
```

Ensure `~/.local/bin` is on your `PATH`. For a system-wide installation use
`sudo make install` (default prefix: `/usr/local`). Uninstall with
`make uninstall PREFIX="$HOME/.local"`, or `sudo make uninstall` respectively.
Translations are installed under `share/locale` relative to the installation
prefix. The executable needs no source files; when distributing it, include the
translation catalogs to retain localized interfaces.

Installing the desktop entry and icon also ensures the correct icon in the
desktop dock/taskbar for subsequent `make run` launches. Restart Disk View after
installing it.

## Translations

To test another language with an available UTF-8 locale:

```sh
LC_ALL=en_US.UTF-8 LANGUAGE=fr ./bin/disk-view
LC_ALL=en_US.UTF-8 LANGUAGE=ja ./bin/disk-view
```

Close an existing Disk View instance first, since subsequent launches activate
the existing application. Korean and Japanese use standard `ko` and `ja`
catalog names (the same languages listed as `kr` and `jp` in Goblin Converter).

Catalog sources are in `po/<language>/LC_MESSAGES/`. `make build` and `make test`
compile them automatically. During development, catalogs are read from `po/`;
installed binaries find them relative to their own installation prefix.

```sh
make locales                       # Compile and validate PO → MO catalogs
make generate_locales              # Extract messages and update existing PO files
```

After changing translatable strings, run `make generate_locales`, complete the
translations and run `make test`. Add source files containing translation calls
to `po/POTFILES`, and add new language codes to `po/LINGUAS`. Translations use
named placeholders such as `%{size}`; keep their names and escape literal
percent signs as `%%` in formatted messages. Locale-dependent specs require
an installed non-C UTF-8 locale and are marked pending if none is available.

## Packaging and releases

```sh
make appimage
make flatpak
```

Both commands create versioned packages and SHA-256 files in `dist/`. The GitHub
Actions workflow attaches them to newly published releases. AppImage builds use
an Ubuntu 24.04 container and include GTK/Adwaita and translations. Flatpak builds
use GNOME SDK 51, offline sources and explicit host-disk access.

See [Linux packaging](doc/packaging.md) for prerequisites, testing and release
steps. It also explains the current Flathub inclusion/AI-manifest restrictions
and the remaining manual submission work. The generated Flatpak manifest is for
local builds, not a Flathub submission.
