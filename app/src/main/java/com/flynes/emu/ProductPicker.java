package com.flynes.emu;

/** One process picker, bound to a recreation-stable host identity and unique result code. */
final class ProductPicker<T> {
    record Pending<T>(String owner,int requestCode,T payload) {}
    private Pending<T> pending;
    private int nextCode=8000;
    Pending<T> begin(String owner,T payload){
        if(pending!=null)throw new IllegalStateException("native_busy");
        if(nextCode>65000)throw new IllegalStateException("native_busy");
        pending=new Pending<>(owner,nextCode++,payload);return pending;
    }
    T take(String owner,int requestCode){
        if(pending==null||!pending.owner().equals(owner)||pending.requestCode()!=requestCode)return null;
        T value=pending.payload();pending=null;return value;
    }
}
