package com.flynes.emu.catalog;

import org.junit.Test;
import static org.junit.Assert.*;

public class NativeReadyObservationTest {
    @Test public void unknownUntilOwnerSuccessfulAndFirstCompletionIsImmutable() {
        NativeReadyObservation observation = new NativeReadyObservation();
        assertNull(observation.snapshot());
        assertTrue(observation.completed(17, 42, 1234));
        assertEquals(new NativeReadyObservation.Ready(17, 42, 1234), observation.snapshot());
        assertFalse(observation.completed(18, 43, 9999));
        assertEquals(new NativeReadyObservation.Ready(17, 42, 1234), observation.snapshot());
    }
    @Test public void invalidCompletionCannotInventReady() {
        NativeReadyObservation observation = new NativeReadyObservation();
        assertThrows(IllegalArgumentException.class, () -> observation.completed(-1, 42, 1234));
        assertThrows(IllegalArgumentException.class, () -> observation.completed(0, 0, 1234));
        assertThrows(IllegalArgumentException.class, () -> observation.completed(0, 42, -1));
        assertNull(observation.snapshot());
    }
}
