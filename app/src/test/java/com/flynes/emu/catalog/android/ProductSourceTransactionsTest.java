package com.flynes.emu.catalog.android;

import com.flynes.emu.app.FlyCatalogCommands;
import com.flynes.emu.catalog.source.ReadPermissionGateway;
import org.junit.Test;
import java.util.*;
import static org.junit.Assert.*;

public class ProductSourceTransactionsTest {
    @Test public void committedRemovalReconcilesProjectionEvenWhenMappingCleanupFails() throws Exception {
        Commands commands = new Commands();
        boolean[] reconciled = {false};
        assertThrows(Exception.class, () -> ProductSourceTransactions.remove(commands,new byte[16],
                () -> { throw new java.io.IOException("mapping storage failed"); },
                () -> reconciled[0] = true));
        assertEquals(1,commands.commits);
        assertTrue("new native generation must be reflected after committed deletion",reconciled[0]);
    }
    @Test public void rejectedRemovalBeginLeavesMappingRegistrationAndGrantUntouched() throws Exception {
        Commands commands = new Commands();commands.begin = -1;
        boolean[] registered = {true};
        var failure = assertThrows(ProductSourceTransactions.Failure.class, () ->
                ProductSourceTransactions.remove(commands,new byte[16],()->registered[0]=false));
        assertEquals("source_write_failed",failure.code());
        assertTrue(registered[0]);assertEquals(0,commands.commits);
    }
    @Test public void rejectedRemovalCommitLeavesMappingRegistrationAndGrantUntouched() throws Exception {
        Commands commands = new Commands();commands.commit = FlyCatalogCommands.CONFLICT;
        boolean[] registered = {true};
        var failure = assertThrows(ProductSourceTransactions.Failure.class, () ->
                ProductSourceTransactions.remove(commands,new byte[16],()->registered[0]=false));
        assertEquals("source_write_failed",failure.code());
        assertTrue(registered[0]);assertEquals(1,commands.commits);
    }
    @Test public void failedRegrantProjectionRestoresOldRegistrationMappingAndLocatorAndReleasesNewGrant() throws Exception {
        Fixture f = new Fixture();
        assertThrows(Exception.class, () -> ProductSourceTransactions.regrant(f.map,f.locators,f.grants,
                f.uuid,"content://new",1,new ProductSourceTransactions.Projection() {
                    public void publish() throws Exception {f.registration="new";throw new java.io.IOException("disk failure");}
                    public void restore() {f.registration="old";}
                }));
        assertEquals("old",f.registration);
        assertEquals("content://old",f.map.get(f.uuid));
        assertEquals("content://old/document/game",f.locators.get(f.uuid,"game.nes"));
        assertNull(f.map.uuidForLocator("content://new"));
        assertEquals(Set.of("content://old"),f.grants.granted);
    }
    @Test public void failedRegrantNeverReleasesAPreexistingSharedGrant() throws Exception {
        Fixture f = new Fixture();f.grants.granted.add("content://new");
        assertThrows(Exception.class, () -> ProductSourceTransactions.regrant(f.map,f.locators,f.grants,
                f.uuid,"content://new",1,new ProductSourceTransactions.Projection() {
                    public void publish() throws Exception {throw new java.io.IOException();}
                    public void restore() { }
                }));
        assertEquals("content://old",f.map.get(f.uuid));
        assertTrue(f.grants.granted.contains("content://new"));
    }
    static class Fixture {
        final Map<String,String> backing = new HashMap<>();
        final AndroidUuidSafMap map = new AndroidUuidSafMap(backing::get,backing::put,backing::remove);
        final AndroidPackageLocatorMap locators = new AndroidPackageLocatorMap();
        final Grants grants = new Grants();
        final byte[] uuid = new byte[16];String registration="old";
        Fixture(){uuid[0]=1;map.put(uuid,"content://old");locators.put(uuid,"game.nes","content://old/document/game");grants.granted.add("content://old");}
    }
    static class Grants implements ReadPermissionGateway {
        final Set<String> granted = new HashSet<>();
        public void takeRead(String locator,int flags){granted.add(locator);}
        public boolean hasPersistedRead(String locator){return granted.contains(locator);}
        public void releaseRead(String locator){granted.remove(locator);}
    }
    static class Commands implements FlyCatalogCommands {
        int begin=0,commit=0,commits;
        public int scanBegin(byte[] id,int scope){return begin;}
        public int scanCommit(int completeness){commits++;return commit;}
        public void scanAbort() { }
        public int scanAddFile(String path,String name,int fd,byte[] sha){return 0;}
        public int favoriteSet(String id,boolean value){return 0;}
        public int markPlayed(String id){return 0;}
    }
}
