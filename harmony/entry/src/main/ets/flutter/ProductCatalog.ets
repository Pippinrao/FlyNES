import { ProductStartupObservation } from '../service/ProductStartupObservation';
import { productMap } from './ProductPolicy';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import nativeApp, { ProductCatalogCapability, ProductCatalogQuery, ProductCatalogRow, ProductCatalogProjection } from 'libentry.so';
import { HarmonySourceMap } from '../platform/HarmonySourceMap';
import { HarmonyRomScan } from '../platform/HarmonyRomScan';
import { builtinGamesSync } from '../service/PlayService';
import { CoverStore } from '../service/CoverStore';

let productViewRevision: number = 0;

export class ProductCatalog {
  private ready: Promise<void> | undefined = undefined;
  private capabilities: ProductCatalogCapability[] = [];
  private legacyIds: Map<string, string> = new Map();
  private current: ProductCatalogQuery | undefined = undefined;
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  initialize(): Promise<void> {
    if (this.ready === undefined) this.ready = this.prepare().catch((error: Error) => { this.ready = undefined; throw error; });
    return this.ready;
  }
  private async prepare(): Promise<void> {
    nativeApp.appOpen(this.context.filesDir, this.context.cacheDir);
    ProductStartupObservation.ownerReady();
    const games = builtinGamesSync(this.context);
    const map = new HarmonySourceMap();
    await map.load(this.context);
    const store = await preferences.getPreferences(this.context, 'flynes_product_builtin');
    const bytes = await this.context.resourceManager.getRawFileContent('builtin-games.json');
    const fingerprint = util.TextDecoder.create('utf-8').decodeWithStream(bytes);
    const rows = nativeApp.catalogSnapshot();
    if (await store.get('manifest', '') !== fingerprint ||
        games.all().some((game) => !rows.some((row) => row.builtin && row.sourceRelativePath === game.assetFilename))) {
      const directory = `${this.context.cacheDir}/product-builtin`;
      if (!fileIo.accessSync(directory)) fileIo.mkdirSync(directory, true);
      const paths: string[] = [];
      try {
        for (const game of games.all()) {
          const path = `${directory}/${game.assetFilename}`;
          const raw = await this.context.resourceManager.getRawFileContent(game.assetPath());
          const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
          try { fileIo.writeSync(file.fd, raw.buffer); } finally { fileIo.closeSync(file); }
          paths.push(path);
        }
        await new HarmonyRomScan().scanDirectory(map.builtinUuid(), directory, 1);
        await store.put('manifest', fingerprint);
        await store.flush();
      } finally {
        for (const path of paths) try { fileIo.unlinkSync(path); } catch (_) {}
      }
    }
    const scanned = nativeApp.catalogSnapshot();
    this.capabilities = [];
    for (const game of games.all()) {
      const row = scanned.find((entry) => entry.builtin && entry.sourceRelativePath === game.assetFilename);
      if (row === undefined) throw new Error('catalog_unavailable');
      await nativeApp.catalogUserStateCopyIfAbsent(game.canonicalId, row.canonicalId);
      this.legacyIds.set(row.canonicalId, game.canonicalId);
      this.capabilities.push({ canonicalId: row.canonicalId, titleEn: game.titleEn, titleZhHans: game.titleZhHans,
        multiplayerSupported: game.multiplayerEligibility === 'SUPPORTED' });
    }
    ProductStartupObservation.catalogReady();
  }
  canonical(id: string): string {
    for (const entry of this.legacyIds) if (entry[1] === id) return entry[0];
    return id;
  }
  legacy(id: string): string { return this.legacyIds.get(id) ?? id; }
  async query(category: string, query: string, multiplayerOnly: boolean, selectedId: string): Promise<Record<string, Object>> {
    await this.initialize();
    const request: ProductCatalogQuery = { category: category, query: query, multiplayerOnly: multiplayerOnly,
      selectedId: this.canonical(selectedId), offset: 0, limit: 128, catalogGeneration: 0,
      viewRevision: ++productViewRevision, capabilities: this.capabilities };
    this.current = request;
    const projected = await nativeApp.productCatalogProject(request);
    if (this.current !== request) throw new Error('snapshot_expired');
    request.catalogGeneration = projected.catalogGeneration;
    return this.projection(projected);
  }
  async window(generation: number, revision: number, offset: number, limit: number): Promise<Record<string, Object>> {
    const current = this.current;
    if (current === undefined || current.viewRevision !== revision || current.catalogGeneration !== generation) throw new Error('snapshot_expired');
    const request: ProductCatalogQuery = { category: current.category, query: current.query,
      multiplayerOnly: current.multiplayerOnly, selectedId: current.selectedId, offset: offset, limit: limit,
      catalogGeneration: generation, viewRevision: revision, capabilities: this.capabilities };
    return this.projection(await nativeApp.productCatalogProject(request));
  }
  async row(id: string): Promise<ProductCatalogRow> {
    await this.initialize();
    return nativeApp.productCatalogItem(this.canonical(id), this.capabilities);
  }
  async item(id: string): Promise<Record<string, Object>> { return this.decorate(await this.row(id)); }
  private projection(value: ProductCatalogProjection): Record<string, Object> {
    return productMap([ ["catalogGeneration", value.catalogGeneration], ["viewRevision", value.viewRevision], ["total", value.total],
      ["offset", value.offset], ["selectedId", value.selectedId], ["items", value.items.map((row) => this.decorate(row))] ]);
  }
  private decorate(row: ProductCatalogRow): Record<string, Object> {
    const covers = new CoverStore(this.context.filesDir);
    let path = covers.localPath(row.canonicalId);
    if (path.length === 0) path = covers.localPath(this.legacy(row.canonicalId));
    let revision = 0;
    if (path.length > 0) try { revision = fileIo.statSync(path).mtime; } catch (_) {}
    return productMap([ ["canonicalId", row.canonicalId], ["titleEn", row.titleEn], ["titleZhHans", row.titleZhHans],
      ["available", row.available], ["unavailableReason", row.available ? '' : 'source_unavailable'],
      ["coverPath", path], ["coverRevision", revision], ["favorite", row.favorite], ["builtin", row.builtin],
      ["variantCount", row.variantCount], ["multiplayerSupported", row.multiplayerSupported] ]);
  }
}
