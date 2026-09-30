import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { Driver, ON } from '@ohos.UiTest';
import process from '@ohos.process';
import nativeApp, { SettingsDto } from 'libentry.so';
import { ProductCatalog } from '../../../main/ets/flutter/ProductCatalog';
import { ProductSources } from '../../../main/ets/flutter/ProductSources';
import { PlayService, RomLaunchLocator } from '../../../main/ets/service/PlayService';
import { retentionCleanup } from './ProductRetentionCleanup';
import { NavigationEntry, saveNavigation, restoreNavigation, writeEvidence, normalHall,
  assertNoGameOrRoom, textControl } from './ProductRetentionFixture';

class SourceProof {
  canonicalId: string = '';
  uuid: string = '';
  relativePath: string = '';
  packageFormat: number = 0;
  originalFilename: string = '';
  contentKey: string = '';
}
class ProcessProof {
  schemaVersion: number = 1;
  seedPid: number = 0;
  verifyPid: number = 0;
  originalNavigation: NavigationEntry[] = [];
  seededNavigation: NavigationEntry[] = [];
  originalSettings: SettingsDto | undefined = undefined;
  seededSettings: string = '';
  sourceMap: string = '';
  sources: string = '';
  content: SourceProof = new SourceProof();
  titleEn: string = '';
  titleZhHans: string = '';
  verified: boolean = false;
  restored: boolean = false;
  failure: string = '';
  cleanupErrors: string[] = [];
}

async function sources(context: common.UIAbilityContext): Promise<string> {
  const result = await new ProductSources(context, () => {}).list();
  const rows = result['items'] as Record<string, Object>[];
  rows.sort((a, b) => String(a['uuid']).localeCompare(String(b['uuid'])));
  return JSON.stringify(rows);
}
async function contentProof(context: common.UIAbilityContext, proof?: SourceProof): Promise<SourceProof> {
  const row = nativeApp.catalogSnapshot().find((candidate) => !candidate.builtin &&
    (proof === undefined ? candidate.sourceRelativePath.startsWith('g2-source-20260930') :
      candidate.canonicalId === proof.canonicalId && candidate.sourceUuidHex === proof.uuid &&
      candidate.sourceRelativePath === proof.relativePath));
  if (row === undefined) throw new Error('Real picker-imported source fixture is required; no substitute is imported');
  const locator = new RomLaunchLocator(); locator.canonicalId = row.canonicalId;
  locator.sourceUuidHex = row.sourceUuidHex; locator.sourceRelativePath = row.sourceRelativePath;
  locator.packageFormat = row.packageFormat; locator.zipEntryName = row.originalFilename;
  const result = new SourceProof(); result.canonicalId = row.canonicalId; result.uuid = row.sourceUuidHex;
  result.relativePath = row.sourceRelativePath; result.packageFormat = row.packageFormat;
  result.originalFilename = row.originalFilename;
  result.contentKey = nativeApp.historyContentKey(await new PlayService().readRom(context, locator));
  expect(result.contentKey.length > 0).assertTrue(); return result;
}

/** External runner must force-stop and start the ordinary launcher between seed and verify.
 * This cold Hypium process is a separate observation from that launcher PID, never a substitute. */
export default function productProcessRetentionTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters;
  const phase = args['-s productRetentionPhase'];
  const run = args['-s productRetentionRun'] ?? '';
  describe('ProductProcessRetention', () => {
    it(`real_product_storage_${phase}`, 0, async () => {
      expect(['seed', 'verify', 'cleanup'].includes(phase)).assertTrue();
      expect(/^[a-z0-9-]{1,40}$/.test(run)).assertTrue();
      const driver = Driver.create(); const context = await normalHall(driver);
      const path = `${context.filesDir}/g2-retention-${run}.json`;
      const sourceStore = preferences.getPreferencesSync(context, { name: 'flynes_source_uuids' });
      let proof = new ProcessProof();
      if (phase === 'seed') {
        expect(fileIo.accessSync(path)).assertFalse();
        proof.seedPid = process.pid; proof.originalNavigation = saveNavigation(context);
        proof.originalSettings = nativeApp.settingsGet();
        proof.sourceMap = sourceStore.getSync('source_map_v1', '') as string;
        proof.sources = await sources(context); proof.content = await contentProof(context);
        writeEvidence(path, proof); // Durable original values before the first mutation.
        try {
          assertNoGameOrRoom();
          const catalog = new ProductCatalog(context);
          const projection = await catalog.query('builtin', '', true, '');
          const rows = projection['items'] as Record<string, Object>[];
          expect(rows.length >= 2).assertTrue();
          const selected = rows[rows.length - 1];
          proof.titleEn = selected['titleEn'] as string; proof.titleZhHans = selected['titleZhHans'] as string;
          const nav = preferences.getPreferencesSync(context, { name: 'game_center_ui' });
          nav.putSync('category', 'builtin'); nav.putSync('multiplayerOnly', true);
          for (const key of ['all', 'recent', 'favorites', 'builtin']) {
            nav.putSync(`selected.${key}`, selected['canonicalId'] as string);
          }
          await nav.flush();
          const settings = nativeApp.settingsGet();
          settings.audioEnabled = settings.audioEnabled === 1 ? 0 : 1;
          settings.autosaveEnabled = settings.autosaveEnabled === 1 ? 0 : 1;
          nativeApp.settingsApply(settings);
          proof.seededNavigation = saveNavigation(context);
          proof.seededSettings = JSON.stringify(nativeApp.settingsGet());
        } catch (error) {
          proof.failure = String(error);
          proof.cleanupErrors = await restore(context, proof);
          throw new Error(proof.failure);
        } finally { writeEvidence(path, proof); }
      } else {
        proof = JSON.parse(fileIo.readTextSync(path)) as ProcessProof;
        try {
          if (phase === 'cleanup') {
            proof.cleanupErrors = await restore(context, proof);
            expect(proof.cleanupErrors.length).assertEqual(0); proof.restored = true;
          } else {
            proof.verifyPid = process.pid;
            expect(proof.verifyPid !== proof.seedPid).assertTrue();
            expect(JSON.stringify(saveNavigation(context))).assertEqual(JSON.stringify(proof.seededNavigation));
            expect(JSON.stringify(nativeApp.settingsGet())).assertEqual(proof.seededSettings);
            expect(sourceStore.getSync('source_map_v1', '') as string).assertEqual(proof.sourceMap);
            expect(await sources(context)).assertEqual(proof.sources);
            expect(JSON.stringify(await contentProof(context, proof.content))).assertEqual(JSON.stringify(proof.content));
            assertNoGameOrRoom();
            await textControl(driver, [proof.titleEn, proof.titleZhHans]);
            const toggle = await textControl(driver, ['Two-player', '双人支持'], 'Toggle');
            expect(await toggle.isChecked()).assertTrue();
            expect(await driver.screenCap(`${context.filesDir}/g2-retention-${run}-verified.png`)).assertTrue();
            proof.verified = true;
          }
        } catch (error) { proof.failure = String(error); throw new Error(proof.failure); }
        finally { writeEvidence(path, proof); }
      }
      console.info(`FlyNES G2 retention phase=${phase} pid=${process.pid} run=${run}`);
    });
  });
}
async function restore(context: common.UIAbilityContext, proof: ProcessProof): Promise<string[]> {
  return await retentionCleanup([
    async () => {
      if (proof.originalSettings === undefined) throw new Error('Missing original settings');
      const settings = nativeApp.settingsGet(); settings.audioEnabled = proof.originalSettings.audioEnabled;
      settings.autosaveEnabled = proof.originalSettings.autosaveEnabled; nativeApp.settingsApply(settings);
      expect(nativeApp.settingsGet().audioEnabled).assertEqual(proof.originalSettings.audioEnabled);
      expect(nativeApp.settingsGet().autosaveEnabled).assertEqual(proof.originalSettings.autosaveEnabled);
    },
    async () => { await restoreNavigation(context, proof.originalNavigation); }
  ]);
}
