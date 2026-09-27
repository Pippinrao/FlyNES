import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import nativeSession from 'libentry.so';

export interface NearbyHostPort {
  host(token: Uint8Array): boolean;
  invite(): string;
  cancel(): void;
}

class NativeHostPort implements NearbyHostPort {
  host(token: Uint8Array): boolean { return nativeSession.nearbyMvpHost(token); }
  invite(): string { return nativeSession.nearbyMvpInvite(); }
  cancel(): void { nativeSession.nearbyMvpCancel(); }
}

function secureToken(): Uint8Array {
  return cryptoFramework.createRandom().generateRandomSync(16).data;
}

/** The native session owns the invitation across page navigation. */
export class NearbyMvpHostFlow {
  private readonly port: NearbyHostPort;
  private readonly token: () => Uint8Array;

  constructor(port: NearbyHostPort = new NativeHostPort(), token: () => Uint8Array = secureToken) {
    this.port = port;
    this.token = token;
  }

  start(): boolean {
    const value = this.token();
    if (value.length !== 16) return false;
    try { return this.port.host(value); }
    finally { value.fill(0); }
  }

  invite(): string { return this.port.invite(); }
  hidePage(): void { }
  disconnect(): void { this.port.cancel(); }
}
