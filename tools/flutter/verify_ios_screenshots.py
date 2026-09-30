"""Compare explicit iOS XCTest screenshot references without accepting output.

Both directories require PNGs, matching <stem>-semantics.txt XCTest dumps and
environment.json. Required environment fields: environmentId, platform (ios),
sdk, runtime, device, pixelRatio. All fields, including optional provenance,
must match exactly. Geometry in XCTest dumps is already in logical points.
This tool never creates review approvals, updates references or masks pixels.
"""
import argparse
from collections import Counter
import importlib.util
import json
import math
from pathlib import Path
import re
import shutil

from PIL import Image, ImageChops, ImageOps

_spec = importlib.util.spec_from_file_location(
    '_g2_visual_comparator', Path(__file__).with_name('verify_g2_visuals.py'))
_visuals = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_visuals)

_NODE = re.compile(r'^\s*[→]?([A-Za-z][A-Za-z0-9 ]*(?: \([^\n,]*\))?),\s*0x[0-9a-fA-F]+,?\s*', re.M)
_NUMBER = r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?'
_RECT = re.compile(r'\{\{\s*(' + _NUMBER + r'),\s*(' + _NUMBER + r')\},\s*\{\s*(' +
                   _NUMBER + r'),\s*(' + _NUMBER + r')\}\}')
_CONTROLS = {'Button', 'Switch', 'Slider', 'TextField', 'SecureTextField', 'TextView',
             'SearchField', 'Picker', 'PickerWheel', 'ScrollView', 'Table', 'CollectionView',
             'Cell', 'Link', 'MenuItem', 'TabBar', 'SegmentedControl', 'Stepper', 'Keyboard',
             'WebView', 'Image', 'StaticText'}


def _attributes(suffix):
    """Read quoted multiline labels without stripping words that resemble keys."""
    attributes, flags = {}, []
    while suffix.strip(' ,\r\n\t'):
        suffix = suffix.lstrip(' ,\r\n\t')
        key = re.match(r'([A-Za-z][\w ]*):\s*', suffix)
        if not key:
            flag, separator, suffix = suffix.partition(',')
            flags.append(flag.strip())
            if not separator:
                break
            continue
        name = key.group(1)
        suffix = suffix[key.end():]
        if suffix.startswith("'"):
            # Apostrophes inside words are ordinary label text. A closing quote
            # must terminate the field, followed by a comma or end of record.
            end = next((m.start() for m in re.finditer("'", suffix[1:])
                        if re.match(r'\s*(?:,|$)', suffix[m.start() + 2:])), None)
            if end is None:
                raise ValueError('unterminated XCTest quoted attribute')
            end += 1
            value, suffix = suffix[1:end], suffix[end + 1:]
        else:
            # XCTest uses unquoted values for text views, including multiline
            # legal text. An ordinary comma is content, not a field boundary.
            boundary = re.search(r',\s*(?=(?:identifier|label|value|placeholderValue):|'
                                 r'(?:Selected|Disabled|Keyboard Focused)(?:\s*(?:,|$)))', suffix)
            value = suffix[:boundary.start()].strip() if boundary else suffix.strip()
            suffix = suffix[boundary.end():] if boundary else ''
        if name in attributes:
            raise ValueError('duplicate XCTest attribute: ' + name)
        if name != 'pid':  # Process identity is not an accessible control fact.
            attributes[name] = value
    return attributes, sorted(flags)


def parse_xctest(text):
    """Return stable semantic facts and keyed point rectangles; reject empty trees.

    Anonymous UIKit/Flutter wrapper views and diagnostic query echoes are not
    controls. Labelled/identified/value-bearing elements, state-bearing wrappers,
    and control roles are retained, including zero-size offscreen control records.
    Repeated role/identifier/label tuples get occurrence numbers in tree order.
    """
    if 'Element subtree:' not in text:
        raise ValueError('missing XCTest Element subtree')
    body = text.replace('\r\n', '\n').split('Element subtree:', 1)[1]
    body = re.split(r'^Path to element:|^Query chain:', body, maxsplit=1, flags=re.M)[0]
    matches = list(_NODE.finditer(body))
    facts, geometry, occurrences, viewport = [], {}, Counter(), None
    for index, node in enumerate(matches):
        role = node.group(1).strip()
        record = body[node.end():matches[index + 1].start() if index + 1 < len(matches) else len(body)].strip()
        if role == 'Application':
            continue
        rectangle = _RECT.match(record)
        if rectangle is None:
            raise ValueError('missing or malformed XCTest rectangle: ' + role)
        bounds = [float(number) for number in rectangle.groups()]
        if not all(math.isfinite(number) for number in bounds) or min(bounds[2:]) < 0:
            raise ValueError('invalid XCTest rectangle: ' + role)
        attributes, flags = _attributes(record[rectangle.end():])
        if role.startswith('Window'):
            if viewport is None or role == 'Window (Main)':
                viewport = bounds
            continue
        if not attributes and not flags and role not in _CONTROLS:
            continue
        identity = json.dumps([role, attributes.get('identifier', ''), attributes.get('label', '')], ensure_ascii=False)
        occurrence = occurrences[identity]
        occurrences[identity] += 1
        key = f'{identity}#{occurrence}'
        facts.append({'key': key, 'role': role, 'attributes': attributes, 'flags': flags})
        geometry[key] = bounds
    if not facts or not geometry or viewport is None or min(viewport[2:]) <= 0:
        raise ValueError('empty XCTest controls or missing viewport')
    return {'facts': facts, 'geometry': geometry, 'viewport': viewport}


def _environment(directory):
    value = json.loads((directory/'environment.json').read_text(encoding='utf-8-sig'))
    strings = ('environmentId', 'platform', 'sdk', 'runtime', 'device')
    if not isinstance(value, dict) or any(not isinstance(value.get(key), str) or not value[key].strip() for key in strings):
        raise ValueError('incomplete environment identifiers')
    ratio = value.get('pixelRatio')
    if value['platform'] != 'ios' or isinstance(ratio, bool) or not isinstance(ratio, (int, float)) or not math.isfinite(ratio) or ratio <= 0:
        raise ValueError('environment requires ios and a finite positive pixelRatio')
    return value


def _inventory(directory):
    return {path.stem: path for path in directory.glob('*.png') if path.is_file()}


def _diff(before, after):
    # Never resize or register images. For dimension failures only, pad the
    # diagnostic canvas; compare() still fails on the original dimensions.
    size = (max(before.width, after.width), max(before.height, after.height))
    canvases = []
    for image in (before, after):
        canvas = Image.new('RGBA', size)
        canvas.paste(image.convert('RGBA'), (0, 0))
        canvases.append(canvas)
    channels = ImageChops.difference(*canvases).split()
    maximum = channels[0]
    for channel in channels[1:]:
        maximum = ImageChops.lighter(maximum, channel)
    return maximum.convert('RGB')


def verify(expected_root, actual_root, output_root):
    expected_root, actual_root, output_root = (Path(value).resolve() for value in (expected_root, actual_root, output_root))
    for source in (expected_root, actual_root):
        if source == output_root or source in output_root.parents or output_root in source.parents:
            raise ValueError('output directory must be separate from input trees')
    if expected_root == actual_root:
        raise ValueError('expected and actual must be distinct capture directories')
    output_root.mkdir(parents=True, exist_ok=True)
    errors, environments = [], []
    for label, directory in (('expected', expected_root), ('actual', actual_root)):
        try:
            environments.append(_environment(directory))
        except (OSError, ValueError) as error:
            errors.append(f'{label}: missing or invalid environment ({error})')
            environments.append(None)
    if all(environments) and environments[0] != environments[1]:
        errors.append('capture environments differ')
    expected, actual = _inventory(expected_root), _inventory(actual_root)
    if not expected or not actual:
        errors.append('empty screenshot inventory')
    if expected.keys() != actual.keys():
        errors.append('screenshot inventory differs')
    for label, directory, images in (('expected', expected_root, expected), ('actual', actual_root, actual)):
        semantic_ids = {path.name[:-len('-semantics.txt')] for path in directory.glob('*-semantics.txt') if path.is_file()}
        if semantic_ids != set(images):
            errors.append(f'{label}: image/semantics inventory differs')
    cases = []
    for identity in sorted(expected.keys() | actual.keys()):
        failures, parsed, images, artifacts = [], [], [], {}
        for label, directory, inventory, environment in (
                ('expected', expected_root, expected, environments[0]),
                ('actual', actual_root, actual, environments[1])):
            path = inventory.get(identity)
            image = None
            if path is None:
                failures.append(f'missing {label} image')
            else:
                try:
                    with Image.open(path) as opened:
                        opened.load()
                        # XCTest encodes portrait pixels plus EXIF rotation for landscape.
                        # Honor that lossless orientation before comparing logical geometry.
                        image = ImageOps.exif_transpose(opened)
                    target = output_root/f'{identity}-{label}.png'
                    shutil.copyfile(path, target)
                    artifacts[label] = target.name
                except (OSError, ValueError) as error:
                    failures.append(f'invalid {label} image: {error}')
            images.append(image)
            try:
                tree = parse_xctest((directory/f'{identity}-semantics.txt').read_text(encoding='utf-8-sig'))
                parsed.append(tree)
                if image is not None and environment is not None:
                    measured = [number * environment['pixelRatio'] for number in tree['viewport'][2:]]
                    if any(abs(a - b) > .001 for a, b in zip(measured, image.size)):
                        failures.append(f'{label} screenshot size disagrees with XCTest viewport/pixelRatio')
            except (OSError, ValueError) as error:
                failures.append(f'invalid or missing {label} semantics: {error}')
                parsed.append(None)
        if all(parsed) and parsed[0]['facts'] != parsed[1]['facts']:
            failures.append('XCTest semantic labels/identifiers/values/roles/state differ')
        result = {'passed': False, 'outlierRatio': None, 'geometryFailures': []}
        if all(image is not None for image in images):
            if all(parsed):
                result = _visuals.compare(*images, parsed[0]['geometry'], parsed[1]['geometry'])
            else:
                result = _visuals.compare(*images)
            _diff(*images).save(output_root/f'{identity}-diff.png')
            artifacts['diff'] = f'{identity}-diff.png'
        result.update(id=identity, integrityFailures=failures, artifacts=artifacts)
        result['passed'] = result['passed'] and not failures
        cases.append(result)
    report = {'passed': bool(cases) and not errors and all(case['passed'] for case in cases),
              'scope': 'Explicit iOS reference comparison only; no review approval or full G2 certification is inferred.',
              'channelTolerance': _visuals.CHANNEL_TOLERANCE,
              'maxOutlierRatio': _visuals.MAX_OUTLIER_RATIO,
              'maxGeometryDelta': _visuals.MAX_GEOMETRY_DELTA,
              'geometryUnits': 'XCTest logical points', 'orientation': 'EXIF transpose only; no scaling/resampling; raw inputs preserved', 'diffKind': 'maximum absolute RGBA channel difference; unscaled canvas',
              'environment': environments[0], 'environmentFailures': errors, 'cases': cases}
    (output_root/'report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('expected', 'actual', 'output'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    try:
        report = verify(args.expected, args.actual, args.output)
    except (OSError, ValueError) as error:
        parser.exit(1, f'iOS screenshot comparison failed: {error}\n')
    print(f"iOS screenshot comparison: {'PASS' if report['passed'] else 'FAIL'} ({len(report['cases'])} captures)")
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
