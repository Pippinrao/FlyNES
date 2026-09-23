package com.flynes.emu;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

public final class NearbyUiNetworkPathTest {
    @Test public void connectedLanWinsOverHotspot() {
        assertEquals("192.168.1.18", NearbyUiNetworkPath.choose(
                new String[]{"169.254.4.5", "192.168.1.18"}, "10.42.0.1"));
    }

    @Test public void hotspotFollowsWhenLanIsMissing() {
        assertEquals("10.42.0.1", NearbyUiNetworkPath.choose(new String[0], "10.42.0.1"));
    }

    @Test public void noRouteCreatesNoInvitation() {
        assertNull(NearbyUiNetworkPath.choose(new String[]{"127.0.0.1"}, null));
    }
}
