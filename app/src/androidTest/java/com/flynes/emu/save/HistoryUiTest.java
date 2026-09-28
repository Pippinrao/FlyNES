package com.flynes.emu.save;

import static androidx.test.espresso.Espresso.onView;
import static androidx.test.espresso.action.ViewActions.*;
import static androidx.test.espresso.assertion.ViewAssertions.matches;
import static androidx.test.espresso.assertion.ViewAssertions.doesNotExist;
import static androidx.test.espresso.matcher.ViewMatchers.*;
import static org.hamcrest.Matchers.*;
import static org.junit.Assert.*;

import android.content.Context;
import android.content.Intent;
import android.widget.Button;
import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import com.flynes.emu.MainActivity;
import com.flynes.emu.NesCore;
import com.flynes.emu.R;
import com.flynes.emu.catalog.BuiltinGames;
import java.io.File;
import java.io.InputStream;
import java.nio.file.Files;
import org.junit.*;
import org.junit.runner.RunWith;

/** Uses an isolated DB and restores any pre-existing test installation DB on exit. */
@RunWith(AndroidJUnit4.class)
public class HistoryUiTest {
    private Context context;
    private File database, backupDir;
    private String key;
    @Before
    public void isolate() throws Exception {
        context = ApplicationProvider.getApplicationContext();
        database = new File(context.getFilesDir(), "save-history.sqlite");
        backupDir = new File(context.getCacheDir(), "ui-history-backup-" + System.nanoTime());
        assertTrue(backupDir.mkdir());
        for (String suffix : new String[] {"", "-wal", "-shm"}) {
            File file = new File(database.getPath() + suffix);
            if (file.exists())
                Files.move(file.toPath(), new File(backupDir, file.getName()).toPath());
        }
        NesCore core = new NesCore();
        try {
            core.create();
            BuiltinGames games;
            try (InputStream in = context.getAssets().open(BuiltinGames.ASSET_NAME)) {
                games = BuiltinGames.parse(in);
            }
            try (InputStream in = context.getAssets().open(games.all().get(0).assetPath())) {
                core.loadRom(in.readAllBytes());
            }
            key = core.romInfo().identity().sha1();
        } finally {
            core.destroy();
        }
    }
    @After
    public void restoreInstallation() throws Exception {
        for (String suffix : new String[] {"", "-wal", "-shm"})
            Files.deleteIfExists(new File(database.getPath() + suffix).toPath());
        for (File saved : backupDir.listFiles())
            Files.move(
                saved.toPath(), new File(database.getParentFile(), saved.getName()).toPath());
        assertTrue(backupDir.delete());
    }
    @Test
    public void selectingIntervalReenablesAutomaticSaving() {
        var repository = com.flynes.emu.settings.SettingsAccess.repository(context);
        var original = repository.load();
        var preferences = context.getSharedPreferences("save_history", Context.MODE_PRIVATE);
        boolean had = preferences.contains("interval_ms");
        long originalInterval = preferences.getLong("interval_ms", 60000);
        try {
            repository.save(original.toBuilder().autosaveEnabled(false).build());
            try (ActivityScenario<MainActivity> scenario =
                     ActivityScenario.launch(MainActivity.class)) {
                onView(withId(R.id.pause_button)).perform(click());
                onView(withId(R.id.pause_save_interval)).perform(scrollTo(), click());
                onView(withText("30 s")).perform(click());
                assertTrue("choosing an interval must enable automatic saving",
                    repository.load().autosaveEnabled());
            }
        } finally {
            repository.save(original);
            if (had)
                preferences.edit().putLong("interval_ms", originalInterval).commit();
            else
                preferences.edit().remove("interval_ms").commit();
        }
    }
    @Test
    public void gameDetailsKeepOnlyPrimaryLaunchAction() {
        try (ActivityScenario<com.flynes.emu.HomeActivity> scenario =
                 ActivityScenario.launch(com.flynes.emu.HomeActivity.class)) {
            android.os.SystemClock.sleep(1500);
            onView(withText(R.string.history_title)).check(doesNotExist());
            onView(withText(R.string.history_restart)).check(doesNotExist());
            onView(withId(R.id.launch_selected)).check(matches(isDisplayed()));
            screenshot("android-save-home.png");
        }
    }
    @Test
    public void saveAdvanceRestoreRestartAndReopenFromUi() {
        long checkpoint;
        byte[] first;
        long fresh;
        try (
            ActivityScenario<MainActivity> scenario = ActivityScenario.launch(MainActivity.class)) {
            android.os.SystemClock.sleep(1500);
            onView(withId(R.id.pause_button)).perform(click());
            screenshot("android-save-menu.png");
            onView(withId(R.id.pause_save)).perform(scrollTo(), click());
            onView(isAssignableFrom(android.widget.EditText.class))
                .perform(replaceText("UI checkpoint"));
            onView(withText(R.string.history_save)).perform(click());
            try (HistoryStore store = new HistoryStore(database)) {
                checkpoint = store.head(key);
                first = store.read(key, checkpoint, false);
                assertTrue(checkpoint > 0);
                assertTrue(store.read(key, checkpoint, true).length > 0);
            }
            onView(withId(R.id.pause_continue)).perform(scrollTo(), click());
            android.os.SystemClock.sleep(1000);
            onView(withId(R.id.pause_button)).perform(click());
            try (HistoryStore store = new HistoryStore(database)) {
                assertNotEquals(checkpoint, store.head(key));
                assertFalse(
                    java.util.Arrays.equals(first, store.read(key, store.head(key), false)));
            }
            onView(withId(R.id.pause_history)).perform(scrollTo(), click());
            android.os.SystemClock.sleep(2000);
            screenshot("android-save-history.png");
            onView(allOf(isAssignableFrom(Button.class), withText(containsString("UI checkpoint"))))
                .perform(scrollTo(), click());
            onView(withText(R.string.history_restore)).perform(click());
            try (HistoryStore store = new HistoryStore(database)) {
                assertEquals(checkpoint, store.head(key));
            }
            onView(withId(R.id.pause_continue)).check(matches(isDisplayed()));
        }
        Intent paused =
            new Intent(context, MainActivity.class).putExtra("save_history_action", "history");
        try (ActivityScenario<MainActivity> scenario = ActivityScenario.launch(paused)) {
            try (HistoryStore store = new HistoryStore(database)) {
                assertEquals(checkpoint, store.head(key));
                assertArrayEquals(first, store.read(key, store.head(key), false));
            }
            onView(withText(R.string.history_cancel)).perform(click());
            onView(withId(R.id.pause_restart)).perform(scrollTo(), click());
            onView(withId(android.R.id.button1)).perform(click());
            try (HistoryStore store = new HistoryStore(database)) {
                fresh = store.head(key);
                assertNotEquals(checkpoint, fresh);
                assertFalse(java.util.Arrays.equals(first, store.read(key, fresh, false)));
                assertArrayEquals(first, store.read(key, checkpoint, false));
            }
        }
        try (ActivityScenario<MainActivity> scenario = ActivityScenario.launch(paused)) {
            try (HistoryStore store = new HistoryStore(database)) {
                assertEquals(fresh, store.head(key));
            }
            onView(withText(R.string.history_cancel)).perform(click());
        }
    }
    private void screenshot(String name) {
        android.graphics.Bitmap bitmap = androidx.test.platform.app.InstrumentationRegistry
                .getInstrumentation().getUiAutomation().takeScreenshot();
        try (var output = new java.io.FileOutputStream(new File(context.getCacheDir(), name))) {
            assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output));
        } catch (java.io.IOException failure) { throw new AssertionError(failure); }
        finally { bitmap.recycle(); }
    }
}
