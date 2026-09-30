#!/usr/bin/env python3
"""Compare complete Flutter semantics trees, without accepting or editing goldens.

Only SemanticsNode numeric IDs and OrdinalSortKey runtime object identities are
normalized. All other text, indentation, bounds, identifiers and state remain.
Accepts one manifest family or roots containing matching manifest families.
This supplements the visual comparator; it does not certify native VoiceOver.
"""
from __future__ import annotations
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re

NODE = re.compile(r'^([ \t│├└─]*SemanticsNode#)\d+(?=\s*$)')
SORT_KEY = re.compile(r'^([ \t│├└─]*sortKey: OrdinalSortKey#)[0-9a-fA-F]+(?=\(order: )')
QUOTES = re.compile(r'(?<!\\)"')


def normalize(text):
    lines = []
    quoted = False
    for line in text.splitlines(keepends=True):
        if not quoted:
            line = NODE.sub(r'\g<1>ID', line)
            line = SORT_KEY.sub(r'\g<1>ID', line)
        lines.append(line)
        if len(QUOTES.findall(line)) % 2:
            quoted = not quoted
    return ''.join(lines)


def compare_text(expected, actual):
    valid = [bool(re.search(r'^[ \t│├└─]*SemanticsNode#\d+\s*$', text, re.M))
             for text in (expected, actual)]
    before, after = normalize(expected), normalize(actual)
    return {'passed': all(valid) and before == after,
            'reason': 'missing or empty Flutter semantics tree' if not all(valid)
                      else ('complete tree differs' if before != after else ''),
            'normalizedExpected': before, 'normalizedActual': after}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def discover(root, side, errors):
    if not root.is_dir():
        errors.append(f'{side}: missing input directory')
        return {}
    found = {str(path.parent.relative_to(root)): path for path in root.rglob('manifest.json')}
    if not found:
        errors.append(f'{side}: no manifest families')
    if '.' in found and len(found) > 1:
        errors.append(f'{side}: mixed root and nested manifest families')
    return found


def inventory(manifest, side, family, errors):
    prefix = f'{side}/{family}'
    try:
        cases = json.loads(manifest.read_text(encoding='utf-8'))
        if not isinstance(cases, list) or not cases:
            raise ValueError('manifest must be a nonempty list')
    except (OSError, UnicodeError, ValueError) as error:
        errors.append(f'{prefix}: invalid manifest ({error})')
        return {}
    result = {}
    paths = set()
    for case in cases:
        if not isinstance(case, dict) or not isinstance(case.get('id'), str) or not case['id']:
            errors.append(f'{prefix}: missing case ID')
            continue
        identity = case['id']
        if identity in result:
            errors.append(f'{prefix}: duplicate case ID {identity}')
            continue
        result[identity] = None
        name = case.get('semantics')
        if not isinstance(name, str) or not name or Path(name).is_absolute():
            errors.append(f'{prefix}/{identity}: missing or invalid semantics path')
            continue
        path = (manifest.parent / name).resolve()
        if not path.is_relative_to(manifest.parent.resolve()):
            errors.append(f'{prefix}/{identity}: semantics path escapes family')
            continue
        if path in paths:
            errors.append(f'{prefix}/{identity}: duplicate semantics file reference')
        paths.add(path)
        result[identity] = path
        if not path.is_file():
            errors.append(f'{prefix}/{identity}: missing semantics file {name}')
    extras = {path.resolve() for path in manifest.parent.rglob('*.semantics.txt')} - paths
    for path in sorted(extras):
        errors.append(f'{prefix}: unlisted semantics file {path.relative_to(manifest.parent.resolve())}')
    return result


def verify(expected_root, actual_root, output_root):
    expected, actual, output = [Path(path).resolve() for path in (expected_root, actual_root, output_root)]
    if output.is_relative_to(expected) or output.is_relative_to(actual):
        raise ValueError('Output must be outside both input capture directories')
    output.mkdir(parents=True, exist_ok=True)
    errors = []
    before_families = discover(expected, 'expected', errors)
    after_families = discover(actual, 'actual', errors)
    for family in sorted(before_families.keys() - after_families.keys()):
        errors.append(f'actual: missing family {family}')
    for family in sorted(after_families.keys() - before_families.keys()):
        errors.append(f'actual: additional family {family}')
    cases = []
    family_counts = {}
    for family in sorted(before_families.keys() | after_families.keys()):
        before = inventory(before_families[family], 'expected', family, errors) if family in before_families else {}
        after = inventory(after_families[family], 'actual', family, errors) if family in after_families else {}
        family_counts[family] = {'expected': len(before), 'actual': len(after)}
        for identity in sorted(before.keys() | after.keys()):
            record = {'family': family, 'id': identity, 'passed': False}
            a, b = before.get(identity), after.get(identity)
            if identity not in before or identity not in after:
                record['reason'] = 'additional actual case' if identity not in before else 'missing actual case'
                errors.append(f'{family}/{identity}: {record["reason"]}')
            elif a is None or b is None or not a.is_file() or not b.is_file():
                record['reason'] = 'missing or invalid semantics file'
            else:
                try:
                    # Decode bytes directly: do not silently normalize line endings.
                    result = compare_text(a.read_bytes().decode('utf-8'), b.read_bytes().decode('utf-8'))
                    record.update(passed=result['passed'], reason=result['reason'],
                                  expectedSha256=sha256(a), actualSha256=sha256(b))
                    if not result['passed']:
                        stem = f'{len(cases):03d}-' + re.sub(r'[^A-Za-z0-9_.-]', '_', identity)
                        before_path = output / (stem + '-expected.txt')
                        after_path = output / (stem + '-actual.txt')
                        diff_path = output / (stem + '-diff.txt')
                        before_path.write_bytes(a.read_bytes()); after_path.write_bytes(b.read_bytes())
                        diff_path.write_text(''.join(difflib.unified_diff(
                            result['normalizedExpected'].splitlines(keepends=True),
                            result['normalizedActual'].splitlines(keepends=True),
                            fromfile=f'{family}/{identity}-expected', tofile=f'{family}/{identity}-actual')),
                            encoding='utf-8')
                        record.update(expected=str(before_path), actual=str(after_path), diff=str(diff_path))
                except (OSError, UnicodeError) as error:
                    record['reason'] = f'cannot read semantics: {error}'
            cases.append(record)
    report = {'passed': bool(cases) and not errors and all(item['passed'] for item in cases),
              'normalization': 'only declaration-line SemanticsNode numeric IDs and OrdinalSortKey object IDs; quoted labels preserved',
              'expectedRoot': str(expected), 'actualRoot': str(actual), 'families': family_counts,
              'inventoryErrors': errors, 'cases': cases, 'caseCount': len(cases),
              'passedCount': sum(item['passed'] for item in cases)}
    (output / 'report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('expected', 'actual', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    report = verify(args.expected, args.actual, args.output)
    print(f"Complete Flutter semantics: {'PASS' if report['passed'] else 'FAIL'} "
          f"({report['passedCount']}/{report['caseCount']} cases; {len(report['inventoryErrors'])} inventory errors)")
    return 0 if report['passed'] else 1

if __name__ == '__main__': raise SystemExit(main())
