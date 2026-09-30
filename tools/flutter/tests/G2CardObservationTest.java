package com.flynes.emu;
import java.util.List;

/** Runs against the actual androidTest classifier without Android or a device. */
public final class G2CardObservationTest {
    static G2CardObservation.Node node(String role,String label,int top,int bottom,boolean clickable,G2CardObservation.Node... children) {
        return new G2CardObservation.Node(role,label,true,clickable,100,top,900,bottom,List.of(children));
    }
    static void check(boolean condition,String message){if(!condition)throw new AssertionError(message);}
    public static void main(String[] ignored) {
        var categories=node("android.widget.HorizontalScrollView",null,0,100,false,
                node("android.widget.Button","All",0,100,true));
        var filter=node("android.widget.Switch","Two-player",120,180,true);
        var loading=node("android.view.View","Loading library…",190,300,false);
        check(!G2CardObservation.card(node("root",null,0,1000,false,categories,filter,loading)),
                "Category buttons before the real grid must not count as first card");
        for(String role:new String[]{"android.widget.Button","android.widget.ImageView"}) {
            var card=node(role,"Actual catalog title",200,600,true);
            var grid=node("android.widget.HorizontalScrollView",null,190,900,false,card);
            check(G2CardObservation.card(node("root",null,0,1000,false,categories,filter,grid)),
                    "Real catalog card below the filter must be recognized regardless of cover");
        }
        check(!G2CardObservation.card(node("root",null,0,1000,false,categories,loading)),
                "Missing catalog filter anchor must fail closed");
        var empty=node("android.widget.HorizontalScrollView",null,190,900,false);
        check(!G2CardObservation.card(node("root",null,0,1000,false,categories,filter,empty)),"Empty grid has no first card");
        System.out.println("PASS 4 card semantics cases (both card roles)");
    }
}
