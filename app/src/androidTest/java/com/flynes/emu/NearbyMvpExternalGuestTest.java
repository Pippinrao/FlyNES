package com.flynes.emu;

import android.content.Intent;
import android.os.SystemClock;

import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.platform.app.InstrumentationRegistry;

import com.flynes.emu.video.GameSurfaceView;

import org.junit.Test;
import org.junit.Assume;

import static org.junit.Assert.*;

/** Opt-in external simulator pairing through the product's guest owner and playback surface. */
public final class NearbyMvpExternalGuestTest {
    @Test public void guestUsesProductGpuAudioAndP2Input() throws Exception {
        FlyNesApplication app = ApplicationProvider.getApplicationContext();
        String invite = InstrumentationRegistry.getArguments().getString("crossAppInvite", "");
        Assume.assumeTrue("Run only with an external simulator host", !invite.isEmpty());
        assertTrue("External invitation is required", invite.startsWith("flynes-lan-v1:"));
        // Physical devices can defer ActivityScenario's launch from a background
        // instrumentation process. Establish the foreground before the peer starts.
        try (android.os.ParcelFileDescriptor descriptor = InstrumentationRegistry
                .getInstrumentation().getUiAutomation().executeShellCommand(
                        "am start -W -n com.flynes.emu/.HomeActivity");
             java.io.FileInputStream output = new java.io.FileInputStream(descriptor.getFileDescriptor())) {
            String foreground = new String(output.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
            assertTrue("Game center must enter the foreground: " + foreground,
                    foreground.contains("Status: ok"));
        }
        NearbyMvpOwner owner = app.nearbyMvpOwner();
        owner.close();
        try {
            assertTrue(owner.startGuest(NearbyMvpLanAddress.current(), invite));
            NearbyMvpSession session = owner.session();
            long deadline = SystemClock.elapsedRealtime() + 20_000;
            while (session.snapshot()[0] != NearbyMvpSession.LOBBY &&
                    session.snapshot()[0] != NearbyMvpSession.CONFIGURING &&
                    session.snapshot()[0] != NearbyMvpSession.ENDED &&
                    SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(10);
            int[] joined = session.snapshot();
            assertTrue("Guest must connect before host configuration: state=" + joined[0] + " reason=" + joined[1],
                    joined[0] == NearbyMvpSession.LOBBY || joined[0] == NearbyMvpSession.CONFIGURING);
            deadline = SystemClock.elapsedRealtime() + 15_000;
            while (session.peerGameKey().isEmpty() && SystemClock.elapsedRealtime() < deadline)
                SystemClock.sleep(10);
            String key = session.peerGameKey();
            assertFalse("Host must publish a catalog game identity", key.isEmpty());
            NearbyMvpGame.Selection selection = NearbyMvpGame.load(app, key);
            assertTrue(session.selectRom(selection.rom));
            assertTrue(session.confirm());
            deadline = SystemClock.elapsedRealtime() + 15_000;
            while (session.snapshot()[0] != NearbyMvpSession.RUNNING &&
                    SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(10);
            assertEquals(NearbyMvpSession.RUNNING, session.snapshot()[0]);
            assertEquals(NearbyMvpSession.GUEST_P2, session.snapshot()[4]);
            assertTrue(session.submitInput(0x01));
            deadline = SystemClock.elapsedRealtime() + 1000;
            while (session.snapshot()[10] != 0x01 && SystemClock.elapsedRealtime() < deadline)
                SystemClock.sleep(5);
            assertEquals("P2 input reaches a completed core frame", 0x01, session.snapshot()[10]);
            try (ActivityScenario<MainActivity> page = ActivityScenario.launch(
                    new Intent(app, MainActivity.class).putExtra("nearby_mvp", true))) {
                long roomHoldMs = Long.parseLong(InstrumentationRegistry.getArguments()
                        .getString("roomHoldMs", "0"));
                int requiredFrames = roomHoldMs > 0 ? 120 : 600;
                deadline = SystemClock.elapsedRealtime() + 20_000;
                while (session.completedFrames() < requiredFrames &&
                        SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(20);
                assertTrue("External guest must play " + requiredFrames + " real frames",
                        session.completedFrames() >= requiredFrames);
                page.onActivity(activity -> {
                    GameSurfaceView surface = activity.findViewById(R.id.game_surface);
                    assertNotNull(surface);
                    assertTrue("Shared GPU presenter consumes guest frames",
                            surface.presenterStats().uploadedFrames() > (roomHoldMs > 0 ? 30 : 100));
                    assertTrue("AudioTrack consumes guest PCM",
                            activity.nearbyAudioWrittenSamplesForTest() > 0);
                });
                long holdMs = Long.parseLong(InstrumentationRegistry.getArguments()
                        .getString("playHoldMs", "0"));
                if (roomHoldMs > 0) SystemClock.sleep(roomHoldMs);
                if (holdMs > 0) {
                    byte[] firstSessionId = session.sessionId();
                    long holdDeadline = SystemClock.elapsedRealtime() + holdMs;
                    boolean reconfigured = false;
                    boolean secondGamePlayed = false;
                    while (SystemClock.elapsedRealtime() < holdDeadline) {
                        int[] state = session.snapshot();
                        if (state[0] == NearbyMvpSession.CONFIGURING && state[5] == 0) {
                            String nextKey = session.peerGameKey();
                            if (!nextKey.isEmpty()) {
                                assertNotEquals("The host must pick a different game", key, nextKey);
                                NearbyMvpGame.Selection next = NearbyMvpGame.load(app, nextKey);
                                assertTrue(session.selectRom(next.rom));
                                assertTrue(session.confirm());
                                reconfigured = true;
                            }
                        }
                        if (reconfigured && !secondGamePlayed
                                && state[0] == NearbyMvpSession.RUNNING
                                && session.completedFrames() > 30) {
                            assertArrayEquals(firstSessionId, session.sessionId());
                            secondGamePlayed = true;
                        }
                        SystemClock.sleep(20);
                    }
                    assertTrue("Guest must follow host's same-session game switch", reconfigured);
                    assertTrue("Second game must advance on guest", secondGamePlayed);
                }
            }
        } finally {
            owner.close();
        }
    }
}
