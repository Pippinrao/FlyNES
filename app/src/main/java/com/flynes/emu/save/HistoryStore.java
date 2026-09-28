package com.flynes.emu.save;

import java.io.File;

/** Serialized JNI facade. SQLite and all retention/integrity policy belong to save_history. */
public final class HistoryStore implements AutoCloseable {
    static {
        System.loadLibrary("nescore");
    }
    public static final int AUTO = 0, MANUAL = 1, PROTECTION = 2, LEGACY = 3;
    public record Entry(long id, long createdMs, long playedMs, int kind, boolean pinned,
        boolean head, String label, String session, long parent) {}
    private long handle;
    public HistoryStore(File file) {
        this(file, 0);
    }
    public HistoryStore(File file, long maxContentBytes) {
        if (maxContentBytes < 0)
            throw new IllegalArgumentException("Negative quota");
        handle = nOpen(file.getAbsolutePath(), maxContentBytes);
    }
    public synchronized long put(String key, byte[] state, byte[] thumbnail, int kind, String label,
        long played, String session, long parent, boolean head) {
        return nPut(live(), key, state, thumbnail, kind, label, played, session, parent, head);
    }
    public synchronized Entry[] list(String key) {
        return nList(live(), key);
    }
    public synchronized byte[] read(String key, long id, boolean thumbnail) {
        return nRead(live(), key, id, thumbnail);
    }
    public synchronized long head(String key) {
        return nHead(live(), key);
    }
    public synchronized void setHead(String key, long id) {
        nAction(live(), 4, id, key, false);
    }
    public synchronized long[] prepare(String key, long target, byte[] current, byte[] thumbnail,
        long played, String session, String label) {
        return nPrepare(live(), key, target, current, thumbnail, played, session, label);
    }
    public synchronized void finish(long operation) {
        nAction(live(), 0, operation, "", false);
    }
    public synchronized void recover(long operation) {
        nAction(live(), 6, operation, "", false);
    }
    public synchronized void cancel(long operation) {
        nAction(live(), 1, operation, "", false);
    }
    public synchronized long[] pending(String key) {
        return nPending(live(), key);
    }
    public synchronized void rename(long id, String label) {
        nAction(live(), 2, id, label, false);
    }
    public synchronized void pin(long id, boolean pin) {
        nAction(live(), 3, id, "", pin);
    }
    public synchronized void delete(long id) {
        nAction(live(), 5, id, "", false);
    }
    private long live() {
        if (handle == 0)
            throw new IllegalStateException("Save history is closed");
        return handle;
    }
    @Override
    public synchronized void close() {
        if (handle != 0) {
            nClose(handle);
            handle = 0;
        }
    }
    private static native long nOpen(String path, long maxContentBytes);
    private static native void nClose(long h);
    private static native long nPut(long h, String key, byte[] state, byte[] thumbnail, int kind,
        String label, long played, String session, long parent, boolean head);
    private static native Entry[] nList(long h, String key);
    private static native byte[] nRead(long h, String key, long id, boolean thumbnail);
    private static native long nHead(long h, String key);
    private static native long[] nPrepare(long h, String key, long target, byte[] current,
        byte[] thumbnail, long played, String session, String label);
    private static native long[] nPending(long h, String key);
    private static native void nAction(long h, int action, long id, String text, boolean flag);
}
