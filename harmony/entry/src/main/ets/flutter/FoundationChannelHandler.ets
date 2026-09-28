import { common } from '@kit.AbilityKit';
import { MethodCall, MethodCallHandler, MethodResult } from '@ohos/flutter_ohos';
import nativeProduct from 'libentry.so';
import { CatalogProductService } from '../service/CatalogProductService';
import { builtinGamesSync } from '../service/PlayService';
import { foundationSnapshot } from './FoundationProjection';

// Process-local bridge response sequence, deliberately not a native catalog revision.
let foundationGeneration: number = 0;

/** Temporary G1 transport; the existing N-API owner retains the app/catalog. */
export class FoundationChannelHandler implements MethodCallHandler {
  private readonly context: common.UIAbilityContext;
  private readonly catalog: CatalogProductService = new CatalogProductService();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'catalogSnapshot') {
      result.notImplemented();
      return;
    }
    try {
      nativeProduct.appOpen(this.context.filesDir, this.context.cacheDir);
      // Reuse the verified query; the native UI's fallback must not conceal a
      // transport failure or replace this snapshot with a second query.
      const nativeSnapshot = nativeProduct.catalogSnapshot();
      const rows = this.catalog.loadRowsFromSnapshot(builtinGamesSync(this.context), nativeSnapshot);
      foundationGeneration++;
      const snapshot = foundationSnapshot(rows, foundationGeneration);
      console.info(`FlyNES Flutter catalog generation=${snapshot.generation} games=${snapshot.games.length}`);
      result.success(snapshot);
    } catch (error) {
      console.error(`FlyNES Flutter catalog query failed: ${error}`);
      result.error('catalog_unavailable', '暂时无法读取游戏目录', null);
    }
  }
}
