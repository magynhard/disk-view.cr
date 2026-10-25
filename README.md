# Disk View

A small, read-only GTK4/libadwaita application written in Crystal for Linux. The interface
is in German. Disk usage is displayed using native horizontal GTK progress bars.

## Features

- Mounted local filesystems and common network mounts, including total, used,
  available and reserved space when reported by the filesystem.
- Unmounted disks and partitions, including their capacity. Usage cannot be
  determined without mounting a filesystem; Disk View does not mount devices.
- Compact drive groups (`sda`, `sdb`, NVMe, etc.) with indented partitions,
  physical drive capacity and aggregated filesystem usage. Partial totals are
  explicitly marked when some partitions cannot be measured.
- Native Adwaita expander rows start collapsed. Click a drive to reveal its
  partitions; your expansion choices are preserved across refreshes in the
  current session.
- Bind mounts and subvolumes of the same filesystem are grouped together.
- Automatic refresh every 15 seconds and a manual refresh button.
- Light and dark appearance follow the system preference, including live changes,
  using libadwaita's default color scheme.
- Asynchronous filesystem queries so slow network mounts do not block the UI.
- No root privileges, shell commands or charting libraries required at runtime.
- Original scalable application icon, desktop launcher and an Adwaita About
  dialog with author, version and license information.

## Requirements

Linux, Crystal 1.20+, Shards, GTK4, libadwaita 1.5+ and GObject Introspection.
Building also requires `glib-compile-resources` (provided by the GLib development
packages); the icon is embedded in the executable.

On Arch / Manjaro:

```sh
sudo pacman -S --needed base-devel crystal shards gtk4 libadwaita gobject-introspection
```

On Debian / Ubuntu:

```sh
sudo apt install build-essential crystal shards libgtk-4-dev libadwaita-1-dev libgirepository1.0-dev gobject-introspection gir1.2-gtk-4.0 gir1.2-adw-1
```

Your distribution may require installing a current Crystal compiler and Shards
separately. A graphical session is required to run the application.

## Run

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

Use the header-bar menu for **About Disk View**, refresh and close. Keyboard
shortcuts: `Ctrl+R` to refresh, `F1` for About, and `Ctrl+W` to close.

## Install

Install the executable, desktop launcher and icon for your user:

```sh
make install PREFIX="$HOME/.local"
```

Ensure `~/.local/bin` is on your `PATH`. For a system-wide installation use
`sudo make install` (default prefix: `/usr/local`). Uninstall with
`make uninstall PREFIX="$HOME/.local"`, or `sudo make uninstall` respectively.
The executable can also be copied and run on its own without the source files.

## Scope

Discovery uses `/proc/self/mountinfo`, `/proc/swaps` and `/sys/class/block`.
Pseudo-filesystems, RAM disks and loop/Snap images are hidden. Partitions are
grouped using sysfs parent relationships, with numeric partition ordering.
Mapped devices (LVM, RAID, encryption) form separate groups; their underlying
partitions are identified as in use, without attributing the mapped filesystem's
usage to a physical device. Filesystem capacities larger than their backing
partition are excluded from drive totals to avoid counting an entire storage
pool as one disk's usage. A drive's percentage uses its physical capacity;
unpartitioned capacity is not counted as available filesystem space. Unknown
partition usage is never counted as free space.
Only filesystems visible in the application's mount namespace can be listed.
Capacity and occupancy are filesystem values, not directory-size estimates.
The application does not scan directory trees, modify partitions or mount drives.

## Author and license

Created by [Matthäus J. N. Beyrle](https://github.com/magynhard).
Released under the [MIT License](LICENSE). The application icon is original
SVG artwork distributed under the same license.
