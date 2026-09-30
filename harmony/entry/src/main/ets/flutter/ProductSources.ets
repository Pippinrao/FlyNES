import { folderSelectionAvailable, productMap } from './ProductPolicy';
import deviceInfo from '@ohos.deviceInfo';
import { common } from '@kit.AbilityKit';
import { fileShare, picker } from '@kit.CoreFileKit';
import nativeApp, { ScanJobStatusDto } from 'libentry.so';
import { HarmonySourceMap } from '../platform/HarmonySourceMap';
import { HarmonyRomScan } from '../platform/HarmonyRomScan';

/** Process-owned operation: hiding a Flutter View only removes its observation. */
export class ProductSources {
  private map: HarmonySourceMap = new HarmonySourceMap();
  private scanOwner: HarmonyRomScan = new HarmonyRomScan();
  private busy: boolean = false;
  private refresh: Promise<void> | undefined = undefined;
  private activeUuid: string = '';
  private operation: number = 0;
  private phase: string = '';
  private completed: number = 0;
  private cancellable: boolean = false;
  private failures: Map<string, string> = new Map();
  private cancelled: Set<string> = new Set();
  private context: common.UIAbilityContext;
  private changed: () => void;
  constructor(context: common.UIAbilityContext, changed: () => void) { this.context = context; this.changed = changed; }

  private supportsFolderSelection(): boolean {
    return folderSelectionAvailable(deviceInfo.deviceType, deviceInfo.sdkApiVersion,
      canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection'));
  }

  async list(): Promise<Record<string, Object>> {
    // Never reload the map in the middle of a provisional regrant transaction.
    if (!this.busy) {
      if (this.refresh === undefined) this.refresh = this.loadAndReconcile();
      const refresh = this.refresh;
      try { await refresh; } finally { if (this.refresh === refresh) this.refresh = undefined; }
    }
    const statuses = nativeApp.sourceStatusList();
    const catalog = nativeApp.catalogSnapshot();
    const ids = this.map.uuids();
    for (const status of statuses) if (!ids.includes(status.uuidHex)) ids.push(status.uuidHex);
    const items: Record<string, Object>[] = [];
    for (const uuid of ids) {
      const state = statuses.find((entry) => entry.uuidHex === uuid);
      if (this.map.pendingRemovals().includes(uuid) && state === undefined) continue;
      const builtin = state?.sourceScope === 1;
      const uri = this.map.get(uuid);
      const active = this.busy && this.activeUuid === uuid;
      const lost = !builtin && uri.length === 0;
      const stale = state?.freshness === 2;
      items.push(productMap([ ["uuid", uuid], ["name", builtin ? 'Built-in games' : uri.split('/').pop() || ''],
        ["type", builtin ? 'builtin' : state?.sourceScope === 4 ? 'file' : 'folder'],
        ["count", new Set(catalog.filter((row) => row.sourceUuidHex === uuid).map((row) => row.canonicalId)).size],
        ["builtin", builtin], ["status", active ? 'scanning' : this.failures.has(uuid) ? 'failed' : this.cancelled.has(uuid) ? 'cancelled' : lost ? 'unavailable' : stale || state?.lastCompleteness === 2 ? 'partial' : 'ready'],
        ["reason", this.failures.get(uuid) ?? (lost ? 'permission_required' : '')], ["canReauthorize", !builtin && state?.sourceScope !== 4 && this.supportsFolderSelection()],
        ["canCancel", active && this.cancellable], ["operationId", active ? `${this.operation}` : ''],
        ["phase", active ? this.phase : ''], ["completed", active ? this.completed : 0] ]));
    }
    const folder = this.supportsFolderSelection();
    return productMap([ ["items", items], ["folderSelection", productMap([
      ["available", folder], ["reason", folder ? '' : 'folder_selection_unsupported'] ])] ]);
  }

  private async loadAndReconcile(): Promise<void> {
    await this.map.load(this.context);
    await this.reconcileRemovals();
  }

  private async loadForMutation(): Promise<void> {
    // begin() reserves mutations synchronously; an older list owns its refresh
    // until reconciliation finishes, so it cannot clear this mutation's journal.
    if (this.refresh !== undefined) await this.refresh;
    await this.map.load(this.context);
  }

  private begin(): void {
    if (this.busy) throw new Error('source_busy');
    this.busy = true;
    this.operation++;
    this.phase = 'preparing';
    this.cancellable = false;
    this.completed = 0;
  }
  private finish(): void {
    this.busy = false;
    this.cancellable = false;
    this.activeUuid = '';
    this.changed();
  }
  async remove(uuid: string): Promise<void> {
    this.begin();
    try {
      await this.loadForMutation();
      if (nativeApp.sourceStatusList().some((entry) => entry.uuidHex === uuid && entry.sourceScope === 1)) throw new Error('invalid_argument');
      const pending = this.map.pendingRemovals().includes(uuid);
      const exists = nativeApp.sourceStatusList().some((entry) => entry.uuidHex === uuid);
      await this.map.markRemoval(uuid);
      if (!pending || exists) {
        try { nativeApp.sourceRemove(uuid); } catch (error) {
          await this.map.clearRemoval(uuid);
          throw error as Error;
        }
      }
      try { await this.cleanupRemoval(uuid); } catch (_) { throw new Error('source_cleanup_failed'); }
    } finally { this.finish(); }
  }
  private async cleanupRemoval(uuid: string): Promise<void> {
    this.map.remove(uuid);
    await this.map.flush();
    await this.map.clearRemoval(uuid);
  }
  private async reconcileRemovals(): Promise<void> {
    const statuses = nativeApp.sourceStatusList();
    for (const uuid of this.map.pendingRemovals()) {
      try {
        if (statuses.some((entry) => entry.uuidHex === uuid)) await this.map.clearRemoval(uuid);
        else await this.cleanupRemoval(uuid);
      } catch (_) { this.failures.set(uuid, 'source_cleanup_failed'); }
    }
  }
  async pick(kind: string, uuid: string = '', started?: (value: Record<string, Object>) => void): Promise<Record<string, Object>> {
    if (kind !== 'file' && kind !== 'folder') throw new Error('invalid_argument');
    if (uuid.length > 0 && kind !== 'folder') throw new Error('invalid_argument');
    if (kind === 'folder' && !this.supportsFolderSelection()) throw new Error('folder_selection_unsupported');
    this.begin();
    try {
      await this.loadForMutation();
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = kind === 'file' ? 100 : 1;
      options.selectMode = kind === 'file' ? picker.DocumentSelectMode.FILE : picker.DocumentSelectMode.FOLDER;
      if (kind === 'file') options.fileSuffixFilters = ['NES ROMs|.nes,.zip,.unf,.unif'];
      const uris = await new picker.DocumentViewPicker(this.context).select(options);
      if (uris.length === 0) return productMap([ ["status", 'cancelled'], ["operationId", `${this.operation}`] ]);
      if (kind === 'file') {
        const directory = `${this.context.filesDir}/roms`;
        const copied = await this.scanOwner.importDocumentUris(uris, directory);
        if (copied === 0) throw new Error('no_compatible_files');
        let managed = this.map.uuids().find((id) => this.map.get(id) === directory) ?? '';
        if (managed.length === 0) managed = this.map.newUuidHex();
        await this.assignAndScan(managed, directory, 4, started);
      } else {
        const policy: fileShare.PolicyInfo = { uri: uris[0], operationMode: fileShare.OperationMode.READ_MODE };
        const granted = await fileShare.checkPersistentPermission([policy]);
        if (granted.length !== 1) throw new Error('authorization_lost');
        const protectedGrant = granted[0] || this.map.uuids().some((id) => this.map.get(id) === uris[0]);
        try {
          await fileShare.persistPermission([policy]);
          await fileShare.activatePermission([policy]);
          const existing = this.map.uuids().find((id) => this.map.get(id) === uris[0]);
          await this.assignAndScan(uuid.length > 0 ? uuid : existing ?? this.map.newUuidHex(), uris[0], 2, started);
        } catch (error) {
          const failure = error as Error;
          if (!protectedGrant && failure.message !== 'source_reauthorize_cleanup_failed' &&
              !this.map.uuids().some((id) => this.map.get(id) === uris[0])) {
            try {
              const current = await fileShare.checkPersistentPermission([policy]);
              if (current[0]) {
                await fileShare.deactivatePermission([policy]);
                await fileShare.revokePermission([policy]);
              }
            } catch (_) {
              this.failures.set(this.activeUuid, 'source_reauthorize_cleanup_failed');
              throw new Error('source_reauthorize_cleanup_failed');
            }
          }
          throw failure;
        }
      }
      return productMap([ ["status", 'completed'], ["operationId", `${this.operation}`] ]);
    } catch (error) {
      if (this.cancelled.has(this.activeUuid) && (error as Error).message === 'scan cancelled' &&
          !this.failures.has(this.activeUuid))
        return productMap([ ["status", 'cancelled'], ["operationId", `${this.operation}`] ]);
      throw error as Error;
    } finally { this.finish(); }
  }
  private async assignAndScan(uuid: string, uri: string, scope: number, started?: (value: Record<string, Object>) => void): Promise<void> {
    const previous = this.map.get(uuid);
    try {
      this.map.put(uuid, uri);
      await this.map.flush();
      await this.run(uuid, uri, scope, started);
    } catch (error) {
      if (previous.length > 0) this.map.put(uuid, previous); else this.map.remove(uuid);
      try { await this.map.flush(); } catch (_) {
        this.failures.set(uuid, 'source_reauthorize_cleanup_failed');
        throw new Error('source_reauthorize_cleanup_failed');
      }
      throw error as Error;
    }
  }
  async scan(uuid: string, started?: (value: Record<string, Object>) => void): Promise<Record<string, Object>> {
    this.begin();
    try {
      await this.loadForMutation();
      const uri = this.map.get(uuid);
      if (uri.length === 0) throw new Error('authorization_lost');
      const state = nativeApp.sourceStatusList().find((entry) => entry.uuidHex === uuid);
      await this.run(uuid, uri, state?.sourceScope ?? 2, started);
      return productMap([ ["status", 'completed'], ["operationId", `${this.operation}`] ]);
    } catch (error) {
      if (this.cancelled.has(this.activeUuid) && (error as Error).message === 'scan cancelled' &&
          !this.failures.has(this.activeUuid))
        return productMap([ ["status", 'cancelled'], ["operationId", `${this.operation}`] ]);
      throw error as Error;
    } finally { this.finish(); }
  }
  cancel(uuid: string, operationId: string): Record<string, Object> {
    if (!this.busy || uuid !== this.activeUuid || operationId !== `${this.operation}` ||
        !this.cancellable || !this.scanOwner.cancelActiveScan()) throw new Error('cancellation_unavailable');
    this.phase = 'cancelling';
    this.cancellable = false;
    this.changed();
    return productMap([ ["status", 'cancelling'], ["operationId", operationId] ]);
  }
  private async run(uuid: string, uri: string, scope: number, started?: (value: Record<string, Object>) => void): Promise<void> {
    this.activeUuid = uuid;
    this.phase = 'scanning';
    this.failures.delete(uuid);
    this.cancelled.delete(uuid);
    this.changed();
    started?.(productMap([ ["status", 'started'], ["operationId", `${this.operation}`] ]));
    try { await this.scanOwner.scanDirectory(uuid, uri, scope, (progress: ScanJobStatusDto) => {
      if (progress.phase === 4) this.cancelled.add(uuid);
      const cancelling = this.phase === 'cancelling';
      this.cancellable = !cancelling && (progress.phase === 1 || progress.phase === 2);
      this.phase = progress.phase === 6 ? 'committing' : progress.phase === 3 ? 'completed' :
        progress.phase === 4 ? 'cancelled' : progress.phase === 5 ? 'failed' :
        cancelling ? 'cancelling' : 'scanning';
      this.completed = progress.processedFiles;
      this.changed();
    }); } catch (error) {
      if (!this.cancelled.has(uuid)) this.failures.set(uuid, 'scan_failed');
      throw error as Error;
    }
  }
}
