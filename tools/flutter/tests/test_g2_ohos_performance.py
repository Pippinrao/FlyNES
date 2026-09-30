import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('oh_summary', Path(__file__).resolve().parents[1] / 'summarize_ohos_performance.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def report():
    counters = []
    for time in range(0, 65001, 20):
        runtime = {key: 0 for key in ('audioUnderflows', 'audioPostFallbackUnderflows',
            'audioShortReads', 'audioLockMisses', 'audioDroppedSamples')}
        runtime.update(sourceFrames=time // 20, sourceFps=50, sourceStandard=2,
                       audioProducedSamples=time * 48, audioConsumedSamples=time * 48,
                       audioCallbackCount=time // 20, running=True, paused=False)
        counters.append(dict(beginMs=time, endMs=time + 1, runtime=runtime,
                             renderer=dict(presentedFrames=time // 20, presentFailures=0)))
    return dict(verificationStage='G2', complete=True, failure='', entry='flutter',
        buildMode='release', actualApplicationDebug=False, engineBefore=False, engineAfter=True,
        preferencesRestored=True, coreClosedAfterReturn=True, canonicalId='game:test', contentKey='TEST',
        emulatedMs=65000, autosaveIntervalMs=60000, uptimeStartMs=1000, uptimeEndMs=66000,
        requestedCounterPollMs=20, requestedMemoryPollMs=1000,
        beforeHead=1, afterHead=2, beforeRows=[dict(id=1, kind=0)],
        afterRows=[dict(id=1, kind=0), dict(id=2, kind=0)], newAutoRows=[dict(id=2, kind=0)],
        counters=counters, memory=[dict(beginMs=t, endMs=t+1, pssKb=1000, head=1 if t < 60000 else 2, error='')
            for t in range(0, 65001, 1000)],
        inputs=[dict(beginMs=t, firstAppliedMs=t+10, injectionReturnedMs=t+20,
            releasedObservedMs=t+50, observedButtons=1, error='') for t in range(5000, 65001, 5000)])


class G2OhosPerformanceTest(unittest.TestCase):
    def test_complete_real_workload_shape_is_valid(self):
        self.assertTrue(module.summarize(report())['captureComplete'])

    def test_partial_invalid_audio_and_input_are_not_silently_filtered(self):
        changes = [lambda r: r['counters'][5]['runtime'].pop('audioUnderflows'),
                   lambda r: r['inputs'][0].update(error='injection failed'),
                   lambda r: r['inputs'][0].update(firstAppliedMs=-1),
                   lambda r: r['inputs'][0].update(releasedObservedMs=-1)]
        for change in changes:
            value = report(); change(value)
            with self.subTest(change=change):
                self.assertFalse(module.summarize(value)['captureComplete'])

    def test_release_route_and_restoration_are_required(self):
        for field, value in [('buildMode', 'debug'), ('actualApplicationDebug', True),
                ('engineAfter', False), ('engineBefore', True), ('preferencesRestored', False),
                ('coreClosedAfterReturn', False), ('autosaveIntervalMs', 0)]:
            sample = report(); sample[field] = value
            with self.subTest(field=field):
                self.assertFalse(module.summarize(sample)['captureComplete'])

    def test_auto_must_be_new_and_present_in_authoritative_rows(self):
        for rows in [[dict(id=1, kind=0)], [dict(id=3, kind=0)], [dict(id=2, kind=1)]]:
            value = report(); value['newAutoRows'] = rows
            with self.subTest(rows=rows):
                self.assertFalse(module.summarize(value)['captureComplete'])

    def test_stalled_media_cannot_pass_just_because_samples_exist(self):
        value = report()
        for sample in value['counters']:
            sample['runtime']['audioConsumedSamples'] = 0
        self.assertFalse(module.summarize(value)['captureComplete'])

    def test_truncated_observation_cannot_certify_the_reported_workload(self):
        value = report()
        value['counters'] = value['counters'][:2]
        value['memory'] = value['memory'][:1]
        value['inputs'] = value['inputs'][:1]
        self.assertFalse(module.summarize(value)['captureComplete'])

    def test_endpoints_without_save_window_observations_are_incomplete(self):
        value = report()
        value['counters'] = [value['counters'][0], value['counters'][-1]]
        self.assertFalse(module.summarize(value)['captureComplete'])
        value = report()
        for sample in value['memory']:
            sample['head'] = 1
        self.assertFalse(module.summarize(value)['captureComplete'])

    def test_new_render_failures_fail_but_an_unchanged_initial_count_is_separate(self):
        value = report()
        for sample in value['counters']:
            sample['renderer']['presentFailures'] = 3
        self.assertTrue(module.summarize(value)['captureComplete'])
        value['counters'][-1]['renderer']['presentFailures'] = 4
        self.assertFalse(module.summarize(value)['captureComplete'])


if __name__ == '__main__':
    unittest.main()
