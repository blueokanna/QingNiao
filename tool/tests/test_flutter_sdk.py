"""Regression coverage for detached, shallow Flutter SDK checkouts."""

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "check_flutter_sdk", Path(__file__).resolve().parents[1] / "check_flutter_sdk.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class FlutterCheckoutTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="qingniao-flutter-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.origin = self.root / "origin"
        self.origin.mkdir()
        self.git(self.origin, "init", "--quiet")
        self.commit("first")
        self.previous = self.git(self.origin, "rev-parse", "HEAD")
        self.commit("release")
        self.revision = self.git(self.origin, "rev-parse", "HEAD")
        self.git(self.origin, "tag", "3.47.9")

    def git(self, root, *args):
        return subprocess.run(["git", "-C", str(root), *args], check=True,
                              capture_output=True, text=True).stdout.strip()

    def commit(self, message):
        self.git(self.origin, "-c", "user.name=CI Test", "-c", "user.email=ci@example.invalid",
                 "commit", "--allow-empty", "--quiet", "-m", message)

    def test_exact_release_is_accepted(self):
        CHECK.verify_checkout(self.origin, "3.47.9", self.revision)

    def test_tagless_shallow_checkout_fails_then_recovers_with_history_and_tags(self):
        checkout = self.root / "shallow"
        self.git(self.root, "clone", "--quiet", "--no-tags", "--depth=1",
                 self.origin.as_uri(), str(checkout))
        self.assertEqual(self.git(checkout, "rev-parse", "--is-shallow-repository"), "true")
        with self.assertRaisesRegex(ValueError, "Fetch release tags/history"):
            CHECK.verify_checkout(checkout, "3.47.9", self.revision)
        self.git(checkout, "fetch", "--quiet", "--unshallow", "--tags", "origin")
        CHECK.verify_checkout(checkout, "3.47.9", self.revision)

    def test_moved_release_tag_is_rejected(self):
        self.git(self.origin, "tag", "-f", "3.47.9", self.previous)
        with self.assertRaisesRegex(ValueError, "tag does not point"):
            CHECK.verify_checkout(self.origin, "3.47.9", self.revision)

    def test_wrong_checkout_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "checkout does not match"):
            CHECK.verify_checkout(self.origin, "3.47.9", self.previous)


class FlutterMetadataTest(unittest.TestCase):
    def setUp(self):
        self.revision = "a" * 40
        self.data = {"frameworkVersion": "3.47.9", "flutterVersion": "3.47.9",
                     "frameworkRevision": self.revision, "dartSdkVersion": "3.13.7"}

    def test_matching_metadata(self):
        CHECK.verify_metadata(self.data, "3.47.9", self.revision, "3.13.7")

    def test_unknown_or_stale_metadata_is_rejected(self):
        for field, value in (("frameworkVersion", "0.0.0-unknown"),
                             ("frameworkRevision", "b" * 40),
                             ("dartSdkVersion", "3.0.0"),
                             ("flutterVersion", "3.50.0")):
            with self.subTest(field=field), self.assertRaises(ValueError):
                CHECK.verify_metadata({**self.data, field: value}, "3.47.9", self.revision, "3.13.7")


if __name__ == "__main__":
    unittest.main()
