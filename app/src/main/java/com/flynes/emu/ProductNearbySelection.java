package com.flynes.emu;
import java.util.function.LongSupplier;
import java.util.function.BooleanSupplier;

/** Selection orchestration borrows a room; it never owns or closes its session or network. */
final class ProductNearbySelection {
    record Selection(byte[] bytes,String key,String title) {}
    @FunctionalInterface interface Action {void run() throws Exception;}
    @FunctionalInterface interface Guard {void run(Action action) throws Exception;}
    interface Port {
        void ready() throws Exception;
        Selection load() throws Exception;
        int state();boolean returnLobby();boolean select(Selection selection);boolean confirm();
        void publish(Selection selection);void complete();
    }
    static final class Failure extends Exception {
        final String code;Failure(String code){super(code);this.code=code;}
    }
    /** Admission is the command's linearization point. Invalidation never waits for native work. */
    static final class CommandLease {
        private boolean valid=true;
        synchronized void invalidate(){valid=false;}
        void run(Object roomOwner,BooleanSupplier sameRoom,Action command) throws Exception {
            synchronized(roomOwner) {
                synchronized(this) {
                    if(!valid)throw new Failure("stale_host");
                    if(!sameRoom.getAsBoolean())throw new Failure("nearby_unavailable");
                    // This command is now admitted against the captured room. Later invalidation
                    // suppresses subsequent commands, but cannot cancel synchronous native work.
                }
                // Keep replacement/close excluded, without retaining the host lease monitor.
                command.run();
            }
        }
    }
    static void run(Port port,Guard guard,LongSupplier now,Action wait) throws Exception {
        run(port,guard,guard,now,wait);
    }
    static void run(Port port,Guard guard,Guard completionGuard,LongSupplier now,Action wait) throws Exception {
        guard.run(()->{});port.ready();guard.run(()->{});
        Selection selection=port.load();guard.run(()->{});
        int state=state(port,guard);
        if(state==NearbyMvpSession.RUNNING||state==NearbyMvpSession.CONFIGURING)
            guard.run(()->require(port.returnLobby()));
        long deadline=now.getAsLong()+3000;
        while(state(port,guard)==NearbyMvpSession.RETURNING) {
            if(now.getAsLong()>=deadline)throw new Failure("nearby_unavailable");
            wait.run();guard.run(()->{});
        }
        guard.run(()->require(port.select(selection)));
        guard.run(()->require(port.confirm()));
        guard.run(()->port.publish(selection));
        completionGuard.run(port::complete);
    }
    private static int state(Port port,Guard guard) throws Exception {
        int[] value=new int[1];guard.run(()->value[0]=port.state());return value[0];
    }
    private static void require(boolean success) throws Failure {if(!success)throw new Failure("nearby_unavailable");}
}
