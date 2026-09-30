"""Operate task HVD controls from fresh accessibility trees and retain evidence."""
import argparse
import json
import re
import subprocess
import time
from pathlib import Path


class HarmonyUi:
    def __init__(self, hdc, target, output):
        if not target.startswith('127.0.0.1:'):
            raise ValueError('Task simulator targets only')
        self.hdc, self.target, self.output = str(hdc), target, Path(output)
        self.output.mkdir(parents=True, exist_ok=True)

    def run(self, *args):
        result = subprocess.run([self.hdc, '-t', self.target, *args], capture_output=True, check=True)
        text = result.stdout.decode('utf-8', errors='replace')
        if '[Fail]' in text or 'error: failed' in text:
            raise RuntimeError(text)
        return text

    def tree(self):
        self.run('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/g2-ui.json')
        self.run('file', 'recv', '/data/local/tmp/g2-ui.json', str(self.output/'latest.json'))
        raw = (self.output/'latest.json').read_text(encoding='utf-8')
        tree = json.loads(raw)
        rows = []

        def visit(node):
            attrs = node.get('attributes', {})
            if (attrs.get('text') or attrs.get('description') or attrs.get('id')
                    or attrs.get('clickable') == 'true' or attrs.get('type') == 'TextInput'):
                rows.append(attrs)
            for child in node.get('children', []):
                visit(child)
        visit(tree)
        return raw, rows

    def record(self, value):
        with (self.output/'actions.jsonl').open('a', encoding='utf-8') as stream:
            stream.write(json.dumps({'time': time.time(), **value}, ensure_ascii=False)+'\n')

    def snapshot(self, tag):
        raw, rows = self.tree()
        self.run('shell', 'uitest', 'screenCap', '-p', '/data/local/tmp/g2-ui.png')
        self.run('file', 'recv', '/data/local/tmp/g2-ui.png', str(self.output/f'{tag}.png'))
        (self.output/f'{tag}.tree.json').write_text(raw, encoding='utf-8')
        (self.output/f'{tag}.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
        self.record({'snapshot':tag, 'nodes':len(rows)})
        return rows

    def tap(self, label):
        _, rows = self.tree()
        matches = [r for r in rows if label in (r.get('text'), r.get('description'), r.get('id'))
                   and r.get('enabled') != 'false' and r.get('visible') != 'false']
        # Prefer the actionable node when a parent and child share a label.
        clickable = [r for r in matches if r.get('clickable') == 'true']
        if clickable:
            matches = clickable
        if len(matches) != 1:
            raise AssertionError(f'{label!r}: expected one enabled observed node, got {len(matches)}')
        self.click_node(matches[0], label)

    def tap_type(self, type_name):
        _, rows = self.tree()
        matches = [r for r in rows if r.get('type') == type_name
                   and r.get('enabled') != 'false' and r.get('visible') != 'false']
        if len(matches) != 1:
            raise AssertionError(f'{type_name}: expected one enabled observed node, got {len(matches)}')
        self.click_node(matches[0], type_name)

    def click_node(self, row, label):
        bounds = list(map(int, re.findall(r'-?\d+', row['bounds'])))
        if len(bounds) != 4 or bounds[2] <= bounds[0] or bounds[3] <= bounds[1]:
            raise AssertionError(f'Invalid target bounds: {row}')
        x, y = (bounds[0]+bounds[2])//2, (bounds[1]+bounds[3])//2
        self.run('shell','uitest','uiInput','click',str(x),str(y))
        self.record({'tap':label, 'bounds':bounds, 'type':row.get('type')})


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hdc',default='D:/soft/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe')
    parser.add_argument('--target',default='127.0.0.1:5557')
    parser.add_argument('--output',required=True)
    parser.add_argument('--tap')
    parser.add_argument('--snapshot')
    args=parser.parse_args()
    ui=HarmonyUi(args.hdc,args.target,args.output)
    if args.tap: ui.tap(args.tap)
    if args.snapshot:
        print(json.dumps(ui.snapshot(args.snapshot),ensure_ascii=False))
