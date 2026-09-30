package com.flynes.emu.catalog.android;

import com.flynes.emu.app.FlyCatalogCommands;
import com.flynes.emu.catalog.source.ReadPermissionGateway;

/** Checked source mutations; called only on the catalog's serial owner. */
public final class ProductSourceTransactions {
    private ProductSourceTransactions() { }
    @FunctionalInterface public interface Action { void run() throws Exception; }
    public interface Projection { void publish() throws Exception; void restore() throws Exception; }
    public static final class Failure extends Exception {
        private final String code;
        Failure(String code,Throwable cause) {super(code,cause);this.code=code;}
        public String code() {return code;}
    }
    public static void remove(FlyCatalogCommands commands,byte[] uuid,Action removeRegistration) throws Exception {
        remove(commands,uuid,removeRegistration,()->{});
    }
    public static void remove(FlyCatalogCommands commands,byte[] uuid,Action removeRegistration,
            Action reconcileProjection) throws Exception {
        int begun = commands.scanBegin(uuid,FlyCatalogCommands.SOURCE_SCOPE_USER_DIRECTORY);
        if (begun != FlyCatalogCommands.OK) {
            commands.scanAbort();
            throw new Failure("source_write_failed",null);
        }
        int committed = commands.scanCommit(FlyCatalogCommands.SCAN_FULL);
        if (committed != FlyCatalogCommands.OK) {
            commands.scanAbort();
            throw new Failure("source_write_failed",null);
        }
        Exception cleanup = null;
        try { removeRegistration.run(); }
        catch (Exception failure) { cleanup = failure; }
        // The native commit already happened. Even failed preference cleanup must
        // publish that generation, otherwise every subsequent window is stale.
        try { reconcileProjection.run(); }
        catch (Exception failure) {
            if (cleanup == null) cleanup = failure; else cleanup.addSuppressed(failure);
        }
        if (cleanup != null) throw new Failure("source_cleanup_failed",cleanup);
    }
    public static void regrant(AndroidUuidSafMap map,AndroidPackageLocatorMap locators,
            ReadPermissionGateway permissions,byte[] uuid,String locator,int flags,Projection projection) throws Exception {
        String previous = map.get(uuid);
        if (previous == null) throw new IllegalArgumentException("unknown source");
        byte[] assigned = map.uuidForLocator(locator);
        if (assigned != null && !java.util.Arrays.equals(assigned,uuid))
            throw new IllegalArgumentException("source already registered");
        boolean grantedBefore = permissions.hasPersistedRead(locator);
        var oldLocators = locators.snapshot();
        boolean publishing = false;
        try {
            permissions.takeRead(locator,flags);
            map.put(uuid,locator);
            locators.invalidateSource(uuid);
            publishing = true;
            projection.publish();
        } catch (Exception cause) {
            Failure failure = new Failure("source_reauthorize_failed",cause);
            try { if (!previous.equals(map.get(uuid))) map.put(uuid,previous); }
            catch (Exception rollback) { failure.addSuppressed(rollback); }
            locators.restoreSource(uuid,oldLocators);
            if (publishing) {
                try { projection.restore(); }
                catch (Exception rollback) { failure.addSuppressed(rollback); }
            }
            // A grant already held by the app, or still referenced after failed compensation,
            // belongs to an existing source and must remain untouched.
            if (!grantedBefore && map.uuidForLocator(locator)==null) {
                try { if (permissions.hasPersistedRead(locator)) permissions.releaseRead(locator); }
                catch (Exception release) { failure.addSuppressed(release); }
            }
            throw failure;
        }
    }
}
