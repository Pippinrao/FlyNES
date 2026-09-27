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
            owner.gameTitle(selection.title);
            owner.gameKey(selection.entry.canonicalId);
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
                scenario.onActivity(activity -> activity.findViewById(R.id.pause_button).performClick());
                scenario.onActivity(activity -> activity.findViewById(R.id.pause_game_center).performClick());
                SystemClock.sleep(300);
                assertTrue("return to room preserves the loaded game",
                        host.snapshot()[0] == NearbyMvpSession.RUNNING);
                long heldFrame = host.completedFrames();
                SystemClock.sleep(100);
                assertTrue("room pauses original progress", host.completedFrames() == heldFrame);
            }
            long roomFrame = host.completedFrames();
            try (ActivityScenario<NearbyLobbyActivity> room = ActivityScenario.launch(NearbyLobbyActivity.class)) {
                room.onActivity(activity -> {
                    assertTrue("room offers continue for the loaded game",
                            activity.findViewById(R.id.nearby_lobby_resume).isShown());
                    assertTrue("room retains the current title", owner.gameTitle().equals(selection.title));
                    assertTrue("room retains screenshot identity", owner.gameKey().equals(selection.entry.canonicalId));
                    activity.findViewById(R.id.nearby_lobby_choose_game).performClick();
                });
                SystemClock.sleep(500);
                assertTrue("opening the picker retains paused progress", host.completedFrames() == roomFrame);
                assertTrue("guest can continue while host browses games", guest.resumeGame());
                deadline = SystemClock.elapsedRealtime() + 3000;
                while (host.completedFrames() <= roomFrame + 5 && SystemClock.elapsedRealtime() < deadline)
                    SystemClock.sleep(10);
                assertTrue("continue advances the original frame counter", host.completedFrames() > roomFrame + 5);
                SystemClock.sleep(600);
                androidx.test.espresso.Espresso.onView(androidx.test.espresso.matcher.ViewMatchers.withId(R.id.pause_button))
                        .check(androidx.test.espresso.assertion.ViewAssertions.matches(
                                androidx.test.espresso.matcher.ViewMatchers.isDisplayed()));
            }
        } finally {
            owner.close();
            guest.close();
        }
    }
}
