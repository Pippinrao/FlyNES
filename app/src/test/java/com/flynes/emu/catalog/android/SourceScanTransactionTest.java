package com.flynes.emu.catalog.android;
import static org.junit.Assert.*;
import com.flynes.emu.app.FlyCatalogCommands;
import com.flynes.emu.catalog.source.SourceScanOperations;
import java.util.concurrent.CancellationException;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Test;
public class SourceScanTransactionTest {
    @Test public void successfulFatalCommitRestoresOldLocatorsAndLeavesOtherSourcesUntouched() throws Exception {
        byte[] source=new byte[16],other=new byte[16];source[0]=1;other[0]=2;
        var locators=new AndroidPackageLocatorMap();
        locators.put(source,"game.nes","content://old/game");
        locators.put(other,"other.nes","content://other/game");
        var before=locators.snapshot();var commands=new Commands();
        try(var transaction=new SourceScanTransaction(commands,new SourceScanOperations().begin("source"),
                source,()->locators.restoreSource(source,before))) {
            locators.put(source,"game.nes","content://candidate/replacement");
            locators.put(source,"new.nes","content://candidate/new");
            transaction.commit(FlyCatalogCommands.SCAN_FATAL);
        }
        assertEquals(before,locators.snapshot());
        assertEquals(1,commands.commits);assertEquals(1,commands.aborts);
    }
    @Test public void successfulPartialCommitKeepsCandidateLocators() throws Exception {
        var commands=new Commands();AtomicInteger restores=new AtomicInteger();
        try(var transaction=new SourceScanTransaction(commands,new SourceScanOperations().begin("source"),
                new byte[16],restores::incrementAndGet)) {transaction.commit(FlyCatalogCommands.SCAN_PARTIAL);}
        assertEquals(0,restores.get());assertEquals(1,commands.commits);
    }
    @Test public void cancelledIngestionAbortsAndRestoresLocatorsWithoutCommit() throws Exception {
        var operations=new SourceScanOperations();var op=operations.begin("source");var commands=new Commands();
        AtomicInteger restores=new AtomicInteger();
        try(var transaction=new SourceScanTransaction(commands,op,new byte[16],restores::incrementAndGet)) {
            operations.cancel("source",op.id());
            assertThrows(CancellationException.class,()->transaction.commit(FlyCatalogCommands.SCAN_FULL));
        }
        assertEquals(0,commands.commits);assertEquals(1,commands.aborts);assertEquals(1,restores.get());
    }
    @Test public void commitConflictFailsAndRestoresWhileSuccessfulCommitKeepsLocators() throws Exception {
        for(int result:new int[]{FlyCatalogCommands.CONFLICT,FlyCatalogCommands.OK}) {
            var op=new SourceScanOperations().begin("source");var commands=new Commands();commands.commit=result;
            AtomicInteger restores=new AtomicInteger();
            try(var transaction=new SourceScanTransaction(commands,op,new byte[16],restores::incrementAndGet)) {
                if(result==0)transaction.commit(FlyCatalogCommands.SCAN_FULL);
                else assertEquals("scan_conflict",assertThrows(ProductSourceTransactions.Failure.class,
                        ()->transaction.commit(FlyCatalogCommands.SCAN_FULL)).code());
            }
            assertEquals(result==0?0:1,restores.get());assertEquals(1,commands.aborts);
        }
    }
    static class Commands extends ProductSourceTransactionsTest.Commands {
        int aborts;@Override public void scanAbort(){aborts++;}
    }
}
