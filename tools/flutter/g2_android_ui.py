"""Record simulator UI actions against observed Android accessibility labels.

No install, reset, permission override, hidden product route or golden update.
System picker actions use the same fresh accessibility tree as product actions.
"""
import argparse
import json
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path


class AndroidUi:
    def __init__(self, adb, serial, output):
        if not serial.startswith('emulator-'):
            raise ValueError('This G2 helper is restricted to task simulators')
        self.adb, self.serial = str(adb), serial
        self.output = Path(output)
        self.output.mkdir(parents=True, exist_ok=True)

    def run(self, *args):
        return subprocess.run([self.adb, '-s', self.serial, *args], check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout

    def tree(self):
        self.run('shell', 'uiautomator', 'dump', '/sdcard/g2-uiauto.xml')
        raw = self.run('exec-out', 'cat', '/sdcard/g2-uiauto.xml')
        return raw, ET.fromstring(raw)

    def record(self, event):
        event = {'timeUtc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), **event}
        with (self.output/'actions.jsonl').open('a', encoding='utf-8') as stream:
            stream.write(json.dumps(event, ensure_ascii=False)+'\n')

    def snapshot(self, tag):
        if not re.fullmatch(r'[a-zA-Z0-9_-]+', tag):
            raise ValueError('Capture tag must be a plain name')
        raw, tree = self.tree()
        image = self.run('exec-out', 'screencap', '-p')
        (self.output/f'{tag}.xml').write_bytes(raw)
        (self.output/f'{tag}.png').write_bytes(image)
        rows = [{'text': n.get('text'), 'label': n.get('content-desc'),
                 'bounds': n.get('bounds'), 'clickable': n.get('clickable'),
                 'enabled': n.get('enabled'), 'checked': n.get('checked'),
                 'selected': n.get('selected'), 'focused': n.get('focused'),
                 'resourceId': n.get('resource-id')} for n in tree.iter('node')
                if n.get('text') or n.get('content-desc')]
        (self.output/f'{tag}.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
        self.record({'snapshot': tag, 'nodes': len(rows)})
        return rows

    def tap(self, label):
        _, tree = self.tree()
        candidates = [n for n in tree.iter('node') if label in (n.get('text'), n.get('content-desc'))
                      and n.get('enabled') == 'true']
        if len(candidates) != 1:
            raise AssertionError(f'Expected one enabled observed node for {label!r}, found {len(candidates)}')
        bounds = list(map(int, re.findall(r'\d+', candidates[0].get('bounds', ''))))
        if len(bounds) != 4 or bounds[2] <= bounds[0] or bounds[3] <= bounds[1]:
            raise AssertionError('Target has no visible bounds')
        x, y = (bounds[0]+bounds[2])//2, (bounds[1]+bounds[3])//2
        self.run('shell', 'input', 'tap', str(x), str(y))
        self.record({'tap': label, 'bounds': bounds})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', required=True)
    parser.add_argument('--serial', default='emulator-5582')
    parser.add_argument('--output', required=True)
    parser.add_argument('action', choices=['snapshot', 'tap', 'back'])
    parser.add_argument('value', nargs='?')
    args = parser.parse_args()
    ui = AndroidUi(args.adb, args.serial, args.output)
    if args.action == 'snapshot':
        print(json.dumps(ui.snapshot(args.value), ensure_ascii=False, indent=2))
    elif args.action == 'tap':
        ui.tap(args.value)
    else:
        ui.run('shell', 'input', 'keyevent', 'KEYCODE_BACK')
        ui.record({'key': 'BACK'})


if __name__ == '__main__':
    main()
