# Changelog

## [0.1.4] - 2026-11-20

### Added
- Add translations in 34 additional languages, bringing the total to 44.
- Localize the desktop entry and expand translated application metadata.

### Documentation
- Streamline the README and add contributor guidance.

## [0.1.3] - 2026-11-14

### Added
- Linked GiB/GB buttons beside the content heading to switch between binary and
  decimal sizes. Capacities, usage figures and tooltips update immediately without
  rescanning drives or rebuilding rows; expanded groups remain open.
- Automatic saving and restoration of the selected unit across application
  restarts, using the XDG configuration directory, including in Flatpak.
- Regression coverage for decimal formatting, unit boundaries and saved preferences.

### Changed
- Use decimal units (GB) by default when no valid preference has been saved.
- Let drive and partition rows follow the full window width instead of centering
  the content within a maximum width.

### Documentation
- Add `AGENTS.md` with development checks and the end-to-end GitHub release process.
- Document the published-release trigger, CI verification and expected download assets.
- Correct the README download instructions to reflect AppImage and Flatpak releases.

## [0.1.2] - 2026-10-27

### Added
- Drive connection labels for SATA, NVMe, USB and SD/MMC, combined with SSD/HDD
  information where reliable (for example, `SSD · SATA`).
- NVMe and MMC detection from kernel device names when udev metadata is missing.
- Regression tests for connection detection, USB bridges and partition grouping.

### Fixed
- USB sticks and SD/MMC media no longer appear as HDDs or SSDs based on unreliable
  rotational flags. They show their connection and a removable-media icon instead.

### Documentation
- Clarify the intended audience in the README and document connection labels.
- Add this changelog with the release history.

## [0.1.1] - 2026-10-26

### Added
- Asynchronous mount and unmount controls for individual filesystems and drive
  groups through UDisks2, excluding active system mounts and unsupported volumes.
- Windows filesystem and partition identification, including volume labels,
  NTFS/exFAT/FAT, Microsoft reserved, recovery, EFI and BitLocker partitions.
- AppImage and standalone Flatpak packages, reproducible build scripts and
  automated release packaging.

### Fixed
- Consistent red usage warnings at 90% capacity across supported package formats.
- Application icons in Flatpak installation previews.
- Localized AppStream descriptions and release notes in all ten supported languages.
- Flatpak CI dependency setup without relying on a container package manager.

### Documentation
- Refresh the application screenshot and document Linux packaging.

## [0.1.0] - 2026-10-25

### Added
- Initial Linux release with a native GTK4/libadwaita interface.
- Hierarchical drive and partition overview with capacity and filesystem usage bars.
- Automatic refresh, preserved expanded groups and system light/dark appearance.
- Translations in English, German, French, Spanish, Simplified Chinese, Russian,
  Italian, Polish, Korean and Japanese.
- Application metadata, icon and installation instructions.

[0.1.4]: https://github.com/magynhard/disk-view.cr/compare/0.1.3...0.1.4
[0.1.3]: https://github.com/magynhard/disk-view.cr/compare/0.1.2...0.1.3
[0.1.2]: https://github.com/magynhard/disk-view.cr/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/magynhard/disk-view.cr/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/magynhard/disk-view.cr/releases/tag/0.1.0
