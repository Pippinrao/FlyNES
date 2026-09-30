package com.flynes.emu;

import java.util.*;
import java.util.concurrent.Executor;
import java.util.function.Function;

/** Provider display names belong to the platform, not the shared catalog.
 * The supplied worker must execute asynchronously and serially, as the bridge's namesWorker does.
 */
final class ProductSourceNames {
    record Entry(String locator,String name) {}
    interface Store {Entry read(String uuid);void write(String uuid,Entry value);void remove(String uuid);}
    // The UI supplies its localized fallback; a provider may legitimately return "Game source".
    private static final String FALLBACK="";
    private static final class Lookup {
        final String locator;String name;
        Lookup(String locator,String name){this.locator=locator;this.name=name;}
    }
    private final Store store;
    private final Executor worker;
    private final Function<String,String> provider;
    private final Runnable changed;
    private final Map<String,Lookup> names=new HashMap<>();
    ProductSourceNames(Store store,Executor worker,Function<String,String> provider,Runnable changed) {
        this.store=store;this.worker=worker;this.provider=provider;this.changed=changed;
    }
    synchronized String get(String uuid,String locator) {
        Lookup current=names.get(uuid);
        if(current!=null&&current.locator==null)return FALLBACK; // Removal tombstone; stale projections cannot revive it.
        if(current==null||!current.locator.equals(locator))current=start(uuid,locator);
        return current.name;
    }
    synchronized void refresh(String uuid,String locator) {start(uuid,locator);}
    synchronized void remove(String uuid) {
        names.put(uuid,new Lookup(null,FALLBACK));
        enqueue(()->{try{store.remove(uuid);}catch(RuntimeException unavailable){/* Metadata must not fail source removal. */}});
    }
    private Lookup start(String uuid,String locator) {
        Lookup previous=names.get(uuid);
        String retained=previous!=null?previous.name:null;
        Lookup lookup=new Lookup(locator,displayName(retained)==null?FALLBACK:retained);
        names.put(uuid,lookup);
        enqueue(()->resolve(uuid,lookup));
        return lookup;
    }
    private void enqueue(Runnable action) {
        // Called under the short cache monitor so lookup/removal queue order matches identity changes.
        try{worker.execute(action);}catch(RuntimeException unavailable){/* Metadata work is best effort. */}
    }
    private synchronized boolean current(String uuid,Lookup lookup) {return names.get(uuid)==lookup;}
    private void resolve(String uuid,Lookup lookup) {
        if(!current(uuid,lookup))return;
        if(lookup.name.isEmpty()) {
            Entry saved=null;
            try{saved=store.read(uuid);}catch(RuntimeException unavailable){/* No saved display name. */}
            if(saved!=null)publish(uuid,lookup,displayName(saved.name()));
        }
        if(!current(uuid,lookup))return;
        String name;
        try{name=displayName(provider.apply(lookup.locator));}catch(RuntimeException unavailable){return;}
        if(name==null||!publish(uuid,lookup,name))return;
        // An admitted write may finish after invalidation. The same serial queue orders a later
        // removal/new lookup after it, while cache reads and lifecycle work never wait for disk.
        try{store.write(uuid,new Entry(lookup.locator,name));}catch(RuntimeException unavailable){/* Display names are best-effort metadata. */}
    }
    private boolean publish(String uuid,Lookup lookup,String name) {
        if(name==null)return false;
        boolean notify;
        synchronized(this) {
            if(names.get(uuid)!=lookup)return false; // Removed source or a newer locator/regrant lookup.
            notify=!name.equals(lookup.name);lookup.name=name;
        }
        if(notify)changed.run();
        return true;
    }
    private static String displayName(String value) {
        if(value==null)return null;
        String name=value.trim();
        // Never fall back to document IDs, internal paths or locator strings.
        if(name.isEmpty()||name.indexOf('/')>=0||name.indexOf('\\')>=0||name.indexOf('\n')>=0||name.indexOf('\r')>=0)return null;
        return name;
    }
}
