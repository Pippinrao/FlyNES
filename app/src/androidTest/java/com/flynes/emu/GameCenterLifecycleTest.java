package com.flynes.emu;

import android.os.SystemClock;

import androidx.test.core.app.ActivityScenario;
import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

import static org.junit.Assert.assertNotNull;

/** A pending catalog diff must not crash when the game center is recreated. */
@RunWith(AndroidJUnit4.class)
public final class GameCenterLifecycleTest {
    @Test public void cachedCatalogSurvivesActivityRecreation() {
        try (ActivityScenario<HomeActivity> scenario = ActivityScenario.launch(HomeActivity.class)) {
            SystemClock.sleep(1500);
            scenario.onActivity(activity -> assertNotNull(activity.findViewById(R.id.game_grid)));
            scenario.recreate();
            SystemClock.sleep(1500);
            scenario.onActivity(activity -> assertNotNull(activity.findViewById(R.id.game_grid)));
        }
    }
}
