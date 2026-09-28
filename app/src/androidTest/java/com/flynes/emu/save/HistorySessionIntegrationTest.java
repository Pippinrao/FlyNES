package com.flynes.emu.save;
import static org.junit.Assert.*;

import android.content.Context;
import android.database.sqlite.SQLiteDatabase;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import com.flynes.emu.NesCore;
import com.flynes.emu.catalog.BuiltinGames;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import org.junit.Test;
import org.junit.runner.RunWith;
@RunWith(AndroidJUnit4.class)
public class HistorySessionIntegrationTest {
    @Test
    public void selectedHeadSkipsUnreadableLegacyAutosave() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File file = new File(context.getCacheDir(), "history-lazy-legacy-" + System.nanoTime() + ".sqlite");
        NesCore core = new NesCore();
        core.create();
        byte[] rom = batteryRom();
        try (HistoryStore store = new HistoryStore(file)) {
            assertTrue(core.loadRom(rom) >= 0);
            core.setAudioFormat(48000, 0);
            String key = core.romInfo().identity().sha1();
            core.runFrames(20);
            byte[] selected = core.saveState();
            long head = store.put(key, selected, null, HistoryStore.MANUAL,
                "Selected", 500, "one", 0, true);
            core.runFrames(20);
            HistoryClock clock = new HistoryClock();
            HistorySession session = new HistorySession(core, store, key, rom, clock, () -> null);
            try {
                session.initializeFromLegacyLoader(() -> { throw new IOException("unreadable legacy file"); });
            } catch (IOException failure) {
                fail("a valid selected head must not read the legacy autosave: " + failure.getMessage());
            }
            assertArrayEquals(selected, core.saveState());
            assertEquals(head, store.head(key));
            assertEquals(1, store.list(key).length);
            assertEquals(500, clock.playedMs());
        } finally {
            core.destroy();
            SQLiteDatabase.deleteDatabase(file);
        }
    }

    @Test
    public void legacyLoaderMigratesOnlyWhenHistoryHasNoHead() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File file = new File(context.getCacheDir(), "history-lazy-migrate-" + System.nanoTime() + ".sqlite");
        NesCore core = new NesCore();
        core.create();
        byte[] rom = batteryRom();
        try (HistoryStore store = new HistoryStore(file)) {
            assertTrue(core.loadRom(rom) >= 0);
            core.setAudioFormat(48000, 0);
            core.runFrames(20);
            byte[] legacy = core.saveState();
            String key = core.romInfo().identity().sha1();
            core.runFrames(20);
            HistorySession session = new HistorySession(core, store, key, rom, new HistoryClock(), () -> null);
            int[] reads = {0};
            HistorySession.LegacyLoader loader = () -> {
                reads[0]++;
                return new SaveRecord(legacy, 100);
            };
            session.initializeFromLegacyLoader(loader);
            assertArrayEquals(legacy, core.saveState());
            assertTrue(store.head(key) > 0);
            assertEquals(HistoryStore.LEGACY, store.list(key)[0].kind());
            session.initializeFromLegacyLoader(loader);
            assertEquals("migration reads legacy storage only once", 1, reads[0]);
            assertEquals(1, store.list(key).length);
        } finally {
            core.destroy();
            SQLiteDatabase.deleteDatabase(file);
        }
    }


    @Test
    public void failedRestoreReopensAtRolledBackLiveProgress() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File file = new File(context.getCacheDir(), "history-rollback-head-" + System.nanoTime() + ".sqlite");
        NesCore core = new NesCore();
        core.create();
        byte[] rom = batteryRom();
        byte[] live;
        try {
            assertTrue(core.loadRom(rom) >= 0);
            core.setAudioFormat(48000, 0);
            String key = core.romInfo().identity().sha1();
            try (HistoryStore store = new HistoryStore(file)) {
                HistoryClock clock = new HistoryClock();
                HistorySession session = new HistorySession(core, store, key, rom, clock, () -> null);
                session.save(HistoryStore.MANUAL, "Old head");
                core.runFrames(20);
                clock.advance(500000);
                live = core.saveState();
                long bad = store.put(key, new byte[] {9, 9}, null, HistoryStore.MANUAL,
                    "Invalid core state", 0, "one", 0, false);
                try {
                    session.restore(bad);
                    fail("invalid core state accepted");
                } catch (IllegalStateException expected) {
                }
                assertArrayEquals("restore failure rolls back live progress", live, core.saveState());
                assertArrayEquals("persisted head must match rolled-back live progress",
                    live, store.read(key, store.head(key), false));
                assertEquals(0, store.pending(key)[0]);
            }
            core.runFrames(20);
            try (HistoryStore store = new HistoryStore(file)) {
                HistoryClock clock = new HistoryClock();
                new HistorySession(core, store, key, rom, clock, () -> null).initialize(null);
                assertArrayEquals(live, core.saveState());
                assertEquals(500, clock.playedMs());
            }
        } finally {
            core.destroy();
            SQLiteDatabase.deleteDatabase(file);
        }
    }

    @Test
    public void interruptedRecoveryKeepsPendingIntentAndHeadUntilRetry() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File file = new File(context.getCacheDir(), "history-recovery-" + System.nanoTime() + ".sqlite");
        NesCore core = new NesCore();
        core.create();
        byte[] rom = batteryRom();
        assertTrue(core.loadRom(rom) >= 0);
        core.setAudioFormat(48000, 0);
        String key = core.romInfo().identity().sha1();
        try {
            long head;
            long[] pending;
            byte[] backup;
            try (HistoryStore store = new HistoryStore(file)) {
                head = store.put(key, core.saveState(), null, HistoryStore.MANUAL,
                    "Selected", 0, "one", 0, true);
                core.runFrames(20);
                backup = core.saveState();
                pending = store.prepare(key, head, backup, null, 500, "one", "Before restore");
            }
            core.runFrames(20);
            byte[] original = core.saveState();
            // Reject only publishing the protection head. The old split implementation
            // commits cancellation before this fault; atomic recovery must commit neither.
            try (SQLiteDatabase fault = SQLiteDatabase.openDatabase(
                     file.getAbsolutePath(), null, SQLiteDatabase.OPEN_READWRITE)) {
                fault.execSQL("CREATE TRIGGER reject_recovery_head BEFORE UPDATE ON heads "
                    + "WHEN NEW.entry_id=" + pending[1]
                    + " BEGIN SELECT RAISE(ABORT, 'injected recovery failure'); END");
            }
            try (HistoryStore store = new HistoryStore(file)) {
                HistorySession session = new HistorySession(
                    core, store, key, rom, new HistoryClock(), () -> null);
                try {
                    session.initialize(null);
                    fail("recovery fault must be reported");
                } catch (IllegalStateException expected) {
                }
                assertArrayEquals("failed recovery rolls back the live core", original, core.saveState());
                assertEquals("failed recovery retains selected head", head, store.head(key));
                assertEquals("failed recovery must retain pending intent", pending[0], store.pending(key)[0]);
            }
            try (SQLiteDatabase fault = SQLiteDatabase.openDatabase(
                     file.getAbsolutePath(), null, SQLiteDatabase.OPEN_READWRITE)) {
                fault.execSQL("DROP TRIGGER reject_recovery_head");
            }
            try (HistoryStore store = new HistoryStore(file)) {
                HistoryClock clock = new HistoryClock();
                new HistorySession(core, store, key, rom, clock, () -> null).initialize(null);
                assertArrayEquals(backup, core.saveState());
                assertEquals(pending[1], store.head(key));
                assertEquals(0, store.pending(key)[0]);
                assertEquals(500, clock.playedMs());
            }
        } finally {
            core.destroy();
            SQLiteDatabase.deleteDatabase(file);
        }
    }

    @Test
    public void failedSelectedHeadLoadRestoresPreviousCoreState() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File file =
            new File(context.getCacheDir(), "history-bad-head-" + System.nanoTime() + ".sqlite");
        NesCore core = new NesCore();
        core.create();
        byte[] rom = batteryRom();
        assertTrue(core.loadRom(rom) >= 0);
        core.setAudioFormat(48000, 0);
        core.runFrames(20);
        byte[] original = core.saveState();
        byte[] corrupt = java.util.Arrays.copyOf(original, original.length - 4);
        java.nio.ByteBuffer header =
            java.nio.ByteBuffer.wrap(corrupt).order(java.nio.ByteOrder.LITTLE_ENDIAN);
        header.putLong(69, corrupt.length - 81);
        java.util.zip.CRC32 crc = new java.util.zip.CRC32();
        crc.update(corrupt, 81, corrupt.length - 81);
        header.putInt(77, (int) crc.getValue());
        String key = core.romInfo().identity().sha1();
        try (HistoryStore store = new HistoryStore(file)) {
            long bad =
                store.put(key, corrupt, null, HistoryStore.MANUAL, "damaged", 100, "one", 0, true);
            HistorySession session =
                new HistorySession(core, store, key, rom, new HistoryClock(), () -> null);
            try {
                session.initialize(null);
                fail("truncated inner NST accepted");
            } catch (IllegalStateException expected) {
            }
            assertArrayEquals(
                "failed startup load must roll back core mutation", original, core.saveState());
            assertEquals(bad, store.head(key));
            assertEquals(1, store.list(key).length);
        } finally {
            core.destroy();
            file.delete();
        }
    }

    @Test
    public void restartKeepsLiveBatteryRamAndSelectedSaveAcrossReopen() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File file =
            new File(context.getCacheDir(), "history-battery-" + System.nanoTime() + ".sqlite");
        byte[] rom = batteryRom();
        NesCore core = new NesCore();
        core.create();
        try (HistoryStore store = new HistoryStore(file)) {
            assertTrue(core.loadRom(rom) >= 0);
            core.setAudioFormat(48000, 0);
            core.runFrames(2);
            int first = cpuRam(core.saveState())[0] & 255;
            HistorySession session = new HistorySession(
                core, store, core.romInfo().identity().sha1(), rom, new HistoryClock(), () -> null);
            session.restart();
            byte[] fresh = core.saveState();
            core.runFrames(2);
            assertEquals("battery-backed RAM survives restart", (first + 1) & 255,
                cpuRam(core.saveState())[0] & 255);
            assertTrue(core.loadState(fresh) >= 0);
            core.runFrames(2);
            assertEquals("fresh head includes retained battery RAM", (first + 1) & 255,
                cpuRam(core.saveState())[0] & 255);
        } finally {
            core.destroy();
            file.delete();
        }
    }

    // Minimal authored NROM: increment battery byte $6000 at reset, mirror it to CPU RAM,
    // then loop forever. No external or copyrighted ROM fixture is needed.
    private static byte[] batteryRom() {
        byte[] rom = new byte[16 + 16384 + 8192];
        rom[0] = 'N';
        rom[1] = 'E';
        rom[2] = 'S';
        rom[3] = 26;
        rom[4] = 1;
        rom[5] = 1;
        rom[6] = 2;
        int[] program = {0x78, 0xee, 0x00, 0x60, 0xad, 0x00, 0x60, 0x85, 0x00, 0x4c, 0x09, 0x80};
        for (int i = 0; i < program.length; i++) rom[16 + i] = (byte) program[i];
        for (int offset : new int[] {0x3ffa, 0x3ffc, 0x3ffe}) {
            rom[16 + offset] = 0;
            rom[16 + offset + 1] = (byte) 0x80;
        }
        return rom;
    }
    private static byte[] cpuRam(byte[] state) throws Exception {
        int cpu = findChunk(state, 101, state.length, "CPU");
        int length =
            java.nio.ByteBuffer.wrap(state).order(java.nio.ByteOrder.LITTLE_ENDIAN).getInt(cpu + 4);
        int ram = findChunk(state, cpu + 8, cpu + 8 + length, "RAM");
        int count =
            java.nio.ByteBuffer.wrap(state).order(java.nio.ByteOrder.LITTLE_ENDIAN).getInt(ram + 4);
        if (state[ram + 8] == 0)
            return java.util.Arrays.copyOfRange(state, ram + 9, ram + 8 + count);
        java.util.zip.Inflater inflater = new java.util.zip.Inflater();
        try {
            inflater.setInput(state, ram + 9, count - 1);
            byte[] decoded = new byte[2048];
            assertEquals(2048, inflater.inflate(decoded));
            return decoded;
        } finally {
            inflater.end();
        }
    }
    private static int findChunk(byte[] bytes, int start, int end, String tag) {
        for (int p = start; p + 8 <= end;) {
            if (bytes[p] == tag.charAt(0) && bytes[p + 1] == tag.charAt(1)
                && bytes[p + 2] == tag.charAt(2) && bytes[p + 3] == 0)
                return p;
            p += 8
                + java.nio.ByteBuffer.wrap(bytes)
                      .order(java.nio.ByteOrder.LITTLE_ENDIAN)
                      .getInt(p + 4);
        }
        throw new AssertionError("missing " + tag + " chunk");
    }

    @Test
    public void restoreRestartAndReopenUseSelectedHeadAndPreserveHistory() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File file =
            new File(context.getCacheDir(), "history-session-" + System.nanoTime() + ".sqlite");
        NesCore core = new NesCore();
        core.create();
        BuiltinGames games;
        try (InputStream in = context.getAssets().open(BuiltinGames.ASSET_NAME)) {
            games = BuiltinGames.parse(in);
        }
        byte[] rom;
        try (InputStream in = context.getAssets().open(games.all().get(0).assetPath())) {
            rom = in.readAllBytes();
        }
        core.loadRom(rom);
        core.setAudioFormat(48000, 0);
        String key = core.romInfo().identity().sha1();
        byte[] fresh;
        try (HistoryStore store = new HistoryStore(file)) {
            HistoryClock clock = new HistoryClock();
            HistorySession session = new HistorySession(core, store, key, rom, clock, () -> null);
            core.runFrames(30);
            clock.advance(500000);
            byte[] first = core.saveState();
            long id = session.save(HistoryStore.MANUAL, "First");
            assertTrue("manual save committed", id > 0);
            core.runFrames(30);
            clock.advance(500000);
            byte[] later = core.saveState();
            session.restore(id);
            assertArrayEquals(first, core.saveState());
            assertEquals(id, store.head(key));
            assertEquals(500, clock.playedMs());
            long bad = store.put(
                key, new byte[] {9, 9}, null, HistoryStore.AUTO, "bad", 2000, "test", id, false);
            try {
                session.restore(bad);
                fail("core-invalid target accepted");
            } catch (IllegalStateException expected) {
            }
            assertArrayEquals(first, core.saveState());
            assertArrayEquals(first, store.read(key, store.head(key), false));
            session.restart();
            fresh = core.saveState();
            assertFalse(java.util.Arrays.equals(first, fresh));
            assertEquals(0, clock.playedMs());
            assertTrue(store.list(key).length >= 4);
            assertArrayEquals(first, store.read(key, id, false));
        }
        try (HistoryStore store = new HistoryStore(file)) {
            core.runFrames(10);
            HistorySession session =
                new HistorySession(core, store, key, rom, new HistoryClock(), () -> null);
            session.initialize(null);
            assertArrayEquals(fresh, core.saveState());
        } finally {
            core.destroy();
            file.delete();
        }
    }
    @Test
    public void migrationValidatesBeforePublishingAndIsIdempotent() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File file =
            new File(context.getCacheDir(), "history-migrate-" + System.nanoTime() + ".sqlite");
        NesCore core = new NesCore();
        core.create();
        BuiltinGames games;
        try (InputStream in = context.getAssets().open(BuiltinGames.ASSET_NAME)) {
            games = BuiltinGames.parse(in);
        }
        byte[] rom;
        try (InputStream in = context.getAssets().open(games.all().get(0).assetPath())) {
            rom = in.readAllBytes();
        }
        core.loadRom(rom);
        core.setAudioFormat(48000, 0);
        core.runFrames(20);
        byte[] original = core.saveState();
        String key = core.romInfo().identity().sha1();
        try (HistoryStore store = new HistoryStore(file)) {
            HistorySession session =
                new HistorySession(core, store, key, rom, new HistoryClock(), () -> null);
            try {
                session.initialize(new SaveRecord(new byte[] {1}, 100));
                fail("invalid migration accepted");
            } catch (IllegalStateException expected) {
            }
            assertEquals(0, store.head(key));
            assertArrayEquals(original, core.saveState());
            session.initialize(new SaveRecord(original, 100));
            assertTrue(store.head(key) > 0);
            int count = store.list(key).length;
            session.initialize(new SaveRecord(original, 100));
            assertEquals(count, store.list(key).length);
        } finally {
            core.destroy();
            file.delete();
        }
    }
}
