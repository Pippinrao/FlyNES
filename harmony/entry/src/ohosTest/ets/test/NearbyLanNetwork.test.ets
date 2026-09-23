import { describe, it, expect } from '@ohos/hypium';
import { parseWifiEnvelope, parseLanInvite } from
  '../../../main/ets/service/NearbyLanNetwork';

const INVITE: string = 'flynes-lan-v1:192.168.43.1:4242:' + 'a'.repeat(64) + ':' + 'b'.repeat(32);

export default function nearbyLanNetworkTest(): void {
  describe('NearbyLanNetwork', () => {
    it('wifi_envelope_decodes_colons_spaces_and_unicode', 0, () => {
      const envelope = 'flynes-wifi-v1:Caf%C3%A9%3A%20NES:pass%3Aword%208:' + encodeURIComponent(INVITE);
      const parsed = parseWifiEnvelope(envelope);
      expect(parsed !== null).assertTrue();
      expect(parsed!.ssid).assertEqual('Café: NES');
      expect(parsed!.passphrase).assertEqual('pass:word 8');
      expect(parsed!.invite).assertEqual(INVITE);
    });

    it('wifi_envelope_rejects_malformed_fields', 0, () => {
      expect(parseWifiEnvelope('flynes-wifi-v1:bad%ZZ:password8:' + encodeURIComponent(INVITE)) === null)
        .assertTrue();
      expect(parseWifiEnvelope('flynes-wifi-v1:' + 'x'.repeat(33) + ':password8:' + encodeURIComponent(INVITE)) === null)
        .assertTrue();
      expect(parseWifiEnvelope('flynes-wifi-v1:Test:short:' + encodeURIComponent(INVITE)) === null)
        .assertTrue();
      expect(parseWifiEnvelope('flynes-wifi-v1:Test:password8:invalid') === null).assertTrue();
    });

    it('lan_invite_requires_valid_endpoint_and_pin', 0, () => {
      expect(parseLanInvite(INVITE)).assertEqual(4242);
      expect(parseLanInvite(INVITE.replace(':4242:', ':0:'))).assertEqual(0);
      expect(parseLanInvite(INVITE.replace('192.168.43.1', '127.0.0.1'))).assertEqual(0);
      expect(parseLanInvite(INVITE + ':extra')).assertEqual(0);
    });

  });
}
