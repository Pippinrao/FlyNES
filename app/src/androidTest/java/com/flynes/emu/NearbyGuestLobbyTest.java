package com.flynes.emu;

import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

@RunWith(AndroidJUnit4.class)
public final class NearbyGuestLobbyTest {
    @Test public void guestSelectsTheHostsMatchingLocalRom() throws Exception {
        FlyNesApplication app = (FlyNesApplication) ApplicationProvider.getApplicationContext();
        NearbyMvpOwner guest = app.nearbyMvpOwner();
        guest.close();
        NearbyMvpSession host = new NearbyMvpSession();
        try {
            String address = NearbyMvpLanAddress.current();
            assertTrue(address != null && host.host(address));
            String invite = awaitInvite(host);
            assertTrue(guest.startGuest(address, invite));
            NearbyMvpSession joiner = guest.session();
            long deadline = android.os.SystemClock.elapsedRealtime() + 10_000;
            int hostState = 0;
            int guestState = 0;
            while (android.os.SystemClock.elapsedRealtime() < deadline) {
                hostState = host.snapshot()[0];
                guestState = joiner.snapshot()[0];
                if (hostState == NearbyMvpSession.LOBBY && guestState == NearbyMvpSession.LOBBY) break;
                android.os.SystemClock.sleep(10);
            }
            assertEquals("host=" + java.util.Arrays.toString(host.snapshot())
                    + " guest=" + java.util.Arrays.toString(joiner.snapshot()),
                    NearbyMvpSession.LOBBY, joiner.snapshot()[0]);
            NearbyMvpGame.Selection selected = NearbyMvpGame.load(app);
            assertTrue(host.selectGame(selected.rom, selected.entry.canonicalId));
            try (ActivityScenario<NearbyLobbyActivity> ignored =
                         ActivityScenario.launch(NearbyLobbyActivity.class)) {
                deadline = android.os.SystemClock.elapsedRealtime() + 5_000;
                while (android.os.SystemClock.elapsedRealtime() < deadline
                        && joiner.snapshot()[5] == 0) {
                    host.snapshot();
                    android.os.SystemClock.sleep(20);
                }
                assertEquals("guest should configure the host's game", 1, joiner.snapshot()[5]);
                assertEquals("guest should keep P2", 2, joiner.snapshot()[4]);
                ignored.onActivity(activity -> {
                    android.widget.LinearLayout seat =
                            activity.findViewById(R.id.nearby_lobby_row_seat);
                    assertEquals("P2", ((android.widget.TextView) seat.getChildAt(1)).getText());
                    assertTrue("guest cannot replace the host's game",
                            !activity.findViewById(R.id.nearby_lobby_row_rom_identity).isClickable());
                });
            }
        } finally {
            guest.close();
            host.close();
        }
    }

    @Test public void guestRetriesWhenHostChangesRomButKeepsTheGameKey() throws Exception {
        FlyNesApplication app = (FlyNesApplication) ApplicationProvider.getApplicationContext();
        NearbyMvpOwner guest = app.nearbyMvpOwner();
        guest.close();
        NearbyMvpSession host = new NearbyMvpSession();
        try {
            String address = NearbyMvpLanAddress.current();
            assertTrue(address != null && host.host(address));
            assertTrue(guest.startGuest(address, awaitInvite(host)));
            NearbyMvpSession joiner = guest.session();
            long deadline = android.os.SystemClock.elapsedRealtime() + 10_000;
            while (android.os.SystemClock.elapsedRealtime() < deadline &&
                    (host.snapshot()[0] != NearbyMvpSession.LOBBY ||
                     joiner.snapshot()[0] != NearbyMvpSession.LOBBY))
                android.os.SystemClock.sleep(10);
            assertEquals(NearbyMvpSession.LOBBY, joiner.snapshot()[0]);
            NearbyMvpGame.Selection selected = NearbyMvpGame.load(app);
            byte[] otherVariant = selected.rom.clone();
            otherVariant[otherVariant.length / 2] ^= 1;
            assertTrue(host.selectGame(otherVariant, selected.entry.canonicalId));
            try (ActivityScenario<NearbyLobbyActivity> ignored =
                         ActivityScenario.launch(NearbyLobbyActivity.class)) {
                deadline = android.os.SystemClock.elapsedRealtime() + 5_000;
                while (android.os.SystemClock.elapsedRealtime() < deadline &&
                        joiner.snapshot()[1] != 7) android.os.SystemClock.sleep(20);
                assertEquals("first ROM variant must mismatch", 0, joiner.snapshot()[5]);
                String firstConfig = joiner.peerConfigToken();
                assertTrue(host.selectGame(selected.rom, selected.entry.canonicalId));
                deadline = android.os.SystemClock.elapsedRealtime() + 5_000;
                while (android.os.SystemClock.elapsedRealtime() < deadline &&
                        (joiner.snapshot()[5] == 0 || firstConfig.equals(joiner.peerConfigToken())))
                    android.os.SystemClock.sleep(20);
                assertTrue("host's changed configuration must be visible",
                        !firstConfig.equals(joiner.peerConfigToken()));
                assertEquals("guest must retry the now-matching ROM", 1, joiner.snapshot()[5]);
            }
        } finally {
            guest.close();
            host.close();
        }
    }

    private static String awaitInvite(NearbyMvpSession host) {
        long deadline = android.os.SystemClock.elapsedRealtime() + 5_000;
        String invite;
        do {
            invite = host.invite();
            if (invite != null) return invite;
            android.os.SystemClock.sleep(10);
        } while (android.os.SystemClock.elapsedRealtime() < deadline);
        throw new AssertionError("host did not publish an invitation");
    }
}
