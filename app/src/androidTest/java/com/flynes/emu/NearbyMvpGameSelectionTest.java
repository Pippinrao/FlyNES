package com.flynes.emu;

import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;

import com.flynes.emu.catalog.BuiltinGames;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.IOException;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;

@RunWith(AndroidJUnit4.class)
public final class NearbyMvpGameSelectionTest {
    @Test public void guestLoadsOnlyTheHostSelectedGame() throws Exception {
        android.content.Context context = ApplicationProvider.getApplicationContext();
        NearbyMvpGame.Selection host = NearbyMvpGame.load(context);
        NearbyMvpGame.Selection guest = NearbyMvpGame.load(context, host.entry.canonicalId);
        assertEquals(host.entry.canonicalId, guest.entry.canonicalId);
        assertArrayEquals(host.rom, guest.rom);
    }

    @Test public void missingPeerGameDoesNotSilentlyPickAnotherRom() throws Exception {
        android.content.Context context = ApplicationProvider.getApplicationContext();
        try {
            NearbyMvpGame.load(context, "unknown-canonical-id");
            fail("a missing peer game must stop local confirmation");
        } catch (IOException expected) {
            // The caller shows a local-content error instead of confirming a different ROM.
        }
    }
}
