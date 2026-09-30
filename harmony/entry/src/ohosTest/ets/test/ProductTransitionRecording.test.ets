import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { Driver, ON } from '@ohos.UiTest';

/** Explicit test recording of the task app; system capture consent is not bypassed. */
export default function productTransitionRecordingTest() {
  const args = abilityDelegatorRegistry.getArguments().parameters;
  describe('ProductTransitionRecording', () => {
    it('records_actual_native_handoffs_with_microphone_disabled', 0, async () => {
      const label = args['-s transitionRecording'] ?? '';
      expect(/^[a-z0-9-]{1,40}$/.test(label)).assertTrue();
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const driver = Driver.create();
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000) !== null).assertTrue();
      const context = (await delegator.getCurrentTopAbility()).context;
      const path = `${context.filesDir}/g2-transitions-${label}.mp4`;
      expect(fileIo.accessSync(path)).assertFalse();
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      let recorder: media.AVScreenCaptureRecorder | undefined;
      let started = false;
      let stopped = false;
      try {
        recorder = await media.createAVScreenCaptureRecorder();
        recorder.on('stateChange', (state: media.AVScreenCaptureStateCode) => {
          console.info(`FlyNES G2 capture state=${state} epochMs=${Date.now()}`);
          if (state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_STARTED) started = true;
        });
        recorder.on('error', (error) => {
          console.error(`FlyNES G2 capture ERROR code=${error.code} message=${error.message}`);
        });
        await recorder.init({ fd: file.fd, frameWidth: 1280, frameHeight: 720, videoBitrate: 6000000 });
        await recorder.setMicEnabled(false);
        await recorder.startRecording();
        // This fixture is explicitly invoked for the user's screenshot/animation
        // audit. Operate the real system consent, without bypassing its API.
        const consent = await driver.waitForComponent(ON.text('允许'), 10000);
        expect(consent !== null).assertTrue();
        if (consent !== null) await consent.click();
        for (let index = 0; index < 1200 && !started; index++) await driver.delayMs(100);
        expect(started).assertTrue();
        console.info(`FlyNES G2 capture READY path=${path} epochMs=${Date.now()}`);
        await driver.delayMs(90000);
        await recorder.stopRecording();
        stopped = true;
      } finally {
        try {
          if (recorder !== undefined) {
            try { if (started && !stopped) await recorder.stopRecording(); }
            finally { await recorder.release(); }
          }
        } finally { fileIo.closeSync(file.fd); }
      }
      expect(fileIo.statSync(path).size > 10000).assertTrue();
      console.info(`FlyNES G2 capture COMPLETE path=${path} bytes=${fileIo.statSync(path).size}`);
    });
  });
}
