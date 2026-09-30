package com.flynes.emu;

import java.util.IdentityHashMap;
import java.util.List;

/** Test-owned host identities; used on the main thread by lifecycle/draw callbacks. */
final class G2StartupHosts<H> {
    private final IdentityHashMap<H,Long> hosts=new IdentityHashMap<>();
    private boolean closing;
    private boolean observed;
    boolean created(H host){observed=true;hosts.putIfAbsent(host,0L);return !closing;}
    void drawn(H host,long time){
        if(!closing&&hosts.getOrDefault(host,-1L)==0)hosts.put(host,time);
    }
    long drawTime(H host){return closing?0:hosts.getOrDefault(host,0L);}
    boolean destroyed(H host){return hosts.remove(host)!=null;}
    List<H> beginClose(){closing=true;return List.copyOf(hosts.keySet());}
    boolean closed(){return closing&&observed&&hosts.isEmpty();}
    int count(){return hosts.size();}
}
