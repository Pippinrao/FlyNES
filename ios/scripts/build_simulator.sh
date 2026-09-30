#!/bin/bash
# Run from a synced checkout on the Mac. Does not modify global xcode-select.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cmake_bin="${CMAKE_BIN:-$HOME/Developer/FlyNES-tools/cmake-3.31.8-macos-universal/CMake.app/Contents/bin/cmake}"
build_dir="${FLYNES_BUILD_DIR:-$repo_dir/build/ios-simulator}"
evidence_dir="$build_dir/evidence"
mkdir -p "$evidence_dir"
test -x "$cmake_bin"
xcodebuild -version | tee "$evidence_dir/xcode-version.txt"
sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
arch="$(uname -m)"
case "$arch" in arm64|x86_64) ;; *) echo "Unsupported Mac architecture: $arch" >&2; exit 1;; esac
flutter_args=(-DFLYNES_IOS_FLUTTER=OFF)
if [ "${FLYNES_NATIVE_BASELINE:-0}" != 1 ]; then
  FLYNES_FLUTTER_MODE=Debug bash "$repo_dir/tools/flutter/Build-Ios.sh"
  flutter_args=(-DFLYNES_IOS_FLUTTER=ON
    "-DFLYNES_FLUTTER_FRAMEWORK_DIR=${FLYNES_FLUTTER_OUTPUT:-$repo_dir/.artifacts/flutter-ios/frameworks}/Debug")
fi
"$cmake_bin" -S "$repo_dir/ios/app" -B "$build_dir" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk_path" \
  -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 "${flutter_args[@]}"
"$cmake_bin" --build "$build_dir" --config Debug --target FlyNES --parallel "${FLYNES_BUILD_JOBS:-2}" \
  2>&1 | tee "$evidence_dir/build.log"
app_path="$build_dir/Debug-iphonesimulator/FlyNES.app"
test -f "$app_path/FlyNES"
test -f "$app_path/default.metallib"
test -f "$app_path/en.lproj/Localizable.strings"
test -f "$app_path/zh-Hans.lproj/Localizable.strings"
xcrun lipo -archs "$app_path/FlyNES" | tee "$evidence_dir/architectures.txt"
printf '%s\n' "$app_path"
