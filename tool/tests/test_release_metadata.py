"""Release safety regressions using fixture APKs; never create signing keys."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import zipfile


SPEC = importlib.util.spec_from_file_location(
    "generate_release_metadata", Path(__file__).resolve().parents[1] / "generate_release_metadata.py")
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)
CERTIFICATE = "a1" * 32
MANIFEST = '''<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.blue.qingniao" android:versionName="0.1.1" android:versionCode="1">
    <application android:debuggable="false" /></manifest>'''
SIGNATURE = f'''Verifies
Verified using v2 scheme (APK Signature Scheme v2): true
Number of signers: 1
Signer #1 certificate DN: CN=Qingniao Release
Signer #1 certificate SHA-256 digest: {CERTIFICATE}
'''


class ReleaseMetadataTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="qingniao-release-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.pubspec = self.root / "pubspec.yaml"
        self.pubspec.write_text("name: qingniao\nversion: 0.1.1+1\n", encoding="utf-8")
        self.apk = self.root / RELEASE.APK_NAME
        self.write_apk()

    def write_apk(self, exclude=None):
        with zipfile.ZipFile(self.apk, "w") as archive:
            for abi in RELEASE.ABIS:
                for library in ("libapp.so", "libflutter.so", "librust_lib_qingniao.so"):
                    entry = f"lib/{abi}/{library}"
                    if entry != exclude:
                        archive.writestr(entry, b"fixture, not an executable library")

    def generate(self, **overrides):
        arguments = dict(apk=self.apk, name="0.1.1", code=1, manifest=MANIFEST,
                         signature=SIGNATURE, certificate=CERTIFICATE)
        arguments.update(overrides)
        return RELEASE.create_metadata(**arguments)

    def test_metadata_matches_updater_contract_and_exact_apk_bytes(self):
        result = self.generate()
        self.assertEqual(result, {
            "schemaVersion": 1, "versionName": "0.1.1", "versionCode": 1,
            "apkName": "qingniao-release.apk",
            "sha256": hashlib.sha256(self.apk.read_bytes()).hexdigest(),
            "size": self.apk.stat().st_size,
        })
        self.assertIs(type(result["versionCode"]), int)
        self.assertIs(type(result["size"]), int)
        self.assertEqual(json.loads(json.dumps(result)), result)

    def test_pubspec_and_exact_stable_tag(self):
        self.assertEqual(RELEASE.read_version(self.pubspec, "v0.1.1"), ("0.1.1", 1))
        for tag in ("v0.1.0", "0.1.1", "v0.1.1+1", "v0.1.1-rc.1", "v0.1.1\n"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                RELEASE.read_version(self.pubspec, tag)

    def test_invalid_versions_are_rejected(self):
        for version in ("0.1.1", "0.1.1+0", "0.1.1+-1", "0.1.1+01", "0.1.1+1.0",
                        "0.1.1-rc.1+1", "00.1.1+1", "0.1.1+2100000001", f"0.1.1+{1 << 63}"):
            self.pubspec.write_text(f"version: {version}\n", encoding="utf-8")
            with self.subTest(version=version), self.assertRaises(ValueError):
                RELEASE.read_version(self.pubspec)
        self.pubspec.write_text("version: 0.1.1+1\nversion: 0.1.1+2\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "exactly one"):
            RELEASE.read_version(self.pubspec)

    def test_quoted_version_and_comment(self):
        self.pubspec.write_text("version: '0.1.1+1' # release\n", encoding="utf-8")
        self.assertEqual(RELEASE.read_version(self.pubspec), ("0.1.1", 1))

    def test_supported_android_version_code_boundary(self):
        code = 2_100_000_000
        self.pubspec.write_text(f"version: 0.1.1+{code}\n", encoding="utf-8")
        self.assertEqual(RELEASE.read_version(self.pubspec), ("0.1.1", code))
        manifest = MANIFEST.replace('android:versionCode="1"', f'android:versionCode="{code}"')
        self.assertEqual(self.generate(code=code, manifest=manifest)["versionCode"], code)
        major = MANIFEST.replace('android:versionCode="1"',
                                'android:versionCode="1" android:versionCodeMajor="1"')
        with self.assertRaisesRegex(ValueError, "versionCodeMajor"):
            self.generate(manifest=major)
        with self.assertRaisesRegex(ValueError, "versionCode"):
            self.generate(code=code + 1, manifest=manifest.replace(str(code), str(code + 1)))

    def test_wrong_manifest_identity_or_version_is_rejected(self):
        for old, new in (("com.blue.qingniao", "com.blue.qingniao.benchmark"),
                         ('versionName="0.1.1"', 'versionName="0.1.0"'),
                         ('versionCode="1"', 'versionCode="2"'),
                         ('versionCode="1"', 'versionCode="0"'),
                         ('versionCode="1"', 'versionCode="-1"'),
                         ('versionCode="1"', 'versionCode="4294967296"')):
            with self.subTest(new=new), self.assertRaises(ValueError):
                self.generate(manifest=MANIFEST.replace(old, new))

    def test_debuggable_and_test_only_apks_are_rejected(self):
        for attribute in ("debuggable", "testOnly"):
            with self.subTest(attribute=attribute), self.assertRaisesRegex(ValueError, attribute):
                self.generate(manifest=MANIFEST.replace('android:debuggable="false"',
                                                       f'android:{attribute}="true"'))

    def test_split_apk_manifest_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Split APK"):
            self.generate(manifest=MANIFEST.replace("<manifest ", '<manifest split="config.arm64_v8a" '))

    def test_profile_or_release_signed_with_debug_key_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Android Debug"):
            self.generate(signature=SIGNATURE.replace("Qingniao Release", "Android Debug"))

    def test_wrong_missing_or_multiple_signers_are_rejected(self):
        for signature in (SIGNATURE.replace(CERTIFICATE, "b2" * 32),
                          SIGNATURE.replace("certificate SHA-256", "public key SHA-256"),
                          SIGNATURE + f"Signer #2 certificate SHA-256 digest: {CERTIFICATE}\n"):
            with self.subTest(signature=signature), self.assertRaisesRegex(ValueError, "pinned production"):
                self.generate(signature=signature)
        for certificate in ("", "abc", "g" * 64):
            with self.subTest(certificate=certificate), self.assertRaisesRegex(ValueError, "fingerprint"):
                self.generate(certificate=certificate)

    def test_colon_separated_uppercase_certificate_is_accepted(self):
        self.generate(certificate=":".join(["A1"] * 32))

    def test_v1_only_signature_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "v2 or v3"):
            self.generate(signature=SIGNATURE.replace("v2 scheme", "v1 scheme"))

    def test_missing_native_architecture_is_rejected(self):
        for abi in RELEASE.ABIS:
            with self.subTest(abi=abi):
                self.write_apk(exclude=f"lib/{abi}/libflutter.so")
                with self.assertRaisesRegex(ValueError, "Universal APK is missing"):
                    self.generate()

    def test_wrong_filename_empty_and_invalid_apk_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "must be named"):
            self.generate(apk=self.root / "app-release.apk")
        self.apk.write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "empty"):
            self.generate()
        self.apk.write_bytes(b"not an APK")
        with self.assertRaisesRegex(ValueError, "valid ZIP"):
            self.generate()

    def test_oversized_apk_is_rejected_before_reading(self):
        with mock.patch.object(Path, "stat", return_value=mock.Mock(st_size=RELEASE.MAX_APK_SIZE + 1)), \
                self.assertRaisesRegex(ValueError, "256 MiB"):
            self.generate()

    def test_duplicate_zip_entries_are_rejected(self):
        import warnings
        with zipfile.ZipFile(self.apk, "a") as archive, warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            archive.writestr("lib/arm64-v8a/libapp.so", b"duplicate")
        with self.assertRaisesRegex(ValueError, "duplicate ZIP"):
            self.generate()

    def cli_arguments(self, output):
        return ["generate_release_metadata.py", "create", "--pubspec", str(self.pubspec),
                "--tag", "v0.1.1", "--apk", str(self.apk), "--apkanalyzer", "apkanalyzer",
                "--apksigner", "apksigner", "--output", str(output)]

    def test_cli_verifies_tools_and_writes_utf8_json(self):
        output = self.root / "update.json"
        with mock.patch("sys.argv", self.cli_arguments(output)), \
                mock.patch.dict(os.environ, {"QINGNIAO_SIGNING_CERT_SHA256": CERTIFICATE}), \
                mock.patch.object(RELEASE, "run_tool", side_effect=[MANIFEST, SIGNATURE]) as tools:
            RELEASE.main()
        self.assertEqual(json.loads(output.read_text(encoding="utf-8")), self.generate())
        self.assertEqual(tools.call_args_list, [
            mock.call(["apkanalyzer", "manifest", "print", str(self.apk)]),
            mock.call(["apksigner", "verify", "--verbose", "--print-certs", str(self.apk)]),
        ])

    def test_failed_verification_removes_stale_metadata(self):
        output = self.root / "update.json"
        output.write_text("stale metadata", encoding="utf-8")
        with mock.patch("sys.argv", self.cli_arguments(output)), \
                mock.patch.object(RELEASE, "run_tool", side_effect=ValueError("invalid signature")), \
                self.assertRaises(SystemExit) as failure:
            RELEASE.main()
        self.assertEqual(failure.exception.code, 1)
        self.assertFalse(output.exists())

    def test_version_mismatch_removes_stale_metadata(self):
        output = self.root / "update.json"
        output.write_text("stale metadata", encoding="utf-8")
        self.pubspec.write_text("version: 0.1.2+2\n", encoding="utf-8")
        with mock.patch("sys.argv", self.cli_arguments(output)), self.assertRaises(SystemExit):
            RELEASE.main()
        self.assertFalse(output.exists())

    def test_failed_android_tool_cannot_be_accepted(self):
        result = mock.Mock(returncode=1, stdout=SIGNATURE, stderr="DOES NOT VERIFY")
        with mock.patch.object(RELEASE.subprocess, "run", return_value=result), \
                self.assertRaisesRegex(ValueError, "failed"):
            RELEASE.run_tool(["apksigner", "verify", str(self.apk)])


if __name__ == "__main__":
    unittest.main()
