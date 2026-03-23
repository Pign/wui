package wui.ui;

import wui.View;

/**
 * A toggle switch control. Maps to WinUI ToggleSwitch.
 *
 * Usage:
 *   new ToggleSwitch("Dark Mode", darkModeState)
 */
class ToggleSwitch extends View {
    public function new(?label:String, ?binding:Dynamic) {
        super("ToggleSwitch");
        if (label != null) properties.set("label", label);
        if (binding != null) properties.set("binding", binding);
    }
}
