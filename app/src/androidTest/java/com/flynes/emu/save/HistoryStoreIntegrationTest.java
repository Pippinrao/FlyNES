package com.flynes.emu.save;

import static org.junit.Assert.*;

import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import com.flynes.emu.NesCore;
import com.flynes.emu.catalog.BuiltinGames;
import java.io.File;
import java.io.InputStream;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public class HistoryStoreIntegrationTest {
    @Test
    public void quotaRejectsProtectionBeforeChangingHead() {
        Context context = ApplicationProvider.getApplicationContext();
        File file =
            new File(context.getCacheDir(), "history-quota-" + System.nanoTime() + ".sqlite");
        try (HistoryStore store = new HistoryStore(file, 3)) {
            long first = store.put(
                "rom", new byte[] {1, 2}, null, HistoryStore.MANUAL, "", 0, "one", 0, true);
            try {
                store.prepare("rom", first, new byte[] {3, 4}, null, 10, "one", "");
                fail("backup quota must reject restore");
            } catch (IllegalStateException expected) {
                assertTrue(expected.getMessage().contains("full"));
            }
            assertEquals(first, store.head("rom"));
            assertEquals(1, store.list("rom").length);
            assertEquals(0, store.pending("rom")[0]);
        } finally {
            file.delete();
        }
    }
    @Test
    public void selectedHeadSurvivesReopenAndKeepsProtection() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File file =
            new File(context.getCacheDir(), "history-test-" + System.nanoTime() + ".sqlite");
        long early;
        try (HistoryStore store = new HistoryStore(file)) {
            early = store.put("rom", new byte[] {1, 2}, new byte[] {9}, HistoryStore.MANUAL,
                "early", 100, "one", 0, true);
            assertTrue("committed save must have an id", early > 0);
            store.put(
                "rom", new byte[] {3}, null, HistoryStore.AUTO, "later", 200, "one", early, true);
            long[] pending =
                store.prepare("rom", early, new byte[] {4}, null, 300, "one", "Before restore");
            assertArrayEquals(new byte[] {4}, store.read("rom", pending[1], false));
            store.finish(pending[0]);
            assertEquals(early, store.head("rom"));
            store.rename(early, "Checkpoint");
            store.pin(early, true);
            assertTrue(store.list("rom").length >= 3);
        }
        try (HistoryStore store = new HistoryStore(file)) {
            assertEquals(early, store.head("rom"));
            assertArrayEquals(new byte[] {1, 2}, store.read("rom", early, false));
            assertArrayEquals(new byte[] {9}, store.read("rom", early, true));
            try {
                store.read("other-ROM", early, false);
                fail("wrong ROM accepted");
            } catch (IllegalStateException expected) {
            }
        }
        file.delete();
    }
    @Test
    public void restoresRealCoreSnapshotAndRejectsMissingTargetWithoutMovingHead()
        throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File file =
            new File(context.getCacheDir(), "history-core-test-" + System.nanoTime() + ".sqlite");
        NesCore core = new NesCore();
        try (HistoryStore store = new HistoryStore(file)) {
            assertTrue(core.create());
            BuiltinGames games;
            try (InputStream in = context.getAssets().open(BuiltinGames.ASSET_NAME)) {
                games = BuiltinGames.parse(in);
            }
            byte[] rom;
            try (InputStream in = context.getAssets().open(games.all().get(0).assetPath())) {
                rom = in.readAllBytes();
            }
            assertTrue(core.loadRom(rom) >= 0);
            core.setAudioFormat(48000, 0);
            core.runFrames(30);
            String key = core.romInfo().identity().sha1();
            byte[] first = core.saveState();
            long id = store.put(key, first, null, HistoryStore.MANUAL, "", 100, "test", 0, true);
            core.runFrames(60);
            byte[] advanced = core.saveState();
            assertFalse(java.util.Arrays.equals(first, advanced));
            long[] op = store.prepare(key, id, advanced, null, 200, "test", "Before restore");
            assertTrue(core.loadState(store.read(key, id, false)) >= 0);
            store.finish(op[0]);
            assertArrayEquals(first, core.saveState());
            try {
                store.prepare(key, Long.MAX_VALUE, first, null, 100, "test", "");
                fail("missing target accepted");
            } catch (IllegalStateException expected) {
            }
            assertEquals(id, store.head(key));
        } finally {
            core.destroy();
            file.delete();
        }
    }
}
