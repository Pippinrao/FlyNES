package com.flynes.emu;

import static org.junit.Assert.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;

public class ProductSourceNamesTest {
    @Test public void restartLoadsSavedNameAsynchronouslyThenRetainsItInMemory() {
        Fixture f=new Fixture();var first=f.cache();
        assertEquals("",first.get("source-a","content://old"));f.run("My ROMs");
        assertEquals("My ROMs",first.get("source-a","content://old"));
        var restarted=f.cache();assertEquals("",restarted.get("source-a","content://old"));f.run(null);
        assertEquals("My ROMs",restarted.get("source-a","content://old"));
    }
    @Test public void failedOrEmptyProviderQueryPreservesPersistedName() {
        for(String failed:new String[]{null,"","  ","content://provider/internal/123","/storage/private/roms"}) {
            Fixture f=new Fixture();f.saved.put("source-a",new ProductSourceNames.Entry("content://old","My ROMs"));
            var cache=f.cache();assertEquals("",cache.get("source-a","content://old"));f.run(failed);
            assertEquals("My ROMs",cache.get("source-a","content://old"));assertEquals("My ROMs",f.saved.get("source-a").name());
        }
    }
    @Test public void revokedPermissionAfterRestartRetainsLastSuccessfulLabel() {
        Fixture f=new Fixture();f.saved.put("source-a",new ProductSourceNames.Entry("content://old","My ROMs"));
        var cache=new ProductSourceNames(f,f,locator->{throw new SecurityException("revoked");},()->f.changes++);
        assertEquals("",cache.get("source-a","content://old"));f.run(null);
        assertEquals("My ROMs",cache.get("source-a","content://old"));assertEquals(1,f.changes);
    }
    @Test public void reauthorizationUsesSameIdentityButRejectsOldLocatorResult() {
        Fixture f=new Fixture();f.saved.put("source-a",new ProductSourceNames.Entry("content://old","My ROMs"));
        var cache=f.cache();cache.get("source-a","content://old");f.run(null);
        cache.refresh("source-a","content://old");
        assertEquals("My ROMs",cache.get("source-a","content://new"));
        f.run("Old directory");assertEquals("My ROMs",cache.get("source-a","content://new"));
        f.run("New directory");assertEquals("New directory",cache.get("source-a","content://new"));
        assertEquals(new ProductSourceNames.Entry("content://new","New directory"),f.saved.get("source-a"));
        assertEquals("",cache.get("source-b","content://old"));
    }
    @Test public void removalDeletesOnlyItsRecordAndIgnoresLateProviderResult() {
        Fixture f=new Fixture();f.saved.put("source-a",new ProductSourceNames.Entry("content://a","A"));
        f.saved.put("source-b",new ProductSourceNames.Entry("content://b","B"));
        var cache=f.cache();cache.get("source-a","content://a");cache.remove("source-a");f.run("Late A");f.run(null);
        assertFalse(f.saved.containsKey("source-a"));assertEquals("B",f.saved.get("source-b").name());assertEquals(0,f.changes);
    }
    @Test public void sameLocatorRegrantRetriesPreviouslyFailedLookup() {
        Fixture f=new Fixture();var cache=f.cache();cache.get("source-a","content://a");f.run(null);
        cache.refresh("source-a","content://a");assertEquals("Regrant must retry the provider",1,f.pending.size());f.run("Granted again");
        assertEquals("Granted again",cache.get("source-a","content://a"));assertEquals(1,f.changes);
    }
    @Test public void metadataStorageFailureCannotFailRefreshOrRemoval() {
        Fixture f=new Fixture();
        var failedStore=new ProductSourceNames.Store() {
            public ProductSourceNames.Entry read(String uuid){throw new IllegalStateException("read failed");}
            public void write(String uuid,ProductSourceNames.Entry value){throw new IllegalStateException("write failed");}
            public void remove(String uuid){throw new IllegalStateException("remove failed");}
        };
        var cache=new ProductSourceNames(failedStore,f,locator->f.providerName,()->f.changes++);
        assertEquals("",cache.get("source-a","content://a"));f.run(null);
        cache.refresh("source-a","content://a");f.run("My ROMs");
        assertEquals("My ROMs",cache.get("source-a","content://a"));cache.remove("source-a");f.run(null);
    }
    @Test public void blockedStoreReadDoesNotBlockColdGetOrOtherSources() throws Exception {assertBlockedStoreResponsive("read");}
    @Test public void blockedStoreWriteDoesNotBlockCachedGetOrRemoval() throws Exception {assertBlockedStoreResponsive("write");}
    @Test public void blockedStoreRemoveDoesNotBlockGetOrResurrectRemovedName() throws Exception {assertBlockedStoreResponsive("remove");}
    private void assertBlockedStoreResponsive(String operation) throws Exception {
        ExecutorService worker=Executors.newSingleThreadExecutor(r->new Thread(r,"source-name-test-worker"));
        ExecutorService caller=Executors.newSingleThreadExecutor(r->new Thread(r,"source-name-test-ui"));
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        var ioThread=new AtomicReference<String>();var saved=new ConcurrentHashMap<String,ProductSourceNames.Entry>();
        saved.put("source-a",new ProductSourceNames.Entry("content://a","Saved A"));
        var store=new ProductSourceNames.Store(){
            void block(String method) {
                if(!operation.equals(method))return;
                ioThread.set(Thread.currentThread().getName());entered.countDown();
                try{if(!release.await(5,TimeUnit.SECONDS))throw new AssertionError("fixture timeout");}
                catch(InterruptedException e){throw new AssertionError(e);}
            }
            public ProductSourceNames.Entry read(String uuid){block("read");return saved.get(uuid);}
            public void write(String uuid,ProductSourceNames.Entry value){block("write");saved.put(uuid,value);}
            public void remove(String uuid){block("remove");saved.remove(uuid);}
        };
        var cache=new ProductSourceNames(store,worker,uri->"Provider A",()->{});
        try {
            Future<?> initial=caller.submit(()->{
                if(operation.equals("remove"))cache.remove("source-a");else cache.get("source-a","content://a");
            });
            assertTrue(entered.await(2,TimeUnit.SECONDS));
            assertEquals("All store I/O belongs to the names worker", "source-name-test-worker",ioThread.get());
            initial.get(500,TimeUnit.MILLISECONDS);
            caller.submit(()->cache.get("source-a","content://a")).get(500,TimeUnit.MILLISECONDS);
            caller.submit(()->cache.get("source-b","content://b")).get(500,TimeUnit.MILLISECONDS);
            caller.submit(()->cache.remove("source-a")).get(500,TimeUnit.MILLISECONDS);
            assertEquals("",caller.submit(()->cache.get("source-a","content://a")).get(500,TimeUnit.MILLISECONDS));
            release.countDown();worker.submit(()->{}).get(2,TimeUnit.SECONDS);
            assertFalse("Queued removal must follow any previously admitted write",saved.containsKey("source-a"));
            assertEquals("",cache.get("source-a","content://a"));
        }finally {release.countDown();worker.shutdownNow();caller.shutdownNow();worker.awaitTermination(2,TimeUnit.SECONDS);caller.awaitTermination(2,TimeUnit.SECONDS);}
    }
    @Test public void removalTombstoneRejectsStaleReadsButExplicitRegrantCanReplaceIt() {
        Fixture f=new Fixture();f.saved.put("source-a",new ProductSourceNames.Entry("content://old","Old A"));
        var cache=f.cache();cache.get("source-a","content://old");cache.remove("source-a");
        assertEquals("",cache.get("source-a","content://old"));assertEquals(2,f.pending.size());
        cache.refresh("source-a","content://new");f.run("Late old result");f.run(null);f.run("New A");
        assertEquals("New A",cache.get("source-a","content://new"));
        assertEquals(new ProductSourceNames.Entry("content://new","New A"),f.saved.get("source-a"));
    }
    @Test public void unavailableNameWorkerCannotFailSourceReauthorization() {
        Fixture f=new Fixture();
        var cache=new ProductSourceNames(f,work->{throw new java.util.concurrent.RejectedExecutionException();},locator->"name",()->{});
        cache.refresh("source-a","content://a");assertEquals("",cache.get("source-a","content://a"));
    }
    static final class Fixture implements ProductSourceNames.Store,Executor {
        final Map<String,ProductSourceNames.Entry> saved=new HashMap<>();final Deque<Runnable> pending=new ArrayDeque<>();
        String providerName;int changes;
        ProductSourceNames cache(){return new ProductSourceNames(this,this,locator->providerName,()->changes++);}
        public ProductSourceNames.Entry read(String uuid){return saved.get(uuid);}
        public void write(String uuid,ProductSourceNames.Entry value){saved.put(uuid,value);}
        public void remove(String uuid){saved.remove(uuid);}
        public void execute(Runnable work){pending.add(work);}
        void run(String name){providerName=name;pending.remove().run();}
    }
}
