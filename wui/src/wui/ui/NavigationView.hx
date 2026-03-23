package wui.ui;

import wui.View;

/**
 * Navigation container with sidebar. Maps to WinUI NavigationView.
 *
 * Usage:
 *   new NavigationView([
 *       NavigationItem("Home", homeView),
 *       NavigationItem("Settings", settingsView)
 *   ])
 */
class NavigationView extends View {
    public function new(items:Array<NavigationItem>) {
        super("NavigationView");
        properties.set("items", items);
    }
}

typedef NavigationItem = {
    label:String,
    ?icon:String,
    content:View
};
