"""Check real game pixels, independently of successful GL swaps/counters.

For the stationary multi-colour render-observation fixture only. This is a
colour-presence regression assertion, not a perceptual golden or latency test.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import struct

from PIL import Image


def verify_cycle(directory: Path) -> dict:
    report = json.loads((directory / "boundary.json").read_text(encoding="utf-8"))
    width, height = report["width"], report["height"]
    raw = (directory / "core.rgb565").read_bytes()
    if len(raw) != width * height * 2:
        raise ValueError("incomplete core pixel buffer")
    counts = Counter(struct.unpack(f"<{width * height}H", raw))
    palette = []
    for value, count in counts.most_common():
        rgb = ((value >> 11) * 255 // 31, ((value >> 5) & 63) * 255 // 63,
               (value & 31) * 255 // 31)
        if max(rgb) - min(rgb) >= 40 and count >= width * height * .1:
            palette.append((rgb, count / (width * height)))
    if len(palette) < 2:
        raise ValueError("fixture needs two substantial chromatic regions")
    screen = Image.open(directory / "running.png").convert("RGB")
    view = report["viewport"]
    box = tuple(view[key] for key in ("left", "top", "right", "bottom"))
    if not (0 <= box[0] < box[2] <= screen.width and
            0 <= box[1] < box[3] <= screen.height):
        raise ValueError("render viewport is outside actual screenshot")
    pixels = list(struct.iter_unpack("BBB", screen.crop(box).resize((width, height)).tobytes()))
    checks = []
    for rgb, fraction in palette[:2]:
        observed = sum(max(abs(a - b) for a, b in zip(pixel, rgb)) <= 16
                       for pixel in pixels) / len(pixels)
        checks.append({"rgb": rgb, "coreFraction": fraction,
                       "screenFraction": observed,
                       "minimum": fraction * .5, "pass": observed >= fraction * .5})
    return {"cycle": report["cycle"], "pass": all(x["pass"] for x in checks),
            "checks": checks}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--cycles", type=int, required=True)
    args = parser.parse_args()
    if not 1 <= args.cycles <= 20:
        parser.error("cycles must be in 1..20")
    results = [verify_cycle(args.directory / str(i)) for i in range(1, args.cycles + 1)]
    passed = all(row["pass"] for row in results)
    print(json.dumps({"pass": passed, "cycles": results}, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
