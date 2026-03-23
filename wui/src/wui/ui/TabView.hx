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
class TabView extends View {
    public function new(tabs:Array<TabItem>) {
        super("TabView");
        properties.set("tabs", tabs);
    }
}

typedef TabItem = {
    label:String,
    ?icon:String,
    content:View
};
