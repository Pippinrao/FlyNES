package com.flynes.emu;

import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

@RunWith(AndroidJUnit4.class)
public final class NearbyLobbyHostChoiceTest {
    @Test public void pairingLeavesTheHostInAnEmptyLobbyUntilTheyChooseFromTheGameCenter()
            throws Exception {
        FlyNesApplication app = ApplicationProvider.getApplicationContext();
        NearbyMvpOwner owner = app.nearbyMvpOwner();
        owner.close();
        NearbyMvpSession guest = new NearbyMvpSession();
        try {
            String address = NearbyMvpLanAddress.current();
            assertTrue(address != null && owner.startHost(address));
            NearbyMvpSession host = owner.session();
            String invite = null;
            long deadline = android.os.SystemClock.elapsedRealtime() + 5_000;
            while (invite == null && android.os.SystemClock.elapsedRealtime() < deadline) {
                invite = host.invite();
                android.os.SystemClock.sleep(10);
            }
            assertTrue(invite != null && guest.join(address, invite));
            deadline = android.os.SystemClock.elapsedRealtime() + 10_000;
            while ((host.snapshot()[0] != NearbyMvpSession.LOBBY ||
                    guest.snapshot()[0] != NearbyMvpSession.LOBBY) &&
                    android.os.SystemClock.elapsedRealtime() < deadline)
                android.os.SystemClock.sleep(10);
            assertEquals(NearbyMvpSession.LOBBY, host.snapshot()[0]);
            try (ActivityScenario<NearbyLobbyActivity> scenario =
                         ActivityScenario.launch(NearbyLobbyActivity.class)) {
                android.os.SystemClock.sleep(600);
                assertEquals("pairing must not select a default game", NearbyMvpSession.LOBBY,
                        host.snapshot()[0]);
                assertEquals("", owner.gameTitle());
                scenario.onActivity(activity -> {
                    assertTrue(activity.findViewById(R.id.nearby_lobby_row_rom_identity)
                            .hasOnClickListeners());
                    assertEquals("there is no entry confirmation step", 0,
                            activity.getResources().getIdentifier("nearby_lobby_confirm", "id",
                                    activity.getPackageName()));
                });
            }
        } finally {
            owner.close();
            guest.close();
        }
    }
}
