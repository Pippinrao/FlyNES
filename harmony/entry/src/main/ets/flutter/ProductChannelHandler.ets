import { productMap } from './ProductPolicy';
import { common, bundleManager } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { preferences } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { vibrator } from '@kit.SensorServiceKit';
import { MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import nativeApp, { GameCenterRow, SettingsDto } from 'libentry.so';
import { ProductHostLease, patchProductSetting } from './ProductPolicy';
import { ProductSources } from './ProductSources';
import { ProductCatalog } from './ProductCatalog';
import { productBuildRevision } from './ProductBuildInfo';
import { LicenseModel } from '../pages/LicenseModel';
import { runtimeLanguageFor } from '../pages/SettingsHelpers';
import { builtinGamesSync, PlayService, RomLaunchLocator, takeRomOpenError } from '../service/PlayService';
import { SaveHistoryService } from '../service/SaveHistoryService';
import { CheckpointStore } from '../service/CheckpointStore';
import { localizedGameTitle } from '../service/CatalogProductService';
import { nearbyRoomGame } from '../service/NearbyRoomGame';

export class ProductRouteContext {
  route: string = 'hall';
  purpose: string = 'single';
  returnToken: string = '';
  presentationToken: string = '';
}
class ProductRequest {
  private result: MethodResult;
  private requestId: number;
  generation: number;
  private instanceId: string;
  private completed: boolean = false;
  constructor(result: MethodResult, requestId: number, generation: number, instanceId: string) {
    this.result = result; this.requestId = requestId; this.generation = generation; this.instanceId = instanceId;
  }
  success(value: Record<string, Object>): void {
    if (this.completed) return;
    this.completed = true;
    value['requestId'] = this.requestId; value['hostGeneration'] = this.generation; value['instanceId'] = this.instanceId;
    this.result.success(value);
  }
  error(code: string): void {
    if (this.completed) return;
    this.completed = true;
    this.result.error(code, 'The operation could not be completed.', null);
  }
}
class PendingRoute {
  request: ProductRequest;
  token: string;
  constructor(request: ProductRequest, token: string) { this.request = request; this.token = token; }
}

/** One retained channel owns platform coordination, independently of its View. */
export class ProductChannelHandler implements MethodCallHandler {
  private readonly instanceId: string = util.generateRandomUUID(false);
  private readonly lease: ProductHostLease = new ProductHostLease();
  private route: ProductRouteContext = new ProductRouteContext();
  private readonly catalog: ProductCatalog;
  private readonly sources: ProductSources;
  private pending: Map<string, PendingRoute> = new Map();
  private nearbyTimer: number = -1;
  private selecting: ProductRequest | undefined = undefined;
  private presented: (() => void) | undefined = undefined;
  private beforeNative: (() => Promise<void>) | undefined = undefined;
  private context: common.UIAbilityContext;
  private channel: MethodChannel;
  constructor(context: common.UIAbilityContext, channel: MethodChannel) {
    this.context = context; this.channel = channel;
    this.catalog = new ProductCatalog(context);
    this.sources = new ProductSources(context, () => this.changed(['sources', 'catalog']));
  }
  attach(route: ProductRouteContext, presented?: () => void, beforeNative?: () => Promise<void>): number {
    const generation = this.lease.acquire(route.returnToken);
    this.route = new ProductRouteContext();
    this.route.route = route.route; this.route.purpose = route.purpose; this.route.returnToken = route.returnToken;
    this.route.presentationToken = `${this.instanceId}:${generation}`;
    this.presented = presented;
    this.beforeNative = beforeNative;
    this.channel.invokeMethod('contextChanged', this.event(productMap([ ["context", this.route] ])));
    const pending = this.pending.get(route.returnToken);
    if (pending !== undefined) {
      this.pending.delete(route.returnToken);
      const reason = takeRomOpenError();
      pending.request.success(productMap([ ["status", reason.length === 0 ? 'returned' : 'unavailable'], ["reason", reason.length === 0 ? '' : 'launch_unavailable'] ]));
    }
    this.changed(['catalog', 'resume', 'settings', 'sources']);
    if (route.purpose === 'nearby') this.nearbyTimer = setInterval(() => {
      if (this.selecting) return;
      const snapshot = nativeApp.nearbyMvpSnapshot();
      if (snapshot.state === 6 && !snapshot.paused) router.back();
    }, 100);
    return generation;
  }
  detach(generation: number): void {
    if (!this.lease.release(generation)) return;
    this.presented = undefined;
    this.beforeNative = undefined;
    if (this.nearbyTimer !== -1) clearInterval(this.nearbyTimer);
    this.nearbyTimer = -1;
  }
  private event(value: Record<string, Object>): Record<string, Object> {
    value['instanceId'] = this.instanceId; value['hostGeneration'] = this.lease.generation;
    return value;
  }
  private changed(domains: string[]): void {
    if (this.lease.accepts(this.lease.generation)) this.channel.invokeMethod('projectionChanged', this.event(productMap([ ["domains", domains] ])));
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    const id: Object | null = call.argument('requestId');
    const generation: Object | null = call.argument('hostGeneration');
    if (typeof id !== 'number' || typeof generation !== 'number' ||
        (!this.lease.accepts(generation) && !(['bootstrap', 'presentationContext'].includes(call.method) && generation === 0 && this.lease.accepts(this.lease.generation)))) {
      result.error('stale_host', 'The page context changed.', null); return;
    }
    const request = new ProductRequest(result, id, this.lease.generation, this.instanceId);
    void this.dispatch(call, request).catch((error: Error) => {
      const stable = ['invalid_argument', 'invalid_setting', 'capability_locked', 'source_busy', 'snapshot_expired',
        'authorization_lost', 'cancellation_unavailable', 'route_busy', 'invalid_page', 'no_compatible_files',
        'source_cleanup_failed', 'source_reauthorize_cleanup_failed', 'folder_selection_unsupported'];
      request.error(stable.includes(error.message) ? error.message : 'operation_failed');
    });
  }
  private string(call: MethodCall, key: string, fallback: string = ''): string {
    const value: Object | null = call.argument(key);
    if (value === null || value === undefined) return fallback;
    if (typeof value !== 'string') throw new Error('invalid_argument');
    return value;
  }
  private number(call: MethodCall, key: string): number {
    const value: Object | null = call.argument(key);
    if (typeof value !== 'number' || !Number.isInteger(value)) throw new Error('invalid_argument');
    return value;
  }
  private bool(call: MethodCall, key: string): boolean {
    const value: Object | null = call.argument(key);
    if (typeof value !== 'boolean') throw new Error('invalid_argument');
    return value;
  }
  private async dispatch(call: MethodCall, request: ProductRequest): Promise<void> {
    // These two messages must work even when catalog initialization fails, so
    // the already-rasterized localized error/retry page can become visible.
    if (call.method === 'presentationContext') {
      const locale = nativeApp.settingsGet().localeTag;
      request.success(productMap([["context", this.route], ["locale", locale === 'system' ? i18n.System.getSystemLanguage() : locale]])); return;
    }
    if (call.method === 'presentationReady') {
      if (this.string(call, 'token') !== this.route.presentationToken) { request.error('stale_host'); return; }
      if (this.number(call, 'frameNumber') <= 0) { request.error('invalid_argument'); return; }
      const reveal = this.presented;
      this.presented = undefined;
      reveal?.();
      request.success(productMap([["accepted", true]])); return;
    }
    await this.catalog.initialize();
    if (!this.lease.accepts(request.generation)) { request.error('stale_host'); return; }
    switch (call.method) {
      case 'bootstrap': {
        const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
        const locale = nativeApp.settingsGet().localeTag;
        request.success(productMap([ ["protocolVersion", 1], ["localePreference", locale], ["locale", locale === 'system' ? i18n.System.getSystemLanguage() : locale],
          ["version", info.versionName], ["buildRevision", await productBuildRevision(this.context)], ["context", this.route], ["capabilities", this.capabilities()], ["preferences", await this.navigation()] ])); return;
      }
      case 'catalogQuery': request.success(await this.catalog.query(this.string(call, 'category'), this.string(call, 'query'),
        this.bool(call, 'multiplayerOnly'), this.string(call, 'selectedId'))); return;
      case 'catalogWindow': request.success(await this.catalog.window(this.number(call, 'catalogGeneration'),
        this.number(call, 'viewRevision'), this.number(call, 'offset'), this.number(call, 'limit'))); return;
      case 'catalogItem': request.success(await this.catalog.item(this.string(call, 'canonicalId'))); return;
      case 'resumeCapability': await this.resume(call, request); return;
      case 'setFavorite': {
        const id = this.catalog.canonical(this.string(call, 'canonicalId'));
        const favorite = this.bool(call, 'value');
        nativeApp.catalogFavoriteSet(id, favorite);
        this.changed(['catalog']); request.success(productMap([ ["canonicalId", id], ["favorite", favorite] ])); return;
      }
      case 'saveNavigation': request.success(await this.navigation(call)); return;
      case 'sources': request.success(await this.sources.list()); return;
      case 'pickSource': case 'scanSource': {
        let answered = false;
        const started = (value: Record<string, Object>): void => { answered = true; request.success(value); };
        try {
          const value = call.method === 'pickSource' ?
            await this.sources.pick(this.string(call, 'kind'), this.string(call, 'sourceUuid'), started) :
            await this.sources.scan(this.string(call, 'uuid'), started);
          if (!answered) request.success(value);
        } catch (error) { if (!answered) throw error as Error; }
        return;
      }
      case 'cancelScan': request.success(this.sources.cancel(this.string(call, 'uuid'), this.string(call, 'operationId'))); return;
      case 'removeSource': await this.sources.remove(this.string(call, 'uuid')); request.success(productMap([ ["completed", true] ])); return;
      case 'settings': request.success(this.settings()); return;
      case 'patchSetting': {
        const key = this.string(call, 'key');
        const value: Object | null = call.argument('value');
        if (value === null) throw new Error('invalid_setting');
        const next = patchProductSetting(nativeApp.settingsGet(), key, value);
        nativeApp.settingsApply(next);
        if (key === 'localeTag') {
          i18n.System.setAppPreferredLanguage(next.localeTag === 'system' ? 'default' : next.localeTag);
          this.context.getApplicationContext().setLanguage(runtimeLanguageFor(next.localeTag, i18n.System.getSystemLanguage()));
        }
        this.changed(['settings']); request.success(this.settings()); return;
      }
      case 'resetControls': {
        const next = nativeApp.settingsGet(); next.directionMode = 2; next.hapticLevel = 2; next.distinctAbHaptics = 1;
        nativeApp.controlLayoutApply(nativeApp.controlLayoutRecommended()); nativeApp.settingsApply(next);
        this.changed(['settings']); request.success(this.settings()); return;
      }
      case 'previewHaptics': await this.previewHaptics(); request.success(productMap([ ["completed", true] ])); return;
      case 'licenses': request.success(productMap([ ["items", LicenseModel.all(builtinGamesSync(this.context)).map((entry) => {
        const row: Record<string, Object> = productMap([ ["id", entry.fileName], ["title", entry.displayName], ["sourceUrl", entry.sourceUrl] ]); return row;
      })] ])); return;
      case 'licenseText': {
        const id = this.string(call, 'id');
        if (LicenseModel.byFileName(id, builtinGamesSync(this.context)) === undefined) throw new Error('invalid_argument');
        const raw = await this.context.resourceManager.getRawFileContent(id);
        request.success(productMap([ ["text", LicenseModel.resolveBody(id, util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeWithStream(raw))] ])); return;
      }
      case 'copyText': await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.string(call, 'text'))); request.success(productMap([ ["completed", true] ])); return;
      case 'openLink': {
        const url = this.string(call, 'url');
        if (!/^https?:\/\/[^\s\/@]+(?:[^\s]*)$/i.test(url)) throw new Error('invalid_argument');
        await this.context.startAbility({ action: 'ohos.want.action.viewData', uri: url }); request.success(productMap([ ["completed", true] ])); return;
      }
      case 'launch': await this.launch(call, request); return;
      case 'openNative': await this.openNative(call, request); return;
      case 'detach': request.success(productMap([ ["completed", true] ])); return;
      case 'closeHost': request.success(productMap([ ["completed", true] ])); if (Number(router.getLength()) > 1) router.back(); else await this.context.terminateSelf(); return;
      default: request.error('unknown_method');
    }
  }
  private capabilities(): Record<string, Object> {
    return productMap([ ["videoQualityPreset.3", productMap([ ["available", false], ["reason", 'hardware_evidence_required'] ])],
      ["customTemporalMode.2", productMap([ ["available", false], ["reason", 'hardware_evidence_required'] ])],
      ["customRefreshPolicy.2", productMap([ ["available", false], ["reason", 'unsupported_option'] ])],
      ["customRefreshPolicy.4", productMap([ ["available", false], ["reason", 'hardware_evidence_required'] ])],
      ["customRefreshPolicy.5", productMap([ ["available", false], ["reason", 'hardware_evidence_required'] ])] ]);
  }
  private settings(): Record<string, Object> {
    const value = nativeApp.settingsGet();
    const values: Record<string, Object> = productMap([ ["videoQualityPreset", value.videoQualityPreset], ["customRefreshPolicy", value.customRefreshPolicy],
      ["customTemporalMode", value.customTemporalMode], ["customSpatialMode", value.customSpatialMode], ["customPostEffect", value.customPostEffect],
      ["aspectMode", value.aspectMode], ["adaptiveProtection", value.adaptiveProtection === 1], ["directionMode", value.directionMode],
      ["hapticLevel", value.hapticLevel], ["distinctAbHaptics", value.distinctAbHaptics === 1], ["audioEnabled", value.audioEnabled === 1],
      ["audioFocusPolicy", value.audioFocusPolicy], ["localeTag", value.localeTag], ["autosaveEnabled", value.autosaveEnabled === 1] ]);
    return productMap([ ["values", values], ["capabilities", this.capabilities()],
      ["layoutSummary", nativeApp.controlLayoutGet() === nativeApp.controlLayoutRecommended() ? "recommended" : "custom"] ]);
  }
  private async navigation(call?: MethodCall): Promise<Record<string, Object>> {
    const store = await preferences.getPreferences(this.context, 'game_center_ui');
    if (call !== undefined) {
      const category = this.string(call, 'category');
      if (!['all', 'recent', 'favorites', 'builtin'].includes(category)) throw new Error('invalid_argument');
      const selections = call.argument('selections') as Map<string, Object>;
      if (!(selections instanceof Map)) throw new Error('invalid_argument');
      await store.put('category', category); await store.put('multiplayerOnly', this.bool(call, 'multiplayerOnly'));
      for (const key of ['all', 'recent', 'favorites', 'builtin']) {
        const id = selections.get(key);
        if (typeof id === 'string') await store.put(`selected.${key}`, id);
      }
      await store.flush();
    }
    const selections: Record<string, Object> = {};
    for (const key of ['all', 'recent', 'favorites', 'builtin']) selections[key] = this.catalog.canonical(await store.get(`selected.${key}`, '') as string);
    return productMap([ ["category", await store.get('category', 'all')], ["multiplayerOnly", await store.get('multiplayerOnly', false)], ["selections", selections] ]);
  }
  private locator(row: GameCenterRow): RomLaunchLocator {
    const locator = new RomLaunchLocator(); locator.canonicalId = row.canonicalId;
    locator.sourceUuidHex = row.sourceUuidHex; locator.sourceRelativePath = row.sourceRelativePath;
    locator.packageFormat = row.packageFormat; locator.zipEntryName = row.originalFilename; return locator;
  }
  private async resume(call: MethodCall, request: ProductRequest): Promise<void> {
    try {
      const row = await this.catalog.row(this.string(call, 'canonicalId'));
      const rom = await new PlayService().readRom(this.context, this.locator(row));
      const history = new SaveHistoryService(`${this.context.filesDir}/save-history.db`, nativeApp.historyContentKey(rom));
      const legacy = new CheckpointStore(this.context.filesDir);
      request.success(productMap([ ["state", history.hasResume(() => legacy.read(this.catalog.legacy(row.canonicalId))) ? 'available' : 'none'], ["reason", ''] ]));
    } catch (_) { request.success(productMap([ ["state", 'unavailable'], ["reason", 'resume_unavailable'] ])); }
  }
  private async launch(call: MethodCall, request: ProductRequest): Promise<void> {
    const token = this.route.returnToken;
    if (this.pending.has(token)) throw new Error('route_busy');
    this.pending.set(token, new PendingRoute(request, token));
    this.selecting = request;
    try {
      const nearby = this.string(call, 'purpose') === 'nearby';
      const roomGeneration = nearby ? nativeApp.nearbyMvpSnapshot().roomGeneration : 0;
      const row = await this.catalog.row(this.string(call, 'canonicalId'));
      if (nearby && !row.multiplayerSupported) throw new Error('multiplayer_unsupported');
      const rom = await new PlayService().readRom(this.context, this.locator(row));
      const title = localizedGameTitle(row.titleEn, row.titleZhHans, row.originalFilename, nativeApp.settingsGet().localeTag, i18n.System.getSystemLanguage());
      if (!this.lease.accepts(request.generation)) throw new Error('stale_host');
      if (nearby) {
        let state = nativeApp.nearbyMvpSnapshot();
        if (state.roomGeneration !== roomGeneration) throw new Error('stale_room');
        if (state.role === 1 && (state.state === 5 || state.state === 6)) {
          if (!nativeApp.nearbyMvpReturnLobby()) throw new Error('route_unavailable');
          const deadline = Date.now() + 3000;
          while (nativeApp.nearbyMvpSnapshot().state === 7 && Date.now() < deadline) await new Promise<void>((resolve) => { setTimeout(resolve, 20); });
          state = nativeApp.nearbyMvpSnapshot();
        }
        // ReturnLobby can suspend while another page acquires the same engine.
        // Check the lease again before mutating the room or navigating that page.
        if (!this.lease.accepts(request.generation) || this.pending.get(token)?.request !== request)
          throw new Error('stale_host');
        if (state.roomGeneration !== roomGeneration || state.role !== 1 || state.state !== 3) throw new Error('route_unavailable');
        const selected = await nativeApp.nearbyMvpSelectGameAsync(rom, row.canonicalId, roomGeneration);
        if (!this.lease.accepts(request.generation) || this.pending.get(token)?.request !== request)
          throw new Error('stale_host');
        state = nativeApp.nearbyMvpSnapshot();
        if (!selected.selected || selected.roomGeneration !== roomGeneration || state.roomGeneration !== roomGeneration ||
            state.role !== 1 || state.state !== 5 || !nativeApp.nearbyMvpConfirm()) throw new Error('route_unavailable');
        nearbyRoomGame.select(row.canonicalId, title);
        this.pending.delete(token); request.success(productMap([ ["status", 'returned'], ["reason", ''] ]));
        router.back();
      } else {
        await this.beforeNative?.();
        if (!this.lease.accepts(request.generation) || this.pending.get(token)?.request !== request)
          throw new Error('stale_host');
        await router.pushUrl({ url: 'pages/RunGame', params: {
        canonicalId: row.canonicalId, sourceUuidHex: row.sourceUuidHex, sourceRelativePath: row.sourceRelativePath,
        packageFormat: `${row.packageFormat}`, zipEntryName: row.originalFilename, titleEn: row.titleEn,
        titleZhHans: row.titleZhHans, title: title, foundationReturn: true
        } });
      }
    } catch (_) {
      if (this.pending.get(token)?.request === request) this.pending.delete(token);
      request.success(productMap([ ["status", 'unavailable'], ["reason", 'launch_unavailable'] ]));
    } finally { if (this.selecting === request) this.selecting = undefined; }
  }
  private async openNative(call: MethodCall, request: ProductRequest): Promise<void> {
    const page = this.string(call, 'page');
    const token = this.route.returnToken;
    if (this.pending.has(token)) throw new Error('route_busy');
    let url = page === 'layout' ? 'pages/ControlLayout' : '';
    const params: Record<string, Object> = {};
    if (page === 'nearby') {
      const state = nativeApp.nearbyMvpSnapshot().state;
      url = state === 2 ? 'pages/NearbyPairing' : [3, 5, 6, 7].includes(state) ? 'pages/NearbyLobby' : 'pages/NearbyFriends';
      if (state === 2) { params['mode'] = 'scan'; params['resume'] = 'true'; }
    }
    if (url.length === 0) throw new Error('invalid_page');
    this.pending.set(token, new PendingRoute(request, token));
    try {
      await this.beforeNative?.();
      if (!this.lease.accepts(request.generation) || this.pending.get(token)?.request !== request)
        throw new Error('stale_host');
      await router.pushUrl({ url: url, params: params });
    }
    catch (_) {
      if (this.pending.get(token)?.request === request) this.pending.delete(token);
      request.error('route_unavailable');
    }
  }
  private async previewHaptics(): Promise<void> {
    const value = nativeApp.settingsGet();
    if (value.hapticLevel === 1) return;
    await vibrator.startVibration({ type: 'preset', effectId: 'haptic.clock.timer', count: 1,
      intensity: [0, 0, 40, 70, 100][value.hapticLevel] ?? 40 }, { usage: 'touch' });
  }
}
