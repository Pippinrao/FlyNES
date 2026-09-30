package com.flynes.emu.catalog.android;
import com.flynes.emu.app.FlyCatalogCommands;
import com.flynes.emu.catalog.source.SourceScanOperations;

/** Catalog-thread transaction; provider cancellation never calls native abort concurrently. */
final class SourceScanTransaction implements AutoCloseable {
    private final FlyCatalogCommands commands;
    private final SourceScanOperations.Operation operation;
    private final Runnable restoreLocators;
    private boolean candidatesAccepted;
    SourceScanTransaction(FlyCatalogCommands commands,SourceScanOperations.Operation operation,
            byte[] uuid,Runnable restoreLocators) throws ProductSourceTransactions.Failure {
        this.commands=commands;this.operation=operation;this.restoreLocators=restoreLocators;
        operation.checkpoint();
        if(commands.scanBegin(uuid,FlyCatalogCommands.SOURCE_SCOPE_USER_DIRECTORY)!=FlyCatalogCommands.OK) {
            commands.scanAbort();throw new ProductSourceTransactions.Failure("scan_failed",null);
        }
    }
    void commit(int completeness) throws ProductSourceTransactions.Failure {
        operation.committing();
        int result=commands.scanCommit(completeness);
        if(result!=FlyCatalogCommands.OK)throw new ProductSourceTransactions.Failure(
                result==FlyCatalogCommands.CONFLICT?"scan_conflict":"scan_failed",null);
        // FATAL publishes stale old rows but discards every candidate, including its locator.
        candidatesAccepted=completeness!=FlyCatalogCommands.SCAN_FATAL;
    }
    @Override public void close(){try{commands.scanAbort();}finally{if(!candidatesAccepted)restoreLocators.run();}}
}
