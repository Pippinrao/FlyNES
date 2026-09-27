package com.flynes.emu.ui;

import android.view.View;

import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.lifecycle.Lifecycle;

import com.flynes.emu.FlyNesApplication;
import com.flynes.emu.NearbyLobbyActivity;
import com.flynes.emu.NearbySessionOwner;
import com.flynes.emu.R;

import org.junit.Test;
import org.junit.runner.RunWith;

import static org.junit.Assert.*;

/** Pairing has no extra entry confirmation control. */
@RunWith(AndroidJUnit4.class)
public final class NearbyLobbyConfirmationTest {
    @org.junit.Before public void resetMvpSession() {
        ((FlyNesApplication) ApplicationProvider.getApplicationContext()).nearbyMvpOwner().close();
    }
    @Test public void lobbyHasNoEntryConfirmationControl() {
        try (ActivityScenario<NearbyLobbyActivity> scenario =
                     ActivityScenario.launch(NearbyLobbyActivity.class)) {
            scenario.onActivity(activity -> {
                assertEquals(0, activity.getResources().getIdentifier(
                        "nearby_lobby_confirm", "id", activity.getPackageName()));
                NearbySessionOwner owner = ((FlyNesApplication) activity.getApplication())
                        .nearbySessionOwner();
                NearbySessionOwner.Snapshot before = owner.snapshot();
                assertFalse(before.canConfirmGameConfig());
                assertEquals(0, owner.snapshot().pendingConfigLocalConfirmed);
                assertEquals(0, owner.snapshot().pendingConfigPeerConfirmed);
                assertEquals(before.gameState, owner.snapshot().gameState);
            });
        }
    }

    @Test public void realOwnerRejectsEmptyAndStaleConfigWithoutStarting() {
        try (NearbySessionOwner owner = NearbySessionOwner.create()) {
            NearbySessionOwner.Snapshot before = owner.snapshot();
            assertArrayEquals(new byte[32], before.pendingConfigId());
            assertEquals(0L, before.pendingConfigRevision);
            assertEquals(-1, owner.confirmGameConfig(null, 1));
            assertEquals(-1, owner.confirmGameConfig(new byte[31], 1));
            assertEquals(-1, owner.confirmGameConfig(new byte[32], 1));
            byte[] staleId = new byte[32];
            staleId[0] = 42;
            assertEquals(-3, owner.confirmGameConfig(staleId, 1));
            assertEquals("generic action path must not bypass displayed config binding",
                    -1, owner.submitAction(24, null));
            NearbySessionOwner.Snapshot after = owner.snapshot();
            assertEquals(0, after.pendingConfigLocalConfirmed);
            assertEquals(0, after.pendingConfigPeerConfirmed);
            assertEquals(NearbySessionOwner.GAME_NOT_STARTED, after.gameState);
        }
    }

    @Test public void resumedLobbyRefreshesFromTheSameOwner() {
        try (ActivityScenario<NearbyLobbyActivity> scenario =
                     ActivityScenario.launch(NearbyLobbyActivity.class)) {
            scenario.moveToState(Lifecycle.State.CREATED);
            scenario.moveToState(Lifecycle.State.RESUMED);
            scenario.onActivity(activity -> {
                NearbySessionOwner owner = ((FlyNesApplication) activity.getApplication())
                        .nearbySessionOwner();
                assertEquals(owner.snapshot().linkState, activity.boundLinkState());
                assertEquals(0, activity.getResources().getIdentifier(
                        "nearby_lobby_confirm", "id", activity.getPackageName()));
            });
        }
    }
}
