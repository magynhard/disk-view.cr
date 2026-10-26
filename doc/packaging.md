# Linux packaging

## Outputs

`make appimage` and `make flatpak` produce versioned files in the ignored `dist/`
directory, with a separate SHA-256 file for each package. The version comes from
`shard.yml`; the AppStream release version must match it.

| Format | Build environment | Runtime |
| --- | --- | --- |
| AppImage | Docker, Ubuntu 24.04, Crystal 1.21.0 | Linux x86_64, glibc 2.39 or newer; GTK/Adwaita and other app libraries are bundled |
| Local Flatpak | GNOME SDK 51, Crystal 1.21.0 | Flatpak 1.17.0 or newer, GNOME Platform 51 |

UDisks2 and a desktop polkit agent remain host services for both formats.
Neither package installs a second system daemon. Do not run the application as
root. File usage queries and device discovery do not require a privileged app.

The AppImage pipeline targets x86_64. The local Flatpak inputs include official
x86_64 and aarch64 compiler archives, but x86_64 is the initially tested target.

## AppImage

Install Docker, Python 3.12+, PyYAML and Make. Start Docker and ensure your user
can run it. For example, on Arch/Manjaro the packaging tools are `docker`,
`python`, `python-yaml` and `make`. No GTK development packages are required on
the host for this build; they are installed in the builder image.

```sh
make appimage
chmod +x dist/Disk_View-0.1.0-x86_64.AppImage
./dist/Disk_View-0.1.0-x86_64.AppImage
```

Replace `0.1.0` with the current version. On hosts without a usable FUSE setup:

```sh
./dist/Disk_View-0.1.0-x86_64.AppImage --appimage-extract-and-run
```

The builder pins Crystal, linuxdeploy, the GTK plugin and the AppImage runtime by
SHA-256. It builds the application against Ubuntu 24.04 libraries rather than
copying a binary from the developer's rolling-release distribution. The
AppImage contains application translations, GTK/Adwaita catalogs when available,
GSettings schemas, dconf, icons, loader modules, licenses and build-package
information. The runtime hook preserves Wayland and system-controlled dark/light
style rather than forcing X11 or a fixed GTK theme.

The tool and shard pins are in `packaging/sources.json`. Shared-library package
updates follow Ubuntu's supported repositories; builds are repeatable source
builds, not a promise of bit-identical output across repository updates.

## Local Flatpak

Install Flatpak 1.17+, flatpak-builder, AppStream (with `appstreamcli compose`),
OSTree, Python 3.12+, PyYAML and Make.
Install the matching SDK/runtime from Flathub before building:

```sh
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.gnome.Platform//51 org.gnome.Sdk//51
make flatpak
flatpak install --user dist/Disk_View-0.1.0-x86_64.flatpak
flatpak run de.magynhard.DiskView
```

The local manifest is generated under `build/flatpak/` from a clean source
snapshot and immutable dependency revisions. All downloads are declared as
Flatpak sources. The actual compiler/generator/application build is offline;
`shards install` is not run in the sandbox. The Boehm GC runtime is built from
source. Compiler binaries are build tools, not prebuilt application binaries.
All ten small app catalogs are included in the local bundle, without requiring
a separate app-specific Locale bundle.

AppStream metadata is composed before export with PNG icons. The build checks
that both 64- and 128-pixel icons exist so the single-file bundle can embed them
for the software center's local installation preview.

Build/export directories and caches are local and ignored by Git. The generated
OSTree export repo uses a 512 MB free-space reserve instead of a percentage of
the entire disk. `FLATPAK_REPO_DIR` can point to a different **dedicated generated
export directory**, for example on a volume with more free space.

### Why these sandbox permissions are needed

- `wayland`, `fallback-x11`, `ipc`: native GTK desktop presentation.
- `dri`: rendering, without access to all device nodes.
- `host-root:ro`: host mount table, sysfs and filesystem statistics under
  `/run/host/root`; otherwise the app would incorrectly report the Flatpak
  runtime's root filesystem. This permission requires Flatpak 1.17+.
- `/run/udev:ro`: cached filesystem types, labels and partition roles through
  libudev. No direct probing of raw block devices is performed.
- System-bus access only to `org.freedesktop.UDisks2`: explicit mount/unmount
  requests using normal polkit authorization.

The application receives read access to the host filesystem. It uses that
access for metadata/statistics, not directory-content scanning. Mount controls
can change the host's mount state through UDisks2; read-only filesystem grants
do not make these explicit D-Bus operations read-only. The manifest does not
request `--share=network`, host-command execution, `--socket=system-bus` or
`--device=all`. The host-root grant is nevertheless broad read access and needs
to be reviewed as such, rather than described as a tightly isolated sandbox.

Displayed mount paths remain host paths. Only filesystem I/O is translated into
the host-root mapping. Mount points are read from the kernel's host mount table;
arbitrary user paths are not naively resolved through absolute host symlinks.

## GitHub Releases

`.github/workflows/linux-packages.yml` builds both packages for pull requests,
pushes to `master`, manual workflow runs and published GitHub releases. Ordinary
builds upload workflow artifacts. A published-release event additionally attaches
the AppImage, local Flatpak and their checksums to that release. Only the final
upload job has repository-write permission. The workflow does not submit anything
to Flathub.

Before publishing a new version:

1. Update `shard.yml` and the first release entry in
   `data/de.magynhard.DiskView.metainfo.xml`, including its date/notes.
2. If dependencies changed, update the immutable revisions/checksums in
   `packaging/sources.json` to match `shard.lock`.
3. Run `make validate-metadata`, `make test`, and both package builds.
4. Commit and push the source and workflow. Tag that commit with the matching
   version and publish its GitHub release. The workflow accepts an optional `v`
   prefix, but the numeric version must match `shard.yml`.

An existing `0.1.0` tag made before this packaging work does not contain these
files. Use a new tagged version containing them for future automatic builds.
For a manual release attachment after a local build:

```sh
version=$(python3 scripts/packaging.py version)
gh release upload YOUR_RELEASE_TAG "dist/Disk_View-${version}-x86_64.AppImage" "dist/Disk_View-${version}-x86_64.AppImage.sha256"
```

## Flathub submission status and remaining work

**A locally working Flatpak is not the same as Flathub acceptance.** Flathub
builds accepted applications from source manifests; it is not a binary upload
service for `.flatpak` files or AppImages.

The [current inclusion requirements](https://docs.flathub.org/docs/for-app-authors/requirements)
are a concrete blocker for an automated or ready-to-copy submission here:

- They exclude host-oriented system utilities in general. Disk View's use of
  host mount information and UDisks2 needs a human eligibility discussion with
  Flathub maintainers before promising distribution there. The policy also
  considers development history and host-dependent functionality.
- They prohibit AI-generated **or AI-assisted** Flathub manifests, and AI tools
  must not open/automate submission PRs or generate their messages/review replies.
- They require disclosure of known AI-generated application/packaging material,
  identifying the affected parts and approximate extent. This repository has
  AI-assisted application code, translations, documentation, artwork and local
  packaging. The submitter must assess and disclose that accurately.

Consequently, the generated manifest is explicitly **local development only**.
Do not copy or submit it as a human-authored Flathub manifest. It is not an
exception to those requirements, and merely reviewing/reformatting it does not
remove its AI-assisted origin.

After eligibility is confirmed, a human maintainer must independently prepare
the submission under the rules then in force. The technical facts to check are:

- Keep the existing application ID `de.magynhard.DiskView` and demonstrate
  control of the corresponding `magynhard.de` domain when required.
- Use the latest supported GNOME runtime/SDK at submission time.
- Build the application and runtime dependencies from source, using a published
  application tag **and its immutable commit**, not the local directory source
  used by development builds. Pin all offline dependencies.
- Place a manually authored manifest named after the app ID at the top level of
  the submission repository. Declare any architecture restriction in a manually
  authored `flathub.json` if needed.
- Review and justify the host-root, udev and UDisks permissions with maintainers.
  Verify the minimum Flatpak version and mounted-device visibility after changes.
- Validate the upstream desktop file, icon and metainfo. Publish the current
  screenshot and metadata URLs in the source repository before submitting.
- Follow the [manual submission process](https://docs.flathub.org/docs/for-app-authors/submission)
  and later [domain verification](https://docs.flathub.org/docs/for-app-authors/verification).

No Flathub PR, account changes or publication is performed by the scripts or CI.
