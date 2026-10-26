import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("packaging_inputs", ROOT / "scripts/packaging.py")
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)


class PackagingTests(unittest.TestCase):
    def test_shard_pins_and_appstream_version_match(self):
        self.assertRegex(packaging.verify(), r"^\d+\.\d+\.\d+(?:[-+].+)?$")

    def test_downloads_have_sha256_and_https(self):
        sources = [packaging.PINS[name] for name in ("gc", "linuxdeploy", "gtk_plugin", "appimage_runtime")]
        sources += [packaging.PINS["crystal"][arch] for arch in ("x86_64", "aarch64")]
        for source in sources:
            self.assertRegex(source["sha256"], r"^[a-f0-9]{64}$")
            self.assertTrue(source["url"].startswith("https://"))

    def test_lock_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "shard.lock").write_text((ROOT / "shard.lock").read_text().replace("0.26.0", "0.25.0"))
            (root / "shard.yml").write_text((ROOT / "shard.yml").read_text())
            with self.assertRaisesRegex(ValueError, "gi-crystal"):
                packaging.verify(root)

    def test_local_manifest_has_explicit_host_access_and_offline_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            packaging.flatpak_manifest(destination)
            manifest = json.loads((destination / "de.magynhard.DiskView.json").read_text())
            permissions = manifest["finish-args"]
            self.assertIn("--filesystem=host-root:ro", permissions)
            self.assertIn("--filesystem=/run/udev:ro", permissions)
            self.assertIn("--system-talk-name=org.freedesktop.UDisks2", permissions)
            self.assertIn("--require-version=1.17.0", permissions)
            self.assertNotIn("--device=all", permissions)
            self.assertNotIn("--share=network", permissions)
            self.assertNotIn("--socket=system-bus", permissions)
            self.assertFalse(manifest["separate-locales"])
            self.assertIn("NOT a Flathub", manifest["x-local-development-only"])
            module = manifest["modules"][-1]
            git_sources = [source for source in module["sources"] if source["type"] == "git"]
            self.assertEqual(len(git_sources), len(packaging.PINS["shards"]))
            for source in git_sources:
                self.assertRegex(source["commit"], r"^[a-f0-9]{40}$")
            snapshot = Path(module["sources"][0]["path"])
            for name in (".git", "lib", "bin", "build", "dist"):
                self.assertFalse((snapshot / name).exists(), name)

    def test_appimage_does_not_force_a_theme_or_display_backend(self):
        hook = (ROOT / "packaging/appimage/gtk-runtime.sh").read_text()
        self.assertNotRegex(hook, r"(?m)^export (GTK_THEME|GDK_BACKEND)=")
        self.assertIn("GIO_MODULE_DIR", hook)

    def test_release_upload_is_gated_and_builds_are_read_only(self):
        import yaml

        workflow = yaml.load((ROOT / ".github/workflows/linux-packages.yml").read_text(), Loader=yaml.BaseLoader)
        self.assertEqual(workflow["permissions"]["contents"], "read")
        upload = workflow["jobs"]["release-assets"]
        self.assertEqual(upload["if"], "github.event_name == 'release'")
        self.assertEqual(upload["permissions"]["contents"], "write")
        self.assertCountEqual(upload["needs"], ["appimage", "flatpak"])
        self.assertEqual(workflow["on"]["release"]["types"], ["published"])


if __name__ == "__main__":
    unittest.main()
