package wui.ui;

import wui.View;

/**
 * Displays a scrollable list of items. Maps to WinUI ListView.
 *
 * Usage:
 *   new ListView(items, (item) -> new Text(item.name))
 */
class ListView extends View {
    public function new(items:Dynamic, ?itemTemplate:Dynamic -> View) {
        super("ListView");
        properties.set("items", items);
        if (itemTemplate != null) properties.set("itemTemplate", itemTemplate);
    }
}
