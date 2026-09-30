"""Source contract for the system launch screen; video verification is separate."""
import json
from pathlib import Path
import plistlib
import unittest


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "ios/app"


class LaunchBackgroundContractTests(unittest.TestCase):
    def test_system_launch_background_matches_flutter_in_every_appearance(self):
        # CMake substitutes the CPU XML fragment before writing the final plist.
        template = (APP / "Info.plist.in").read_text(encoding="utf-8")
        info = plistlib.loads(template.replace("@FLYNES_REQUIRED_CPU@", "").encode())
        self.assertNotIn("UILaunchStoryboardName", info)
        self.assertEqual(info.get("UILaunchScreen", {}).get("UIColorName"), "LaunchBackground",
                         "System launch must explicitly use the app's dark named color")
        asset = APP / "Assets.xcassets/LaunchBackground.colorset/Contents.json"
        self.assertTrue(asset.is_file(), "The referenced launch color must be bundled")
        colors = json.loads(asset.read_text(encoding="utf-8"))["colors"]
        self.assertTrue(any(c.get("idiom") == "universal" and not c.get("appearances")
                            for c in colors), "A universal non-appearance-specific color is required")
        for entry in colors:
            self.assertEqual(entry["color"]["color-space"], "srgb")
            components = entry["color"]["components"]
            rgb = tuple(int(components[channel], 16) for channel in ("red", "green", "blue"))
            self.assertEqual(rgb, (0x12, 0x13, 0x16))
            self.assertEqual(float(components["alpha"]), 1.0)
        theme = (ROOT / "ui/flutter/lib/design_system/app_theme.dart").read_text(encoding="utf-8")
        self.assertRegex(theme, r"background\s*=\s*Color\(0xFF121316\)")
        cmake = (APP / "CMakeLists.txt").read_text(encoding="utf-8")
        self.assertRegex(cmake, r"target_sources\(FlyNES\s+PRIVATE\s+Assets\.xcassets\)")
        self.assertRegex(cmake, r"set_source_files_properties\(Assets\.xcassets\s+PROPERTIES\s+MACOSX_PACKAGE_LOCATION\s+Resources\)")


if __name__ == "__main__":
    unittest.main()
