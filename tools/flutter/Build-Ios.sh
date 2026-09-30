#!/bin/bash
# Build the shared Dart module as XCFrameworks for the existing production host.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
flutter_bin="${FLUTTER_BIN:-flutter}"
output="${FLYNES_FLUTTER_OUTPUT:-$repo_dir/.artifacts/flutter-ios/frameworks}"
mode="${FLYNES_FLUTTER_MODE:-Debug}"
sdk_identity="$("$flutter_bin" --version --machine)"
printf '%s' "$sdk_identity" | python3 -c '
import json,sys
s=json.load(sys.stdin)
expected={"frameworkVersion":"3.38.10", "frameworkRevision":"c6f67dede3d4aa1aa7a69dd56a3494a5cde6cc80", "engineRevision":"cafcda5721a78a7884db92f13c5e89f7643d52dd", "dartSdkVersion":"3.10.9"}
if any(s.get(k)!=v for k,v in expected.items()):
    raise SystemExit("iOS requires the reviewed Flutter 3.38.10 / Dart 3.10.9 toolchain")
'
# Separate generated module and SDK lock; shared Dart files remain authoritative.
# In particular, an iOS build must not rewrite the Android/OH lock or .dart_tool.
mkdir -p "$repo_dir/.artifacts/flutter-ios"
run_dir="$(mktemp -d "$repo_dir/.artifacts/flutter-ios/build.XXXXXX")"
module="$run_dir/module"
mkdir -p "$module"
cp -R "$repo_dir/ui/flutter/lib" "$module/lib"
cp "$repo_dir/ui/flutter/pubspec.yaml" "$repo_dir/ui/flutter/.metadata" "$module/"
cp "$repo_dir/tools/flutter/locks/ios-3.38.10.lock" "$module/pubspec.lock"
printf '%s\n' "$sdk_identity" > "$run_dir/sdk.json"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
cd "$module"
"$flutter_bin" --suppress-analytics pub get --enforce-lockfile
case "$mode" in
  Debug) flags=(--debug --no-profile --no-release) ;;
  Release) flags=(--no-debug --no-profile --release) ;;
  *) echo 'FLYNES_FLUTTER_MODE must be Debug or Release' >&2; exit 2 ;;
esac
"$flutter_bin" --suppress-analytics build ios-framework "${flags[@]}" --no-plugins --output="$output"
printf 'XCFrameworks: %s/%s\n' "$output" "$mode"
echo 'Simulator slices always use the Flutter debug runtime; only iphoneos Release is AOT.'
