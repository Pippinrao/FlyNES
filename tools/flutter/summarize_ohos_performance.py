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


def summarize(report):
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
    args=parser.parse_args()
    result=summarize(json.loads(args.report.read_text(encoding='utf-8-sig')))
    encoded=json.dumps(result,indent=2)+'\n'
    if args.output:
        with args.output.open('x', encoding='utf-8') as stream:
            stream.write(encoded)
    print(encoded,end='')
    return 0 if result['captureComplete'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
