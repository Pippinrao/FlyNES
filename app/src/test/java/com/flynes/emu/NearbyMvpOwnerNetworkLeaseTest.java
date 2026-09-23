package com.flynes.emu;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.util.concurrent.atomic.AtomicInteger;

public final class NearbyMvpOwnerNetworkLeaseTest {
    @Test public void hostRegenerationKeepsHotspotButLeavingReleasesItOnce() {
        NearbyMvpOwner owner = new NearbyMvpOwner();
        AtomicInteger releases = new AtomicInteger();
        owner.attachNetworkLease(releases::incrementAndGet);
        owner.resetSessionKeepingNetwork();
        assertEquals(0, releases.get());
        owner.close();
        owner.close();
        assertEquals(1, releases.get());
    }

    @Test public void replacingNetworkLeaseReleasesPreviousLease() {
        NearbyMvpOwner owner = new NearbyMvpOwner();
        AtomicInteger releases = new AtomicInteger();
        owner.attachNetworkLease(releases::incrementAndGet);
        owner.attachNetworkLease(releases::incrementAndGet);
        assertEquals(1, releases.get());
        owner.close();
        assertEquals(2, releases.get());
    }
}
