export interface WifiEnvelope {
  ssid: string;
  passphrase: string;
  invite: string;
}

function utf8Length(value: string): number {
  return encodeURIComponent(value).replace(/%[0-9A-F]{2}/g, 'x').length;
}

export function parseLanInvite(invite: string): number {
  if (invite.length > 256) return 0;
  const parts = invite.split(':');
  if (parts.length !== 5 || parts[0] !== 'flynes-lan-v1') return 0;
  const ip = parts[1].split('.');
  if (ip.length !== 4) return 0;
  const octets: number[] = [];
  for (const part of ip) {
    if (!/^(0|[1-9][0-9]{0,2})$/.test(part)) return 0;
    const octet = Number(part);
    if (octet > 255) return 0;
    octets.push(octet);
  }
  if (octets[0] === 0 || octets[0] === 127 || octets[0] >= 224 ||
    (octets[0] === 169 && octets[1] === 254) || octets[3] === 0 || octets[3] === 255) return 0;
  if (!/^[1-9][0-9]{0,4}$/.test(parts[2])) return 0;
  const port = Number(parts[2]);
  if (port > 65535 || !/^[a-fA-F0-9]{64}$/.test(parts[3]) || !/^[a-fA-F0-9]{32}$/.test(parts[4])) return 0;
  return port;
}

export function parseWifiEnvelope(text: string): WifiEnvelope | null {
  if (!text.startsWith('flynes-wifi-v1:') || text.length > 1024) return null;
  const fields = text.substring('flynes-wifi-v1:'.length).split(':');
  if (fields.length !== 3 || fields.some((field: string): boolean => field.length === 0)) return null;
  try {
    const ssid = decodeURIComponent(fields[0]);
    const passphrase = decodeURIComponent(fields[1]);
    const invite = decodeURIComponent(fields[2]);
    if (utf8Length(ssid) === 0 || utf8Length(ssid) > 32 ||
      passphrase.length < 8 || passphrase.length > 63 || parseLanInvite(invite) === 0) return null;
    return { ssid: ssid, passphrase: passphrase, invite: invite };
  } catch {
    return null;
  }
}
