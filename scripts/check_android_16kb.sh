#!/usr/bin/env bash
set -euo pipefail

apk="${1:-client/build/app/outputs/flutter-apk/app-debug.apk}"
if [[ ! -f "$apk" ]]; then
  echo "APK not found: $apk" >&2
  exit 1
fi

android_sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$android_sdk" && -d "$HOME/Library/Android/sdk" ]]; then
  android_sdk="$HOME/Library/Android/sdk"
elif [[ -z "$android_sdk" && -d "$HOME/Android/Sdk" ]]; then
  android_sdk="$HOME/Android/Sdk"
fi
if [[ -z "$android_sdk" || ! -d "$android_sdk" ]]; then
  echo "Android SDK not found. Set ANDROID_HOME or ANDROID_SDK_ROOT." >&2
  exit 1
fi

build_tools="$(find "$android_sdk/build-tools" -type f -name zipalign | sort -V | tail -1)"
if [[ -z "$build_tools" ]]; then
  echo "zipalign was not found in the Android SDK build tools." >&2
  exit 1
fi
"$build_tools" -c -P 16 -v 4 "$apk" >/dev/null
echo "APK ZIP entries satisfy 16 KB alignment."

readobj="$(find "${ANDROID_NDK_HOME:-$android_sdk/ndk}" -type f -path '*/toolchains/llvm/prebuilt/*/bin/llvm-readobj' | sort -V | tail -1)"
if [[ -z "$readobj" ]]; then
  echo "llvm-readobj was not found in the Android NDK" >&2
  exit 1
fi

temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
unzip -qq "$apk" 'lib/*/*.so' -d "$temporary"

failed=0
while IFS= read -r library; do
  while IFS= read -r alignment; do
    if (( alignment < 16384 )); then
      echo "16 KB alignment failure: $library has LOAD alignment $alignment" >&2
      failed=1
    fi
  done < <("$readobj" --program-headers "$library" | awk '/Type: PT_LOAD/{load=1; next} load && /Alignment:/{print $2; load=0}')
done < <(find "$temporary/lib/arm64-v8a" "$temporary/lib/x86_64" -type f -name '*.so' -print)

if (( failed == 0 )); then
  echo "Native LOAD segments satisfy 16 KB alignment."
fi
exit "$failed"
