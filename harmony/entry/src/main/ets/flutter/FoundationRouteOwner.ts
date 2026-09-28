export interface FoundationRouteResult {
  status: string;
  reason: string;
}

/** One native route per engine; stale asynchronous completions cannot claim it. */
export class FoundationRouteOwner {
  private serial: number = 0;
  private pending: number = 0;
  private left: boolean = false;
  private complete: ((result: FoundationRouteResult) => void) | undefined = undefined;

  begin(complete: (result: FoundationRouteResult) => void): number {
    if (this.pending !== 0) return 0;
    this.pending = ++this.serial;
    this.left = false;
    this.complete = complete;
    return this.pending;
  }

  isCurrent(token: number): boolean { return token !== 0 && token === this.pending; }
  hidden(): void { if (this.pending !== 0) this.left = true; }
  shown(reason: string = ''): void {
    if (this.pending !== 0 && this.left) this.finish(reason.length === 0 ? 'returned' : 'unavailable', reason);
  }
  failed(token: number): void {
    if (this.isCurrent(token)) this.finish('unavailable', '当前无法启动游戏');
  }
  cancel(): void { if (this.pending !== 0) this.finish('cancelled', ''); }

  private finish(status: string, reason: string): void {
    const complete = this.complete;
    this.pending = 0;
    this.left = false;
    this.complete = undefined;
    complete?.({ status: status, reason: reason });
  }
}
