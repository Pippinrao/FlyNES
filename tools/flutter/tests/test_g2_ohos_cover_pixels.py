import importlib.util
from pathlib import Path
import unittest

import cv2
import numpy as np

spec = importlib.util.spec_from_file_location('oh_pixels', Path(__file__).parents[1] / 'g2_ohos_cover_pixels.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FractionalCoverTest(unittest.TestCase):
    def setUp(self):
        # Deterministic sharp pixel art, not one of the game's observed covers.
        random = np.random.default_rng(142)
        cells = random.integers(0, 256, (60, 64, 3), dtype=np.uint8)
        self.cover = cv2.resize(cells, (256, 240), interpolation=cv2.INTER_NEAREST)
        scale = .823
        # OpenCV's forward affine rasterization supplies a fractional placement,
        # independently from the verifier's inverse-coordinate candidate sampler.
        transform = np.float32([[scale, 0, .5 + (scale - 1) / 2],
                                [0, scale, .25 + (scale - 1) / 2]])
        self.painted = cv2.warpAffine(self.cover, transform, (211, 198),
                                      flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)

    def test_fractional_uniform_scale_matches_without_relaxing_mae(self):
        result = module.compare_cover(self.painted, self.cover, [0, 0, 211, 198])
        self.assertTrue(result['matches'], result)
        self.assertLessEqual(result['meanAbsoluteRgbError'], 6)
        self.assertGreaterEqual(result['correlation'], .95)

    def test_stale_or_wrong_color_image_cannot_pass_geometric_fit(self):
        for wrong in (np.flip(self.painted, axis=1).copy(), self.painted[:, :, ::-1].copy()):
            result = module.compare_cover(wrong, self.cover, [0, 0, 211, 198])
            self.assertFalse(result['matches'], result)

    def test_invalid_bounds_and_flat_unidentifiable_source_are_rejected(self):
        with self.assertRaises(ValueError):
            module.compare_cover(self.painted, self.cover, [-1, 0, 211, 198])
        with self.assertRaises(ValueError):
            module.compare_cover(self.painted, np.zeros_like(self.cover), [0, 0, 211, 198])


if __name__ == '__main__':
    unittest.main()
