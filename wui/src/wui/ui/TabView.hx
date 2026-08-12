package wui.ui;

import wui.View;

/**
 * A tabbed interface. Maps to WinUI TabView.
 *
 * Usage:
 *   new TabView([
 *       { label: "Tab 1", content: view1 },
 *       { label: "Tab 2", content: view2 }
 *   ])
 */
@:winuiType("TabView")
@:build(wui.macros.ControlBuilder.build())
class TabView extends Control {
    public function new(tabs:Array<TabItem>) {
        // WinUI holds items, not contents. The tabs become children here so a
        // host that inserts children generically -- the push sink does -- builds
        // the same thing the transpiled path builds from the `tabs` property,
        // which is kept for it.
        super("TabView", [for (t in tabs) new TabViewItem(t.label, t.content)]);
        properties.set("tabs", tabs);
    }
}

typedef TabItem = {
    label:String,
    ?icon:String,
    content:View
};
