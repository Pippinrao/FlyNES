import importlib.util
import copy
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / 'g2_android_performance.py'
spec = importlib.util.spec_from_file_location('g2_performance', PATH) if PATH.exists() else None
module = importlib.util.module_from_spec(spec) if spec else None
if spec:
    spec.loader.exec_module(module)


class G2EvidenceTest(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(module, 'G2 must reject incomplete Release evidence')

    def test_failed_debug_or_unrestored_save_is_rejected(self):
        report = dict(result='PASS', targetDebuggable=False, preferencesRestored=True,
                      playedMs=65000, intervalMs=60000, automaticSaves=[dict(id=2)],
                      contentKey='same', requestedCanonicalId='same', engineBefore=False,
                      engineAfter=False, entry='native')
        summary = dict(captureComplete=True, invalidFrameGapCount=0,
                       saveWindowCoreGapMs=dict(max=30),
                       softwareTouchToCoreMs=dict(count=10),
                       observedUnderrunIncrementsLowerBound=0,
                       audioCounterResetCount=0)
        report['memoryAndAudio'] = [dict(runtimeFailures=0, audioPlaybackFrames=50,audioUnderruns=0),
                                    dict(runtimeFailures=0, audioPlaybackFrames=100,audioUnderruns=0)]
        self.assertEqual(module.save_errors(report, summary), [])
        for key, value in [('result', 'incomplete'), ('targetDebuggable', True),
                           ('preferencesRestored', False), ('engineAfter', True),
                           ('playedMs', 64999)]:
            bad = copy.deepcopy(report); bad[key] = value
            self.assertTrue(module.save_errors(bad, summary), key)
        for key, value in [('softwareTouchToCoreMs', dict(count=0)),
                           ('observedUnderrunIncrementsLowerBound', None)]:
            bad = copy.deepcopy(summary); bad[key] = value
            self.assertTrue(module.save_errors(report, bad), key)

    def test_partial_audio_counters_cannot_hide_behind_zero_lower_bound(self):
        report=dict(result='PASS',targetDebuggable=False,preferencesRestored=True,engineBefore=False,
                    engineAfter=False,entry='native',playedMs=65000,intervalMs=60000,
                    automaticSaves=[dict(id=2)],contentKey='same',requestedCanonicalId='same')
        summary=dict(captureComplete=True,invalidFrameGapCount=0,saveWindowCoreGapMs=dict(max=20),
                     softwareTouchToCoreMs=dict(count=10),observedUnderrunIncrementsLowerBound=0)
        good=[dict(runtimeFailures=0,audioPlaybackFrames=value,audioUnderruns=0) for value in [10,20,30,40]]
        report['memoryAndAudio']=good
        self.assertEqual(module.save_errors(report,summary),[])
        for field in ['audioPlaybackFrames','audioUnderruns']:
            for missing in [None,-1]:
                bad=copy.deepcopy(report)
                if missing is None: del bad['memoryAndAudio'][2][field]
                else: bad['memoryAndAudio'][2][field]=missing
                self.assertTrue(module.save_errors(bad,summary),f'{field} {missing}')
            for invalid in [None,True,'0']:
                bad=copy.deepcopy(report);bad['memoryAndAudio'][2][field]=invalid
                self.assertTrue(module.save_errors(bad,summary),f'{field} invalid {invalid}')
        stalled=copy.deepcopy(report)
        for row in stalled['memoryAndAudio'][2:]:row['audioPlaybackFrames']=20
        self.assertTrue(module.save_errors(stalled,summary),'one advancing pair does not prove full audio observation')
        reset=copy.deepcopy(report);reset['memoryAndAudio'][2]['audioPlaybackFrames']=0
        self.assertEqual(module.save_errors(reset,summary),[],'known resets remain explicitly reported, not unknown')

    def test_gc_request_without_completed_collection_is_not_heap_evidence(self):
        good = dict(cycle=5, gcBefore=10, gcAfter=11, weakMarkerCleared=True, javaUsedBytes=100)
        final = dict(good, cycle=20, javaUsedBytes=100 + 16*1024*1024)
        result = module.heap_growth([good, final])
        self.assertEqual(result['status'], 'pass')
        final['javaUsedBytes'] += 1
        self.assertEqual(module.heap_growth([good, final])['status'], 'fail')
        final['gcAfter'] = final['gcBefore']
        self.assertEqual(module.heap_growth([good, final])['status'], 'blocked')
        final['gcAfter'] += 1; final['weakMarkerCleared'] = False
        self.assertEqual(module.heap_growth([good, final])['status'], 'blocked')

    def test_startup_requires_owner_event_pid_generation_and_release(self):
        report = dict(result='PASS', targetDebuggable=False, preferencesRestored=True, pid=42,
                      route='native', engineBefore=False, engineAfter=False,
                      nativeGenerationAtEnd=7,
                      nativeOwnerReady=dict(pid=42, generation=7, elapsedRealtimeMs=1234),
                      primaryInteractive=dict(sinceProcessMs=1500, sinceActivityRequestMs=500),
                      firstVisibleCard=dict(sinceProcessMs=1550),
                      nativeSnapshotCountAtEnd=7)
        self.assertEqual(module.startup_errors(report), [])
        for field, value in [('pid',43), ('generation',8), ('elapsedRealtimeMs',None)]:
            bad=copy.deepcopy(report); bad['nativeOwnerReady'][field]=value
            self.assertTrue(module.startup_errors(bad))

    def test_parallel_observation_requires_draw_and_cannot_pair_with_old_boundary(self):
        sample=dict(schema=3,result='PASS',targetDebuggable=False,preferencesRestored=True,pid=42,
                    route='native',engineBefore=False,engineAfter=False,nativeGenerationAtEnd=7,
                    nativeOwnerReady=dict(pid=42,generation=7,elapsedRealtimeMs=100,sinceProcessMs=100),
                    primaryInteractive=dict(elapsedRealtimeMs=200,sinceProcessMs=200,sinceActivityRequestMs=180),
                    firstVisibleCard=dict(elapsedRealtimeMs=210,sinceProcessMs=210),nativeSnapshotCountAtEnd=7,
                    observerStartedElapsedRealtimeMs=30,hostFirstDraw=dict(elapsedRealtimeMs=150),
                    primaryHostDrawElapsedRealtimeMs=150,cardHostDrawElapsedRealtimeMs=150,
                    hostsDestroyedBeforePreferenceRestore=True,audioOwnersAfterCleanup=0)
        self.assertEqual(module.startup_errors(sample),[])
        for field,value in [('hostFirstDraw',{}),('observerStartedElapsedRealtimeMs',None),
                            ('hostFirstDraw',dict(elapsedRealtimeMs=250)),
                            ('primaryHostDrawElapsedRealtimeMs',0),('cardHostDrawElapsedRealtimeMs',300),
                            ('hostsDestroyedBeforePreferenceRestore',False),('audioOwnersAfterCleanup',1)]:
            bad=copy.deepcopy(sample);bad[field]=value
            self.assertTrue(module.startup_errors(bad),field)
        routes={route:[dict(copy.deepcopy(sample),kind='warmup' if i<2 else 'measured',pid=i,
                           nativeOwnerReady=dict(sample['nativeOwnerReady'],pid=i),route=route,
                           engineAfter=route=='flutter',schema=3 if route=='native' else 2)
                       for i in range(14)] for route in ['native','flutter']}
        self.assertIn('different_observation_boundary',module.paired_startup(routes)['errors'])

    def test_startup_pair_cannot_accept_missing_warmup_or_duplicate_process(self):
        samples = [dict(kind='warmup' if i<2 else 'measured', pid=i+1) for i in range(14)]
        self.assertEqual(module.cohort_errors(samples), [])
        self.assertTrue(module.cohort_errors(samples[1:]))
        samples[-1]['pid']=samples[-2]['pid']
        self.assertTrue(module.cohort_errors(samples))

    def test_auto_resume_before_store_reports_the_real_frame_during_io(self):
        names=['auto.audio_stop.begin','auto.audio_stop.end','save.capture.begin','save.capture.end',
               'save.thumbnail.begin','save.thumbnail.end','auto.audio_restart.request',
               'auto.audio_restart.submitted','save.store.begin','save.store.end']
        report=dict(startedEpochMs=100,finishedEpochMs=200,savePhaseDiagnosticsEnabled=True,
                    savePhaseEvents=[dict(phase=name,monotonicNs=(i+1)*1000000,epochMs=150) for i,name in enumerate(names)],
                    coreFrameEvents=[[1,500000,149],[2,9500000,151]])
        good=module.save_phase_summary(report)
        self.assertEqual(good['status'],'complete')
        operation=good['operations'][0]
        self.assertEqual(operation['audioRestartToFirstFrameMs'],2.5)
        self.assertEqual(operation['stopRequestToFirstFrameMs'],8.5)
        self.assertEqual(operation['storeMs'],1)
        self.assertEqual(operation['firstResumedSequence'],2)
        self.assertEqual(operation['resumeOrder'],'before_store')
        bad=copy.deepcopy(report)
        bad['savePhaseEvents'][5],bad['savePhaseEvents'][6]=bad['savePhaseEvents'][6],bad['savePhaseEvents'][5]
        self.assertEqual(module.save_phase_summary(bad)['status'],'incomplete')

    def test_save_phase_diagnostics_require_the_real_resume_frame_and_complete_order(self):
        self.assertTrue(hasattr(module,'save_phase_summary'),'Diagnostic reader must reject partial save stages')
        names=['auto.audio_stop.begin','auto.audio_stop.end','save.capture.begin','save.capture.end',
               'save.thumbnail.begin','save.thumbnail.end','save.store.begin','save.store.end',
               'auto.audio_restart.request','auto.audio_restart.submitted']
        report=dict(startedEpochMs=100,finishedEpochMs=200,savePhaseDiagnosticsEnabled=True,
                    savePhaseEvents=[dict(phase=name,monotonicNs=(i+1)*1000000,epochMs=150) for i,name in enumerate(names)],
                    coreFrameEvents=[[1,500000,149],[2,12000000,151]])
        good=module.save_phase_summary(report)
        self.assertEqual(good['status'],'complete')
        self.assertEqual(good['operations'][0]['audioRestartToFirstFrameMs'],3)
        self.assertEqual(good['operations'][0]['audioStopMs'],1)
        bad=copy.deepcopy(report);bad['coreFrameEvents']=bad['coreFrameEvents'][:1]
        self.assertEqual(module.save_phase_summary(bad)['status'],'incomplete')
        bad=copy.deepcopy(report);del bad['savePhaseEvents'][4]
        self.assertEqual(module.save_phase_summary(bad)['status'],'incomplete')
        bad=copy.deepcopy(report);bad['savePhaseEvents'][3]['monotonicNs']=1
        self.assertEqual(module.save_phase_summary(bad)['status'],'incomplete')


if __name__ == '__main__': unittest.main()
