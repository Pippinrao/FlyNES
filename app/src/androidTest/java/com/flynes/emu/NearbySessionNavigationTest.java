package com.flynes.emu;


import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

import static org.junit.Assert.assertTrue;

@RunWith(AndroidJUnit4.class)
public final class NearbySessionNavigationTest {
    @Test public void endedInvitationReturnsToNearbyEntry() {
        FlyNesApplication app = (FlyNesApplication) ApplicationProvider.getApplicationContext();
        String ipv4 = NearbyMvpLanAddress.current();
        assertTrue(ipv4 != null && app.nearbyMvpOwner().startHost(ipv4));
        try (ActivityScenario<NearbyPairingActivity> scenario =
                     ActivityScenario.launch(NearbyPairingActivity.class)) {
            app.nearbyMvpOwner().close();
            try { Thread.sleep(600L); } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
            }
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().waitForIdleSync();
            final boolean[] entry = {false};
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                for (android.app.Activity activity :
                        androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance()
                                .getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED)) {
                    entry[0] = activity instanceof NearbyFriendsActivity;
                }
            });
            assertTrue("ended invitation must return to Nearby entry", entry[0]);
        } finally {
            app.nearbyMvpOwner().close();
        }
    }

    @Test public void endedPlayOpensNearbyEntry() {
        FlyNesApplication app = (FlyNesApplication) ApplicationProvider.getApplicationContext();
        app.nearbyMvpOwner().close();
        android.content.Intent play = new android.content.Intent(app, MainActivity.class)
                .putExtra("nearby_mvp", true);
        try (ActivityScenario<MainActivity> scenario = ActivityScenario.launch(play)) {
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().waitForIdleSync();
            final boolean[] entry = {false};
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                for (android.app.Activity activity :
                        androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance()
                                .getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED)) {
                    entry[0] = activity instanceof NearbyFriendsActivity;
                }
            });
            assertTrue("an ended match returns to Nearby entry", entry[0]);
        }
    }

    @Test public void nearbyEntryResumesExistingInvitation() {
        FlyNesApplication app = (FlyNesApplication) ApplicationProvider.getApplicationContext();
        String ipv4 = NearbyMvpLanAddress.current();
        assertTrue(ipv4 != null && app.nearbyMvpOwner().startHost(ipv4));
        try (ActivityScenario<HomeActivity> scenario = ActivityScenario.launch(HomeActivity.class)) {
            scenario.onActivity(activity -> activity.findViewById(R.id.open_nearby).performClick());
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().waitForIdleSync();
            final boolean[] invitation = {false};
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                for (android.app.Activity activity :
                        androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance()
                                .getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED)) {
                    invitation[0] = activity instanceof NearbyPairingActivity;
                }
            });
            assertTrue("reopening Nearby must resume the same invitation", invitation[0]);
        } finally {
            app.nearbyMvpOwner().close();
        }
    }

    @Test public void explicitDisconnectClosesSessionAndReturnsToEntry() {
        FlyNesApplication app = (FlyNesApplication) ApplicationProvider.getApplicationContext();
        String ipv4 = NearbyMvpLanAddress.current();
        assertTrue(ipv4 != null && app.nearbyMvpOwner().startHost(ipv4));
        try (ActivityScenario<NearbyLobbyActivity> scenario =
                     ActivityScenario.launch(NearbyLobbyActivity.class)) {
            scenario.onActivity(activity -> {
                int action = activity.getResources().getIdentifier("nearby_lobby_disconnect",
                        "id", activity.getPackageName());
                assertTrue("disconnect must be a visible lobby action", action != 0);
                com.google.android.material.appbar.MaterialToolbar toolbar =
                        activity.findViewById(R.id.nearby_lobby_toolbar);
                assertTrue(toolbar.getMenu().performIdentifierAction(action, 0));
            });
            assertTrue("explicit disconnect must close the session", !app.nearbyMvpOwner().active());
        } finally {
            app.nearbyMvpOwner().close();
        }
    }

    @Test public void leavingLobbyPageKeepsActiveSession() {
        FlyNesApplication app = (FlyNesApplication) ApplicationProvider.getApplicationContext();
        String ipv4 = NearbyMvpLanAddress.current();
        assertTrue("emulator must expose a local address", ipv4 != null);
        assertTrue("host must start for lifecycle test", app.nearbyMvpOwner().startHost(ipv4));
        try (ActivityScenario<NearbyLobbyActivity> scenario =
                     ActivityScenario.launch(NearbyLobbyActivity.class)) {
            scenario.onActivity(activity -> {
                com.google.android.material.appbar.MaterialToolbar toolbar =
                        activity.findViewById(R.id.nearby_lobby_toolbar);
                boolean clicked = false;
                for (int i = 0; i < toolbar.getChildCount(); i++) {
                    if (toolbar.getChildAt(i) instanceof android.widget.ImageButton) {
                        clicked = toolbar.getChildAt(i).performClick();
                        break;
                    }
                }
                assertTrue("toolbar back control must be clickable", clicked);
            });
            assertTrue("leaving the page must retain the connection", app.nearbyMvpOwner().active());
        } finally {
            app.nearbyMvpOwner().close();
        }
    }
}
