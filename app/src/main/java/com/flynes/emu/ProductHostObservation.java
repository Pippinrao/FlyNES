package com.flynes.emu;

/** Observation leases only; never owns or stops catalog/game/network work. */
final class ProductHostObservation<H> {
    private H host;
    private long ticket;
    private boolean visible,subscribed;
    synchronized void attach(H value){host=value;visible=true;subscribed=true;ticket++;}
    synchronized void detach(H value){if(host==value){host=null;visible=false;ticket++;}}
    synchronized void suspend(H value){if(host==value){visible=false;ticket++;}}
    synchronized void resume(H value){if(host==value){visible=true;ticket++;}}
    synchronized void unsubscribe(){subscribed=false;ticket++;}
    synchronized void subscribe(){subscribed=true;ticket++;}
    synchronized long ticket(){return ticket;}
    synchronized boolean accepts(long value){return value==ticket&&host!=null&&visible&&subscribed;}
}
