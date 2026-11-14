"""Verify pinned Flutter Git identity before accepting SDK version metadata."""

import argparse
import json
from pathlib import Path
import re
import subprocess


def verify_checkout(root: Path, version: str, revision: str) -> None:
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Expected a stable Flutter release version")
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Expected a full Flutter commit SHA")

    def resolve(ref: str) -> str:
        result = subprocess.run(["git", "-C", str(root), "rev-parse", "--verify", ref],
                                capture_output=True, text=True, check=False)
        if result.returncode:
            raise ValueError(f"Cannot resolve Flutter {ref}. Fetch release tags/history before running Flutter.")
        return result.stdout.strip()

    if resolve("HEAD") != revision:
        raise ValueError("Flutter checkout does not match the pinned revision")
    if resolve(f"refs/tags/{version}^{{commit}}") != revision:
        raise ValueError("Flutter release tag does not point to the pinned revision")


def verify_metadata(data: dict, version: str, revision: str, dart_version: str) -> None:
    expected = {"frameworkVersion": version, "frameworkRevision": revision,
                "dartSdkVersion": dart_version}
    for field, value in expected.items():
        if data.get(field) != value:
            raise ValueError(f"Unexpected {field}: expected {value}, got {data.get(field)!r}")
    if data.get("flutterVersion", version) != version:
        raise ValueError("Flutter version metadata is inconsistent")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-root", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--metadata", type=Path)
    parser.add_argument("--dart-version")
    args = parser.parse_args()
    if args.metadata and not args.dart_version:
        parser.error("--dart-version is required with --metadata")
    try:
        verify_checkout(args.sdk_root, args.version, args.revision)
        if args.metadata:
            data = json.loads(args.metadata.read_text(encoding="utf-8-sig"))
            if not isinstance(data, dict):
                raise ValueError("Flutter version metadata must be an object")
            verify_metadata(data, args.version, args.revision, args.dart_version)
    except (ValueError, OSError) as error:
        parser.exit(1, f"Flutter SDK verification failed: {error}\n")
    print(f"Verified Flutter {args.version} at {args.revision}")


if __name__ == "__main__":
    main()
