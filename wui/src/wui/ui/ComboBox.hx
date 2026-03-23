package wui.ui;

import wui.View;

/**
 * A dropdown picker. Maps to WinUI ComboBox.
 *
 * Usage:
 *   new ComboBox(["Option A", "Option B", "Option C"], selectedState)
 */
class ComboBox extends View {
    public function new(options:Array<String>, ?binding:Dynamic) {
        super("ComboBox");
        properties.set("options", options);
        if (binding != null) properties.set("binding", binding);
    }
}
