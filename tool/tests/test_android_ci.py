"""Exercise SDK bootstrap without a real SDK, credentials or network access."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "setup_android_sdk.sh"


@unittest.skipIf(
    os.name != "posix",
    "tool/setup_android_sdk.sh targets the Linux CI runner; Windows has no "
    "POSIX bash that can execute it",
)
class AndroidSdkBootstrapTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="qingniao-ci-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.sdk = self.root / "sdk with spaces"
        self.manager = self.sdk / "cmdline-tools/latest/bin/sdkmanager"
        self.manager.parent.mkdir(parents=True)
        self.manager.write_text(
            '#!/usr/bin/env bash\nset -eu\n'
            'printf "%s\\n" "$@" >> "$SDK_TEST_LOG"\n'
            'case "$*" in\n'
            '  *--version*) phase=version ;;\n'
            '  *--licenses*) phase=licenses; read -r answer; test "$answer" = y ;;\n'
            '  *) phase=install ;;\n'
            'esac\n'
            'if [[ "${SDK_TEST_FAIL:-}" == "$phase" ]]; then exit 19; fi\n',
            encoding="utf-8", newline="\n",
        )
        self.manager.chmod(0o755)
        self.env = os.environ.copy()
        self.env.pop("ANDROID_HOME", None)
        self.env.pop("ANDROID_SDK_ROOT", None)
        self.env.update({
            "ANDROID_HOME": self.sdk.as_posix(),
            "GITHUB_ENV": (self.root / "environment").as_posix(),
            "GITHUB_PATH": (self.root / "path").as_posix(),
            "SDK_TEST_LOG": (self.root / "calls").as_posix(),
        })
        self.bash = os.environ.get("BASH_EXECUTABLE") or shutil.which("bash")
        if not self.bash:
            self.fail("Bash is required to verify the Linux CI bootstrap")

    def run_bootstrap(self):
        return subprocess.run([self.bash, str(SCRIPT.as_posix())], env=self.env,
                              capture_output=True, text=True, timeout=20)

    def test_sdkmanager_outside_path_and_sdk_path_with_spaces(self):
        result = self.run_bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = (self.root / "calls").read_text().splitlines()
        for package in ("platform-tools", "platforms;android-36", "build-tools;36.0.0", "ndk;28.2.13676358"):
            self.assertIn(package, calls)
        self.assertIn(f"--sdk_root={self.sdk.as_posix()}", calls)
        environment = (self.root / "environment").read_text()
        self.assertIn(f"ANDROID_HOME={self.sdk.as_posix()}", environment)
        self.assertIn(f"ANDROID_SDK_ROOT={self.sdk.as_posix()}", environment)
        self.assertIn(self.manager.parent.as_posix(), (self.root / "path").read_text())

    def test_sdk_root_environment_fallback(self):
        self.env["ANDROID_SDK_ROOT"] = self.env.pop("ANDROID_HOME")
        result = self.run_bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_sdk_fails_before_installation(self):
        self.env.pop("ANDROID_HOME")
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("::error::", result.stderr)
        self.assertFalse((self.root / "calls").exists())

    def test_missing_command_line_tools_fails_clearly(self):
        self.manager.unlink()
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("command-line tools are missing", result.stderr)

    def test_sdk_failures_are_not_swallowed(self):
        for phase in ("version", "licenses", "install"):
            with self.subTest(phase=phase):
                self.env["SDK_TEST_FAIL"] = phase
                result = self.run_bootstrap()
                self.assertEqual(result.returncode, 19, result.stderr)


if __name__ == "__main__":
    unittest.main()
