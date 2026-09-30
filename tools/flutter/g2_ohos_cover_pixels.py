"""Compare an observed complete OH cover rectangle, allowing subpixel placement.

This reads evidence only. No masking, gamma/color fit, contrast fit, title/button
exclusion, or independent horizontal/vertical distortion is permitted.
"""
import cv2
import numpy as np
import argparse
import json
from pathlib import Path

# Fixed raster-rounding model for every source/fixture, not fitted per game:
# one shared scale, <= one device pixel of extent rounding on either axis,
# <= .75 device pixel origin phase, quarter-pixel phase sampling. No color DOF.
SCALE_SAMPLES = 17
ORIGIN_PHASES = np.arange(-.75, 1, .25)


def compare_cover(screen, cover, bounds):
    left, top, right, bottom = bounds
    if not (0 <= left < right <= screen.shape[1] and 0 <= top < bottom <= screen.shape[0]):
        raise ValueError('Complete observed cover bounds required')
    if float(cover.std()) < 4:
        raise ValueError('Flat cover cannot identify a frame')
    observed = screen[top:bottom, left:right]
    height, width = observed.shape[:2]
    source_height, source_width = cover.shape[:2]
    low = max((width-1)/source_width, (height-1)/source_height)
    high = min((width+1)/source_width, (height+1)/source_height)
    if low <= 0 or low > high:
        raise ValueError('Observed rectangle does not preserve source aspect within pixel rounding')
    yy, xx = np.indices((height, width), dtype=np.float32)
    best = None
    observed_float = observed.astype(float)
    for scale in np.linspace(low, high, SCALE_SAMPLES):
        for dx in ORIGIN_PHASES:
            for dy in ORIGIN_PHASES:
                map_x = ((xx+.5-dx)/scale-.5).astype(np.float32)
                map_y = ((yy+.5-dy)/scale-.5).astype(np.float32)
                predicted = cv2.remap(cover, map_x, map_y, cv2.INTER_LINEAR,
                                      borderMode=cv2.BORDER_REPLICATE)
                error = float(np.abs(observed_float-predicted).mean())
                if best is None or error < best['meanAbsoluteRgbError']:
                    best = dict(meanAbsoluteRgbError=error, uniformScale=float(scale),
                                originPhase=[float(dx), float(dy)],
                                correlation=float(np.corrcoef(observed.ravel(), predicted.ravel())[0, 1]))
    best['matches'] = best['meanAbsoluteRgbError'] <= 6 and best['correlation'] >= .95
    best['bounds'] = bounds
    best['policy'] = 'uniform-scale extent rounding +/-1px; 17 scales; origin +/-0.75px in 0.25px steps; complete rectangle; no color fitting'
    return best


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--restored', type=Path, required=True)
    parser.add_argument('--restarted', type=Path, required=True)
    parser.add_argument('--cover', type=Path, required=True)
    parser.add_argument('--old-cover', type=Path, required=True)
    parser.add_argument('--bounds', type=int, nargs=4, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    files = [args.before, args.restored, args.restarted, args.cover, args.old_cover]
    images = [cv2.imread(str(path)) for path in files]
    if any(image is None for image in images):
        raise ValueError('All evidence PNGs must decode')
    before, restored, restarted, cover, old = images
    result = dict(beforeNewCover=compare_cover(before, cover, args.bounds),
                  restoredNewCover=compare_cover(restored, cover, args.bounds),
                  restartedNewCover=compare_cover(restarted, cover, args.bounds),
                  restoredOldCoverNegative=compare_cover(restored, old, args.bounds),
                  scope='Fixed observed complete cover rectangle. Fractional raster geometry fit, no claim to recover exact Skia transform or color calibration.')
    result['passed'] = (not result['beforeNewCover']['matches'] and
                        result['restoredNewCover']['matches'] and result['restartedNewCover']['matches'] and
                        not result['restoredOldCoverNegative']['matches'])
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    if not result['passed']:
        raise SystemExit('Changed complete cover pixels were not demonstrated')


if __name__ == '__main__':
    main()
