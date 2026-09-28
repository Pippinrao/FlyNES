package com.flynes.emu;

import java.util.Map;

/** A read-only capability query; native launch remains the authority on restoring state. */
final class FoundationResumeQuery {
    @FunctionalInterface interface Reader { byte[] read() throws Exception; }
    static Map<String, String> read(Reader head, Reader legacy) {
        try {
            byte[] state = head.read();
            if (state == null) state = legacy.read();
            if (state == null) return Map.of("state", "none");
            return state.length > 0 ? Map.of("state", "available")
                    : Map.of("state", "unavailable", "reason", "Progress unavailable");
        } catch (Exception failure) {
            return Map.of("state", "unavailable", "reason", "Progress unavailable");
        }
    }
}
