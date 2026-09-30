"""Strict G2 Release paired evidence validation; collection is explicitly opt-in.

Never installs, builds, clears data/logs, signs, seeds ROMs, or changes device settings.
The instrumentation restores its temporary navigation/autosave preferences. Real
AUTO history and ordinary gameplay records remain legitimate product writes.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from summarize_save_performance import summarize, distribution

PACKAGE = 'com.flynes.emu'
RUNNER = PACKAGE + '.test/' + PACKAGE + '.test.SingleDeviceCertificationRunner'
FILES = '/sdcard/Android/data/' + PACKAGE + '/files/'


def common_errors(report, route):
    errors = []
    for key, expected in [('result', 'PASS'), ('targetDebuggable', False), ('preferencesRestored', True),
                          ('engineBefore', False)]:
        if key not in report or report[key] != expected:
            errors.append(key)
    if route == 'native' and report.get('engineAfter') is not False:
        errors.append('native_initialized_flutter')
    if route == 'flutter' and report.get('engineAfter') is not True:
        errors.append('flutter_engine_absent')
    return errors


def startup_errors(report):
    errors = common_errors(report, report.get('route'))
    ready = report.get('nativeOwnerReady') or {}
    if (ready.get('pid') != report.get('pid') or ready.get('generation') != report.get('nativeGenerationAtEnd')
            or not isinstance(ready.get('elapsedRealtimeMs'), (int, float))):
        errors.append('native_owner_event_missing_or_wrong_identity')
    for field in ['primaryInteractive', 'firstVisibleCard']:
        if not isinstance(report.get(field, {}).get('sinceProcessMs'), (int, float)):
            errors.append(field)
    if not report.get('nativeSnapshotCountAtEnd', 0) > 0:
        errors.append('empty_catalog')
    if report.get('schema',2)>=3:
        draw=(report.get('hostFirstDraw') or {}).get('elapsedRealtimeMs')
        started=report.get('observerStartedElapsedRealtimeMs')
        for field in ('primaryInteractive','firstVisibleCard'):
            observed=report.get(field,{}).get('elapsedRealtimeMs')
            current_draw=report.get('primaryHostDrawElapsedRealtimeMs' if field=='primaryInteractive' else 'cardHostDrawElapsedRealtimeMs')
            if (not all(isinstance(value,(int,float)) and not isinstance(value,bool) and value>0
                        for value in (draw,started,observed,current_draw))
                    or observed<draw or observed<started or observed<current_draw):
                errors.append('parallel_observation_or_host_draw_missing')
                break
        if report.get('hostsDestroyedBeforePreferenceRestore') is not True or report.get('audioOwnersAfterCleanup')!=0:
            errors.append('startup_owner_cleanup_unproven')
    return errors


def cohort_errors(samples):
    errors = []
    if sum(row.get('kind') == 'warmup' for row in samples) != 2:
        errors.append('requires_two_warmups')
    if sum(row.get('kind') == 'measured' for row in samples) != 12:
        errors.append('requires_twelve_measured')
    pids = [row.get('pid') for row in samples]
    if None in pids or len(set(pids)) != len(pids):
        errors.append('not_distinct_cold_processes')
    return errors


def save_errors(report, summary):
    errors = common_errors(report, report.get('entry'))
    if report.get('playedMs', 0) < 65000 or report.get('intervalMs') != 60000:
        errors.append('actual_65s_and_60s_auto_required')
    if not report.get('automaticSaves') or not report.get('contentKey') or not report.get('requestedCanonicalId'):
        errors.append('actual_auto_and_explicit_content_required')
    if not summary.get('captureComplete') or summary.get('invalidFrameGapCount') != 0:
        errors.append('invalid_frame_capture')
    if summary.get('saveWindowCoreGapMs', {}).get('max') is None:
        errors.append('save_window_unobserved')
    if summary.get('softwareTouchToCoreMs', {}).get('count', 0) < 1:
        errors.append('no_real_input_samples')
    if summary.get('observedUnderrunIncrementsLowerBound') is None:
        errors.append('audio_counter_unavailable')
    rows = report.get('memoryAndAudio', [])
    if any(row.get('runtimeFailures', -1) != 0 for row in rows):
        errors.append('renderer_failure_or_missing')
    heads = [row.get('audioPlaybackFrames', -1) for row in rows]
    audio_complete=all(isinstance(row.get(field),int) and not isinstance(row.get(field),bool) and row[field]>=0
                       for row in rows for field in ('audioPlaybackFrames','audioUnderruns'))
    if not audio_complete:
        errors.append('audio_samples_incomplete')
    if len(heads) < 2 or audio_complete and not any(b > a >= 0 for a, b in zip(heads, heads[1:])):
        errors.append('audio_playback_not_advancing')
    if audio_complete and any(a==b for a,b in zip(heads,heads[1:])):
        errors.append('audio_playback_stalled')
    return errors


def heap_growth(checkpoints):
    selected = {row.get('cycle'): row for row in checkpoints}
    if not all(cycle in selected for cycle in (5, 20)):
        return dict(status='blocked', reason='missing_5_or_20_checkpoint')
    for cycle in (5, 20):
        row = selected[cycle]
        if (row.get('gcBefore', -1) < 0 or row.get('gcAfter', -1) <= row['gcBefore']
                or row.get('weakMarkerCleared') is not True or row.get('javaUsedBytes', -1) < 0):
            return dict(status='blocked', reason='collection_completion_unproven')
    growth = selected[20]['javaUsedBytes'] - selected[5]['javaUsedBytes']
    return dict(status='pass' if growth <= 16*1024*1024 else 'fail', growthBytes=growth,
                limitBytes=16*1024*1024, scope='ART used heap after verified GC; not Dart/native/PSS')


def save_phase_summary(report):
    if report.get('savePhaseDiagnosticsEnabled') is not True:return dict(status='disabled')
    names=['auto.audio_stop.begin','auto.audio_stop.end','save.capture.begin','save.capture.end',
           'save.thumbnail.begin','save.thumbnail.end','save.store.begin','save.store.end',
           'auto.audio_restart.request','auto.audio_restart.submitted']
    early_resume=names[:6]+names[8:]+names[6:8]
    events=[row for row in report.get('savePhaseEvents',[])
            if report.get('startedEpochMs',math.inf)<=row.get('epochMs',-1)<=report.get('finishedEpochMs',-math.inf)]
    operations=[]
    for index,event in enumerate(events):
        if event.get('phase')!=names[0]:continue
        group=events[index:index+len(names)]
        stamps=[row.get('monotonicNs') for row in group]
        order=[row.get('phase') for row in group]
        if (order not in (names,early_resume)
                or not all(isinstance(n,int) and not isinstance(n,bool) and n>0 for n in stamps)
                or any(b<a for a,b in zip(stamps,stamps[1:]))):
            return dict(status='incomplete',reason='missing_or_unordered_stages',operations=operations)
        stamp={row['phase']:row['monotonicNs'] for row in group}
        restart=stamp['auto.audio_restart.request']
        frame=next((row for row in report.get('coreFrameEvents',[]) if row[1]>=restart),None)
        if frame is None:return dict(status='incomplete',reason='no_real_resumed_core_frame',operations=operations)
        operations.append(dict(audioStopMs=(stamps[1]-stamps[0])/1e6,captureMs=(stamps[3]-stamps[2])/1e6,
            thumbnailMs=(stamps[5]-stamps[4])/1e6,storeMs=(stamp['save.store.end']-stamp['save.store.begin'])/1e6,
            resumeOrder='before_store' if order==early_resume else 'after_store',
            audioRestartToFirstFrameMs=(frame[1]-restart)/1e6,stopRequestToFirstFrameMs=(frame[1]-stamps[0])/1e6,
            firstResumedSequence=frame[0],stopRequestMonotonicNs=stamps[0]))
    return dict(status='complete' if operations else 'incomplete',operations=operations,
                scope='Opt-in software stages, includes diagnostic overhead; does not change paired performance limits')


def paired_startup(routes):
    errors=[]; metrics={}
    if len({row.get('schema',2) for samples in routes.values() for row in samples})>1:
        errors.append('different_observation_boundary')
    for route, samples in routes.items():
        errors.extend(route + ':' + item for item in cohort_errors(samples))
        for row in samples:
            errors.extend(route + ':' + item for item in startup_errors(row))
        measured=[row for row in samples if row['kind']=='measured']
        metrics[route]={field:distribution([row.get(field,{}).get(clock) for row in measured])
                        for field,clock in [('primaryInteractive','sinceProcessMs'),('nativeOwnerReady','sinceProcessMs')]}
        metrics[route]['interactiveSinceRequest']=distribution([row.get('primaryInteractive',{}).get('sinceActivityRequestMs') for row in measured])
    counts={row.get('nativeSnapshotCountAtEnd') for values in routes.values() for row in values}
    if len(counts)!=1: errors.append('catalog_counts_differ')
    result=dict(valid=not errors, errors=errors, metrics=metrics, budgetVersion='G1 formulas; paired G2 Release native values')
    if not errors and set(routes)=={'native','flutter'}:
        n,f=metrics['native'],metrics['flutter']
        limits=dict(interactiveProcessMs=n['primaryInteractive']['p95']+1500, interactiveRequestMs=4000,
                    nativeReadyProcessMs=n['nativeOwnerReady']['p95']*1.1+100)
        result['limits']=limits
        result['pass']=(f['primaryInteractive']['p95']<=limits['interactiveProcessMs']
                        and f['interactiveSinceRequest']['p95']<=4000
                        and f['nativeOwnerReady']['p95']<=limits['nativeReadyProcessMs'])
    return result


def paired_save(reports, logs):
    summaries={route:summarize(report,logs[route]) for route,report in reports.items()}
    for route,report in reports.items():
        heads=[row.get('audioPlaybackFrames',-1) for row in report.get('memoryAndAudio',[])]
        summaries[route]['audioPlaybackHeadResetCount']=sum(
            isinstance(a,int) and isinstance(b,int) and not isinstance(a,bool) and not isinstance(b,bool) and 0<=b<a
            for a,b in zip(heads,heads[1:]))
    errors=[route+':'+error for route,report in reports.items() for error in save_errors(report,summaries[route])]
    if len({r.get('contentKey') for r in reports.values()})!=1: errors.append('different_content')
    if len({r.get('requestedCanonicalId') for r in reports.values()})!=1: errors.append('different_canonical')
    # Permit only the one ordinary record produced by the earlier paired run.
    if max(r.get('recordsBefore',0) for r in reports.values())-min(r.get('recordsBefore',0) for r in reports.values())>2:
        errors.append('history_scale_changed')
    result=dict(valid=not errors,errors=errors,summaries=summaries)
    if not errors:
        n,f=summaries['native'],summaries['flutter']
        limits=dict(pssKb=n['pssKb']['p95']+128*1024,coreGapP95Ms=n['coreFrameGapMs']['p95']*1.1+2,
                    saveWindowMaxMs=n['saveWindowCoreGapMs']['max']+16.7,
                    inputP95Ms=n['softwareTouchToCoreMs']['p95']+16.7,observedUnderrunIncrementsLowerBound=0)
        result['limits']=limits
        result['pass']=(f['pssKb']['p95']<=limits['pssKb'] and f['coreFrameGapMs']['p95']<=limits['coreGapP95Ms']
                        and f['saveWindowCoreGapMs']['max']<=limits['saveWindowMaxMs']
                        and f['softwareTouchToCoreMs']['p95']<=limits['inputP95Ms']
                        and n['observedUnderrunIncrementsLowerBound']==0 and f['observedUnderrunIncrementsLowerBound']==0)
    return result


def write_json(path, value):
    path.write_text(json.dumps(value,indent=2),encoding='utf-8')


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def collect(args):
    if not args.allow_device_collection: raise ValueError('Collection requires explicit quiet-slot opt-in')
    if args.serial!='emulator-5582': raise ValueError('This task collector is scoped to emulator-5582')
    args.output.mkdir(parents=True,exist_ok=False)
    def adb(*command, timeout=30):
        run=subprocess.run([args.adb,'-s',args.serial,*command],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout)
        if run.returncode: raise RuntimeError('adb failed: '+run.stderr)
        return run.stdout
    paths=adb('shell','pm','path',PACKAGE).strip().splitlines()
    if len(paths)!=1 or not paths[0].startswith('package:'): raise ValueError('Expected one universal installed APK')
    installed=args.output/'installed-main.apk';adb('pull',paths[0][8:],str(installed))
    if sha(installed)!=sha(args.apk): raise ValueError('Installed APK differs from frozen artifact')
    manifest=dict(mainSha256=sha(args.apk),testSha256=sha(args.test_apk),serial=args.serial,
                  warmups=2,measured=12,mode='require actual non-debuggable target',collectionStarted=time.time(),
                  savePhaseDiagnostics=args.save_phase_diagnostics,
                  quietSlotDeclared=True,dartHeap='unavailable in Release',status='incomplete')
    manifest['device']=dict(fingerprint=adb('shell','getprop','ro.build.fingerprint').strip(),
                            fontScale=adb('shell','settings','get','system','font_scale').strip(),
                            locale=adb('shell','getprop','persist.sys.locale').strip(),
                            display=adb('shell','wm','size').strip())
    (args.output/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    test_paths=adb('shell','pm','path',PACKAGE+'.test').strip().splitlines()
    if len(test_paths)!=1: raise ValueError('Expected one installed test APK')
    installed_test=args.output/'installed-test.apk';adb('pull',test_paths[0][8:],str(installed_test))
    if sha(installed_test)!=sha(args.test_apk): raise ValueError('Installed test APK differs from frozen artifact')
    def run_one(label, klass, flags, pattern, timeout):
        adb('shell','am','force-stop',PACKAGE)
        if adb('shell','pidof '+PACKAGE+' || true').strip(): raise ValueError('Not process cold')
        before=set(adb('shell','ls '+FILES+pattern+' 2>/dev/null || true').split())
        began=int(adb('shell','date','+%s').strip())*1000
        command=['shell','am','instrument','-w','-r','-e','class',PACKAGE+'.'+klass,'-e','g2Release','true']
        for key,value in flags.items(): command+=['-e',key,str(value)]
        text=adb(*command,RUNNER,timeout=timeout)
        (args.output/(label+'.instrumentation.log')).write_text(text,encoding='utf-8')
        logs=adb('logcat','-d','-v','epoch','-s','FlyNES','FlyNesStartup')
        (args.output/(label+'.logcat')).write_text(logs,encoding='utf-8')
        after=set(adb('shell','ls '+FILES+pattern+' 2>/dev/null || true').split())
        candidates=sorted(after-before) if '*' in pattern else list(after)
        if len(candidates)!=1: raise ValueError('Missing or ambiguous fresh evidence '+label)
        path=args.output/(label+'.json');adb('pull',candidates[0],str(path))
        report=json.loads(path.read_text(encoding='utf-8'))
        if 'OK (1 test)' not in text or re.search('FAILURES!!!|Process crashed|INSTRUMENTATION_FAILED',text):
            raise ValueError('Instrumentation failure: '+label)
        if pattern.startswith('g1-') and 'save' in pattern and report.get('startedEpochMs',0)<began-1000:
            raise ValueError('Stale save evidence')
        return report,logs
    try:
        if args.phase in ('all','startup'):
            routes={}
            for route in ('native','flutter'):
                samples=[]
                for index in range(14):
                    report,_=run_one(f'startup-{route}-{index:02}', 'G1StartupObservationTest',
                        dict(g1StartupObservation='true',g1StartupRoute=route,g1ExpectedSelectedCanonicalId=args.canonical_id),
                        'g1-startup-'+route+'-*.json',60)
                    report['kind']='warmup' if index<2 else 'measured';samples.append(report)
                    if startup_errors(report): raise ValueError(str(startup_errors(report)))
                routes[route]=samples
                if route=='native':
                    native=paired_startup(routes)
                    if not native['valid']: raise ValueError(str(native['errors']))
                    metrics=native['metrics']['native']
                    write_json(args.output/'startup-budget-before-flutter.json',dict(
                        native=metrics,interactiveProcessMs=metrics['primaryInteractive']['p95']+1500,
                        interactiveRequestMs=4000,nativeReadyProcessMs=metrics['nativeOwnerReady']['p95']*1.1+100))
            (args.output/'startup-summary.json').write_text(json.dumps(paired_startup(routes),indent=2),encoding='utf-8')
        if args.phase in ('all','save'):
            reports={};logs={}
            for route in ('native','flutter'):
                flags=dict(g1NativePerformance='true',g1Entry=route,g1CanonicalId=args.canonical_id,g1ExpectedContentKey=args.content_key)
                if args.save_phase_diagnostics:flags['g2SavePhaseDiagnostics']='true'
                reports[route],logs[route]=run_one('save-'+route,'G1NativeSavePerformanceTest',
                    flags,
                    'g1-'+route+'-save-performance.json',190)
                observed=summarize(reports[route],logs[route])
                if args.save_phase_diagnostics:
                    write_json(args.output/('save-'+route+'-phases.json'),save_phase_summary(reports[route]))
                errors=save_errors(reports[route],observed)
                write_json(args.output/('save-'+route+'-validity.json'),dict(errors=errors,summary=observed))
                if errors: raise ValueError(str(errors))
                if route=='native':
                    write_json(args.output/'save-budget-before-flutter.json',dict(
                        native=observed,pssKb=observed['pssKb']['p95']+128*1024,
                        coreGapP95Ms=observed['coreFrameGapMs']['p95']*1.1+2,
                        saveWindowMaxMs=observed['saveWindowCoreGapMs']['max']+16.7,
                        inputP95Ms=observed['softwareTouchToCoreMs']['p95']+16.7,
                        observedUnderrunIncrementsLowerBound=0))
            (args.output/'save-summary.json').write_text(json.dumps(paired_save(reports,logs),indent=2),encoding='utf-8')
        if args.phase in ('all','memory'):
            results={}
            for route in ('flutter',):
                report,_=run_one('memory-'+route,'G2ReleaseMemoryTest',
                    dict(g2Memory='true',g1Entry=route,g1CanonicalId=args.canonical_id), 'g2-memory-'+route+'-*.json',300)
                errors=common_errors(report,route)
                results[route]=dict(errors=errors,heap=heap_growth(report.get('checkpoints',[])),
                                    pssKb=distribution([row.get('pssKb') for row in report.get('cycles',[])]),
                                    dartHeap='unavailable: Release VM service disabled',native='see raw per-cycle nativeHeapBytes')
            (args.output/'memory-summary.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
        manifest['status']='collected; inspect separate validity and budget outcomes'
    finally:
        adb('shell','am','force-stop',PACKAGE)
        manifest['collectionFinished']=time.time()
        (args.output/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial',required=True);parser.add_argument('--adb',default='adb')
    parser.add_argument('--apk',required=True,type=Path);parser.add_argument('--test-apk',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path);parser.add_argument('--canonical-id',required=True)
    parser.add_argument('--content-key',required=True);parser.add_argument('--phase',choices=['all','startup','save','memory'],default='all')
    parser.add_argument('--allow-device-collection',action='store_true')
    parser.add_argument('--save-phase-diagnostics',action='store_true',help='Opt-in bounded save-stage monotonic diagnostics on both routes; requires matching diagnostic main')
    collect(parser.parse_args())


if __name__=='__main__': main()
