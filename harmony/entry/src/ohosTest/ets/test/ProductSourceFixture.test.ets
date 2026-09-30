import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo } from '@kit.CoreFileKit';
import { Driver, ON } from '@ohos.UiTest';

/** Task-only licensed ZIP copies; no catalog, permission or scan calls. */
export default function productSourceFixtureTest() {
  const phase = abilityDelegatorRegistry.getArguments().parameters['-s sourceFixtureLoad'];
  describe('ProductSourceFixture', () => {
    it('prepares_or_removes_only_the_named_scan_workload', 0, async () => {
      expect(phase === 'prepare' || phase === 'cleanup').assertTrue();
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      await Driver.create().waitForComponent(ON.id('flutter_foundation_host'), 15000);
      const context = (await delegator.getCurrentTopAbility()).context;
      const directory = `${context.filesDir}/roms`;
      const source = `${directory}/g2-source-20260930.zip`;
      expect(fileIo.accessSync(source)).assertTrue();
      if (phase === 'prepare') {
        // Preflight every destination before creating any task file.
        for (let index = 1; index <= 400; index++) {
          expect(fileIo.accessSync(`${directory}/g2-scan-load-20260930-${index}.zip`)).assertFalse();
        }
        for (let index = 1; index <= 400; index++) {
          fileIo.copyFileSync(source, `${directory}/g2-scan-load-20260930-${index}.zip`);
        }
      } else {
        for (let index = 1; index <= 400; index++) {
          const path = `${directory}/g2-scan-load-20260930-${index}.zip`;
          if (fileIo.accessSync(path)) fileIo.unlinkSync(path);
        }
      }
      expect(fileIo.accessSync(source)).assertTrue();
      expect(fileIo.accessSync(`${directory}/g2-source-20260930.nes`)).assertTrue();
    });
  });
}
