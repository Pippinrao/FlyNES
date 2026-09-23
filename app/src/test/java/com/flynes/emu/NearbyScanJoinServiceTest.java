package com.flynes.emu;

import static org.junit.Assert.*;

import org.junit.Test;

public final class NearbyScanJoinServiceTest {
    private static final String INVITE = "flynes-lan-v1:192.168.43.1:4242:"
            + "a".repeat(64) + ":" + "b".repeat(32);

    private static final class Wifi implements NearbyGuestConnectFlow.WifiPort {
        NearbyGuestConnectFlow.WifiReady ready;
        int closes;
        @Override public void connect(String ssid, String passphrase,
                                      NearbyGuestConnectFlow.WifiReady callback) { ready = callback; }
        @Override public void close() { closes++; }
    }

    private static final class Session implements NearbyScanJoinService.SessionPort {
        int joins;
        AutoCloseable lease;
        @Override public boolean join(String ipv4, String invite) { joins++; return INVITE.equals(invite); }
        @Override public void hold(AutoCloseable retained) { lease = retained; }
        @Override public void close() {}
    }

    @Test public void plainQrJoinsLanWithoutWifiPrompt() {
        Wifi wifi = new Wifi();
        Session session = new Session();
        NearbyScanJoinService service = new NearbyScanJoinService(wifi, session, () -> "192.168.43.2");
        assertTrue(service.joinScannedText(INVITE, () -> {}, () -> {}));
        assertEquals(1, session.joins);
        assertNull(wifi.ready);
        assertNull(session.lease);
    }

    @Test public void hotspotQrWaitsForWifiThenRetainsLinkForSession() {
        Wifi wifi = new Wifi();
        Session session = new Session();
        NearbyScanJoinService service = new NearbyScanJoinService(wifi, session, () -> null);
        String qr = NearbyNetworkInvite.withWifi("Host NES", "password8", INVITE);
        assertTrue(service.joinScannedText(qr, () -> {}, () -> {}));
        assertEquals(0, session.joins);
        assertTrue(wifi.ready.onReady("192.168.43.2"));
        assertEquals(1, session.joins);
        assertSame(wifi, session.lease);
    }

    @Test public void cancelledWifiResultCannotStartLanSession() {
        Wifi wifi = new Wifi();
        Session session = new Session();
        NearbyScanJoinService service = new NearbyScanJoinService(wifi, session, () -> null);
        assertTrue(service.joinScannedText(
                NearbyNetworkInvite.withWifi("Host", "password8", INVITE), () -> {}, () -> {}));
        NearbyGuestConnectFlow.WifiReady late = wifi.ready;
        service.close();
        assertFalse(late.onReady("192.168.43.2"));
        assertEquals(0, session.joins);
    }
}
