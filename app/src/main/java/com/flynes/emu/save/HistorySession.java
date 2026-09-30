package com.flynes.emu.save;

import com.flynes.emu.NesCore;
import java.io.IOException;
import java.util.UUID;
import java.util.function.Supplier;

/** Capture requires a quiescent core. The AUTO hook may resume after capture;
 * SQLite only receives independent bytes and never calls the live core. */
public final class HistorySession {
    private final NesCore core;
    private final HistoryStore store;
    private final String key;
    private final byte[] rom;
    private final HistoryClock clock;
    private final Supplier<byte[]> thumbnail;
    private String session = UUID.randomUUID().toString();
    private long parent;
    @FunctionalInterface
    public interface LegacyLoader {
        SaveRecord load() throws IOException;
    }
    public HistorySession(NesCore core, HistoryStore store, String key, byte[] rom,
        HistoryClock clock, Supplier<byte[]> thumbnail) {
        this.core = core;
        this.store = store;
        this.key = key;
        this.rom = rom;
        this.clock = clock;
        this.thumbnail = thumbnail;
    }
    public void initialize(SaveRecord legacy) {
        try {
            initializeFromLegacyLoader(() -> legacy);
        } catch (IOException impossible) {
            throw new AssertionError(impossible);
        }
    }
    public void initializeFromLegacyLoader(LegacyLoader legacyLoader) throws IOException {
        byte[] original = capture();
        try {
            long[] pending = store.pending(key);
            if (pending[0] != 0) {
                load(store.read(key, pending[2], false));
                store.recover(pending[0]);
            }
            long head = store.head(key);
            if (head != 0) {
                load(store.read(key, head, false));
                select(metadata(head));
                return;
            }
            SaveRecord legacy = legacyLoader.load();
            if (legacy != null) {
                load(legacy.state());
                parent = store.put(
                    key, legacy.state(), image(), HistoryStore.LEGACY, "", 0, session, 0, true);
                clock.restore(0);
            }
        } catch (RuntimeException failure) {
            // A valid container can contain an incompatible/truncated NST. Nestopia may
            // reset or partially mutate the machine before returning a decoding error.
            rollback(original, failure);
            throw failure;
        }
    }
    public long save(int kind, String label) {
        return save(kind,label,null);
    }
    private long save(int kind,String label,Runnable afterCapture) {
        if (kind == HistoryStore.AUTO && !clock.changed())
            return parent;
        long capturedMicros=clock.captureMicros();
        byte[] state = SavePhaseTrace.measure("save.capture",this::capture);
        byte[] image = SavePhaseTrace.measure("save.thumbnail",this::image);
        if(afterCapture!=null)afterCapture.run();
        long id =
            SavePhaseTrace.measure("save.store",()->store.put(key, state, image, kind, label, capturedMicros/1000, session, parent, true));
        parent = id;
        clock.savedAt(capturedMicros);
        return id;
    }
    /** Resume only the captured core; do not reenter session/storage from this hook. */
    public long saveAutomatic(Runnable afterCapture) {
        return save(HistoryStore.AUTO,"",java.util.Objects.requireNonNull(afterCapture));
    }
    public void restore(long target) {
        HistoryStore.Entry targetEntry = metadata(target);
        byte[] original = capture();
        long[] pending = store.prepare(
            key, target, original, image(), clock.playedMs(), session, "Before restore");
        try {
            load(store.read(key, target, false));
            store.finish(pending[0]);
            select(targetEntry);
        } catch (RuntimeException failure) {
            rollback(original, failure);
            try {
                store.recover(pending[0]);
                select(metadata(pending[1]));
            } catch (RuntimeException recovery) {
                failure.addSuppressed(recovery);
            }
            throw failure;
        }
    }
    public void restart() {
        byte[] original = capture();
        long previousTime = clock.playedMs();
        String previousSession = session;
        long backup = store.put(key, original, image(), HistoryStore.PROTECTION, "Before restart",
            previousTime, session, parent, true);
        parent = backup;
        try {
            // Reload in the existing native context: its battery cache stays owned by this core.
            if (core.loadRom(rom) < 0)
                throw new IllegalStateException("Could not start a new game");
            core.setInput(0);
            String freshSession = UUID.randomUUID().toString();
            long fresh =
                store.put(key, capture(), null, HistoryStore.AUTO, "", 0, freshSession, 0, true);
            parent = fresh;
            session = freshSession;
            clock.restore(0);
        } catch (RuntimeException failure) {
            rollback(original, failure);
            clock.restore(previousTime);
            session = previousSession;
            throw failure;
        }
    }
    private HistoryStore.Entry metadata(long id) {
        for (HistoryStore.Entry entry : store.list(key))
            if (entry.id() == id)
                return entry;
        throw new IllegalStateException("Save record is unavailable");
    }
    private void select(HistoryStore.Entry entry) {
        parent = entry.id();
        session = entry.session();
        clock.restore(entry.playedMs());
    }
    private byte[] capture() {
        byte[] state = core.saveState();
        if (state == null || state.length == 0)
            throw new IllegalStateException("Could not capture game progress");
        return state;
    }
    private byte[] image() {
        try {
            return thumbnail.get();
        } catch (RuntimeException ignored) {
            return null;
        }
    }
    private void load(byte[] state) {
        core.setInput(0);
        if (core.loadState(state) < 0)
            throw new IllegalStateException("This save cannot be loaded by the current core");
        core.setInput(0);
    }
    private void rollback(byte[] state, RuntimeException failure) {
        try {
            load(state);
        } catch (RuntimeException rollback) {
            failure.addSuppressed(rollback);
            throw new IllegalStateException(
                "Restore failed and rollback needs retry; progress remains protected on disk",
                failure);
        }
    }
}
