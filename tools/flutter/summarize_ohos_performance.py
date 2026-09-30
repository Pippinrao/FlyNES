"""Summarize OH instrumented counter observations, never per-frame timings.

Exit 2 for incomplete/failed captures. Zero allocator readings remain unavailable.
"""
import argparse
import json
import math
from pathlib import Path


def stats(values):
    values = sorted(x for x in values if not isinstance(x, bool) and isinstance(x, (int, float)) and math.isfinite(x) and x >= 0)
    if not values:
        return dict(available=False, count=0, minimum=None, median=None, p95=None, maximum=None)
    return dict(available=True, count=len(values), minimum=values[0],
                median=values[(len(values)-1)//2], p95=values[math.ceil(len(values)*.95)-1],
                maximum=values[-1])


def increments(counters, group, key):
    values = [c[group][key] for c in counters if key in c.get(group, {})]
    pairs = list(zip(values, values[1:]))
    return {'available': bool(values), 'observedIncrementsLowerBound': sum(b-a for a,b in pairs if b >= a),
            'resets': sum(b < a for a,b in pairs)}


def validate_g2(report):
    """Validate every observation before aggregation; missing samples are not zero."""
    errors = []
    def number(value, positive=False):
        return (not isinstance(value, bool) and isinstance(value, (int, float))
                and math.isfinite(value) and (value > 0 if positive else value >= 0))
    def require(condition, message):
        if not condition:
            errors.append(message)
    require(report.get('buildMode') == 'release' and report.get('actualApplicationDebug') is False,
            'Actual Release build is required')
    route = report.get('entry')
    require(route in ('native', 'flutter') and report.get('engineBefore') is False
            and report.get('engineAfter') is (route == 'flutter'), 'Engine/entry evidence mismatch')
    require(report.get('preferencesRestored') is True and report.get('coreClosedAfterReturn') is True,
            'Workload cleanup/restoration is incomplete')
    require(report.get('autosaveIntervalMs') == 60000, 'Paired autosave interval must be 60000ms')
    require(bool(report.get('canonicalId')) and bool(report.get('contentKey')), 'Content identity is missing')
    before = report.get('beforeRows', [])
    after = report.get('afterRows', [])
    autos = report.get('newAutoRows', [])
    require(bool(autos) and all(isinstance(row, dict) and row.get('kind') == 0
            and number(row.get('id'), True) and row in after
            and not any(old.get('id') == row['id'] for old in before) for row in autos),
            'AUTO must be new and present in the authoritative final history')
    require(report.get('afterHead') != report.get('beforeHead') and number(report.get('afterHead'), True),
            'History head did not advance')
    start, end = report.get('uptimeStartMs'), report.get('uptimeEndMs')
    wall = end - start if number(start) and number(end) else -1
    require(wall > 0, 'Workload monotonic duration is invalid')
    counters = report.get('counters', [])
    runtime_keys = ('sourceFrames', 'audioUnderflows', 'audioPostFallbackUnderflows', 'audioShortReads',
                    'audioLockMisses', 'audioDroppedSamples', 'audioProducedSamples',
                    'audioConsumedSamples', 'audioCallbackCount')
    require(isinstance(counters, list) and len(counters) >= 2, 'Counter observations are missing')
    previous_time = -1
    counter_valid = True
    for index, sample in enumerate(counters):
        runtime, renderer = sample.get('runtime'), sample.get('renderer')
        begin, end = sample.get('beginMs'), sample.get('endMs')
        valid = (number(begin) and number(end) and end >= begin >= previous_time
                 and isinstance(runtime, dict) and isinstance(renderer, dict)
                 and all(number(runtime.get(key)) for key in runtime_keys)
                 and number(runtime.get('sourceFps'), True)
                 and all(number(renderer.get(key)) for key in ('presentedFrames', 'presentFailures')))
        require(valid, f'Invalid or incomplete counter observation {index}')
        counter_valid = counter_valid and valid
        if number(begin): previous_time = begin
    if counter_valid and len(counters) >= 2:
        require(counters[0]['beginMs'] <= 100 and counters[-1]['endMs'] >= wall - 100,
                'Counter observations do not cover the full workload')
        require(all(b['beginMs'] - a['beginMs'] <= 1000 for a, b in zip(counters, counters[1:])),
                'Counter observation gap exceeds one second; continuous sampling is missing')
        for group, key in [('runtime', 'sourceFrames'), ('runtime', 'audioConsumedSamples'),
                           ('renderer', 'presentedFrames')]:
            require(counters[-1][group][key] > counters[0][group][key], f'{key} did not advance')
        initial_failures = counters[0]['renderer']['presentFailures']
        require(all(sample['renderer']['presentFailures'] == initial_failures for sample in counters),
                'Renderer failure count changed during the workload')
    memory = report.get('memory', [])
    timed_memory = bool(memory) and all(number(sample.get('beginMs')) and number(sample.get('endMs'))
        and sample['endMs'] >= sample['beginMs'] for sample in memory)
    require(timed_memory and memory[0]['beginMs'] <= 1000 and memory[-1]['endMs'] >= wall - 1000,
            'Memory/head observations do not cover the full workload')
    auto_ids = {row['id'] for row in autos if isinstance(row, dict) and number(row.get('id'), True)}
    auto_windows = [(a['beginMs'] - 2000, b['endMs'] + 2000) for a, b in zip(memory, memory[1:])
                    if timed_memory and a.get('head') != b.get('head') and b.get('head') in auto_ids]
    require(bool(auto_windows), 'AUTO head change was not observed')
    if counter_valid and len(counters) >= 2 and auto_windows:
        require(all(counters[0]['beginMs'] <= low and counters[-1]['endMs'] >= high
                    for low, high in auto_windows), 'Counter observations do not cover the AUTO window')
        for low, high in auto_windows:
            window = [sample for sample in counters if low <= sample['beginMs'] <= high]
            for group, key in [('runtime', 'sourceFrames'), ('runtime', 'audioConsumedSamples'),
                               ('renderer', 'presentedFrames')]:
                require(len(window) >= 2 and window[-1][group][key] > window[0][group][key],
                        f'No observed {key} growth inside AUTO window')
    inputs = report.get('inputs', [])
    require(bool(inputs), 'Input observations are missing')
    require(bool(inputs) and number(inputs[0].get('beginMs')) and inputs[0]['beginMs'] <= 6000
            and number(inputs[-1].get('beginMs')) and inputs[-1]['beginMs'] >= wall - 6000,
            'Input observations do not cover the full workload')
    for index, sample in enumerate(inputs):
        times = [sample.get(key) for key in ('beginMs', 'firstAppliedMs', 'releasedObservedMs')]
        valid = all(number(value) for value in times)
        require(valid and times == sorted(times) and not sample.get('error')
                and isinstance(sample.get('observedButtons'), int) and sample['observedButtons'] & 1 == 1,
                f'Invalid input press/release observation {index}')
    return errors


def summarize(report, require_g2=False):
    if require_g2 or report.get('verificationStage') == 'G2':
        errors = validate_g2(report)
        if errors:
            return {'captureComplete': False, 'validationErrors': errors,
                    'reportedFailure': report.get('failure', ''), 'verificationStage': 'G2'}
    counters = report.get('counters', [])
    memory = report.get('memory', [])
    inputs = report.get('inputs', [])
    pss_values = [sample.get('pssKb') for sample in memory]
    valid_pss_samples = sum(isinstance(value, (int, float)) and not isinstance(value, bool)
                            and math.isfinite(value) and value > 0 for value in pss_values)
    memory_errors = [{'sampleIndex': index, 'beginMs': sample.get('beginMs'),
                      'error': sample['error']} for index, sample in enumerate(memory)
                     if sample.get('error')]

    def gaps(group, key, low=0, high=math.inf):
        previous = None
        result = []
        for item in counters:
            if key not in item.get(group, {}):
                continue
            if previous is not None and item[group][key] != previous[group][key]:
                if item[group][key] > previous[group][key] and low <= item['beginMs'] <= high:
                    result.append(item['beginMs']-previous['beginMs'])
                previous = item
            elif previous is None:
                previous = item
        return stats(result)

    changes = [{'previousHead': a['head'], 'nextHead': b['head'],
                'previousObservationBeginMs': a['beginMs'], 'newObservationEndMs': b['endMs']}
               for a,b in zip(memory,memory[1:]) if 'head' in a and 'head' in b and a['head'] != b['head']]
    result = {
        'captureComplete': report.get('complete') is True and not report.get('failure')
            and report.get('emulatedMs', 0) >= 65000 and bool(report.get('newAutoRows'))
            and bool(counters) and bool(memory) and bool(inputs)
            and valid_pss_samples == len(memory) and not memory_errors,
        'reportedFailure': report.get('failure', ''),
        'validPssSamples': valid_pss_samples,
        'memoryReadErrors': memory_errors,
        'scope': 'instrumented counter-growth observation intervals; not per-frame presentation or physical latency',
        'comparisonIdentity': {key: report.get(key) for key in ('entry','contentKey','canonicalId',
            'autosaveIntervalMs','requestedCounterPollMs','requestedMemoryPollMs')},
        'beforeRecordCount': len(report.get('beforeRows', [])),
        'emulatedMs': report.get('emulatedMs'),
        'measuredWallMs': report.get('uptimeEndMs',0)-report.get('uptimeStartMs',0),
        'counterSamples': len(counters), 'memorySamples':len(memory), 'inputSamples':len(inputs),
        'sourceFrames': increments(counters,'runtime','sourceFrames'),
        'presentedFrames': increments(counters,'renderer','presentedFrames'),
        'presentFailures': increments(counters,'renderer','presentFailures'),
        'audio': {k:increments(counters,'runtime',k) for k in ('audioUnderflows','audioPostFallbackUnderflows',
            'audioShortReads','audioLockMisses','audioDroppedSamples','audioProducedSamples',
            'audioConsumedSamples','audioCallbackCount')},
        'memory': {k:stats([v[k] for v in memory if k in v and (k != 'nativeAllocatedBytes' or v[k] > 0)])
            for k in ('pssKb','vssKb','vmHeapUsedKb','vmTotalHeapKb','nativeAllocatedBytes')},
        'memoryReadMs':stats([v['endMs']-v['beginMs'] for v in memory if 'endMs' in v]),
        'pollGapMs':stats([b['beginMs']-a['beginMs'] for a,b in zip(counters,counters[1:])]),
        'sourceGrowthObservationGapMs':gaps('runtime','sourceFrames'),
        'presentGrowthObservationGapMs':gaps('renderer','presentedFrames'),
        'pcmConsumptionGrowthObservationGapMs':gaps('runtime','audioConsumedSamples'),
        'inputFirstAppliedUpperBoundMs':stats([v['firstAppliedMs']-v['beginMs'] for v in inputs
            if v.get('firstAppliedMs',-1) >= 0 and not v.get('error')]),
        'headChanges':changes, 'newAutoRows':report.get('newAutoRows',[])
    }
    if counters:
        result['comparisonIdentity']['sourceFps'] = counters[-1].get('runtime',{}).get('sourceFps')
        result['comparisonIdentity']['sourceStandard'] = counters[-1].get('runtime',{}).get('sourceStandard')
    if changes:
        low=changes[0]['previousObservationBeginMs']-2000
        high=changes[0]['newObservationEndMs']+2000
        result['saveContextWindow']={'beginMs':low,'endMs':high,
            'sourceGrowthGapMs':gaps('runtime','sourceFrames',low,high),
            'presentGrowthGapMs':gaps('renderer','presentedFrames',low,high),
            'pcmConsumptionGrowthGapMs':gaps('runtime','audioConsumedSamples',low,high)}
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report',type=Path)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--g2-release', action='store_true', help='Require complete G2 Release evidence')
    args=parser.parse_args()
    result=summarize(json.loads(args.report.read_text(encoding='utf-8-sig')), args.g2_release)
    encoded=json.dumps(result,indent=2)+'\n'
    if args.output:
        with args.output.open('x', encoding='utf-8') as stream:
            stream.write(encoded)
    print(encoded,end='')
    return 0 if result['captureComplete'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
