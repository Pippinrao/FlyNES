package com.flynes.emu;
import static org.junit.Assert.*;
import org.junit.Test;
public class ProductGameHandoffTest {
    @Test public void abandonedDestinationDropsBorrowedReferenceWithoutFinishingGame() {
        var handoff=new ProductGameHandoff<Object>();Object game=new Object();String token=handoff.begin(game);
        handoff.abandon(token);assertNull(handoff.pending());assertNull(handoff.complete(token));
    }
    @Test public void staleAbandonmentCannotCancelReplacementHandoff() {
        var handoff=new ProductGameHandoff<Object>();Object first=new Object(),second=new Object();
        String old=handoff.begin(first),current=handoff.begin(second);
        handoff.abandon(old);handoff.destroyed(first);assertSame(second,handoff.pending());
        assertSame(second,handoff.complete(current));assertNull(handoff.pending());
    }
    @Test public void destroyedGameCannotRemainReferencedByApplication() {
        var handoff=new ProductGameHandoff<Object>();Object game=new Object();String token=handoff.begin(game);
        handoff.destroyed(game);assertNull(handoff.pending());assertNull(handoff.complete(token));
    }
}
