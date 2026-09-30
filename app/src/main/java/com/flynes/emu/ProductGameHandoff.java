package com.flynes.emu;

/** A borrowed outgoing game reference; abandonment never closes the game owner. */
final class ProductGameHandoff<T> {
    private T game;
    private String token;
    String begin(T value){game=value;token=java.util.UUID.randomUUID().toString();return token;}
    T complete(String incoming){if(token==null||!token.equals(incoming))return null;T result=game;game=null;token=null;return result;}
    void abandon(String incoming){if(token!=null&&token.equals(incoming)){game=null;token=null;}}
    void destroyed(T value){if(game==value){game=null;token=null;}}
    T pending(){return game;}
}
