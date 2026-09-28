package com.flynes.emu.save;
import static org.junit.Assert.*;

import org.junit.Test;
public class HistoryClockTest {
    @Test
    public void onlyCoreProgressTriggersTimerAndPauseSaveDeduplicates() {
        HistoryClock clock = new HistoryClock();
        assertFalse(clock.changed());
        assertFalse(clock.due(60000));
        clock.advance(30000000);
        assertEquals(30000, clock.playedMs());
        assertFalse(clock.due(60000));
        assertTrue(clock.changed());
        clock.saved();
        assertFalse(clock.changed());
        clock.advance(59999000);
        assertFalse(clock.due(60000));
        clock.advance(1000);
        assertTrue(clock.due(60000));
        assertFalse(clock.due(0));
    }
    @Test
    public void restoreResetsBranchTimeAndDedupPosition() {
        HistoryClock clock = new HistoryClock();
        clock.advance(90000000);
        clock.saved();
        clock.restore(12000);
        assertEquals(12000, clock.playedMs());
        assertFalse(clock.changed());
        clock.advance(1000000);
        assertEquals(13000, clock.playedMs());
        assertTrue(clock.changed());
    }
}
