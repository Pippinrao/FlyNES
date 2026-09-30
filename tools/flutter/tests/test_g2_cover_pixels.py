import importlib.util
from pathlib import Path
import unittest
import cv2
import numpy as np

spec = importlib.util.spec_from_file_location('pixels', Path(__file__).parents[1]/'g2_cover_pixels.py')
pixels = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pixels)


class CoverPixelsTest(unittest.TestCase):
    def test_real_scaled_pixels_match_and_old_frame_fails(self):
        rng = np.random.default_rng(19)
        cover = rng.integers(0, 256, (60, 80, 3), dtype=np.uint8)
        screen = np.full((160, 180, 3), 21, dtype=np.uint8)
        screen[51:96, 44:104] = cv2.resize(cover, (60, 45))
        self.assertTrue(pixels.match_cover(screen, cover, [20, 20, 150, 140])['matches'])
        self.assertFalse(pixels.match_cover(screen, np.flip(cover, axis=0).copy(), [20, 20, 150, 140])['matches'])

    def test_flat_color_and_outside_bounds_cannot_certify_a_frame(self):
        screen = np.zeros((160, 180, 3), dtype=np.uint8)
        cover = np.zeros((60, 80, 3), dtype=np.uint8)
        with self.assertRaises(ValueError):
            pixels.match_cover(screen, cover, [20, 20, 150, 140])
        with self.assertRaises(ValueError):
            pixels.match_cover(screen, cover, [20, 20, 190, 140])


if __name__ == '__main__':
    unittest.main()
