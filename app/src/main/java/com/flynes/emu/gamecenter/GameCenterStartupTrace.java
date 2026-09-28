package com.flynes.emu.gamecenter;

import android.graphics.Rect;
import android.os.Process;
import android.util.Log;
import android.view.View;
import android.view.ViewTreeObserver;

import androidx.recyclerview.widget.RecyclerView;

import com.flynes.emu.catalog.android.AndroidCatalogRuntime;

import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.BooleanSupplier;

/** Machine-readable cold-start markers used by the performance gate. */
public final class GameCenterStartupTrace {
    private static final String TAG = "FlyNesStartup";
    private static final long ORIGIN = Process.getStartElapsedRealtime();
    private static final AtomicBoolean SHELL_LOGGED = new AtomicBoolean();
    private static final AtomicBoolean LIST_LOGGED = new AtomicBoolean();
    private static final AtomicBoolean FULL_LIST_LOGGED = new AtomicBoolean();
    private static final AtomicBoolean INTERACTIVE_LOGGED = new AtomicBoolean();

    private GameCenterStartupTrace() { }

    public static void event(String name, String fields) {
        Log.i(TAG, name + " elapsedMs=" + elapsed() + (fields == null || fields.isEmpty()
                ? "" : " " + fields));
    }

    public static ViewTreeObserver.OnPreDrawListener shellVisibleOnNextPreDraw(View root) {
        return new ViewTreeObserver.OnPreDrawListener() {
            @Override public boolean onPreDraw() {
                if (root.getViewTreeObserver().isAlive()) {
                    root.getViewTreeObserver().removeOnPreDrawListener(this);
                }
                if (SHELL_LOGGED.compareAndSet(false, true)) {
                    event("GAME_CENTER_SHELL_VISIBLE", "");
                }
                return true;
            }
        };
    }

    /** An enabled visible primary action is a separate boundary from cached artwork. */
    public static ViewTreeObserver.OnPreDrawListener interactiveOnNextPreDraw(View primary) {
        return new ViewTreeObserver.OnPreDrawListener() {
            @Override public boolean onPreDraw() {
                Rect bounds = new Rect();
                if (!primary.isEnabled() || !primary.hasOnClickListeners()
                        || !primary.getGlobalVisibleRect(bounds) || bounds.isEmpty()) return true;
                if (primary.getViewTreeObserver().isAlive()) {
                    primary.getViewTreeObserver().removeOnPreDrawListener(this);
                }
                if (INTERACTIVE_LOGGED.compareAndSet(false, true))
                    event("GAME_CENTER_INTERACTIVE", "");
                return true;
            }
        };
    }

    public static ViewTreeObserver.OnPreDrawListener visibleOnNextPreDraw(
            RecyclerView grid, int expectedCount, AndroidCatalogRuntime.CacheStatus cacheStatus,
            boolean fullProjection, BooleanSupplier currentSubmission) {
        return new ViewTreeObserver.OnPreDrawListener() {
            @Override public boolean onPreDraw() {
                if (!currentSubmission.getAsBoolean()) {
                    if (grid.getViewTreeObserver().isAlive()) {
                        grid.getViewTreeObserver().removeOnPreDrawListener(this);
                    }
                    return true;
                }
                RecyclerView.Adapter<?> adapter = grid.getAdapter();
                if (adapter == null || adapter.getItemCount() != expectedCount
                        || expectedCount == 0 || grid.getChildCount() == 0) return true;
                Rect bounds = new Rect();
                if (!grid.getChildAt(0).getGlobalVisibleRect(bounds) || bounds.isEmpty()) return true;
                if (grid.getViewTreeObserver().isAlive()) {
                    grid.getViewTreeObserver().removeOnPreDrawListener(this);
                }
                if (LIST_LOGGED.compareAndSet(false, true)) {
                    event("GAME_CENTER_VISIBLE", "count=" + expectedCount + " cache=" + cacheStatus);
                }
                // The fast shell may already have claimed GAME_CENTER_VISIBLE. This marker
                // means the complete adapter is accessible and its first card is on screen;
                // it does not mean every offscreen row was decoded or rendered.
                if (fullProjection && FULL_LIST_LOGGED.compareAndSet(false, true)) {
                    event("GAME_CENTER_FULL_LIST_VISIBLE",
                            "count=" + expectedCount + " cache=" + cacheStatus);
                }
                return true;
            }
        };
    }

    public static ViewTreeObserver.OnPreDrawListener visibleOnNextPreDraw(
            View content, int expectedCount, AndroidCatalogRuntime.CacheStatus cacheStatus) {
        return new ViewTreeObserver.OnPreDrawListener() {
            @Override public boolean onPreDraw() {
                Rect bounds = new Rect();
                if (expectedCount == 0 || !content.getGlobalVisibleRect(bounds) || bounds.isEmpty()) {
                    return true;
                }
                if (content.getViewTreeObserver().isAlive()) {
                    content.getViewTreeObserver().removeOnPreDrawListener(this);
                }
                if (LIST_LOGGED.compareAndSet(false, true)) {
                    event("GAME_CENTER_VISIBLE", "count=" + expectedCount + " cache=" + cacheStatus);
                }
                return true;
            }
        };
    }

    private static long elapsed() {
        return Math.max(0L, android.os.SystemClock.elapsedRealtime() - ORIGIN);
    }
}
