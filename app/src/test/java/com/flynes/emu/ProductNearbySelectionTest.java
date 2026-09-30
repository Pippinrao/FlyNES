package com.flynes.emu;
import static org.junit.Assert.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
public class ProductNearbySelectionTest {
    @Test public void admittedSelectionRunsOnWorkerAndInvalidationDoesNotWaitForIt() throws Exception {
        var lease=new ProductNearbySelection.CommandLease();Object owner=new Object();
        var entered=new CountDownLatch(1);var release=new CountDownLatch(1);
        var selectedThread=new AtomicReference<Thread>();var failure=new AtomicReference<Throwable>();
        Fixture f=new Fixture("") {
            @Override public boolean select(ProductNearbySelection.Selection value) {
                selectedThread.set(Thread.currentThread());entered.countDown();
                try{return release.await(3,TimeUnit.SECONDS);}catch(InterruptedException e){return false;}
            }
        };
        Thread worker=new Thread(()->{try {
            ProductNearbySelection.run(f,action->lease.run(owner,()->true,action),()->0,()->f.state=NearbyMvpSession.LOBBY);
        }catch(Throwable e){failure.set(e);}},"selection-test-worker");
        worker.start();
        try {
            assertTrue(entered.await(2,TimeUnit.SECONDS));assertSame(worker,selectedThread.get());
            var invalidated=new CountDownLatch(1);
            new Thread(()->{lease.invalidate();invalidated.countDown();}).start();
            assertTrue("Invalidation must not acquire the native command monitor",invalidated.await(1,TimeUnit.SECONDS));
        }finally {release.countDown();worker.join(3000);}
        assertFalse(worker.isAlive());assertTrue(failure.get() instanceof ProductNearbySelection.Failure);
        assertEquals("stale_host",((ProductNearbySelection.Failure)failure.get()).code);
        assertEquals(0,f.confirms);assertEquals(0,f.publishes);assertEquals(0,f.completes);
    }
    @Test public void replacementCannotInterleaveWithAdmittedOriginalRoomCommand() throws Exception {
        var lease=new ProductNearbySelection.CommandLease();Object owner=new Object(),original=new Object();
        var current=new AtomicReference<>(original);var entered=new CountDownLatch(1);var release=new CountDownLatch(1);
        var replaced=new CountDownLatch(1);var failure=new AtomicReference<Throwable>();
        Thread command=new Thread(()->{try {lease.run(owner,()->current.get()==original,()->{
            entered.countDown();assertTrue(release.await(3,TimeUnit.SECONDS));assertSame(original,current.get());
        });}catch(Throwable e){failure.set(e);}});
        command.start();assertTrue(entered.await(2,TimeUnit.SECONDS));
        Thread replacement=new Thread(()->{synchronized(owner){current.set(new Object());replaced.countDown();}});
        replacement.start();
        try {assertFalse(replaced.await(100,TimeUnit.MILLISECONDS));}finally {release.countDown();command.join(3000);replacement.join(3000);}
        assertNull(failure.get());assertEquals(0,replaced.getCount());
        var stale=assertThrows(ProductNearbySelection.Failure.class,()->lease.run(owner,()->current.get()==original,()->fail("replaced room mutated")));
        assertEquals("nearby_unavailable",stale.code);
    }
    @Test public void hostLossAfterEachAwaitPreventsRoomMutationAndCompletion() {
        for(String boundary:new String[]{"ready","load","wait"}) {
            Fixture f=new Fixture(boundary);
            assertThrows(ProductNearbySelection.Failure.class,()->f.run());
            assertEquals(boundary,0,f.selects);assertEquals(0,f.confirms);assertEquals(0,f.publishes);assertEquals(0,f.completes);
        }
    }
    @Test public void leaseIsRecheckedBetweenSelectionConfirmationMetadataAndCompletion() {
        for(String boundary:new String[]{"select","confirm","publish"}) {
            Fixture f=new Fixture(boundary);assertThrows(ProductNearbySelection.Failure.class,()->f.run());
            assertEquals(1,f.selects);assertEquals(boundary.equals("select")?0:1,f.confirms);
            assertEquals(boundary.equals("publish")?1:0,f.publishes);assertEquals(0,f.completes);
        }
    }
    @Test public void liveLeaseReturnsOriginalRoomAndCompletesOnce() throws Exception {
        Fixture f=new Fixture("");f.run();assertEquals(1,f.returns);assertEquals(1,f.selects);
        assertEquals(1,f.confirms);assertEquals(1,f.publishes);assertEquals(1,f.completes);
    }
    static class Fixture implements ProductNearbySelection.Port {
        final String invalidateAt;final AtomicBoolean valid=new AtomicBoolean(true);
        int selects,confirms,publishes,completes,returns,state=NearbyMvpSession.RUNNING;long clock;
        Fixture(String boundary){invalidateAt=boundary;}
        void boundary(String name){if(invalidateAt.equals(name))valid.set(false);}
        void run() throws Exception {ProductNearbySelection.run(this,action->{
            if(!valid.get())throw new ProductNearbySelection.Failure("stale_host");action.run();
        },()->clock,()->{boundary("wait");state=NearbyMvpSession.LOBBY;clock+=10;});}
        public void ready(){boundary("ready");}
        public ProductNearbySelection.Selection load(){boundary("load");return new ProductNearbySelection.Selection(new byte[]{1},"game","title");}
        public int state(){return state;}
        public boolean returnLobby(){returns++;state=NearbyMvpSession.RETURNING;return true;}
        public boolean select(ProductNearbySelection.Selection selection){selects++;boundary("select");return true;}
        public boolean confirm(){confirms++;boundary("confirm");return true;}
        public void publish(ProductNearbySelection.Selection selection){publishes++;boundary("publish");}
        public void complete(){completes++;}
    }
}
