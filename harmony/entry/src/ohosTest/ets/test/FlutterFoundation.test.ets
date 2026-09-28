import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, Want } from '@kit.AbilityKit';
import { Driver, ON } from '@ohos.UiTest';
import nativeProduct from 'libentry.so';
import { CatalogProductService } from '../../../main/ets/service/CatalogProductService';
import { builtinGamesSync } from '../../../main/ets/service/PlayService';
import { foundationSnapshot, isFlutterFoundationRoute } from '../../../main/ets/flutter/FoundationProjection';

export default function flutterFoundationTest() {
  describe('FlutterFoundation', () => {
    it('accepts_only_debug_foundation_route', 0, () => {
      expect(isFlutterFoundationRoute('flutter_foundation', true)).assertTrue();
      expect(isFlutterFoundationRoute('flutter_foundation', false)).assertFalse();
      expect(isFlutterFoundationRoute('nearby_lobby', true)).assertFalse();
    });
    it('queries_existing_native_owner_and_shared_manifest_projection', 0, () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.UIAbilityContext;
      nativeProduct.appOpen(context.filesDir, context.cacheDir);
      const nativeRows = nativeProduct.catalogSnapshot();
      expect(nativeRows.length >= 0).assertTrue();
      const games = builtinGamesSync(context);
      const rows = new CatalogProductService().loadRows(games);
      const snapshot = foundationSnapshot(rows, 1);
      expect(snapshot.games.length >= games.all().length).assertTrue();
      expect(snapshot.games.length > 0).assertTrue();
      expect(snapshot.games[0].canonicalId.length > 0).assertTrue();
    });
    it('renders_real_flutter_catalog_in_existing_ability', 0, async () => {
      const want: Want = { bundleName: 'com.flynes.emu', abilityName: 'EntryAbility',
        parameters: { 'flynes.test.page': 'flutter_foundation' } };
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility(want);
      const driver = Driver.create();
      const library = await driver.waitForComponent(ON.id('foundation-library'), 15000);
      expect(library !== null && library !== undefined).assertTrue();
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.UIAbilityContext;
      const games = builtinGamesSync(context).all();
      expect(games.length > 0).assertTrue();
      const card = await driver.waitForComponent(ON.id(`game-card-${games[0].canonicalId}`), 10000);
      expect(card !== null && card !== undefined).assertTrue();
      await driver.screenCap(`${context.filesDir}/flutter-foundation.png`);
    });
  });
}
