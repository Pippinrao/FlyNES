package com.flynes.emu;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.concurrent.atomic.AtomicInteger;

public final class NearbyGuestConnectFlowTest {
    private static final String INVITE = "flynes-lan-v1:192.168.43.1:45321:"
            + "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:"
            + "0123456789abcdef0123456789abcdef";

    @Test public void plainInvitationJoinsImmediatelyOnLan() {
        FakeWifi wifi = new FakeWifi();
        AtomicInteger joins = new AtomicInteger();
        NearbyGuestConnectFlow flow = new NearbyGuestConnectFlow(wifi,
                (ip, invite) -> { joins.incrementAndGet(); return "10.0.0.2".equals(ip) && INVITE.equals(invite); });
        assertTrue(flow.start(INVITE, "10.0.0.2"));
        assertEquals(1, joins.get());
        assertEquals(0, wifi.requests);
    }

    @Test public void wifiInvitationWaitsForJoinAndDropsLateCallbackAfterCancel() {
        FakeWifi wifi = new FakeWifi();
        AtomicInteger joins = new AtomicInteger();
        NearbyGuestConnectFlow flow = new NearbyGuestConnectFlow(wifi,
                (ip, invite) -> { joins.incrementAndGet(); return true; });
        String payload = NearbyNetworkInvite.withWifi("Room", "password", INVITE);
        assertTrue(flow.start(payload, null));
        assertEquals(1, wifi.requests);
        assertEquals(0, joins.get());
        NearbyGuestConnectFlow.WifiReady callback = wifi.callback;
        flow.cancel();
        callback.onReady("192.168.43.22");
        assertEquals(0, joins.get());
        assertTrue(wifi.closed);
    }

    @Test public void wifiReadyJoinsInnerInvitationOnly() {
        FakeWifi wifi = new FakeWifi();
        NearbyGuestConnectFlow flow = new NearbyGuestConnectFlow(wifi,
                (ip, invite) -> "192.168.43.22".equals(ip) && INVITE.equals(invite));
        assertTrue(flow.start(NearbyNetworkInvite.withWifi("Room", "password", INVITE), null));
        assertTrue(wifi.callback.onReady("192.168.43.22"));
        assertFalse(flow.waitingForWifi());
    }

    @Test public void deniedWifiRequestReportsManualFallback() {
        FakeWifi wifi = new FakeWifi();
        AtomicInteger failures = new AtomicInteger();
        NearbyGuestConnectFlow flow = new NearbyGuestConnectFlow(wifi,
                (ip, invite) -> true, failures::incrementAndGet);
        assertTrue(flow.start(NearbyNetworkInvite.withWifi("Room", "password", INVITE), null));
        wifi.callback.onFailed();
        assertEquals(1, failures.get());
        assertFalse(flow.waitingForWifi());
    }

    private static final class FakeWifi implements NearbyGuestConnectFlow.WifiPort {
        int requests;
        boolean closed;
        NearbyGuestConnectFlow.WifiReady callback;
        @Override public void connect(String ssid, String password, NearbyGuestConnectFlow.WifiReady ready) {
            requests++;
            callback = ready;
        }
        @Override public void close() { closed = true; }
    }
}
