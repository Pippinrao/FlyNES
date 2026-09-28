export function nativePerformanceEnabled(optIn: string | undefined, entry: string | undefined): boolean {
  if (optIn !== 'true') return false;
  if (entry !== undefined && entry !== 'native') {
    throw new Error('Flutter performance candidate requires prior numerical budget approval');
  }
  return true;
}

export function performanceRoute(entry: string | undefined, candidateApproved: string | undefined): string {
  if (entry === undefined || entry === 'native') return 'native';
  if (entry !== 'flutter') throw new Error('Unknown performance route');
  if (candidateApproved !== 'true') throw new Error('Flutter candidate requires explicit budget approval');
  return entry;
}

export function performanceBuildMode(requested: string | undefined, actualDebug: boolean): string {
  const mode = requested ?? 'debug';
  if (mode !== 'debug' && mode !== 'release') throw new Error('Unknown performance build mode');
  if ((mode === 'debug') !== actualDebug) throw new Error('Performance build mode/application debug mismatch');
  return mode;
}

/** Mirrors the product history clock: count frames from a previously running interval. */
export class EmulatedProgress {
  playedMs: number = 0;
  private lastSource: number = -1;
  private wasRunning: boolean = false;

  sample(sourceFrames: number, sourceFps: number, running: boolean): void {
    if (this.lastSource >= 0 && this.wasRunning && sourceFps > 0 && Number.isFinite(sourceFps)) {
      this.playedMs += Math.max(0, sourceFrames - this.lastSource) * 1000 / sourceFps;
    }
    this.lastSource = sourceFrames;
    this.wasRunning = running;
  }
}
