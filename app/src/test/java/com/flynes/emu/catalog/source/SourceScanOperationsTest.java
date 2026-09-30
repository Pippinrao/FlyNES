package com.flynes.emu.catalog.source;

import static org.junit.Assert.*;
import java.util.concurrent.CancellationException;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Test;

public class SourceScanOperationsTest {
    @Test public void queuedCancellationRemainsObservableAndDoesNotEnterCommit() {
        var scans=new SourceScanOperations();var op=scans.begin("source");
        assertEquals("queued",scans.snapshot("source").phase());
        assertNull(scans.snapshot("source").total());
        assertEquals("accepted",scans.cancel("source",op.id()));
        assertThrows(CancellationException.class,op::checkpoint);
        assertThrows(CancellationException.class,op::committing);
        op.finish("cancelled","");
        assertEquals(op.id(),scans.snapshot("source").operationId());
        assertEquals("cancelled",scans.snapshot("source").phase());
        assertFalse(scans.snapshot("source").canCancel());
    }
    @Test public void committingCannotCancelOrBeRelabeledByStaleOperation() {
        var scans=new SourceScanOperations();var old=scans.begin("source");old.finish("completed","");
        var op=scans.begin("source");op.enumerating();op.ingesting(2);op.advanced();op.advanced();
        assertEquals(2,scans.snapshot("source").completed());
        assertEquals("ingesting",scans.snapshot("source").phase());
        assertEquals("stale_operation",scans.cancel("source",old.id()));
        op.committing();assertFalse(scans.snapshot("source").canCancel());
        assertEquals("cancellation_unavailable",scans.cancel("source",op.id()));
        op.finish("partial","scan_partial");assertEquals("partial",scans.snapshot("source").phase());
    }
    @Test public void observerDetachDoesNotCancelOwnerAndDuplicateStartFails() throws Exception {
        var scans=new SourceScanOperations();AtomicInteger events=new AtomicInteger();
        var subscription=scans.observe(events::incrementAndGet);var op=scans.begin("source");
        assertThrows(IllegalStateException.class,()->scans.begin("source"));
        subscription.close();int before=events.get();op.enumerating();op.ingesting(0);op.committing();op.finish("completed","");
        assertEquals(before,events.get());assertEquals("completed",scans.snapshot("source").phase());
    }
    @Test public void cancellationSignalsProviderOnceAndStaysPendingUntilOwnerAcknowledges() {
        var scans=new SourceScanOperations();var op=scans.begin("source");AtomicInteger signals=new AtomicInteger();
        op.onCancel(signals::incrementAndGet);op.enumerating();
        assertEquals("accepted",scans.cancel("source",op.id()));
        assertEquals("accepted",scans.cancel("source",op.id()));assertEquals(1,signals.get());
        assertFalse(scans.snapshot("source").canCancel());
        assertEquals("cancelling",scans.snapshot("source").phase());
        assertThrows(CancellationException.class,op::checkpoint);
    }
}
