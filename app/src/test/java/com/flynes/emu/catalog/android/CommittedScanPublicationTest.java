package com.flynes.emu.catalog.android;
import static org.junit.Assert.*;
import java.io.IOException;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Test;
public class CommittedScanPublicationTest {
    @Test public void epochFailureStillPublishesCommittedGenerationAndReportsCommittedFailure() {
        AtomicInteger generation=new AtomicInteger(7);
        Exception failure=assertThrows(Exception.class,()->AndroidCatalogRuntime.reconcileCommittedScan(
                ()->{throw new IOException("epoch failed");},()->generation.set(8)));
        assertEquals("Committed native generation must replace old rows",8,generation.get());
        assertTrue(failure instanceof ProductSourceTransactions.Failure);
        assertEquals("scan_committed_refresh_failed",((ProductSourceTransactions.Failure)failure).code());
    }
    @Test public void projectionFailureIsReportedAfterCommitWithoutLosingEpochFailure() {
        Exception failure=assertThrows(Exception.class,()->AndroidCatalogRuntime.reconcileCommittedScan(
                ()->{throw new IOException("epoch failed");},()->{throw new IOException("projection failed");}));
        assertTrue(failure instanceof ProductSourceTransactions.Failure);
        assertEquals("scan_committed_refresh_failed",((ProductSourceTransactions.Failure)failure).code());
        assertEquals(1,failure.getSuppressed().length);
    }
}
