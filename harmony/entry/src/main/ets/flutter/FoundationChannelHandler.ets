import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { MethodCall, MethodCallHandler, MethodResult } from '@ohos/flutter_ohos';
import nativeProduct, { GameCenterRow } from 'libentry.so';
import { CatalogProductService, localizedGameTitle } from '../service/CatalogProductService';
import { builtinGamesSync, PlayService, RomLaunchLocator, takeRomOpenError } from '../service/PlayService';
import { SaveHistoryService } from '../service/SaveHistoryService';
import { CheckpointStore } from '../service/CheckpointStore';
import { CoverStore } from '../service/CoverStore';
import { foundationSnapshot } from './FoundationProjection';
import { FoundationRouteOwner } from './FoundationRouteOwner';

// Process-local bridge response sequence, deliberately not a native catalog revision.
let foundationGeneration: number = 0;

/** Temporary G1 transport; existing N-API owners retain catalog, storage and play. */
export class FoundationChannelHandler implements MethodCallHandler {
  private readonly context: common.UIAbilityContext;
  private readonly catalog: CatalogProductService = new CatalogProductService();
  private readonly routes: FoundationRouteOwner = new FoundationRouteOwner();
  private disposed: boolean = false;

  constructor(context: common.UIAbilityContext) { this.context = context; }

  onPageHide(): void { this.routes.hidden(); }
  onPageShow(): void {
    this.routes.shown(takeRomOpenError().length > 0 ? '当前无法启动游戏' : '');
  }
  cancel(): void { this.routes.cancel(); }
  dispose(): void { this.cancel(); this.disposed = true; }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (this.disposed) { result.error('host_closed', '暂时无法打开页面', null); return; }
    if (call.method === 'resumeCapability') { void this.resume(call, result); return; }
    if (call.method === 'launch') { void this.launch(call, result); return; }
    if (call.method === 'openNative') { this.openNative(call, result); return; }
    if (call.method !== 'catalogSnapshot') { result.notImplemented(); return; }
    try {
      const rows = this.rows();
      const snapshot = foundationSnapshot(rows, ++foundationGeneration);
      const covers = new CoverStore(this.context.filesDir);
      for (let index = 0; index < snapshot.games.length; index++) {
        try { snapshot.games[index].coverPath = covers.localPath(snapshot.games[index].canonicalId); } catch (_) {}
      }
      console.info(`FlyNES Flutter catalog generation=${snapshot.generation} games=${snapshot.games.length}`);
      result.success(snapshot);
    } catch (error) {
      console.error(`FlyNES Flutter catalog query failed: ${error}`);
      result.error('catalog_unavailable', '暂时无法读取游戏目录', null);
    }
  }

  private rows(): GameCenterRow[] {
    nativeProduct.appOpen(this.context.filesDir, this.context.cacheDir);
    const nativeSnapshot = nativeProduct.catalogSnapshot();
    return this.catalog.loadRowsFromSnapshot(builtinGamesSync(this.context), nativeSnapshot);
  }

  private row(call: MethodCall): GameCenterRow {
    const id: Object | null = call.argument('canonicalId');
    if (typeof id !== 'string' || id.length === 0) throw new Error('Invalid catalog identity');
    const row = this.rows().find((entry) => entry.canonicalId === id);
    if (row === undefined) throw new Error('Catalog entry unavailable');
    return row;
  }

  private locator(row: GameCenterRow): RomLaunchLocator {
    const locator = new RomLaunchLocator();
    locator.canonicalId = row.canonicalId;
    locator.sourceUuidHex = row.sourceUuidHex;
    locator.sourceRelativePath = row.sourceRelativePath;
    locator.packageFormat = row.packageFormat;
    locator.zipEntryName = row.originalFilename;
    return locator;
  }

  private async resume(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const row = this.row(call);
      const rom = await new PlayService().readRom(this.context, this.locator(row));
      const history = new SaveHistoryService(`${this.context.filesDir}/save-history.db`, nativeProduct.historyContentKey(rom));
      const legacy = new CheckpointStore(this.context.filesDir);
      const available = history.hasResume(() => legacy.read(row.canonicalId));
      if (!this.disposed) result.success({ state: available ? 'available' : 'none', reason: '' });
    } catch (_) {
      if (!this.disposed) result.success({ state: 'unavailable', reason: '暂时无法读取进度' });
    }
  }

  private async launch(call: MethodCall, result: MethodResult): Promise<void> {
    const token = this.routes.begin((value) => result.success(value));
    if (token === 0) { result.success({ status: 'unavailable', reason: '当前无法启动游戏' }); return; }
    try {
      const row = this.row(call);
      // Validate the locator before pushing; RunGame remains the sole play owner.
      await new PlayService().readRom(this.context, this.locator(row));
      if (!this.routes.isCurrent(token)) return;
      await router.pushUrl({ url: 'pages/RunGame', params: {
        canonicalId: row.canonicalId, sourceUuidHex: row.sourceUuidHex,
        sourceRelativePath: row.sourceRelativePath, packageFormat: `${row.packageFormat}`,
        zipEntryName: row.originalFilename, titleEn: row.titleEn, titleZhHans: row.titleZhHans,
        title: localizedGameTitle(row.titleEn, row.titleZhHans, row.originalFilename, 'system', i18n.System.getSystemLanguage()),
        foundationReturn: true
      } });
    } catch (_) { this.routes.failed(token); }
  }

  private openNative(call: MethodCall, result: MethodResult): void {
    const page: Object | null = call.argument('page');
    let url = page === 'settings' ? 'pages/Settings' : page === 'sources' ? 'pages/Sources' : '';
    const params: Record<string, Object> = {};
    if (page === 'nearby') {
      // Preserve the existing GameCenter entry behavior for an active room/scan.
      const state = nativeProduct.nearbyMvpSnapshot().state;
      url = state === 2 ? 'pages/NearbyPairing' : state === 3 || state === 5 || state === 6 || state === 7 ?
        'pages/NearbyLobby' : 'pages/NearbyFriends';
      if (state === 2) { params['mode'] = 'scan'; params['resume'] = 'true'; }
    }
    if (url.length === 0) { result.error('invalid_page', '暂时无法打开页面', null); return; }
    const token = this.routes.begin((value) => {
      if (value.status === 'unavailable') result.error('route_unavailable', '暂时无法打开页面', null);
      else result.success(null);
    });
    if (token === 0) { result.error('route_busy', '暂时无法打开页面', null); return; }
    router.pushUrl({ url: url, params: params }).catch(() => this.routes.failed(token));
  }
}
