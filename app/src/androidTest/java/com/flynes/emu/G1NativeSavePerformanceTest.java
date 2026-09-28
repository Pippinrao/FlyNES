package com.flynes.emu;

import static org.junit.Assert.*;
import android.content.Context;
import android.os.Debug;
import android.os.SystemClock;
import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.flynes.emu.save.HistoryClock;
import com.flynes.emu.save.HistoryStore;
import com.flynes.emu.video.FrameAvailableSignal;
import java.io.File;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Opt-in native baseline. Collects software observations without a candidate acceptance budget. */
@RunWith(AndroidJUnit4.class)
public class G1NativeSavePerformanceTest {
    @Test public void measureNativeGameWithSixtySecondAutomaticSave() throws Exception {
        org.junit.Assume.assumeTrue("Task simulator only; explicit performance invocation required",
                "true".equals(InstrumentationRegistry.getArguments().getString("g1NativePerformance")));
        Context context = ApplicationProvider.getApplicationContext();
        boolean throughFlutter = "flutter".equals(InstrumentationRegistry.getArguments().getString("g1Entry"));
        var repository = com.flynes.emu.settings.SettingsAccess.repository(context);
        var settings = repository.load();
        var preferences = context.getSharedPreferences("save_history", Context.MODE_PRIVATE);
        boolean hadInterval = preferences.contains("interval_ms");
        long oldInterval = preferences.getLong("interval_ms", 60000);
        List<long[]> frames = java.util.Collections.synchronizedList(new ArrayList<>());
        JSONArray memory = new JSONArray();
        JSONObject report = new JSONObject().put("mode", throughFlutter
                ? "flutter-to-native-game-debug-simulator" : "native-game-debug-simulator")
                .put("intervalMs", 60000).put("processId", android.os.Process.myPid())
                .put("physicalLatencyCertified", false);
        try {
            assertTrue(repository.save(settings.toBuilder().autosaveEnabled(true).audioEnabled(true).build()));
            assertTrue(preferences.edit().putLong("interval_ms", 60000).commit());
            AtomicReference<MainActivity> owner = new AtomicReference<>();
            var intent = new android.content.Intent(context,
                    throughFlutter ? FlutterFoundationActivity.class : MainActivity.class);
            try (ActivityScenario<?> scenario = ActivityScenario.launch(intent)) {
                if (throughFlutter) {
                    FlutterFoundationIntegrationTest.click(FlutterFoundationIntegrationTest.awaitNode("launch-selected", true));
                    assertTrue(FlutterFoundationIntegrationTest.awaitActivity(MainActivity.class));
                    owner.set(FlutterFoundationIntegrationTest.playingActivity());
                } else scenario.onActivity(game -> owner.set((MainActivity) game));
                MainActivity activity = owner.get();
                HistoryClock clock = (HistoryClock) field(activity, "historyClock");
                FrameAvailableSignal signal = (FrameAvailableSignal) field(activity, "frameAvailable");
                FrameAvailableSignal.Listener listener = sequence -> frames.add(new long[]{
                        sequence, System.nanoTime(), System.currentTimeMillis()});
                signal.addListener(listener);
                try {
                    String key = ((com.flynes.emu.data.RomIdentity) field(activity, "currentRomIdentity")).sha1();
                    report.put("contentKey", key);
                    String expectedKey = InstrumentationRegistry.getArguments().getString("g1ExpectedContentKey", "");
                    if (!expectedKey.isEmpty()) assertEquals("Compare the identical content", expectedKey, key);
                    File database = new File(context.getFilesDir(), "save-history.sqlite");
                    try (HistoryStore store = new HistoryStore(database)) {
                        long beforeHead = store.head(key);
                        java.util.Set<Long> beforeIds = new java.util.HashSet<>();
                        for (HistoryStore.Entry entry : store.list(key)) beforeIds.add(entry.id());
                        report.put("headBefore", beforeHead).put("recordsBefore", beforeIds.size());
                        long startMs = clock.playedMs();
                        long started = SystemClock.elapsedRealtime();
                        report.put("startedEpochMs", System.currentTimeMillis());
                        long deadline = started + 150000;
                        while (clock.playedMs() - startMs < 65000 && SystemClock.elapsedRealtime() < deadline) {
                            SystemClock.sleep(1000);
                            // Reproducible software touch workload; MainActivity's calibrated
                            // touch-to-core-ns log measures the actual native sample boundary.
                            // This deliberately does not claim hardware or OS injection latency.
                            long touchDown = SystemClock.uptimeMillis();
                            InstrumentationRegistry.getInstrumentation().runOnMainSync(() ->
                                    touchA(activity, touchDown, android.view.MotionEvent.ACTION_DOWN));
                            SystemClock.sleep(70);
                            InstrumentationRegistry.getInstrumentation().runOnMainSync(() ->
                                    touchA(activity, touchDown, android.view.MotionEvent.ACTION_UP));
                            Debug.MemoryInfo info = new Debug.MemoryInfo();
                            Debug.getMemoryInfo(info);
                            var video = ((com.flynes.emu.video.GameSurfaceView) field(activity, "view")).presenterStats();
                            AudioThread audio = (AudioThread) field(activity, "audio");
                            long playback = -1;
                            int underruns = -1;
                            if (audio != null) {
                                var track = (android.media.AudioTrack) field(audio, "track");
                                if (track != null) {
                                    try { playback = Integer.toUnsignedLong(track.getPlaybackHeadPosition());
                                        underruns = track.getUnderrunCount(); }
                                    catch (IllegalStateException releasedDuringObservation) { }
                                }
                            }
                            memory.put(new JSONObject().put("elapsedMs", SystemClock.elapsedRealtime() - started)
                                    .put("playedMs", clock.playedMs() - startMs).put("pssKb", info.getTotalPss())
                                    .put("javaUsedBytes", Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory())
                                    .put("nativeHeapBytes", Debug.getNativeHeapAllocatedSize())
                                    .put("submittedFrames", video.submittedFrames())
                                    .put("skippedSequences", video.skippedSequences())
                                    .put("runtimeFailures", video.runtimeFailureCount())
                                    .put("actualPresentationCount", video.actualPresentationCount())
                                    .put("audioPlaybackFrames", playback).put("audioUnderruns", underruns));
                        }
                        report.put("playedMs", clock.playedMs() - startMs)
                                .put("finishedEpochMs", System.currentTimeMillis())
                                .put("wallMs", SystemClock.elapsedRealtime() - started)
                                .put("headAfter", store.head(key)).put("recordsAfter", store.list(key).length);
                        JSONArray saves = new JSONArray();
                        for (HistoryStore.Entry entry : store.list(key)) {
                            if (!beforeIds.contains(entry.id()) && entry.kind() == HistoryStore.AUTO)
                                saves.put(new JSONObject().put("id", entry.id()).put("createdMs", entry.createdMs())
                                        .put("playedMs", entry.playedMs()));
                        }
                        report.put("automaticSaves", saves);
                        assertTrue("Actual emulation must reach the unchanged 60s interval", clock.playedMs() - startMs >= 65000);
                        assertNotEquals("Native timer must persist an automatic save", beforeHead, store.head(key));
                        assertTrue("A new automatic record must exist", saves.length() > 0);
                    }
                } finally {
                    signal.removeListener(listener);
                    if (throughFlutter) InstrumentationRegistry.getInstrumentation().runOnMainSync(activity::finish);
                }
            }
        } finally {
            repository.save(settings);
            if (hadInterval) preferences.edit().putLong("interval_ms", oldInterval).commit();
            else preferences.edit().remove("interval_ms").commit();
            JSONArray events = new JSONArray();
            synchronized (frames) { for (long[] row : frames) events.put(new JSONArray(row)); }
            report.put("coreFrameEvents", events).put("memoryAndAudio", memory);
            Files.write(new File(context.getExternalFilesDir(null), throughFlutter
                    ? "g1-flutter-save-performance.json" : "g1-native-save-performance.json").toPath(),
                    report.toString().getBytes(StandardCharsets.UTF_8));
        }
    }
    private static Object field(Object object, String name) throws Exception {
        Field field = object.getClass().getDeclaredField(name); field.setAccessible(true); return field.get(object);
    }
    private static void touchA(MainActivity game, long downTime, int action) {
        GamepadView pad = game.findViewById(R.id.gamepad);
        var target = pad.hitMapForTest().target(com.flynes.emu.input.GamepadHitMap.Control.A);
        var event = android.view.MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action,
                target.centerX(), target.centerY(), 0);
        try { assertTrue(pad.dispatchTouchEvent(event)); }
        finally { event.recycle(); }
    }
}
