"""Create update.json only after inspecting a production-signed universal APK.

Uses Android SDK apkanalyzer/apksigner; no third-party Python packages required.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile


APK_NAME = "qingniao-release.apk"
PACKAGE_NAME = "com.blue.qingniao"
ANDROID = "{http://schemas.android.com/apk/res/android}"
MAX_VERSION_CODE = 2_100_000_000  # Current Flutter/Android versionCode contract.
MAX_APK_SIZE = 256 * 1024 * 1024  # Matches the app updater's download limit.
ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")
VERSION_PATTERN = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"


def read_version(pubspec: Path, tag: str | None = None) -> tuple[str, int]:
    values = re.findall(r"^version:\s*([^#\r\n]+)", pubspec.read_text(encoding="utf-8-sig"), re.M)
    if len(values) != 1:
        raise ValueError("pubspec must contain exactly one top-level version")
    value = values[0].strip()
    if value[:1] in ("'", '"') and value[-1:] == value[:1]:
        value = value[1:-1]
    if not re.fullmatch(VERSION_PATTERN + r"\+[1-9][0-9]*", value):
        raise ValueError("Production version must be stable major.minor.patch+positiveBuildNumber")
    name, code_text = value.split("+")
    code = int(code_text)
    if code > MAX_VERSION_CODE:
        raise ValueError("versionCode must be in the supported Android range 1..2100000000")
    if tag is not None and tag != f"v{name}":
        raise ValueError(f"Release tag must be v{name}, got {tag!r}")
    return name, code


def inspect_manifest(xml: str, name: str, code: int) -> None:
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as error:
        raise ValueError(f"Cannot parse APK manifest: {error}") from error
    if root.tag != "manifest" or root.get("package") != PACKAGE_NAME:
        raise ValueError(f"APK package must be {PACKAGE_NAME}")
    if root.get("split") is not None or root.get(ANDROID + "isFeatureSplit") not in (None, "false"):
        raise ValueError("Split APK cannot be the universal release APK")
    applications = root.findall("application")
    if len(applications) != 1:
        raise ValueError("APK must have exactly one application")
    for attribute in ("debuggable", "testOnly"):
        if applications[0].get(ANDROID + attribute) not in (None, "false", "0"):
            raise ValueError(f"Production APK must not be {attribute}")
    if root.get(ANDROID + "versionName") != name:
        raise ValueError("APK versionName does not match pubspec/tag")
    minor_text = root.get(ANDROID + "versionCode", "")
    major_text = root.get(ANDROID + "versionCodeMajor", "0")
    if not re.fullmatch(r"[0-9]+", minor_text) or not re.fullmatch(r"[0-9]+", major_text):
        raise ValueError("APK version code components must be unsigned integers")
    minor, major = int(minor_text), int(major_text)
    if major != 0 or not 0 < minor <= MAX_VERSION_CODE:
        raise ValueError("APK versionCode must be in 1..2100000000 without versionCodeMajor")
    if minor != code:
        raise ValueError(f"APK versionCode {minor} does not match pubspec build number {code}")


def inspect_signature(report: str, expected_certificate: str) -> None:
    expected = expected_certificate.strip().lower().replace(":", "")
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("QINGNIAO_SIGNING_CERT_SHA256 must be the production certificate SHA-256 fingerprint")
    if re.search(r"Android\s+Debug", report, re.I):
        raise ValueError("Android Debug certificate is forbidden for production updates")
    digests = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$", report, re.M)
    if len(digests) != 1 or digests[0].lower() != expected:
        raise ValueError("APK must have exactly one signer matching the pinned production certificate")
    if not re.search(r"^Verified using v(?:2|3|3\.1) scheme .*: true\s*$", report, re.M):
        raise ValueError("APK requires a verified v2 or v3 signature")


def create_metadata(apk: Path, name: str, code: int, manifest: str,
                    signature: str, certificate: str) -> dict:
    if apk.name != APK_NAME:
        raise ValueError(f"Release APK must be named {APK_NAME}")
    size = apk.stat().st_size
    if size <= 0:
        raise ValueError("Release APK is empty")
    if size > MAX_APK_SIZE:
        raise ValueError("Release APK exceeds the updater's 256 MiB download limit")
    inspect_manifest(manifest, name, code)
    inspect_signature(signature, certificate)
    try:
        with zipfile.ZipFile(apk) as archive:
            entries = archive.namelist()
            if len(entries) != len(set(entries)):
                raise ValueError("APK contains duplicate ZIP entries")
            for abi in ABIS:
                for library in ("libapp.so", "libflutter.so", "librust_lib_qingniao.so"):
                    entry = f"lib/{abi}/{library}"
                    if entry not in entries or archive.getinfo(entry).file_size == 0:
                        raise ValueError(f"Universal APK is missing {entry}")
    except zipfile.BadZipFile as error:
        raise ValueError("Release APK is not a valid ZIP archive") from error
    with apk.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"schemaVersion": 1, "versionName": name, "versionCode": code,
            "apkName": APK_NAME, "sha256": digest, "size": size}


def run_tool(arguments: list[str]) -> str:
    result = subprocess.run(arguments, capture_output=True, text=True, encoding="utf-8",
                            errors="replace", check=False, timeout=120)
    if result.returncode:
        raise ValueError(f"{Path(arguments[0]).name} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    version = subparsers.add_parser("version", help="Validate pubspec/tag before building")
    version.add_argument("--pubspec", type=Path, default=Path("pubspec.yaml"))
    version.add_argument("--tag")
    version.add_argument("--github-output", type=Path)
    create = subparsers.add_parser("create", help="Verify APK and write update.json")
    create.add_argument("--pubspec", type=Path, default=Path("pubspec.yaml"))
    create.add_argument("--tag", required=True)
    create.add_argument("--apk", type=Path, required=True)
    create.add_argument("--apkanalyzer", required=True)
    create.add_argument("--apksigner", required=True)
    create.add_argument("--output", type=Path, required=True)
    create.add_argument("--signature-report", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "create":
            if args.output.resolve() in (args.apk.resolve(), args.pubspec.resolve()):
                raise ValueError("Metadata output must not overwrite APK or pubspec")
            # A failed check must not leave an earlier update manifest behind.
            args.output.unlink(missing_ok=True)
        name, code = read_version(args.pubspec, args.tag)
        if args.command == "version":
            if args.github_output:
                with args.github_output.open("a", encoding="utf-8", newline="\n") as output:
                    output.write(f"version_name={name}\nversion_code={code}\nrelease_tag=v{name}\n")
            print(f"Verified version {name}+{code} (release tag v{name})")
            return
        manifest = run_tool([args.apkanalyzer, "manifest", "print", str(args.apk)])
        signature = run_tool([args.apksigner, "verify", "--verbose", "--print-certs", str(args.apk)])
        metadata = create_metadata(args.apk, name, code, manifest, signature,
                                   os.environ.get("QINGNIAO_SIGNING_CERT_SHA256", ""))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        if args.signature_report:
            if args.signature_report.resolve() in (args.apk.resolve(), args.pubspec.resolve(), args.output.resolve()):
                raise ValueError("Signature report must not overwrite APK, pubspec or metadata")
            args.signature_report.write_text(signature, encoding="utf-8")
        args.output.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Verified production universal APK {name}+{code}; wrote {args.output}")
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"Release metadata verification failed: {error}\n")


if __name__ == "__main__":
    main()
