package com.flynes.emu;

import com.flynes.emu.catalog.*;
import com.flynes.emu.launch.LaunchRequest;
import org.junit.After;
import org.junit.Test;
import static org.junit.Assert.*;

public class PendingGameLaunchTest {
    @After public void clearFixture() { PendingGameLaunch.consume(); }
    private static LaunchRequest request(String id) {
        return new LaunchRequest(id, "variant", "source", "asset://fixture", null,
                PackageFormat.RAW, RomFormat.INES, CompatibilityState.PLAYABLE,
                new RomHashes("A".repeat(40), "B".repeat(64), "C".repeat(64), "D".repeat(8)), null, null);
    }
    @Test public void finishedHostDiscardsOnlyItsStagedRequest() {
        var request = request("one");
        PendingGameLaunch.stage(request, new byte[] {1});
        PendingGameLaunch.discard(request);
        assertNull(PendingGameLaunch.consume());
    }
    @Test public void lateCancellationCannotRemoveAnotherLaunch() {
        var old = request("one");
        var current = request("two");
        PendingGameLaunch.stage(current, new byte[] {2});
        PendingGameLaunch.discard(old);
        assertSame(current, PendingGameLaunch.consume().request());
    }
}
