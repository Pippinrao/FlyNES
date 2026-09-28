package com.flynes.emu;

import static org.junit.Assert.*;

import android.content.Context;
import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import com.flynes.emu.gamecenter.GameCenterSnapshot;
import com.flynes.emu.gamecenter.GameCenterSnapshotCodec;
import com.flynes.emu.gamecenter.GameCenterState;
import java.lang.reflect.Field;
import java.util.List;
import java.util.concurrent.TimeUnit;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Exercises production snapshot transitions without changing the user's catalog or save data. */
@RunWith(AndroidJUnit4.class)
public class HomeSelectionRetentionTest {
    @Test public void availableSelectionSurvivesStartupWindowAndFullProjection() throws Exception {
        FlyNesApplication app = ApplicationProvider.getApplicationContext();
        app.catalogRuntime().nativeReady().get(20, TimeUnit.SECONDS);
        var original = app.catalogRuntime().gameCenterSnapshot();
        var selected = original.rows().stream().filter(GameCenterSnapshot.Row::launchable).findFirst().orElseThrow();
        var unavailable = new GameCenterSnapshot.Row("selection-test-unavailable", "Unavailable fixture", "",
                "Unavailable fixture", "", "", false, false, 0, 0, 0, false, 0);
        var fixture = new GameCenterSnapshot(original.schemaVersion(), original.nativeGeneration(),
                original.builtinManifestSha256(), original.sourceEpoch(), List.of(unavailable, selected),
                original.sources(), new byte[0]);
        var startup = GameCenterSnapshotCodec.decodeStartup(GameCenterSnapshotCodec.encodeStartup(fixture, 1));
        var full = GameCenterSnapshotCodec.decodeProjection(GameCenterSnapshotCodec.encode(fixture));
        var prefs = app.getSharedPreferences("game_center_ui", Context.MODE_PRIVATE);
        var saved = new java.util.HashMap<String, Object>(prefs.getAll());
        try (ActivityScenario<HomeActivity> scenario = ActivityScenario.launch(HomeActivity.class)) {
            scenario.onActivity(activity -> {
                try {
                    GameCenterState navigation = (GameCenterState) field(activity, "navigation");
                    navigation.setCategory(GameCenterState.Category.ALL);
                    navigation.setQuery("");
                    navigation.setMultiplayerOnly(false);
                    navigation.select(selected.canonicalId());
                    var apply = HomeActivity.class.getDeclaredMethod("applySnapshot", GameCenterSnapshot.class);
                    apply.setAccessible(true);
                    apply.invoke(activity, startup);
                    assertEquals("A partial startup window cannot invalidate an offscreen saved selection",
                            selected.canonicalId(), navigation.selectedCanonicalId());
                    apply.invoke(activity, full);
                    assertEquals("Complete projection retains the available selected identity",
                            selected.canonicalId(), navigation.selectedCanonicalId());
                    assertTrue("The selected available game remains launchable",
                            activity.findViewById(R.id.launch_selected).isEnabled());
                    assertEquals("Only the selected row needs caching before RecyclerView binding", 1,
                            ((java.util.Map<?, ?>) field(activity, "rows")).size());
                    navigation.setQuery("Unavailable fixture");
                    apply.invoke(activity, full);
                    assertEquals("A filtered-out old selection cannot remain active",
                            unavailable.canonicalId(), navigation.selectedCanonicalId());
                    assertFalse(activity.findViewById(R.id.launch_selected).isEnabled());
                } catch (ReflectiveOperationException failure) { throw new AssertionError(failure); }
            });
        } finally {
            var restore = prefs.edit().clear();
            for (var entry : saved.entrySet()) {
                Object value = entry.getValue();
                if (value instanceof String) restore.putString(entry.getKey(), (String) value);
                else if (value instanceof Boolean) restore.putBoolean(entry.getKey(), (Boolean) value);
                else if (value instanceof Integer) restore.putInt(entry.getKey(), (Integer) value);
                else if (value instanceof Long) restore.putLong(entry.getKey(), (Long) value);
            }
            assertTrue(restore.commit());
            assertEquals(saved, prefs.getAll());
        }
    }
    private static Object field(Object owner, String name) throws ReflectiveOperationException {
        Field field = owner.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(owner);
    }
}
