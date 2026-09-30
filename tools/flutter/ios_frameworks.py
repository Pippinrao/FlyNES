"""Resolve verified XCFramework slices for the existing CMake iOS host."""
from pathlib import Path
import argparse
import json
import plistlib


def resolve(directory: Path, platform: str, architecture: str) -> dict:
    if platform not in ("simulator", "device") or directory.name not in ("Debug", "Release"):
        raise ValueError("Expected simulator/device and Debug/Release framework directory")
    frameworks = []
    for name in ("Flutter", "App"):
        bundle = directory / (name + ".xcframework")
        info = plistlib.loads((bundle / "Info.plist").read_bytes())
        candidates = [entry for entry in info["AvailableLibraries"]
                      if entry.get("SupportedPlatform") == "ios"
                      and entry.get("SupportedPlatformVariant", "") == ("simulator" if platform == "simulator" else "")
                      and architecture in entry.get("SupportedArchitectures", [])]
        if len(candidates) != 1:
            raise ValueError(f"{name}: expected one matching slice for {platform}/{architecture}")
        candidate = candidates[0]
        framework = (bundle / candidate["LibraryIdentifier"] / candidate["LibraryPath"]).resolve()
        if bundle.resolve() not in framework.parents or not (framework / name).is_file():
            raise ValueError(f"{name}: invalid or missing framework binary")
        if name == "App" and platform == "simulator" and not (framework / "flutter_assets/kernel_blob.bin").is_file():
            raise ValueError("App: simulator requires a Dart kernel; build the Debug XCFramework configuration")
        frameworks.append(framework.as_posix())
    # Flutter 3.41.7 build_ios_framework always emits DebugIosApplicationBundle
    # for simulator, even when the enclosing configuration is named Release.
    return {"frameworks": frameworks,
            "runtimeMode": "Debug" if platform == "simulator" else directory.name}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("platform", choices=("simulator", "device"))
    parser.add_argument("architecture")
    args = parser.parse_args()
    print(json.dumps(resolve(args.directory, args.platform, args.architecture)))
