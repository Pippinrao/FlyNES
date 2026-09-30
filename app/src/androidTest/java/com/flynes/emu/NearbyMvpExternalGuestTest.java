package com.flynes.emu;

import android.os.SystemClock;
import android.view.MotionEvent;
import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.platform.app.InstrumentationRegistry;
import com.flynes.emu.input.GamepadHitMap;
import com.flynes.emu.video.GameSurfaceView;
import org.junit.Test;
import org.junit.Assume;
import java.net.*;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicReference;
import static org.junit.Assert.*;

/** Real external host, production guest room/automatic ROM resolution and controls. */
public final class NearbyMvpExternalGuestTest {
    @Test public void guestUsesProductGpuAudioAndP2Input() throws Exception {
        FlyNesApplication app = ApplicationProvider.getApplicationContext();
        var args = InstrumentationRegistry.getArguments();
        String invite = args.getString("crossAppInvite", "");
        Assume.assumeTrue("External host fixture is opt-in", !invite.isEmpty());
        assertTrue(invite.startsWith("flynes-lan-v1:"));
        SimulatorGuestRelay relay = null;
        String local = NearbyMvpLanAddress.current();
        if (!args.getString("simulatorRelayToken", "").isEmpty()) {
            assertTrue("Relay is emulator instrumentation only", android.os.Build.HARDWARE.equals("ranchu") || android.os.Build.HARDWARE.equals("goldfish"));
            relay = new SimulatorGuestRelay(local, Integer.parseInt(args.getString("simulatorRelayPort")), args.getString("simulatorRelayToken"));
            String[] fields = invite.split(":"); fields[1] = local; fields[2] = Integer.toString(relay.port());
            invite = String.join(":", fields);
        }
        NearbyMvpOwner owner = app.nearbyMvpOwner();
        owner.close();
        try {
            assertTrue(owner.startGuest(local, invite));
            NearbyMvpSession session = owner.session();
            long deadline = SystemClock.elapsedRealtime() + 30000;
            while (session.snapshot()[0] != NearbyMvpSession.LOBBY && session.snapshot()[0] != NearbyMvpSession.CONFIGURING && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(20);
            assertTrue(session.snapshot()[0] == NearbyMvpSession.LOBBY || session.snapshot()[0] == NearbyMvpSession.CONFIGURING);
            byte[] connectedId = session.sessionId();
            try (ActivityScenario<NearbyLobbyActivity> room = ActivityScenario.launch(NearbyLobbyActivity.class)) {
                NearbyMvpProductPlayTest.awaitActivity(MainActivity.class);
                assertEquals(NearbyMvpSession.RUNNING, session.snapshot()[0]);
                assertEquals(NearbyMvpSession.GUEST_P2, session.snapshot()[4]);
                String firstKey = session.peerGameKey();
                assertFalse(firstKey.isEmpty());
                assertEquals("Production room resolves the first ROM", firstKey, owner.gameKey());
                for (GamepadHitMap.Control control : new GamepadHitMap.Control[]{GamepadHitMap.Control.START,
                        GamepadHitMap.Control.SELECT, GamepadHitMap.Control.A, GamepadHitMap.Control.B, GamepadHitMap.Control.RIGHT}) {
                    float[] point = new float[2];
                    NearbyMvpProductPlayTest.onGame(activity -> {
                        GamepadView pad = activity.findViewById(R.id.gamepad);
                        var target = pad.hitMapForTest().target(control);
                        int[] origin = new int[2]; pad.getLocationOnScreen(origin);
                        point[0] = origin[0] + target.centerX(); point[1] = origin[1] + target.centerY();
                    });
                    long down = SystemClock.uptimeMillis(); touch(down, MotionEvent.ACTION_DOWN, point);
                    int mask = control == GamepadHitMap.Control.START ? 8 : control == GamepadHitMap.Control.SELECT ? 4 :
                            control == GamepadHitMap.Control.A ? 1 : control == GamepadHitMap.Control.B ? 2 : 128;
                    deadline = SystemClock.elapsedRealtime() + 2000;
                    while (session.snapshot()[10] != mask && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(10);
                    assertEquals("Real P2 touch reaches a completed frame", mask, session.snapshot()[10]);
                    touch(down, MotionEvent.ACTION_UP, point); SystemClock.sleep(200);
                }
                deadline = SystemClock.elapsedRealtime() + 15000;
                while (session.completedFrames() < 180 && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(20);
                assertTrue(session.completedFrames() >= 180);
                NearbyMvpProductPlayTest.onGame(activity -> {
                    GameSurfaceView surface = activity.findViewById(R.id.game_surface);
                    assertTrue("GPU consumes real guest frames", surface.presenterStats().uploadedFrames() > 30);
                    assertTrue(activity.nearbyAudioWrittenSamplesForTest() > 4800);
                    try {
                        var play = MainActivity.class.getDeclaredField("nearbyPlay"); play.setAccessible(true);
                        var audio = NearbyMvpPlayController.class.getDeclaredField("audio"); audio.setAccessible(true);
                        var track = (android.media.AudioTrack) audio.get(play.get(activity));
                        assertTrue("AudioTrack actually consumes PCM", Integer.toUnsignedLong(track.getPlaybackHeadPosition()) > 4800);
                    } catch (ReflectiveOperationException failure) { throw new AssertionError(failure); }
                });
                FlutterFoundationIntegrationTest.screenshot("nearby-g2-android-guest.png");
                boolean sawPause = false, sawResume = false;
                long pausedFrame = -1;
                deadline = SystemClock.elapsedRealtime() + Long.parseLong(args.getString("playHoldMs", "90000"));
                while (owner.gameKey().equals(firstKey) && SystemClock.elapsedRealtime() < deadline) {
                    int[] snapshot = session.snapshot();
                    if (snapshot[0] == NearbyMvpSession.RUNNING && snapshot.length > 11 && snapshot[11] != 0) {
                        sawPause = true; pausedFrame = session.completedFrames();
                    } else if (sawPause && snapshot[0] == NearbyMvpSession.RUNNING && session.completedFrames() > pausedFrame + 10) sawResume = true;
                    assertArrayEquals("Room operations retain the connection", connectedId, session.sessionId());
                    SystemClock.sleep(20);
                }
                assertTrue("Guest observes host pause", sawPause);
                assertTrue("Guest resumes the retained game", sawResume);
                while ((session.snapshot()[0] != NearbyMvpSession.RUNNING || session.completedFrames() <= 30) && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(20);
                assertEquals(NearbyMvpSession.RUNNING, session.snapshot()[0]);
                assertNotEquals("Production guest lobby follows second ROM", firstKey, owner.gameKey());
                assertFalse(owner.gameKey().isEmpty());
                assertEquals(session.peerGameKey(), owner.gameKey());
                assertArrayEquals(connectedId, session.sessionId());
                assertTrue(session.completedFrames() > 30);
                NearbyMvpProductPlayTest.awaitActivity(MainActivity.class);
                android.util.Log.i("FlyNesNearby", "event=guest_product_switch second_game=PASS same_session=true");
                SystemClock.sleep(5000);
            }
        } finally {
            owner.close(); if (relay != null) relay.close();
        }
    }
    private static void touch(long down, int action, float[] point) {
        MotionEvent event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, point[0], point[1], 0);
        event.setSource(android.view.InputDevice.SOURCE_TOUCHSCREEN);
        try { InstrumentationRegistry.getInstrumentation().sendPointerSync(event); } finally { event.recycle(); }
    }

    /** Task-owned sockets; local native QUIC packets stay opaque and unchanged. */
    private static final class SimulatorGuestRelay implements AutoCloseable {
        final DatagramSocket local, external;
        final InetSocketAddress server;
        final byte[] prefix;
        final AtomicReference<SocketAddress> nativePeer = new AtomicReference<>();
        final AtomicReference<Throwable> failure = new AtomicReference<>();
        final Thread fromNative, fromRelay;
        volatile boolean closed;
        final long deadline = SystemClock.elapsedRealtime() + 180000;
        SimulatorGuestRelay(String address, int port, String token) throws Exception {
            assertTrue(token.matches("[a-f0-9]{32}")); assertTrue(port >= 1024 && port <= 65535);
            local = new DatagramSocket(new InetSocketAddress(address, 0));
            external = new DatagramSocket(new InetSocketAddress(address, 0));
            local.setSoTimeout(200); external.setSoTimeout(200);
            server = new InetSocketAddress("10.0.2.2", port);
            prefix = ("FG2|" + token + "|G|").getBytes(java.nio.charset.StandardCharsets.US_ASCII);
            fromNative = new Thread(() -> pump(true, address), "g2-relay-native");
            fromRelay = new Thread(() -> pump(false, address), "g2-relay-external");
            external.send(new DatagramPacket(prefix, prefix.length, server));
            fromNative.start(); fromRelay.start();
        }
        int port() { return local.getLocalPort(); }
        void pump(boolean nativeSide, String address) {
            long registration = 0;
            try {
                while (!closed && SystemClock.elapsedRealtime() < deadline) {
                    if (nativeSide && SystemClock.elapsedRealtime() > registration) {
                        external.send(new DatagramPacket(prefix, prefix.length, server)); registration = SystemClock.elapsedRealtime() + 500;
                    }
                    byte[] buffer = new byte[65535]; DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
                    try { (nativeSide ? local : external).receive(packet); } catch (SocketTimeoutException ignored) { continue; }
                    if (packet.getLength() > 65460) continue;
                    if (nativeSide) {
                        if (!packet.getAddress().getHostAddress().equals(address)) continue;
                        nativePeer.compareAndSet(null, packet.getSocketAddress());
                        if (!nativePeer.get().equals(packet.getSocketAddress())) continue;
                        byte[] wrapped = Arrays.copyOf(prefix, prefix.length + packet.getLength());
                        System.arraycopy(buffer, 0, wrapped, prefix.length, packet.getLength());
                        external.send(new DatagramPacket(wrapped, wrapped.length, server));
                    } else if (server.equals(packet.getSocketAddress()) && nativePeer.get() != null) {
                        local.send(new DatagramPacket(buffer, packet.getLength(), nativePeer.get()));
                    }
                }
            } catch (Throwable error) { if (!closed) failure.set(error); }
        }
        public void close() throws Exception {
            closed = true; local.close(); external.close(); fromNative.join(2000); fromRelay.join(2000);
            assertFalse(fromNative.isAlive()); assertFalse(fromRelay.isAlive()); assertNull(failure.get());
        }
    }
}
