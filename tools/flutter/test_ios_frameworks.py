import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("ios_frameworks", Path(__file__).with_name("ios_frameworks.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FrameworkTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "Release"
        for name in ("Flutter", "App"):
            bundle = self.root / (name + ".xcframework")
            libraries = []
            for identifier, archs, variant in [("ios-arm64", ["arm64"], None),
                                                ("ios-arm64_x86_64-simulator", ["arm64", "x86_64"], "simulator")]:
                framework = bundle / identifier / (name + ".framework")
                framework.mkdir(parents=True)
                (framework / name).write_bytes(b"binary fixture")
                if name == "App" and variant == "simulator":
                    assets = framework / "flutter_assets"
                    assets.mkdir()
                    (assets / "kernel_blob.bin").write_bytes(b"kernel fixture")
                info = {"LibraryIdentifier": identifier, "LibraryPath": name + ".framework",
                        "SupportedPlatform": "ios", "SupportedArchitectures": archs}
                if variant:
                    info["SupportedPlatformVariant"] = variant
                libraries.append(info)
            (bundle / "Info.plist").write_bytes(plistlib.dumps({"AvailableLibraries": libraries}))

    def test_simulator_selects_matching_slices_and_reports_debug_even_in_release_folder(self):
        result = module.resolve(self.root, "simulator", "x86_64")
        self.assertEqual(result["runtimeMode"], "Debug")
        self.assertEqual(len(result["frameworks"]), 2)
        self.assertTrue(all("simulator" in item for item in result["frameworks"]))

    def test_device_release_selects_only_arm64_device_slices(self):
        result = module.resolve(self.root, "device", "arm64")
        self.assertEqual(result["runtimeMode"], "Release")
        self.assertEqual(len(result["frameworks"]), 2)
        self.assertTrue(all("simulator" not in item for item in result["frameworks"]))

    def test_missing_architecture_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "matching slice"):
            module.resolve(self.root, "device", "x86_64")

    def test_missing_app_binary_is_rejected(self):
        (self.root / "App.xcframework/ios-arm64/App.framework/App").unlink()
        with self.assertRaisesRegex(ValueError, "binary"):
            module.resolve(self.root, "device", "arm64")

    def test_unknown_platform_is_rejected(self):
        with self.assertRaises(ValueError):
            module.resolve(self.root, "macos", "x86_64")

    def test_simulator_without_dart_kernel_is_rejected_before_host_build(self):
        (self.root / "App.xcframework/ios-arm64_x86_64-simulator/App.framework/flutter_assets/kernel_blob.bin").unlink()
        with self.assertRaisesRegex(ValueError, "kernel"):
            module.resolve(self.root, "simulator", "x86_64")


if __name__ == "__main__":
    unittest.main()
