package wui.ui;

import wui.View;

/**
 * A checkbox control. Maps to WinUI CheckBox.
 *
 * Usage:
 *   new CheckBox("Accept terms", acceptedState)
 */
class CheckBox extends View {
    public function new(?label:String, ?binding:Dynamic) {
        super("CheckBox");
        if (label != null) properties.set("label", label);
        if (binding != null) properties.set("binding", binding);
    }
}
