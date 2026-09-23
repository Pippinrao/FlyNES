package com.flynes.emu;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;

import org.junit.Test;

public final class NearbyNetworkInviteTest {
    private static final String INVITE = "flynes-lan-v1:192.168.43.1:45321:"
            + "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:"
            + "0123456789abcdef0123456789abcdef";

    @Test public void plainInvitationNeedsNoWifiSetup() {
        NearbyNetworkInvite decoded = NearbyNetworkInvite.parse(INVITE);
        assertEquals(INVITE, decoded.lanInvite());
        assertFalse(decoded.hasWifi());
    }

    @Test public void wifiEnvelopeRoundTripsCredentialsAndInvitation() {
        String encoded = NearbyNetworkInvite.withWifi("Fly:热点 1", "pa:ss word", INVITE);
        NearbyNetworkInvite decoded = NearbyNetworkInvite.parse(encoded);
        assertEquals("Fly:热点 1", decoded.ssid());
        assertEquals("pa:ss word", decoded.passphrase());
        assertEquals(INVITE, decoded.lanInvite());
    }

    @Test public void rejectsMalformedOrUnboundedEnvelope() {
        assertNull(NearbyNetworkInvite.parse("flynes-wifi-v1:ssid:pass"));
        assertNull(NearbyNetworkInvite.parse("flynes-wifi-v1:ssid:pass:wrong"));
        assertNull(NearbyNetworkInvite.parse("flynes-wifi-v1:%ZZ:pass:" + INVITE));
        assertNull(NearbyNetworkInvite.parse("flynes-wifi-v1:" + "a".repeat(300) + ":pass:" + INVITE));
    }

    @Test public void rejectsUnroutableOrMalformedLanInvitations() {
        for (String address : new String[]{"999.168.43.1", "127.0.0.1", "169.254.1.2",
                "224.1.2.3", "192.168.1.0", "192.168.1.255"}) {
            String bad = INVITE.replace("192.168.43.1", address);
            assertNull(address, NearbyNetworkInvite.parse(bad));
            assertNull(address, NearbyNetworkInvite.parse("flynes-wifi-v1:Room:password:" +
                    bad.replace(":", "%3A")));
        }
        assertNull(NearbyNetworkInvite.parse(INVITE.replace(":45321:", ":65536:")));
        assertNull(NearbyNetworkInvite.parse(INVITE.replaceFirst("0123456789abcdef", "zzzzzzzzzzzzzzzz")));
    }
}
