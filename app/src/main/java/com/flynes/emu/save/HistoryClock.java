package com.flynes.emu.save;
/** Counts emulated time only; callers report successful core frames. */
public final class HistoryClock {
    private long micros, savedMicros;
    public synchronized void advance(long microseconds) {
        if (microseconds > 0)
            micros += microseconds;
    }
    public synchronized long playedMs() {
        return micros / 1000;
    }
    public synchronized boolean due(long intervalMs) {
        return intervalMs > 0 && (micros - savedMicros) / 1000 >= intervalMs;
    }
    public synchronized boolean changed() {
        return micros != savedMicros;
    }
    public synchronized void saved() {
        savedMicros = micros;
    }
    /** Capture while the core is quiescent; retain precision across resumed I/O. */
    public synchronized long captureMicros() { return micros; }
    public synchronized void savedAt(long capturedMicros) {
        if(capturedMicros<savedMicros||capturedMicros>micros)
            throw new IllegalArgumentException("Checkpoint is outside current history progress");
        savedMicros=capturedMicros;
    }
    public synchronized void restore(long playedMs) {
        micros = Math.max(0, playedMs) * 1000;
        savedMicros = micros;
    }
}
