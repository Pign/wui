package wui.ui;

import wui.View;

/**
 * An expandable/collapsible section. Maps to WinUI Expander.
 *
 * Usage:
 *   new Expander("Advanced Options", new VStack([...]))
 */
class Expander extends View {
    public function new(header:String, content:View, ?isExpanded:Bool) {
        super("Expander", [content]);
        properties.set("header", header);
        if (isExpanded != null) properties.set("isExpanded", isExpanded);
    }
}
