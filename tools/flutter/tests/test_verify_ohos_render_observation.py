import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

from PIL import Image

spec = importlib.util.spec_from_file_location(
    "render_observation", Path(__file__).resolve().parents[1] / "verify_ohos_render_observation.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RenderObservationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.report = {"width": 10, "height": 10, "cycle": 1,
                       "viewport": {"left": 10, "top": 0, "right": 20, "bottom": 10}}
        self.write_report()
        (self.root / "core.rgb565").write_bytes(struct.pack("<100H", *([31] * 60 + [0xFFE0] * 40)))

    def write_report(self):
        (self.root / "boundary.json").write_text(json.dumps(self.report))

    def test_matching_real_viewport_passes(self):
        screen = Image.new("RGB", (30, 10), "black")
        screen.paste((0, 0, 255), (10, 0, 20, 6))
        screen.paste((255, 255, 0), (10, 6, 20, 10))
        screen.save(self.root / "running.png")
        self.assertTrue(module.verify_cycle(self.root)["pass"])

    def test_black_game_is_not_hidden_by_matching_controls_outside_viewport(self):
        screen = Image.new("RGB", (30, 10), "blue")
        screen.paste((255, 255, 0), (0, 6, 30, 10))
        screen.paste((0, 0, 0), (10, 0, 20, 10))
        screen.save(self.root / "running.png")
        self.assertFalse(module.verify_cycle(self.root)["pass"])

    def test_red_atlas_does_not_count_as_game_colours(self):
        Image.new("RGB", (30, 10), "red").save(self.root / "running.png")
        self.assertFalse(module.verify_cycle(self.root)["pass"])

    def test_incomplete_pixels_fail_closed(self):
        (self.root / "core.rgb565").write_bytes(b"\x00")
        with self.assertRaisesRegex(ValueError, "incomplete"):
            module.verify_cycle(self.root)

    def test_out_of_bounds_viewport_fails_closed(self):
        Image.new("RGB", (30, 10), "blue").save(self.root / "running.png")
        self.report["viewport"]["right"] = 40
        self.write_report()
        with self.assertRaisesRegex(ValueError, "outside"):
            module.verify_cycle(self.root)


if __name__ == "__main__":
    unittest.main()
