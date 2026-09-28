import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Driver, ON, PointerMatrix } from '@ohos.UiTest';
import nativePlay from 'libentry.so';

export default function flutterTextureProbeTest() {
  describe('FlutterTextureProbe', () => {
    it('presents_real_frames_and_audio_and_samples_two_flutter_pointers', 0, async () => {
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({ bundleName: 'com.flynes.emu',
        abilityName: 'EntryAbility', parameters: { 'flynes.test.page': 'flutter_texture_probe' } });
      const driver = Driver.create();
      await driver.waitForComponent(ON.id('flutter_texture_probe_host'), 15000);
      await driver.waitForComponent(ON.text('Detach').type('Button'), 15000);
      await driver.delayMs(2000);
      const first = nativePlay.textureProbeStats();
      console.info(`FlyNES texture first ${JSON.stringify(first)}`);
      expect(first.opened && first.attached && first.nativeReady && first.audioStarted).assertTrue();
      expect(first.sourceFrames > 30 && first.presentedFrames > 0).assertTrue();
      expect(first.audioProducedSamples > 0 && first.audioConsumedSamples > 0 && first.audioCallbackCount > 0).assertTrue();
      expect(first.presentFailures).assertEqual(0);
      await driver.delayMs(700);
      const continuing = nativePlay.textureProbeStats();
      expect(continuing.presentedFrames > first.presentedFrames).assertTrue();
      expect(continuing.audioConsumedSamples > first.audioConsumedSamples).assertTrue();
      const a = await (await driver.waitForComponent(ON.text('A').type('Button'), 5000)).getBoundsCenter();
      const b = await (await driver.waitForComponent(ON.text('B').type('Button'), 5000)).getBoundsCenter();
      const matrix = PointerMatrix.create(2, 60);
      for (let step = 0; step < 60; step++) {
        matrix.setPoint(0, step, { x: a.x + (step % 20), y: a.y });
        matrix.setPoint(1, step, { x: b.x + (step % 20), y: b.y });
      }
      let sampledBoth = false;
      const timer = setInterval(() => {
        if ((nativePlay.textureProbeStats().appliedButtons & 3) === 3) sampledBoth = true;
      }, 20);
      try { expect(await driver.injectMultiPointerAction(matrix, 200)).assertTrue(); }
      finally { clearInterval(timer); }
      expect(sampledBoth).assertTrue();
      console.info('FlyNES texture two Flutter pointers sampled together');
      await driver.delayMs(100);
      expect(nativePlay.textureProbeStats().appliedButtons).assertEqual(0);
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      await driver.screenCap(`${context.filesDir}/flutter-texture-probe.png`);
    });
    it('background_stops_source_and_audio_then_foreground_resumes', 0, async () => {
      const driver = Driver.create();
      await driver.pressHome();
      await driver.delayMs(400);
      const paused = nativePlay.textureProbeStats();
      expect(paused.paused).assertTrue();
      await driver.delayMs(400);
      expect(nativePlay.textureProbeStats().sourceFrames).assertEqual(paused.sourceFrames);
      expect(nativePlay.textureProbeStats().audioStarted).assertFalse();
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      await driver.delayMs(700);
      const resumed = nativePlay.textureProbeStats();
      expect(resumed.paused).assertFalse();
      expect(resumed.sourceFrames > paused.sourceFrames && resumed.audioStarted).assertTrue();
      expect(resumed.appliedButtons).assertEqual(0);
      console.info(`FlyNES texture resumed ${JSON.stringify(resumed)}`);
    });
    it('twenty_surface_cycles_preserve_runtime_and_stop_detached_media', 0, async () => {
      const driver = Driver.create();
      let previousFrames = nativePlay.textureProbeStats().sourceFrames;
      for (let index = 0; index < 20; index++) {
        await (await driver.waitForComponent(ON.text('Detach').type('Button'), 5000)).click();
        await driver.waitForComponent(ON.text('Attach').type('Button'), 5000);
        const detached = nativePlay.textureProbeStats();
        expect(detached.opened && !detached.attached && detached.paused).assertTrue();
        await driver.delayMs(80);
        expect(nativePlay.textureProbeStats().sourceFrames).assertEqual(detached.sourceFrames);
        expect(nativePlay.textureProbeStats().audioStarted).assertFalse();
        await (await driver.waitForComponent(ON.text('Attach').type('Button'), 5000)).click();
        await driver.waitForComponent(ON.text('Detach').type('Button'), 5000);
        await driver.delayMs(120);
        const attached = nativePlay.textureProbeStats();
        expect(attached.opened && attached.attached && attached.nativeReady).assertTrue();
        expect(attached.sourceFrames > previousFrames && attached.presentedFrames > 0).assertTrue();
        expect(attached.appliedButtons).assertEqual(0);
        previousFrames = attached.sourceFrames;
        console.info(`FlyNES texture cycle=${index + 1} ${JSON.stringify(attached)}`);
      }
      await driver.delayMs(1000);
      const settled = nativePlay.textureProbeStats();
      expect(settled.audioStarted && settled.audioConsumedSamples > 0).assertTrue();
    });
    it('closing_native_host_releases_the_experimental_runtime', 0, async () => {
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({ bundleName: 'com.flynes.emu',
        abilityName: 'EntryAbility', parameters: { 'flynes.test.page': 'flutter_foundation' } });
      const driver = Driver.create();
      await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000);
      await driver.delayMs(300);
      expect(nativePlay.textureProbeStats().opened).assertFalse();
      expect(nativePlay.textureProbeStats().attached).assertFalse();
    });
  });
}
