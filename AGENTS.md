# Disk View

Crystal + GTK4/libadwaita disk usage overview for Linux. Use English for code,
documentation, release notes and commit messages. Follow the existing conventional
commit style. Default branch: `master`; application ID: `de.magynhard.DiskView`.

## Development

- `src/disks.cr`: mount parsing, sysfs hierarchy, byte formatting and usage totals.
- `src/device_metadata.cr`: cached udev identification; do not probe raw devices.
- `src/platform_paths.cr`: native/Flatpak host-path mapping for disk discovery.
- `src/window.cr`: native Adwaita UI and asynchronous filesystem usage queries.
- `src/preferences.cr`: saved units under the application's XDG config directory.
- `po/`: ten language catalogs. Keep new UI strings translated in every catalog;
  run `make generate_locales` after changing translatable messages.
- `shard.yml` is the version source, including the About dialog. Keep the newest
  AppStream release in `data/de.magynhard.DiskView.metainfo.xml` synchronized.
- Generated bindings, build directories, binaries and packages are ignored.

Use `make setup` to install dependencies and generate bindings when needed.
For changes, run the relevant checks:

```sh
make test
make test-packaging
crystal tool format --check src/ spec/
make validate-metadata
python3 scripts/packaging.py verify
make build
git diff --check
```

Preserve asynchronous queries, cancellation and expanded groups. Changing display
units should only reformat measured bytes, not rescan devices. Test UI changes
with a graphical session or Xvfb; isolate `XDG_CONFIG_HOME` when testing preferences.
Mount/unmount actions use UDisks2 and normal polkit authorization.

## Releases

The full process is in [doc/packaging.md](doc/packaging.md#github-releases).
When the user requests a release:

1. Inspect Git status/diff, remote state, recent releases and CI. Choose an unused
   next version following the repository's existing version/tag convention.
2. Update `shard.yml`, prepend a dated `CHANGELOG.md` entry and add matching
   AppStream release notes in all supported languages. Preserve historical entries.
3. Run the checks above. If dependencies change, synchronize
   `packaging/sources.json` with `shard.lock`; test affected package builds locally.
4. Commit the intended changes and push to `master`. Wait for `Linux packages`
   on that exact commit to pass: it builds both AppImage and Flatpak packages.
5. Create and push an annotated numeric version tag on the tested commit, then
   publish its GitHub release with `gh release create --verify-tag`, an explicit
   title and release notes. Do not merely push a tag or leave the release in draft.
6. Watch the **release-triggered** `Linux packages` run with
   `gh run watch RUN_ID --exit-status`. The `release-assets` job uploads packages
   automatically only after both build jobs succeed.
7. Verify the published release contains the versioned x86_64 `.AppImage` and
   `.flatpak` files plus a separate `.sha256` for each. Return the release URL and
   report CI failures or missing assets accurately.

Builds and asset uploads are automated; version bumps, changelog entries, commits,
tags and release publication are not. Ordinary push/PR/manual runs only upload
workflow artifacts. CI does not publish to Flathub. See the packaging document
for local build prerequisites and the separate Flathub submission status.
