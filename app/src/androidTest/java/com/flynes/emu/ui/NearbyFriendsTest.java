package com.flynes.emu.ui;

import static androidx.test.espresso.Espresso.onView;
import static androidx.test.espresso.Espresso.pressBack;
import static androidx.test.espresso.action.ViewActions.click;
import static androidx.test.espresso.assertion.ViewAssertions.matches;
import static androidx.test.espresso.matcher.ViewMatchers.isDisplayed;
import static androidx.test.espresso.matcher.ViewMatchers.isEnabled;
import static androidx.test.espresso.matcher.ViewMatchers.withId;
import static androidx.test.espresso.matcher.ViewMatchers.withText;

import androidx.test.core.app.ActivityScenario;
import androidx.test.ext.junit.runners.AndroidJUnit4;

import com.flynes.emu.HomeActivity;
import com.flynes.emu.R;

import org.junit.Test;
import org.junit.runner.RunWith;

/** Real game-center navigation to the one nearby entry. */
@RunWith(AndroidJUnit4.class)
public final class NearbyFriendsTest {

    @Test
    public void gameCenterShowsTheNearbyEntry() {
        try (ActivityScenario<HomeActivity> ignored = ActivityScenario.launch(HomeActivity.class)) {
            onView(withId(R.id.open_nearby)).check(matches(isDisplayed()));
            onView(withId(R.id.open_nearby)).check(matches(withText(R.string.nearby_open)));
            onView(withId(R.id.open_nearby)).check(matches(isEnabled()));
        }
    }

    @Test
    public void nearbyEntryOpensTheNearbyPage() {
        try (ActivityScenario<HomeActivity> ignored = ActivityScenario.launch(HomeActivity.class)) {
            onView(withId(R.id.open_nearby)).perform(click());
            // The page is now on screen; this is the only proof that the entry's wiring works.
            onView(withId(R.id.nearby_root)).check(matches(isDisplayed()));
            onView(withId(R.id.nearby_toolbar)).check(matches(isDisplayed()));
            pressBack();
        }
    }

}
