export function nativePerformanceEnabled(optIn: string | undefined, entry: string | undefined): boolean {
  if (optIn !== 'true') return false;
  if (entry !== undefined && entry !== 'native') {
    throw new Error('Flutter performance candidate requires prior numerical budget approval');
  }
  return true;
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
