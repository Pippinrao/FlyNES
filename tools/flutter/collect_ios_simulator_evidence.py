"""Paired Debug iOS simulator launch-command/RSS observations, not release gates.

Requires an already booted, seeded, exclusively assigned simulator and two built
Debug .apps. Installs native then Flutter over the existing bundle, preserving
its data container. Does not build, boot, erase, uninstall, seed, change settings,
drive gameplay, or read stale product-host-diagnostics.json as startup evidence.
The final installed app is the Flutter candidate. Run without other builds/tests.

--environment is an operator-supplied JSON object with nonempty fixtureId,
sourceRevision, coreRevision, flutterSdk, and buildMode="Debug". Revision/fixture
claims are recorded as declarations, not independently verified equivalence.
The Flutter simulator kernel is checked; a directory named Release is not AOT.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import time

BUNDLE = 'com.flynes.app'
WARMUPS = 2
SAMPLES = 12
SETTLE_SECONDS = 3
MEMORY_SAMPLES = 5
MEMORY_INTERVAL_SECONDS = .5
MISSING = [
    'No paired process-clock first-paint/first-interactive/native-owner-ready hooks.',
    'simctl launch command completion is not visible UI, first frame, or interaction readiness.',
    'macOS ps RSS is resident memory; it is neither PSS nor physical footprint.',
    'The fixed post-launch sampling window is not proof of a ready or steady-state hall.',
    'No gameplay/65-second AUTO workload, GC handshake, or 5-to-20-roundtrip heap checkpoints.',
    'Debug simulator results cannot certify Release/AOT or physical-device performance.',
    'Fixture/source/core identity is operator-declared; catalog equivalence and quiescence are not measured.',
]


def positive(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value > 0


def parse_launch_pid(text):
    matches = re.findall(r'^com\.flynes\.app:\s*([1-9][0-9]*)\s*$', text, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError('Launch must report exactly one positive FlyNES PID')
    return int(matches[0])


def parse_rss(text, pid, executable):
    match = re.fullmatch(r'\s*([1-9][0-9]*)\s+([1-9][0-9]*)\s+([^\n]+)\s*', text)
    if not match or int(match[1]) != pid or os.path.normpath(match[3].strip()) != os.path.normpath(executable):
        raise ValueError('RSS is missing or belongs to a different PID/executable')
    return int(match[2])


def distribution(values):
    values = sorted(values)
    return {'count': len(values), 'min': values[0] if values else None,
            'median': ((values[(len(values)-1)//2] + values[len(values)//2]) / 2) if values else None,
            'p95': values[math.ceil(len(values) * .95) - 1] if values else None,
            'max': values[-1] if values else None}


def summarize(routes):
    errors = []
    result = {}
    for role in ('native', 'flutter'):
        rows = routes.get(role, [])
        if len(rows) != WARMUPS + SAMPLES:
            errors.append(role + ': requires 2 warmups and 12 measured launches')
        pids = set()
        launch_values, rss_values = [], []
        for index, row in enumerate(rows):
            row_errors = []
            pid = row.get('pid')
            if type(pid) is not int or pid <= 0 or pid in pids:
                row_errors.append('missing or duplicate process PID')
            pids.add(pid)
            if row.get('index') != index or row.get('warmup') is not (index < WARMUPS):
                row_errors.append('incorrect sample sequence/warmup classification')
            if not positive(row.get('launchCommandWallMs')):
                row_errors.append('invalid launch-command duration')
            memory = row.get('memory', [])
            if len(memory) != MEMORY_SAMPLES:
                row_errors.append('missing RSS samples')
            previous = -1
            for sample_index, sample in enumerate(memory):
                begin, end = sample.get('beginMs'), sample.get('endMs')
                earliest = (SETTLE_SECONDS + sample_index * MEMORY_INTERVAL_SECONDS) * 1000
                if (not positive(sample.get('rssKiB')) or sample.get('pid') != pid or
                        not positive(begin) or not positive(end) or begin < earliest or
                        end < begin or begin < previous):
                    row_errors.append('invalid RSS/process/sample-clock observation')
                if positive(end):
                    previous = end
            row_errors.extend(row.get('errors', []))
            errors.extend(role + '[' + str(index) + ']: ' + error for error in row_errors)
            if not row_errors and index >= WARMUPS:
                launch_values.append(row['launchCommandWallMs'])
                rss_values.extend(sample['rssKiB'] for sample in memory)
        result[role] = {'launchCommandWallMs': distribution(launch_values),
                        'fixedWindowMacOsRssKiB': distribution(rss_values),
                        'firstPaintMs': None, 'firstInteractiveMs': None, 'nativeReadyMs': None,
                        'pssKiB': None, 'physicalFootprintBytes': None, 'postGcHeapBytes': None}
    native = result['native']['fixedWindowMacOsRssKiB']['p95']
    flutter = result['flutter']['fixedWindowMacOsRssKiB']['p95']
    return {'diagnosticCaptureComplete': not errors, 'errors': errors, 'runtimeMode': 'Debug',
            'routes': result, 'fixedWindowRssP95DeltaKiB': flutter - native if not errors else None,
            'limits': MISSING, 'performanceGate': {
                'status': 'not_evaluated', 'reason': 'required startup events and Release/PSS/GC evidence are unavailable',
                'firstInteractiveBudget': 'P95 <= 4000ms and <= native + 1500ms; not applied to simctl wall time',
                'nativeReadyBudget': 'P95 <= native * 1.1 + 100ms; no independent event',
                'gameMemoryBudget': 'Release >=65s with AUTO, PSS P95 delta <=128MiB; not applied to RSS',
                'residualBudget': 'verified GC platform heap at 5->20 roundtrips <=16MiB; unavailable'}}


def launch_command(udid):
    return ['xcrun', 'simctl', 'launch', '--terminate-running-process', udid, BUNDLE]


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def app_metadata(path, role):
    path = Path(path).resolve()
    info = plistlib.loads((path / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != BUNDLE:
        raise ValueError('Expected FlyNES bundle identifier')
    executable = info.get('CFBundleExecutable')
    if not isinstance(executable, str) or not executable or Path(executable).name != executable:
        raise ValueError('Invalid app executable')
    if (info.get('DTPlatformName') != 'iphonesimulator' and
            'iPhoneSimulator' not in info.get('CFBundleSupportedPlatforms', [])):
        raise ValueError('App must declare the iOS Simulator platform')
    files = ['Info.plist', executable]
    flutter = path / 'Frameworks/Flutter.framework/Flutter'
    if role == 'native' and flutter.exists():
        raise ValueError('Native baseline must not embed Flutter')
    if role == 'flutter':
        files += ['Frameworks/Flutter.framework/Flutter', 'Frameworks/App.framework/App',
                  'Frameworks/App.framework/flutter_assets/kernel_blob.bin']
    identities = {name: sha256(path / name) for name in files}
    return {'path': str(path), 'executable': executable, 'artifactFilesSha256': identities,
            'version': info.get('CFBundleShortVersionString'), 'build': info.get('CFBundleVersion')}


def validate_environment(environment):
    if not isinstance(environment, dict) or environment.get('buildMode') != 'Debug':
        raise ValueError('This collector supports declared Debug simulator builds only')
    for key in ('fixtureId', 'sourceRevision', 'coreRevision', 'flutterSdk'):
        if not isinstance(environment.get(key), str) or not environment[key].strip():
            raise ValueError('Missing environment declaration: ' + key)
    return environment


class Commands:
    def __init__(self, directory):
        self.directory = directory
        self.index = 0

    def run(self, command, timeout=45):
        self.index += 1
        stem = f'{self.index:04d}'
        begin = time.perf_counter()
        try:
            completed = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True,
                                       text=True, timeout=timeout)
        except subprocess.TimeoutExpired as error:
            self._save(stem, command, error.stdout or b'', error.stderr or b'', None,
                       (time.perf_counter() - begin) * 1000)
            raise RuntimeError('Command timed out; raw evidence ' + stem) from error
        elapsed = (time.perf_counter() - begin) * 1000
        self._save(stem, command, completed.stdout, completed.stderr, completed.returncode, elapsed)
        if completed.returncode:
            raise RuntimeError('Command failed; raw evidence ' + stem)
        return completed.stdout, elapsed, stem

    def _save(self, stem, command, stdout, stderr, code, elapsed):
        for name, content in (('stdout', stdout), ('stderr', stderr)):
            if isinstance(content, bytes):
                content = content.decode('utf-8', errors='replace')
            (self.directory / (stem + '.' + name + '.txt')).write_text(content, encoding='utf-8')
        with (self.directory / 'commands.jsonl').open('a', encoding='utf-8') as stream:
            stream.write(json.dumps({'id': stem, 'command': command, 'exitCode': code,
                                     'wallMs': elapsed}) + '\n')


def collect_sample(commands, udid, executable, index, deadline):
    row = {'index': index, 'warmup': index < WARMUPS, 'pid': None,
           'launchCommandWallMs': None, 'memory': [], 'errors': []}
    try:
        if time.monotonic() >= deadline:
            raise TimeoutError('Batch deadline exceeded')
        output, wall, evidence = commands.run(launch_command(udid))
        returned = time.perf_counter()
        row.update(pid=parse_launch_pid(output), launchCommandWallMs=wall, launchEvidence=evidence)
        for sample_index in range(MEMORY_SAMPLES):
            due = returned + SETTLE_SECONDS + sample_index * MEMORY_INTERVAL_SECONDS
            time.sleep(max(0, due - time.perf_counter()))
            if time.monotonic() >= deadline:
                raise TimeoutError('Batch deadline exceeded')
            begin = (time.perf_counter() - returned) * 1000
            raw, _, evidence = commands.run(['ps', '-ww', '-p', str(row['pid']), '-o', 'pid=,rss=,comm='], timeout=10)
            end = (time.perf_counter() - returned) * 1000
            row['memory'].append({'pid': row['pid'], 'rssKiB': parse_rss(raw, row['pid'], executable),
                                  'beginMs': begin, 'endMs': end, 'rawEvidence': evidence})
    except (ValueError, OSError, RuntimeError, TimeoutError) as error:
        row['errors'].append(str(error))
    return row


PERSISTENT_DATA_ROOTS = ('Documents', 'Library/Application Support', 'Library/Preferences')


def _checked_path(path):
    # Refuse links in every component, including a linked container/Library.
    # Never resolve a link and then inventory the external target as app data.
    for component in reversed((path, *path.parents)):
        info = component.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_reparse_tag', 0):
            raise RuntimeError('Persistent data contains a symlink/reparse point')
    return info


def persistent_data_snapshot(container):
    root = Path(container)
    if not root.is_absolute() or not stat.S_ISDIR(_checked_path(root).st_mode):
        raise RuntimeError('Persistent data container is unavailable')
    inventory = {}

    def visit(path):
        info = _checked_path(path)
        if stat.S_ISDIR(info.st_mode):
            for entry in sorted(path.iterdir()):
                visit(entry)
        elif stat.S_ISREG(info.st_mode):
            # O_NOFOLLOW closes the final-component link race on macOS. Validate
            # the opened identity and all parents again before reading bytes.
            fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_BINARY', 0))
            with os.fdopen(fd, 'rb') as stream:
                opened = os.fstat(stream.fileno())
                checked = _checked_path(path)
                if (opened.st_dev, opened.st_ino) != (checked.st_dev, checked.st_ino):
                    raise RuntimeError('Persistent file changed while opening')
                digest = hashlib.sha256()
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
                after = os.fstat(stream.fileno())
                if (opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                    raise RuntimeError('Persistent file changed while hashing')
            inventory[path.relative_to(root).as_posix()] = digest.hexdigest()
        else:
            raise RuntimeError('Persistent data contains a non-regular file')

    for name in PERSISTENT_DATA_ROOTS:
        path = root / name
        # Missing optional subtrees mean no files, not a missing container.
        # lstat rejects dangling links rather than treating them as absent.
        try:
            _checked_path(path)
        except FileNotFoundError:
            continue
        visit(path)
    return inventory


def verify_data_overlay(before_path, after_path, before, after):
    if not isinstance(before, dict) or not isinstance(after, dict):
        raise RuntimeError('Persistent data inventory is missing; preservation cannot be verified')
    if before != after:
        raise RuntimeError('Persistent data inventory changed across overlay installation')
    return {'beforePath': str(before_path), 'afterPath': str(after_path),
            'relocated': str(before_path) != str(after_path), 'preserved': True}


def install_preserving_data(commands, udid, metadata, role, report):
    command = ['xcrun', 'simctl', 'get_app_container', udid, BUNDLE, 'data']
    before_path = commands.run(command)[0].strip()
    before = persistent_data_snapshot(before_path)
    observation = {'role': role, 'beforePath': before_path, 'beforeInventory': before,
                   'afterPath': None, 'afterInventory': None, 'preserved': False}
    report.setdefault('dataOverlays', []).append(observation)
    commands.run(['xcrun', 'simctl', 'install', udid, metadata['path']], timeout=90)
    report['lastInstalledRoute'] = role
    after_path = commands.run(command)[0].strip()
    observation.update(afterPath=after_path, relocated=before_path != after_path)
    after = persistent_data_snapshot(after_path)
    observation['afterInventory'] = after
    observation.update(verify_data_overlay(before_path, after_path, before, after))


def collect(args):
    environment = validate_environment(json.loads(args.environment.read_text(encoding='utf-8-sig')))
    apps = {role: app_metadata(path, role) for role, path in
            (('native', args.native_app), ('flutter', args.flutter_app))}
    if apps['native']['artifactFilesSha256'] == apps['flutter']['artifactFilesSha256']:
        raise ValueError('Native and Flutter artifacts must be distinct')
    args.output.mkdir(parents=True, exist_ok=False)
    commands = Commands(args.output)
    report = {'protocolVersion': 1, 'createdAt': datetime.now(timezone.utc).isoformat(),
              'operatorEnvironment': environment, 'artifacts': apps, 'udid': args.udid,
              'routes': {}, 'collectionErrors': [], 'limits': MISSING,
              'protocol': {'order': ['native', 'flutter'], 'warmupsPerRoute': WARMUPS,
                           'measuredLaunchesPerRoute': SAMPLES, 'settleAfterLaunchReturnSeconds': SETTLE_SECONDS,
                           'rssSamplesPerLaunch': MEMORY_SAMPLES, 'rssSampleIntervalSeconds': MEMORY_INTERVAL_SECONDS,
                           'rssClock': 'host monotonic time after simctl launch command return',
                           'launchClock': 'host command start to return; not application process start or first frame',
                           'statistics': 'nearest-rank P95; exclude exactly the first two launches',
                           'buildMode': 'Debug; native mode operator-declared; candidate kernel checked',
                           'dataPreservation': {'roots': list(PERSISTENT_DATA_ROOTS),
                                                'comparison': 'exact relative file paths and SHA256 immediately before/after each install',
                                                'excluded': ['tmp', 'Library/Caches', 'SystemData', 'all paths outside declared roots']}}}
    # Freeze declared setup and sampling formula before any app installation/run.
    (args.output / 'protocol.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    deadline = time.monotonic() + 1200
    try:
        devices = json.loads(commands.run(['xcrun', 'simctl', 'list', 'devices', '--json'])[0])
        selected = [(runtime, device) for runtime, group in devices['devices'].items() for device in group
                    if device.get('udid') == args.udid]
        if len(selected) != 1 or selected[0][1].get('state') != 'Booted':
            raise ValueError('Explicit simulator must already be booted')
        report['simulator'] = {'runtime': selected[0][0], **selected[0][1]}
        report['macOS'] = commands.run(['sw_vers'])[0].strip()
        report['xcode'] = commands.run(['xcodebuild', '-version'])[0].strip()
        report['hostArchitecture'] = commands.run(['uname', '-m'])[0].strip()
        container = commands.run(['xcrun', 'simctl', 'get_app_container', args.udid, BUNDLE, 'data'])[0].strip()
        if not container or not Path(container).is_absolute() or not Path(container).is_dir():
            raise ValueError('An already installed and seeded app data container is required')
        report['preservedDataContainer'] = container
        for role in ('native', 'flutter'):
            metadata = apps[role]
            install_preserving_data(commands, args.udid, metadata, role, report)
            installed = Path(commands.run(['xcrun', 'simctl', 'get_app_container', args.udid, BUNDLE, 'app'])[0].strip())
            if not installed.is_absolute() or not installed.is_dir():
                raise RuntimeError('Installed app path unavailable')
            for name, expected in metadata['artifactFilesSha256'].items():
                if sha256(installed / name) != expected:
                    raise RuntimeError('Installed artifact does not match supplied ' + role + ' file: ' + name)
            executable = str(installed / metadata['executable'])
            report['routes'][role] = []
            for index in range(WARMUPS + SAMPLES):
                row = collect_sample(commands, args.udid, executable, index, deadline)
                report['routes'][role].append(row)
                (args.output / (role + '-samples.json')).write_text(
                    json.dumps(report['routes'][role], indent=2) + '\n', encoding='utf-8')
                if row['errors']:
                    raise RuntimeError(role + ' observation failed; see samples and raw commands')
    except (Exception, KeyboardInterrupt) as error:
        report['collectionErrors'].append(type(error).__name__ + ': ' + str(error))
    report['summary'] = summarize(report['routes'])
    report['summary']['diagnosticCaptureComplete'] &= not report['collectionErrors']
    path = args.output / 'report.json'
    path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    hashes = {entry.name: sha256(entry) for entry in sorted(args.output.iterdir()) if entry.is_file()}
    (args.output / 'evidence-sha256.json').write_text(json.dumps(hashes, indent=2) + '\n', encoding='utf-8')
    print(('DIAGNOSTIC_CAPTURE_COMPLETE' if report['summary']['diagnosticCaptureComplete'] else 'INCOMPLETE') + ': ' + str(path))
    print('Performance gates: NOT EVALUATED (Debug launch-command/RSS observations only).')
    return 0 if report['summary']['diagnosticCaptureComplete'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--udid', required=True)
    parser.add_argument('--native-app', type=Path, required=True)
    parser.add_argument('--flutter-app', type=Path, required=True)
    parser.add_argument('--environment', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='New ignored evidence directory; existing directories are refused')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('Collection runs only on macOS; parser/summary tests are platform independent')
    os.environ.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
    os.umask(0o077)
    try:
        return collect(args)
    except (ValueError, OSError) as error:
        parser.error(str(error))


if __name__ == '__main__':
    sys.exit(main())
