#!/usr/bin/env python3
"""Two real iOS App UI runners; Debug simulator evidence, excluding optical QR scan.
Requires two already booted dedicated task simulators, English app language, and
FLYNES_IOS_BUILD_XCTESTS=ON Debug build. No build/erase/uninstall/ROM staging.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET

TESTS = {'host': 'NearbyTwoAppUITests/testHostFlutterSelectionAcrossTwoApps',
         'guest': 'NearbyTwoAppUITests/testGuestInputAndContinueAcrossTwoApps'}
DEVICES = ('AA68AEFB-A550-49F5-BEDE-6117CA2EC501', '2A1BB7C1-79A2-466D-9C87-A1C23F7F7E2A')
BUNDLE = 'com.flynes.app'


def validate_request(host, guest, tests, timeout):
    if host == guest or not host or not guest:
        raise ValueError('Two distinct simulators are required')
    if tests != TESTS:
        raise ValueError('Only the exact two real-App UI test filters are allowed')
    if not 120 <= timeout <= 900:
        raise ValueError('Timeout must be between 120 and 900 seconds')


def validate_result(data, expected):
    records = []
    def value(item): return item.get('_value') if isinstance(item, dict) else item
    def visit(node, ancestry=()):
        if isinstance(node, list):
            for child in node: visit(child, ancestry)
        elif isinstance(node, dict):
            names = tuple(str(value(node[key])) for key in ('identifier', 'name') if node.get(key))
            path = ancestry + names
            if 'testStatus' in node: records.append((path, value(node['testStatus'])))
            for key, child in node.items():
                if key not in ('identifier', 'name'): visit(child, path)
    visit(data)
    if len(records) != 1 or records[0][1] != 'Success': return False
    tokens = {part.removesuffix('()') for name in records[0][0] for part in name.split('/')}
    return all(part in tokens for part in expected.split('/'))


def validate_phase(state, run, role):
    try:
        return (state['run'] == run and state['role'] == role and state['phase'] == 'done'
                and state['pid'] > 0 and state['replaceCount'] == 1 and state.get('error', '') == ''
                and state['firstInputDelta'] > 0 and state['secondInputDelta'] > 0
                and state['firstGeneration'] == state['resumedGeneration']
                and state['secondGeneration'] > state['firstGeneration'])
    except (KeyError, TypeError): return False


class OwnedFiles:
    def __init__(self): self.files = {}
    def observe(self, path):
        if path.is_symlink() or not path.is_file(): raise RuntimeError('Invalid run-owned file')
        stat = path.stat()
        identity = (stat.st_dev, stat.st_ino, hashlib.sha256(path.read_bytes()).digest())
        if path in self.files and self.files[path] != identity:
            raise RuntimeError('Run-owned file changed; preserved')
        self.files[path] = identity
    def cleanup(self):
        errors = []
        for path, identity in self.files.items():
            if not os.path.lexists(path): continue
            stat = path.lstat()
            if (path.is_symlink() or not path.is_file() or
                (stat.st_dev, stat.st_ino, hashlib.sha256(path.read_bytes()).digest()) != identity):
                errors.append('Preserved changed run-owned file: ' + path.name)
            else: path.unlink()
        return errors


def capture(command, timeout=45):
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    if result.returncode: raise RuntimeError(command[0] + ' failed; sensitive output withheld')
    return result.stdout


def prepare_scheme(project, name, environment, registry):
    tree = ET.parse(project / 'xcshareddata/xcschemes/FlyNESUITests.xcscheme')
    action = tree.find('TestAction'); testables = action.find('Testables')
    reference = tree.find('BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference')
    if testables is None or reference is None: raise RuntimeError('Missing generated UI scheme reference')
    testables.clear(); ET.SubElement(testables, 'TestableReference', {'skipped': 'NO'}).append(copy.deepcopy(reference))
    action.set('shouldUseLaunchSchemeArgsEnv', 'NO')
    old = action.find('EnvironmentVariables')
    if old is not None: action.remove(old)
    variables = ET.SubElement(action, 'EnvironmentVariables')
    for key, value in environment.items():
        ET.SubElement(variables, 'EnvironmentVariable', {'key': key, 'value': str(value), 'isEnabled': 'YES'})
    path = project / ('xcshareddata/xcschemes/' + name + '.xcscheme')
    with path.open('xb') as stream: stream.write(ET.tostring(tree.getroot(), encoding='utf-8', xml_declaration=True))
    registry.observe(path)


def stop_owned(process):
    if process.poll() is not None: return
    try:
        os.killpg(process.pid, signal.SIGTERM); process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=8)
    except ProcessLookupError: process.wait(timeout=8)


def stop_observers(parents, run, output, secrets):
    """Stop only this UUID's test observer, never the App or its native owner."""
    errors = []
    owned = OwnedFiles()
    for role, parent in parents.items():
        for path in parent.glob('*/tmp/nearby-two-' + run + '-state.plist'):
            try:
                state = plistlib.loads(path.read_bytes())
                if state.get('run') != run or state.get('role') != role:
                    raise RuntimeError('Wrong diagnostic fixture identity; preserved')
                prefix = path.parent / ('nearby-two-' + run + '-')
                stop = Path(str(prefix) + 'stop.txt')
                with stop.open('xb') as stream: stream.write(run.encode())
                owned.observe(stop)
                deadline = time.monotonic() + 3
                while not state.get('observerStopped') and time.monotonic() < deadline:
                    time.sleep(0.05)
                    state = plistlib.loads(path.read_bytes())
                data = path.read_bytes()
                (output / (role + '-last-state.plist')).write_bytes(data)
                alive = True
                try: os.kill(int(state['pid']), 0)  # Existence probe only; never terminate the App.
                except ProcessLookupError: alive = False
                if state.get('observerStopped') or not alive: owned.observe(path)
                else: errors.append('Observer did not acknowledge stop; diagnostic state preserved')
                for suffix in ('invite.txt', 'join.txt'):
                    secret = Path(str(prefix) + suffix)
                    if secret.exists(): secrets.observe(secret)
            except Exception as error:
                errors.append(type(error).__name__ + ': diagnostic cleanup failed; files preserved')
    errors += owned.cleanup()
    return errors


def results(bundle, expected, output, role):
    def fetch(reference=None):
        command = ['xcrun', 'xcresulttool', 'get', '--path', str(bundle), '--format', 'json']
        if reference: command += ['--id', reference]
        return json.loads(capture(command))
    root = fetch()
    (output / (role + '-xcresult-root.json')).write_text(json.dumps(root, indent=2))
    refs = {item.get('actionResult', {}).get('testsRef', {}).get('id', {}).get('_value')
            for item in root.get('actions', {}).get('_values', [])}
    summaries = [fetch(ref) for ref in refs if ref]
    (output / (role + '-xcresult-tests.json')).write_text(json.dumps(summaries, indent=2))
    return validate_result(summaries, expected)


def orchestrate(args):
    validate_request(args.host_udid, args.guest_udid, TESTS, args.timeout)
    root = args.root.resolve(); build = root / 'build/ios-simulator'
    app = build / 'Debug-iphonesimulator/FlyNES.app'; project = build / 'flynes_ios_product.xcodeproj'
    if not app.is_dir() or not project.is_dir(): raise RuntimeError('Prebuilt Debug app and UI tests required')
    os.environ.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
    devices = json.loads(capture(['xcrun', 'simctl', 'list', 'devices', '--json']))
    booted = {d['udid'] for group in devices['devices'].values() for d in group if d.get('state') == 'Booted'}
    if not {args.host_udid, args.guest_udid} <= booted: raise RuntimeError('Both task simulators must already be booted')
    run = str(uuid.uuid4()); output = root / '.artifacts/ios-g2' / ('two-app-ui-' + run)
    output.mkdir(mode=0o700); coordination = output / 'coordination'; coordination.mkdir(mode=0o700)
    with (coordination / 'identity.plist').open('xb') as stream: plistlib.dump({'run': run}, stream)
    report = {'passed': False, 'run': run, 'classification': 'two real App simulator UI; QR payload injection, not camera scan',
              'configuration': 'Debug', 'roles': {}, 'errors': []}
    registry = OwnedFiles(); secrets = OwnedFiles(); processes = {}; parents = {}
    try:
        for role, device in (('host', args.host_udid), ('guest', args.guest_udid)):
            capture(['xcrun', 'simctl', 'install', device, str(app)], timeout=60)
            container = Path(capture(['xcrun', 'simctl', 'get_app_container', device, BUNDLE, 'data']).strip())
            if not container.is_absolute() or not container.is_dir() or device not in container.parts:
                raise RuntimeError('Invalid task App container')
            parents[role] = container.parent
            if list((container / 'tmp').glob('nearby-two-*')):
                raise RuntimeError('Existing two-App markers preserved; inspect before starting another run')
            scheme = 'FlyNESTwoUI' + run.replace('-', '') + role
            prepare_scheme(project, scheme, {'FLYNES_TEST_APPLICATION_CONTAINERS': container.parent,
                'FLYNES_TWO_APP_RUN': run, 'FLYNES_TWO_APP_ROLE': role,
                'FLYNES_TWO_APP_COORDINATION': coordination}, registry)
            log = output / (role + '.log'); result = output / (role + '.xcresult')
            report['roles'][role] = {'udid': device, 'test': TESTS[role], 'log': str(log), 'resultBundle': str(result)}
            command = ['xcodebuild', 'test-without-building', '-project', str(project), '-scheme', scheme,
                '-configuration', 'Debug', '-destination', 'platform=iOS Simulator,id=' + device,
                '-destination-timeout', '45', '-parallel-testing-enabled', 'NO',
                '-only-testing:FlyNESUITests/' + TESTS[role], '-resultBundlePath', str(result)]
            with log.open('xb') as stream:
                processes[role] = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.monotonic() + args.timeout
        while any(process.poll() is None for process in processes.values()):
            if time.monotonic() > deadline: raise TimeoutError('Two-App UI deadline exceeded')
            paths = [coordination / 'invite.secret']
            for parent in parents.values():
                paths += list(parent.glob('*/tmp/nearby-two-' + run + '-invite.txt'))
                paths += list(parent.glob('*/tmp/nearby-two-' + run + '-join.txt'))
            for path in paths:
                if path.exists(): secrets.observe(path)
            if any(process.poll() not in (None, 0) for process in processes.values()):
                raise RuntimeError('A UI runner failed; stopping only this run\'s other runner')
            time.sleep(0.2)
        for role, process in processes.items():
            detail = report['roles'][role]; detail['exitCode'] = process.returncode
            detail['exactTestPassed'] = results(Path(detail['resultBundle']), TESTS[role], output, role)
            with (coordination / (role + '-done.plist')).open('rb') as stream: state = plistlib.load(stream)
            detail['finalState'] = state; detail['uiEvidencePassed'] = validate_phase(state, run, role)
        pids = {detail['finalState']['pid'] for detail in report['roles'].values()}
        report['passed'] = len(pids) == 2 and all(d['exitCode'] == 0 and d['exactTestPassed'] and d['uiEvidencePassed'] for d in report['roles'].values())
    except Exception as error:
        report['errors'].append(type(error).__name__ + ': ' + str(error))
    finally:
        for process in processes.values(): stop_owned(process)
        report['errors'] += stop_observers(parents, run, output, secrets)
        shared_invite = coordination / 'invite.secret'
        if shared_invite.exists():
            try: secrets.observe(shared_invite)
            except Exception: report['errors'].append('Changed invitation preserved')
        report['errors'] += secrets.cleanup() + registry.cleanup()
        for role, detail in report['roles'].items():
            if 'exactTestPassed' not in detail:
                try: detail['exactTestPassed'] = results(Path(detail['resultBundle']), TESTS[role], output, role)
                except Exception: detail['exactTestPassed'] = False
        report['passed'] = report['passed'] and not report['errors']
        target = output / 'report.json'; target.write_text(json.dumps(report, indent=2) + '\n')
        print(('PASS' if report['passed'] else 'FAIL') + ': ' + str(target))
    return 0 if report['passed'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--host-udid', choices=DEVICES, default=DEVICES[0])
    parser.add_argument('--guest-udid', choices=DEVICES, default=DEVICES[1])
    parser.add_argument('--timeout', type=float, default=480)
    args = parser.parse_args()
    if sys.platform != 'darwin': parser.error('Mac-only execution; helper tests run on any host')
    os.umask(0o077)
    return orchestrate(args)

if __name__ == '__main__': sys.exit(main())
