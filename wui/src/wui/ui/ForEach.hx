package wui.ui;

import wui.View;

/**
 * Repeats a view template for each item in a collection.
 *
 * Usage:
 *   new ForEach(items, (item) -> new Text(item.name))
 */
class ForEach extends View {
    public function new(items:Dynamic, template:Dynamic -> View) {
        super("ForEach");
        properties.set("items", items);
        properties.set("template", template);
    }
}
