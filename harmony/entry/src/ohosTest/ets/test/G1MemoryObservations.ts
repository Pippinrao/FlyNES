export function memoryRoundTripsEnabled(optIn: string | undefined, approved: string | undefined): boolean {
  if (optIn !== 'true') return false;
  if (approved !== 'true') throw new Error('Flutter memory candidate requires explicit budget approval');
  return true;
}

/** Missing/zero allocator values cannot certify absence of retained memory. */
export function measuredPositive(value: number): number {
  return Number.isSafeInteger(value) && value > 0 ? value : -1;
}

/** Runtime versions may return bigint despite the API 20 GcStats declaration. */
export function gcStatsForJson(stats: Record<string, number | bigint>): Record<string, string> {
  const result: Record<string, string> = {};
  for (const key of Object.keys(stats)) result[key] = String(stats[key]);
  return result;
}

export function gcCountFromStat(value: string | undefined): number {
  if (value === undefined || !/^\d+$/.test(value)) return -1;
  const count = Number(value);
  return Number.isSafeInteger(count) && count >= 0 ? count : -1;
}

/** One bounded ASCII JSON line per loopback connection. */
export class DartAckFrame {
  private text: string = '';
  private complete: boolean = false;
  push(chunk: string): string {
    if (this.complete) throw new Error('ACK frame already complete');
    this.text += chunk;
    if (this.text.length > 16384) throw new Error('ACK too large');
    const end = this.text.indexOf('\n');
    if (end < 0) return '';
    if (end !== this.text.length - 1) throw new Error('Trailing ACK data');
    this.complete = true;
    return this.text.slice(0, end);
  }
}

/** Only evidence from the calling Ark VM; says nothing about Dart or native GC. */
export function gcCountEvidence(before: number, after: number): string {
  if (!Number.isSafeInteger(before) || !Number.isSafeInteger(after) || before < 0 || after < 0) {
    return 'unavailable';
  }
  if (after < before) return 'counter-reset';
  return after > before ? 'observed' : 'not-observed';
}

export function dartHeapWaitEnabled(flag: string | undefined): boolean {
  if (flag === undefined || flag === 'false') return false;
  if (flag !== 'true') throw new Error('Invalid Dart heap wait flag');
  return true;
}

export class DartHeapAck {
  schemaVersion: number = 1;
  runToken: string = '';
  round: number = 0;
  pid: number = 0;
  status: string = '';
  evidenceSha256: string = '';
  isolateId: string = '';
  gcRequested: boolean = false;
  gcObserved: boolean = false;
}

export function validateDartHeapAck(text: string, token: string, round: number, pid: number): DartHeapAck {
  const ack = JSON.parse(text) as DartHeapAck;
  if (ack === null || ack.schemaVersion !== 1 || ack.runToken !== token || ack.round !== round ||
    ack.pid !== pid || ack.status !== 'dart-heap-collected' || typeof ack.isolateId !== 'string' ||
    ack.isolateId.length === 0 || typeof ack.evidenceSha256 !== 'string' ||
    !/^[a-f0-9]{64}$/.test(ack.evidenceSha256) || typeof ack.gcRequested !== 'boolean' ||
    typeof ack.gcObserved !== 'boolean') throw new Error('Invalid or stale Dart heap acknowledgement');
  return ack;
}
