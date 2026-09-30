package com.flynes.emu.catalog.source;

import java.util.LinkedHashMap;
import java.util.UUID;
import java.util.concurrent.CancellationException;
import java.util.concurrent.CopyOnWriteArrayList;

/** Process-owned scan observations. Only the catalog worker advances or commits a scan. */
public final class SourceScanOperations {
    public record Snapshot(String operationId,String phase,int completed,Integer total,
            boolean canCancel,String reason) {}
    private final LinkedHashMap<String,Operation> operations=new LinkedHashMap<>();
    private final CopyOnWriteArrayList<Runnable> observers=new CopyOnWriteArrayList<>();
    public synchronized Operation begin(String sourceId) {
        Operation previous=operations.get(sourceId);
        if(previous!=null&&!previous.terminal)throw new IllegalStateException("native_busy");
        Operation op=new Operation();operations.remove(sourceId);operations.put(sourceId,op);
        if(operations.size()>128)operations.entrySet().removeIf(e->operations.size()>128&&e.getValue().terminal);
        changed();return op;
    }
    public synchronized Snapshot snapshot(String sourceId) {
        Operation op=operations.get(sourceId);return op==null?null:op.snapshot();
    }
    public String cancel(String sourceId,String operationId) {
        Operation op;
        synchronized(this){op=operations.get(sourceId);}
        if(op==null||!op.id.equals(operationId))return "stale_operation";
        return op.cancel();
    }
    public AutoCloseable observe(Runnable callback) {observers.add(callback);return ()->observers.remove(callback);}
    private void changed(){for(Runnable callback:observers)try{callback.run();}catch(RuntimeException ignored){}}
    public final class Operation {
        private final String id=UUID.randomUUID().toString();
        private String phase="queued",reason="";
        private int completed;
        private Integer total;
        private volatile boolean terminal;
        private boolean cancelled;
        private Runnable cancelSignal=()->{};
        public String id(){return id;}
        public synchronized Snapshot snapshot(){return new Snapshot(id,phase,completed,total,
                !terminal&&!phase.equals("committing")&&!cancelled,reason);}
        public synchronized void checkpoint(){if(cancelled)throw new CancellationException();}
        public void onCancel(Runnable signal){boolean fire;synchronized(this){cancelSignal=signal;fire=cancelled;}if(fire)signal.run();}
        private String cancel(){Runnable signal;
            synchronized(this){
                if(terminal||phase.equals("committing"))return "cancellation_unavailable";
                if(cancelled)return "accepted";
                cancelled=true;phase="cancelling";signal=cancelSignal;
            }
            // Provider interruption is independent of native scan ownership.
            try{signal.run();}finally{changed();}return "accepted";
        }
        public void enumerating(){synchronized(this){checkpoint();phase="enumerating";}changed();}
        public void ingesting(int count){synchronized(this){checkpoint();phase="ingesting";total=count;}changed();}
        public void advanced(){synchronized(this){completed++;}changed();checkpoint();}
        public void committing(){synchronized(this){checkpoint();phase="committing";cancelSignal=()->{};}changed();}
        public void finish(String value,String stableReason){synchronized(this){phase=value;reason=stableReason;terminal=true;cancelSignal=()->{};}changed();}
    }
}
