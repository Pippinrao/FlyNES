package com.flynes.emu;

/** A raster acknowledgement belongs to exactly one destination host. */
final class ProductPresentationGate {
    private final String token;
    private boolean ready;
    ProductPresentationGate(String token){this.token=token;}
    boolean acknowledge(String incoming,long frame){
        if(!token.equals(incoming)||frame<=0)return false;
        ready=true;return true;
    }
    boolean ready(){return ready;}
}
