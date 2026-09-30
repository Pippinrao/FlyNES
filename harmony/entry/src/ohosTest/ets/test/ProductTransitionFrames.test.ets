import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo } from '@kit.CoreFileKit';
import { window } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { Component, Driver, ON } from '@ohos.UiTest';
import { launchNormalHall, pauseCommand } from './ProductG2.test';
import nativeApp from 'libentry.so';

interface CapturedFrame { file: string; requestedMs: number; completedMs: number; }

/** Public compositor snapshots; timestamped samples, never represented as 60fps video. */
export default function productTransitionFramesTest() {
  const args = abilityDelegatorRegistry.getArguments().parameters;
  describe('ProductTransitionFrames', () => {
    it('captures_visible_frames_during_a_real_native_handoff', 0, async () => {
      const label = args['-s transitionFrames'] ?? '';
      const action = args['-s transitionAction'] ?? '';
      expect(/^[a-z0-9-]{1,40}$/.test(label)).assertTrue();
      expect(action.length > 0).assertTrue();
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const driver = Driver.create();
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      await driver.waitForComponent(ON.id('flutter_foundation_host'), 20000);
      await driver.delayMs(500);
      const context = (await delegator.getCurrentTopAbility()).context;
      let button: Component | null = null;
      const setup = args['-s transitionSetup'];
      if (setup === 'pause' || setup === 'settings') {
        await launchNormalHall(driver);
        await driver.waitForComponent(ON.text('II'), 15000);
        for (let attempt = 0; attempt < 100 && nativeApp.playRuntimeStatus().sourceFrames < 20; attempt++) {
          await driver.delayMs(50);
        }
        expect(nativeApp.playRuntimeStatus().sourceFrames >= 20).assertTrue();
        if (setup === 'settings') {
          await pauseCommand(driver, context, 'pause_settings');
          button = await driver.waitForComponent(ON.text(action), 15000);
        } else {
          await (await driver.waitForComponent(ON.text('II'), 15000)).click();
          await driver.waitForComponent(ON.id('history-manual-save'), 5000);
          await driver.delayMs(300);
          const drawer = await driver.waitForComponent(ON.type('Scroll'), 5000);
          button = await drawer.scrollSearch(ON.text(action), true, 200);
          await driver.delayMs(300);
        }
      } else button = await driver.waitForComponent(ON.text(action), 30000);
      expect(button !== null).assertTrue();
      const directory = `${context.filesDir}/g2-frames-${label}`;
      expect(fileIo.accessSync(directory)).assertFalse();
      fileIo.mkdirSync(directory);
      const surface = await window.getLastWindow(context);
      const packer = image.createImagePacker();
      const frames: CapturedFrame[] = [];
      const start = Date.now();
      let actionPending: Promise<void> | undefined;
      try {
        for (let index = 0; index < 36; index++) {
          const requestedMs = Date.now() - start;
          const pixels = await surface.snapshot();
          const completedMs = Date.now() - start;
          const name = `${index}.png`;
          const file = fileIo.openSync(`${directory}/${name}`, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
          try { await packer.packToFile(pixels, file.fd, { format: 'image/png', quality: 100 }); }
          finally { fileIo.closeSync(file.fd); await pixels.release(); }
          frames.push({ file: name, requestedMs: requestedMs, completedMs: completedMs });
          if (index === 0 && button !== null) actionPending = button.click();
          await new Promise<void>((resolve) => { setTimeout(resolve, 16); });
        }
        if (actionPending !== undefined) await actionPending;
      } finally {
        await packer.release();
        const manifest = fileIo.openSync(`${directory}/manifest.json`, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
        try { fileIo.writeSync(manifest.fd, JSON.stringify(frames)); }
        finally { fileIo.closeSync(manifest.fd); }
      }
      expect(frames.length).assertEqual(36);
      await driver.screenCap(`${directory}/system-after.png`);
      if (args['-s transitionReadCore'] === 'true') {
        const frame = nativeApp.playStep();
        const raw = fileIo.openSync(`${directory}/core-after.rgb565`, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
        try { fileIo.writeSync(raw.fd, frame.rgb565); } finally { fileIo.closeSync(raw.fd); }
        const state = fileIo.openSync(`${directory}/runtime-after.json`, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
        try { fileIo.writeSync(state.fd, JSON.stringify(nativeApp.playRuntimeStatus())); }
        finally { fileIo.closeSync(state.fd); }
      }
      console.info(`FlyNES G2 actual frames=${directory} durationMs=${Date.now() - start}`);
    });
  });
}
