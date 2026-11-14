#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_ENV:?GITHUB_ENV is required}"
: "${GITHUB_PATH:?GITHUB_PATH is required}"
sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk_root" || ! -d "$sdk_root" ]]; then
  echo '::error::Set ANDROID_HOME or ANDROID_SDK_ROOT to the installed Android SDK.' >&2
  exit 1
fi
sdkmanager="$sdk_root/cmdline-tools/latest/bin/sdkmanager"
if [[ ! -x "$sdkmanager" ]]; then
  echo "::error::Android command-line tools are missing: $sdkmanager" >&2
  exit 1
fi

export ANDROID_HOME="$sdk_root" ANDROID_SDK_ROOT="$sdk_root"
export PATH="$sdk_root/cmdline-tools/latest/bin:$sdk_root/platform-tools:$PATH"
printf 'ANDROID_HOME=%s\nANDROID_SDK_ROOT=%s\n' "$sdk_root" "$sdk_root" >> "$GITHUB_ENV"
printf '%s\n' "$sdk_root/cmdline-tools/latest/bin" "$sdk_root/platform-tools" >> "$GITHUB_PATH"
"$sdkmanager" --sdk_root="$sdk_root" --version
# Ignore yes receiving SIGPIPE, while preserving sdkmanager's exit status.
(set +o pipefail; yes | "$sdkmanager" --sdk_root="$sdk_root" --licenses)
"$sdkmanager" --sdk_root="$sdk_root" \
  'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358'
