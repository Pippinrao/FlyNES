package com.flynes.emu;

import org.junit.Test;
import static org.junit.Assert.*;

public class FoundationResumeQueryTest {
    @Test public void legacyProgressIsAvailableOnlyWhenHeadIsAbsent() {
        assertEquals("available", FoundationResumeQuery.read(() -> null, () -> new byte[] {1}).get("state"));
    }
    @Test public void validHeadNeverReadsBrokenLegacy() {
        assertEquals("available", FoundationResumeQuery.read(() -> new byte[] {1}, () -> {
            throw new AssertionError("A valid head must not read the old slot");
        }).get("state"));
    }
    @Test public void noHeadAndNoLegacyIsNone() {
        assertEquals("none", FoundationResumeQuery.read(() -> null, () -> null).get("state"));
    }
    @Test public void brokenHeadDoesNotSilentlyFallBackToLegacy() {
        assertEquals("unavailable", FoundationResumeQuery.read(() -> { throw new java.io.IOException(); },
                () -> { throw new AssertionError("Must not hide history failure"); }).get("state"));
    }
    @Test public void unreadableLegacyIsUnavailable() {
        assertEquals("unavailable", FoundationResumeQuery.read(() -> null,
                () -> { throw new java.io.IOException(); }).get("state"));
    }
    @Test public void emptyHeadIsUnavailable() {
        assertEquals("unavailable", FoundationResumeQuery.read(() -> new byte[0],
                () -> { throw new AssertionError("Must not hide empty head"); }).get("state"));
    }
}
