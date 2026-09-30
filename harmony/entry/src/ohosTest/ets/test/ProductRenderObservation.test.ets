import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Driver, ON } from '@ohos.UiTest';
import { fileIo } from '@kit.CoreFileKit';
import nativeApp from 'libentry.so';
import { launchNormalHall, pauseCommand } from './ProductG2.test';

/** Read-only boundary evidence: native RGB565 and actual compositor, same pause. */
export default function productRenderObservationTest() {
  const args = abilityDelegatorRegistry.getArguments().parameters;
  describe('ProductRenderObservation', () => {
    it('observes_real_core_pixels_and_presented_game_without_replacing_renderer', 0, async () => {
      const label = args['-s renderObservation'] ?? '';
      expect(/^[a-z0-9-]{1,40}$/.test(label)).assertTrue();
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const driver = Driver.create();
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      await driver.waitForComponent(ON.id('flutter_foundation_host'), 20000);
      const context = (await delegator.getCurrentTopAbility()).context;
      const root = `${context.filesDir}/g2-render-${label}`;
      expect(fileIo.accessSync(root)).assertFalse();
      fileIo.mkdirSync(root);
      const cycles = Number.parseInt(args['-s renderCycles'] ?? '1', 10);
      expect(cycles >= 1 && cycles <= 20).assertTrue();
      for (let cycle = 1; cycle <= cycles; cycle++) {
      const directory = `${root}/${cycle}`;
      fileIo.mkdirSync(directory);
      await driver.delayMs(500);
      await driver.screenCap(`${directory}/hall.png`);
      await launchNormalHall(driver);
      const pause = await driver.waitForComponent(ON.text('II'), 15000);
      await driver.screenCap(`${directory}/launched.png`);
      expect(pause !== null).assertTrue();
      let sourceReady = false;
      for (let index = 0; index < 300; index++) {
        try { sourceReady = nativeApp.playRuntimeStatus().sourceFrames >= 100; }
        catch (error) {
          if (!(error as Error).message.includes('play session is not open')) throw new Error((error as Error).message);
        }
        if (sourceReady) break;
        await driver.delayMs(50);
      }
      expect(sourceReady).assertTrue();
      const viewport = await (await driver.waitForComponent(ON.id('flynes-render-surface'), 5000)).getBounds();
      await driver.screenCap(`${directory}/running.png`);
      await pause.click();
      await driver.waitForComponent(ON.id('history-manual-save'), 5000);
      expect(nativeApp.playRuntimeStatus().paused).assertTrue();
      // Let the render mailbox finish its last pending swap after core pause.
      await driver.delayMs(300);
      const frame = nativeApp.playStep();
      const pixels = new Uint16Array(frame.rgb565);
      const colors = new Set<number>();
      for (let index = 0; index < pixels.length; index++) colors.add(pixels[index]);
      const raw = fileIo.openSync(`${directory}/core.rgb565`, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try { fileIo.writeSync(raw.fd, frame.rgb565); } finally { fileIo.closeSync(raw.fd); }
      const report = fileIo.openSync(`${directory}/boundary.json`, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try {
        fileIo.writeSync(report.fd, JSON.stringify({ width: frame.width, height: frame.height,
          cycle: cycle, viewport: viewport, distinctColors: colors.size,
          runtime: nativeApp.playRuntimeStatus(), render: nativeApp.renderStatus() }));
      } finally { fileIo.closeSync(report.fd); }
      await driver.screenCap(`${directory}/paused.png`);
      expect(colors.size > 8).assertTrue();
      console.info(`FlyNES G2 renderer boundary=${directory} distinctColors=${colors.size}`);
      await pauseCommand(driver, context, 'pause_game_center');
      expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000) !== null).assertTrue();
      }
    });
  });
}
