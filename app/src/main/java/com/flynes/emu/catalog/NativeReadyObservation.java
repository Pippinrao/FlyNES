package com.flynes.emu.catalog;

/** Read-only first successful owner completion; absence means unknown, never zero latency. */
public final class NativeReadyObservation {
    public record Ready(long generation, int pid, long elapsedRealtimeMs) { }
    private final java.util.concurrent.atomic.AtomicReference<Ready> ready = new java.util.concurrent.atomic.AtomicReference<>();
    public Ready snapshot() { return ready.get(); }
    public boolean completed(long generation, int pid, long elapsedRealtimeMs) {
        if (generation < 0 || pid <= 0 || elapsedRealtimeMs < 0) throw new IllegalArgumentException();
        return ready.compareAndSet(null, new Ready(generation, pid, elapsedRealtimeMs));
    }
}
