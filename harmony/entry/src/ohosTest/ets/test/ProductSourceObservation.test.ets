import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Driver, ON } from '@ohos.UiTest';
import { fileIo } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import nativeApp from 'libentry.so';
import { ProductStartupObservation } from '../../../main/ets/service/ProductStartupObservation';
import { PlayService, RomLaunchLocator } from '../../../main/ets/service/PlayService';
import { productMap } from '../../../main/ets/flutter/ProductPolicy';

/** Observes real UI-created sources. Never registers sources, grants or copies ROMs. */
export default function productSourceObservationTest() {
  const args = abilityDelegatorRegistry.getArguments().parameters;
  describe('ProductSourceObservation', () => {
    it('records_real_source_catalog_and_content_identity', 0, async () => {
      const label = args['-s sourceObservationLabel'] ?? '';
      expect(/^[a-z0-9-]{1,40}$/.test(label)).assertTrue();
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      const driver = Driver.create();
      expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000) !== null).assertTrue();
      for (let i = 0; i < 150 && ProductStartupObservation.catalogReadyMs < 0; i++) await driver.delayMs(100);
      expect(ProductStartupObservation.catalogReadyMs >= 0).assertTrue();
      const context = (await delegator.getCurrentTopAbility()).context;
      const catalog = nativeApp.catalogSnapshot();
      const rows = catalog.filter((r) => r.sourceRelativePath.startsWith('g2-source-20260930'));
      const sourceMap = await preferences.getPreferences(context, 'flynes_source_uuids');
      const states = rows.map((r) => nativeApp.catalogUserStateGet(r.canonicalId));
      const retainedId = args['-s sourceObservationCanonicalId'] ?? '';
      if (retainedId.length > 0) {
        expect(/^game:[A-Fa-f0-9]{64}$/.test(retainedId)).assertTrue();
        states.push(nativeApp.catalogUserStateGet(retainedId));
      }
      const contentKeys: string[] = [];
      for (const row of rows) {
        const locator = new RomLaunchLocator(); locator.canonicalId = row.canonicalId;
        locator.sourceUuidHex = row.sourceUuidHex; locator.sourceRelativePath = row.sourceRelativePath;
        locator.packageFormat = row.packageFormat; locator.zipEntryName = row.originalFilename;
        contentKeys.push(nativeApp.historyContentKey(await new PlayService().readRom(context, locator)));
      }
      const result = productMap([['label', label], ['rows', rows], ['states', states], ['retainedId', retainedId],
        ['scanFixtureRows', catalog.filter((r) => r.sourceRelativePath.startsWith('g2-scan-load-20260930-')).length],
        ['sourceStatuses', nativeApp.sourceStatusList()], ['sourceMap', await sourceMap.get('source_map_v1', '')],
        ['contentKeys', contentKeys], ['folderCapability', canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection')]]);
      const path = `${context.filesDir}/g2-source-${label}.json`;
      expect(fileIo.accessSync(path)).assertFalse();
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try { fileIo.writeSync(file.fd, JSON.stringify(result)); fileIo.fsyncSync(file.fd); } finally { fileIo.closeSync(file.fd); }
      console.info(`FlyNES G2 source observation=${path} rows=${rows.length} folderCapability=${result['folderCapability']}`);
    });
  });
}
