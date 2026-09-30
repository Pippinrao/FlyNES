package com.flynes.emu;

import java.util.List;

/** Immutable accessibility facts, also exercised by the standalone JVM fixture. */
final class G2CardObservation {
    record Node(String role, String label, boolean visible, boolean clickable,
                int left, int top, int right, int bottom, List<Node> children) { }
    static boolean card(Node root) {
        if(root==null)return false;
        var anchors=new java.util.ArrayList<Node>();
        anchors(root,anchors);
        return anchors.size()==1&&grid(root,anchors.get(0));
    }
    private static void anchors(Node node,List<Node> found) {
        if(node.visible()&&node.role().equals("android.widget.Switch")
                &&("Two-player".equals(node.label())||"双人支持".equals(node.label())))found.add(node);
        node.children().forEach(child->anchors(child,found));
    }
    private static boolean grid(Node node,Node filter) {
        // The catalog lives below its named filter. A compact category scroller
        // is above it; its buttons cannot satisfy this region's card boundary.
        if(node.visible()&&node.role().equals("android.widget.HorizontalScrollView")
                &&node.top()>=filter.bottom()&&node.left()<filter.right()&&node.right()>filter.left())
            return node.children().stream().anyMatch(child->clickable(child,node));
        return node.children().stream().anyMatch(child->grid(child,filter));
    }
    private static boolean clickable(Node node,Node grid) {
        if(node.visible()&&node.clickable()&&node.label()!=null&&!node.label().isEmpty()
                &&node.right()>grid.left()&&node.left()<grid.right()
                &&node.bottom()>grid.top()&&node.top()<grid.bottom())return true;
        return node.children().stream().anyMatch(child->clickable(child,grid));
    }
}
