package com.flynes.emu.save;

import static org.junit.Assert.*;
import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.flynes.emu.NesCore;
import com.flynes.emu.catalog.BuiltinGames;
import com.flynes.emu.data.RomIdentity;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.HexFormat;
import org.json.JSONObject;
import org.json.JSONArray;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Separate-process seed -> install -r -> verify. Never moves/deletes the existing database. */
@RunWith(AndroidJUnit4.class)
public class G1UpgradeRetentionTest {
    @Test public void preserveSelectedHeadPendingLegacyAndMetadataAcrossReplacement() throws Exception {
        var args = InstrumentationRegistry.getArguments();
        String phase = args.getString("g1UpgradePhase", "");
        org.junit.Assume.assumeTrue("Explicit two-phase invocation only", phase.equals("seed") || phase.equals("verify"));
        String fixture = args.getString("g1UpgradeFixture", "");
        assertTrue("Use a unique fixture name", fixture.matches("[A-Za-z0-9_-]{8,80}"));
        Context context = ApplicationProvider.getApplicationContext();
        File evidence = new File(context.getFilesDir(), "g1-upgrade-" + fixture + ".json");
        byte[] rom;
        BuiltinGames games;
        try (var in = context.getAssets().open(BuiltinGames.ASSET_NAME)) { games = BuiltinGames.parse(in); }
        try (var in = context.getAssets().open(games.all().get(0).assetPath())) { rom = in.readAllBytes(); }
        String key = identity(fixture + "-head").sha1();
        String pendingKey = identity(fixture + "-pending").sha1();
        RomIdentity legacy = identity(fixture + "-legacy");
        File db = new File(context.getFilesDir(), "save-history.sqlite");
        NesCore core = new NesCore();
        core.create();
        try (HistoryStore store = new HistoryStore(db)) {
            assertTrue(core.loadRom(rom) >= 0);
            core.setAudioFormat(48000, 0);
            core.runFrames(8);
            byte[] first = core.saveState();
            core.runFrames(12);
            byte[] current = core.saveState();
            SaveRepository saves = new SaveRepository(context);
            if (phase.equals("seed")) {
                assertFalse("Never overwrite an existing fixture", evidence.exists());
                assertEquals(0, store.list(key).length);
                byte[] thumbnail = {7, 11, 13, 17};
                long selected = store.put(key, first, thumbnail, HistoryStore.MANUAL,
                        "G1 保留备注", 12000, "session-a", 0, true);
                store.pin(selected, true);
                store.put(key, current, null, HistoryStore.AUTO, "newer", 24000, "session-b", selected, true);
                store.setHead(key, selected); // Deliberately select the older record.
                long target = store.put(pendingKey, first, thumbnail, HistoryStore.MANUAL,
                        "pending target", 1000, "session-c", 0, true);
                long[] operation = store.prepare(pendingKey, target, current, thumbnail,
                        25000, "session-d", "Before restore");
                saves.writeAutosave(legacy, first, 7654321);
                saves.writeBattery(legacy, new byte[]{23, 29, 31});
                // These fixture-only keys never overlap the manifest game's actual key.
                saves.writeAutosave(identity(fixture + "-head"), new byte[]{1, 2, 3}, 1);
                assertTrue(context.getSharedPreferences("save_history", 0).edit()
                        .putLong("interval_ms", 300000).commit());
                JSONObject expected = new JSONObject()
                        .put("head", selected).put("rows", rows(store, key))
                        .put("first", android.util.Base64.encodeToString(first, android.util.Base64.NO_WRAP))
                        .put("current", android.util.Base64.encodeToString(current, android.util.Base64.NO_WRAP))
                        .put("operation", operation[0]).put("backup", operation[1])
                        .put("interval", context.getSharedPreferences("save_history", 0).getLong("interval_ms", 60000));
                Files.write(evidence.toPath(), expected.toString().getBytes(StandardCharsets.UTF_8));
            } else {
                assertTrue("Seed must precede replacement", evidence.isFile());
                JSONObject expected = new JSONObject(new String(Files.readAllBytes(evidence.toPath()), StandardCharsets.UTF_8));
                byte[] savedFirst = android.util.Base64.decode(expected.getString("first"), android.util.Base64.DEFAULT);
                byte[] savedCurrent = android.util.Base64.decode(expected.getString("current"), android.util.Base64.DEFAULT);
                assertEquals(expected.getJSONArray("rows").toString(), rows(store, key).toString());
                assertEquals(expected.getLong("head"), store.head(key));
                assertArrayEquals(savedFirst, store.read(key, store.head(key), false));
                assertArrayEquals(new byte[]{7, 11, 13, 17}, store.read(key, store.head(key), true));
                assertEquals(expected.getLong("interval"), context.getSharedPreferences("save_history", 0).getLong("interval_ms", 60000));
                HistorySession session = new HistorySession(core, store, key, rom, new HistoryClock(), () -> null);
                session.initializeFromLegacyLoader(() -> { throw new java.io.IOException("Valid head must not read broken legacy"); });
                assertArrayEquals(savedFirst, core.saveState());
                assertEquals(expected.getLong("operation"), store.pending(pendingKey)[0]);
                HistoryClock pendingClock = new HistoryClock();
                new HistorySession(core, store, pendingKey, rom, pendingClock, () -> null).initialize(null);
                assertEquals(expected.getLong("backup"), store.head(pendingKey));
                assertEquals(0, store.pending(pendingKey)[0]);
                assertEquals(25000, pendingClock.playedMs());
                assertArrayEquals(savedCurrent, core.saveState());
                File oldFile = new File(new File(new File(context.getFilesDir(), "saves"), legacy.directoryName()), "autosave.nst");
                byte[] oldBytes = Files.readAllBytes(oldFile.toPath());
                HistorySession legacySession = new HistorySession(core, store, legacy.sha1(), rom, new HistoryClock(), () -> null);
                legacySession.initializeFromLegacyLoader(() -> saves.readAutosave(legacy).orElseThrow());
                assertTrue(store.head(legacy.sha1()) > 0);
                assertArrayEquals(savedFirst, core.saveState());
                assertArrayEquals(oldBytes, Files.readAllBytes(oldFile.toPath()));
                assertArrayEquals(new byte[]{23, 29, 31}, saves.readBattery(legacy));
                int count = store.list(legacy.sha1()).length;
                legacySession.initializeFromLegacyLoader(() -> { throw new AssertionError("No repeated migration"); });
                assertEquals(count, store.list(legacy.sha1()).length);
            }
        } finally { core.destroy(); }
    }

    private static RomIdentity identity(String value) throws Exception {
        return new RomIdentity(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-1")
                .digest(value.getBytes(StandardCharsets.UTF_8))));
    }
    private static JSONArray rows(HistoryStore store, String key) throws Exception {
        JSONArray result = new JSONArray();
        for (HistoryStore.Entry row : store.list(key)) result.put(new JSONObject()
                .put("id", row.id()).put("createdMs", row.createdMs()).put("playedMs", row.playedMs())
                .put("kind", row.kind()).put("pinned", row.pinned()).put("head", row.head())
                .put("label", row.label()).put("session", row.session()).put("parent", row.parent()));
        return result;
    }
}
