package com.flynes.emu;

public final class G2StartupHostsTest {
    private static void check(boolean value,String reason){if(!value)throw new AssertionError(reason);}
    public static void main(String[] ignored){
        var hosts=new G2StartupHosts<Object>();Object old=new Object(),replacement=new Object();
        check(hosts.created(old),"Initial host admitted");hosts.drawn(old,100);
        hosts.created(replacement);
        check(hosts.drawTime(replacement)==0,"Old host draw must not authorize undrawn replacement controls");
        hosts.destroyed(old);hosts.drawn(replacement,200);
        check(hosts.drawTime(replacement)==200,"Replacement is observable only after its own draw");
        hosts.drawn(replacement,250);
        check(hosts.drawTime(replacement)==200,"First draw for this instance remains stable");
        check(hosts.beginClose().size()==1&&!hosts.closed(),"Cleanup must retain live owner until destroyed");
        Object late=new Object();
        check(!hosts.created(late),"Late launch must be rejected/finished after abandonment");
        check(hosts.count()==2,"Late owner must remain tracked until its destruction");
        hosts.destroyed(replacement);check(!hosts.closed(),"Late owner blocks completed cleanup");
        hosts.destroyed(late);check(hosts.closed(),"All created owners were destroyed");
        Object afterEmpty=new Object();
        check(!hosts.created(afterEmpty),"Destroy-old then create-replacement still rejects the late host");
        check(!hosts.closed(),"A temporarily empty set is not an end to the closing guard");
        hosts.destroyed(afterEmpty);check(hosts.closed(),"Late replacement must also be destroyed");
        System.out.println("PASS instance draw/recreation, stable first draw, abandoned late host cleanup");
    }
}
