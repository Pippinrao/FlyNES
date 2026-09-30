"""Verify a real native cover's pixels inside the observed Flutter card bounds.

This compares exported screenshots, never modifies an app or its image cache.
The owner-write fixture and the natural quality sampler must remain separate.
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def match_cover(screen, cover, bounds):
    left, top, right, bottom = bounds
    if not (0 <= left < right <= screen.shape[1] and
            0 <= top < bottom <= screen.shape[0]):
        raise ValueError('Card bounds must be inside the captured screen')
    region = screen[top:bottom, left:right]
    best = None
    # Recover the painted image scale from pixels, rather than assuming font,
    # density, card padding, or an unclipped accessibility rectangle.
    for width in range(40, min(region.shape[1], cover.shape[1]) + 1):
        height = round(width * cover.shape[0] / cover.shape[1])
        if height > region.shape[0]:
            continue
        candidate = cv2.resize(cover, (width, height), interpolation=cv2.INTER_LINEAR)
        if float(candidate.std()) < 4:
            continue  # A flat color cannot identify the native game frame.
        matches = cv2.matchTemplate(region, candidate, cv2.TM_CCOEFF_NORMED)
        _, score, _, location = cv2.minMaxLoc(matches)
        x, y = location
        observed = region[y:y+height, x:x+width]
        error = float(np.abs(observed.astype(float)-candidate.astype(float)).mean())
        value = dict(correlation=float(score), meanAbsoluteRgbError=error,
                     bounds=[left+x, top+y, left+x+width, top+y+height])
        if best is None or value['correlation'] > best['correlation']:
            best = value
    if best is None:
        raise ValueError('No identifiable image fits the observed card')
    best['matches'] = best['correlation'] >= .95 and best['meanAbsoluteRgbError'] <= 6
    return best


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--cover', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = json.loads(args.report.read_text(encoding='utf-8'))
    bounds = [int(n) for n in report['anchorBefore'].split()]
    images = [cv2.imread(str(p)) for p in (args.before, args.after, args.cover)]
    if any(i is None for i in images):
        raise ValueError('All inputs must be decodable images')
    before, after = [match_cover(screen, images[2], bounds) for screen in images[:2]]
    passed = after['matches'] and not before['matches']
    result = dict(result='PASS' if passed else 'FAIL', before=before, after=after,
                  coverEvidenceMode=report['coverEvidenceMode'],
                  scope='Changed native frame appears in the same observed Flutter card; not natural sampler selection certification')
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    if not passed:
        raise SystemExit('Different real cover pixels were not demonstrated')


if __name__ == '__main__':
    main()
