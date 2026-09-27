package com.flynes.emu;

import android.content.Intent;
import android.os.SystemClock;

import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;

import com.flynes.emu.video.GameSurfaceView;

import org.junit.Test;
import org.junit.runner.RunWith;

import static org.junit.Assert.assertTrue;

@RunWith(AndroidJUnit4.class)
public final class NearbyMvpPresentationTest {
    @Test public void realSessionUsesSoloGpuPresenterAndWritesPcm() throws Exception {
        FlyNesApplication app = (FlyNesApplication) ApplicationProvider.getApplicationContext();
        NearbyMvpOwner owner = app.nearbyMvpOwner();
        owner.close();
        NearbyMvpSession guest = new NearbyMvpSession();
        try {
            String address = NearbyMvpLanAddress.current();
            assertTrue(address != null && owner.startHost(address));
            NearbyMvpSession host = owner.session();
            String invite = null;
            long deadline = SystemClock.elapsedRealtime() + 5000;
            while (SystemClock.elapsedRealtime() < deadline && invite == null) {
                invite = host.invite();
                SystemClock.sleep(10);
            }
            assertTrue(invite != null && guest.join(address, invite));
            deadline = SystemClock.elapsedRealtime() + 5000;
            while (SystemClock.elapsedRealtime() < deadline) {
                int hostState = host.snapshot()[0];
                int guestState = guest.snapshot()[0];
                if (hostState == NearbyMvpSession.LOBBY &&
                        guestState == NearbyMvpSession.LOBBY) break;
                SystemClock.sleep(10);
            }
            NearbyMvpGame.Selection selection = NearbyMvpGame.load(app);
            assertTrue(host.selectGame(selection.rom, selection.entry.canonicalId));
            assertTrue(guest.selectRom(selection.rom));
            assertTrue(host.confirm());
            assertTrue(guest.confirm());
            deadline = SystemClock.elapsedRealtime() + 5000;
            while (SystemClock.elapsedRealtime() < deadline) {
                int hostState = host.snapshot()[0];
                int guestState = guest.snapshot()[0];
                if (hostState == NearbyMvpSession.RUNNING &&
                        guestState == NearbyMvpSession.RUNNING) break;
                SystemClock.sleep(10);
            }
            assertTrue("both apps enter play", host.snapshot()[0] == NearbyMvpSession.RUNNING);
            Intent intent = new Intent(app, MainActivity.class).putExtra("nearby_mvp", true);
            try (ActivityScenario<MainActivity> scenario = ActivityScenario.launch(intent)) {
                deadline = SystemClock.elapsedRealtime() + 5000;
                while (SystemClock.elapsedRealtime() < deadline && host.completedFrames() < 20) {
                    guest.submitInput(0);
                    SystemClock.sleep(8);
                }
                assertTrue("session advances frames", host.completedFrames() >= 20);
                scenario.onActivity(activity -> {
                    assertTrue("nearby uses the solo GPU surface",
                            activity.findViewById(R.id.game_surface) instanceof GameSurfaceView);
                    GameSurfaceView surface = activity.findViewById(R.id.game_surface);
                    assertTrue("native presenter uploads the nearby picture",
                            surface.presenterStats().uploadedFrames() > 0);
                    assertTrue("audio device consumed real nearby PCM",
                            activity.nearbyAudioWrittenSamplesForTest() > 0);
                });
            }
        } finally {
            owner.close();
            guest.close();
        }
    }
}
