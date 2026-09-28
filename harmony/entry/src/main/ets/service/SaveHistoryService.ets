import nativePlay, { HistoryInput, HistoryRow } from 'libentry.so';

/** Platform adapter: captures the emulator; the standalone library stores opaque bytes. */
export class SaveHistoryService {
  playedMs: number = 0;
  intervalMs: number = 60000;
  private path: string;
  private key: string;
  private session: string = `${Date.now()}`;
  private initial: ArrayBuffer = new ArrayBuffer(0);
  private sinceSave: number = 0;
  private lastSource: number = 0;
  private savedFrame: number = -1;
  private wasRunning: boolean = false;

  constructor(path: string, key: string) { this.path = path; this.key = key; }

  /** Read-only capability query; migration and core validation remain in open. */
  hasResume(readLegacy: () => ArrayBuffer | undefined = () => undefined): boolean {
    const head = nativePlay.historyHead(this.path, this.key);
    if (head > 0) return nativePlay.historyRead(this.path, this.key, head, false).byteLength > 0;
    const legacy = readLegacy();
    return legacy !== undefined && legacy.byteLength > 0;
  }

  initialize(restore: boolean, readLegacy: () => ArrayBuffer | undefined = () => undefined): void {
    this.initial = nativePlay.playSaveCheckpoint();
    this.lastSource = nativePlay.playRuntimeStatus().sourceFrames;
    nativePlay.historyRecover(this.path, this.key);
    let head = nativePlay.historyHead(this.path, this.key);
    const legacy = head === 0 ? readLegacy() : undefined;
    if (head === 0 && legacy !== undefined) {
      // Validate old state with the real core before publishing it. Never modify the old file.
      try {
        nativePlay.playLoadCheckpoint(legacy);
        head = this.save(3, '');
      } finally { nativePlay.playLoadCheckpoint(this.initial); }
    }
    if (restore && head > 0) {
      try {
        nativePlay.playLoadCheckpoint(nativePlay.historyRead(this.path, this.key, head, false));
      } catch (error) {
        nativePlay.playSetPaused(true);
        nativePlay.playLoadCheckpoint(this.initial);
        throw new Error(error instanceof Error ? error.message : 'Saved progress could not be loaded');
      }
      const row = this.list().find((item) => item.id === head);
      this.playedMs = row === undefined ? 0 : row.playedMs;
    }
  }

  private input(kind: number, label: string, makeHead: boolean = true): HistoryInput {
    return { playedMs: Math.floor(this.playedMs), kind: kind, label: label, session: this.session,
      parent: nativePlay.historyHead(this.path, this.key), state: nativePlay.playSaveCheckpoint(),
      thumbnail: nativePlay.playStep().rgb565, makeHead: makeHead };
  }

  save(kind: number = 0, label: string = ''): number {
    const paused = nativePlay.playRuntimeStatus().paused;
    nativePlay.playSetPaused(true);
    try {
      const frame = nativePlay.playStep().frameIndex;
      if (kind === 0 && frame === this.savedFrame) return nativePlay.historyHead(this.path, this.key);
      const id = nativePlay.historySave(this.path, this.key, this.input(kind, label));
      this.sinceSave = 0;
      this.savedFrame = frame;
      return id;
    } finally { if (!paused) nativePlay.playSetPaused(false); }
  }

  restore(id: number): void {
    nativePlay.playSetPaused(true);
    try {
      const target = nativePlay.historyRead(this.path, this.key, id, false);
      const row = this.list().find((item) => item.id === id);
      if (row === undefined) throw new Error('Save no longer exists');
      const current = this.input(2, '');
      const operation = nativePlay.historyPrepare(this.path, this.key, id, current);
      try {
        nativePlay.playLoadCheckpoint(target);
        nativePlay.historyFinish(this.path, operation.operation, true);
      } catch (error) {
        // Roll back memory first, then atomically publish its protection as head.
        // If either step fails, keep the pending operation and stay paused.
        nativePlay.playLoadCheckpoint(current.state);
        nativePlay.historyRecover(this.path, this.key);
        throw new Error(error instanceof Error ? error.message : 'Restore failed');
      }
      this.playedMs = row.playedMs;
      this.sinceSave = 0;
      this.lastSource = nativePlay.playRuntimeStatus().sourceFrames;
      this.savedFrame = nativePlay.playStep().frameIndex;
      this.session = `${Date.now()}-${id}`;
    } finally { this.wasRunning = false; }
  }

  restart(): void {
    nativePlay.playSetPaused(true);
    const current = this.input(2, '');
    // Publish the protected current state first: a crash at any following point resumes it.
    nativePlay.historySave(this.path, this.key, current);
    const previousTime = this.playedMs;
    const previousSession = this.session;
    try {
      nativePlay.playRestart();
      this.session = `${Date.now()}-start`;
      this.playedMs = 0;
      nativePlay.historySave(this.path, this.key, this.input(0, ''));
      this.sinceSave = 0;
      this.lastSource = nativePlay.playRuntimeStatus().sourceFrames;
      this.savedFrame = nativePlay.playStep().frameIndex;
      this.wasRunning = false;
    } catch (error) {
      this.playedMs = previousTime;
      this.session = previousSession;
      nativePlay.playLoadCheckpoint(current.state);
      throw new Error(error instanceof Error ? error.message : 'Restart failed');
    }
  }

  advance(sourceFrames: number, sourceFps: number, running: boolean): void {
    const delta = Math.max(0, sourceFrames - this.lastSource);
    this.lastSource = sourceFrames;
    const count = this.wasRunning;
    this.wasRunning = running;
    if (!count || sourceFps <= 0 || !Number.isFinite(sourceFps)) return;
    const elapsed = delta * 1000 / sourceFps;
    this.playedMs += elapsed;
    this.sinceSave += elapsed;
    if (this.intervalMs > 0 && this.sinceSave >= this.intervalMs) {
      try { this.save(); } finally { this.sinceSave = 0; }
    }
  }

  list(): HistoryRow[] { return nativePlay.historyList(this.path, this.key); }
  thumbnail(id: number): ArrayBuffer { return nativePlay.historyRead(this.path, this.key, id, true); }
  edit(id: number, label: string, pinned: boolean, remove: boolean): void {
    nativePlay.historyEdit(this.path, id, label, pinned, remove);
  }
}
