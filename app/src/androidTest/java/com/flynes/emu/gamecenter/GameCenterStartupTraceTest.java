package com.flynes.emu.gamecenter;

import static org.junit.Assert.*;

import androidx.recyclerview.widget.ListAdapter;
import androidx.recyclerview.widget.RecyclerView;
import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.flynes.emu.FlyNesApplication;
import com.flynes.emu.HomeActivity;
import com.flynes.emu.R;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Changes only the activity's projection, never the installed catalog or snapshot files. */
@RunWith(AndroidJUnit4.class)
public class GameCenterStartupTraceTest {
    @Test public void startupWindowCannotClaimFullListMarkerBeforeCompleteProjection() throws Exception {
        FlyNesApplication app = ApplicationProvider.getApplicationContext();
        app.catalogRuntime().bootstrap().get(10, TimeUnit.SECONDS);
        ArrayList<GameCenterSnapshot.Row> rows = new ArrayList<>();
        for (int i = 0; i < 100; i++) {
            rows.add(new GameCenterSnapshot.Row("trace-row-" + i, "Trace " + i, "", "", "", "",
                    false, false, 0, 0, 1, true, 0));
        }
        GameCenterSnapshot source = new GameCenterSnapshot(1, 1, "00".repeat(32), 0,
                rows, List.of(), new byte[0]);
        GameCenterSnapshot startup = GameCenterSnapshotCodec.decodeStartup(
                GameCenterSnapshotCodec.encodeStartup(source, 1));
        GameCenterSnapshot full = GameCenterSnapshotCodec.decodeProjection(
                GameCenterSnapshotCodec.encode(source));
        var flagField = GameCenterStartupTrace.class.getDeclaredField("FULL_LIST_LOGGED");
        flagField.setAccessible(true);
        AtomicBoolean fullLogged = (AtomicBoolean) flagField.get(null);
        try (var scenario = ActivityScenario.launch(HomeActivity.class)) {
            awaitFrames(scenario);
            boolean previous = fullLogged.get();
            try {
                fullLogged.set(false);
                applyAndAwait(scenario, startup);
                assertFalse("startup total count and visible first card do not prove a full projection",
                        fullLogged.get());
                applyAndAwait(scenario, full);
                assertTrue("a subsequent real full projection must still claim the marker", fullLogged.get());
            } finally {
                fullLogged.set(previous);
            }
        }
    }

    private static void applyAndAwait(ActivityScenario<HomeActivity> scenario,
                                      GameCenterSnapshot snapshot) throws Exception {
        CountDownLatch committed = new CountDownLatch(1);
        scenario.onActivity(activity -> {
            try {
                var navigation = HomeActivity.class.getDeclaredField("navigation");
                navigation.setAccessible(true);
                navigation.set(activity, new GameCenterState());
                RecyclerView grid = activity.findViewById(R.id.game_grid);
                var adapter = (ListAdapter<?, ?>) grid.getAdapter();
                grid.getAdapter().registerAdapterDataObserver(new RecyclerView.AdapterDataObserver() {
                    private void check() {
                        if (adapter.getCurrentList().size() == snapshot.rows().size()
                                && adapter.getCurrentList().get(99).equals(snapshot.rows().get(99))) {
                            committed.countDown();
                        }
                    }
                    @Override public void onItemRangeChanged(int start, int count) { check(); }
                    @Override public void onItemRangeInserted(int start, int count) { check(); }
                    @Override public void onItemRangeRemoved(int start, int count) { check(); }
                });
                var apply = HomeActivity.class.getDeclaredMethod("applySnapshot", GameCenterSnapshot.class);
                apply.setAccessible(true);
                apply.invoke(activity, snapshot);
            } catch (ReflectiveOperationException failure) {
                throw new AssertionError(failure);
            }
        });
        assertTrue("projection must commit", committed.await(5, TimeUnit.SECONDS));
        awaitFrames(scenario);
    }

    private static void awaitFrames(ActivityScenario<HomeActivity> scenario) throws Exception {
        InstrumentationRegistry.getInstrumentation().waitForIdleSync();
        CountDownLatch drawn = new CountDownLatch(1);
        scenario.onActivity(activity -> {
            RecyclerView grid = activity.findViewById(R.id.game_grid);
            assertNotNull("full activity layout must be installed", grid);
            grid.postOnAnimation(() -> grid.postOnAnimation(drawn::countDown));
        });
        assertTrue("view must draw", drawn.await(5, TimeUnit.SECONDS));
    }
}
