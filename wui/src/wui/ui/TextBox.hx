package wui.ui;

import wui.View;

/**
 * Text input field. Maps to WinUI TextBox.
 *
 * Usage:
 *   new TextBox("Enter name...")
 *       .width(200)
 */
class TextBox extends View {
    public function new(?placeholder:String, ?binding:Dynamic) {
        super("TextBox");
        if (placeholder != null) properties.set("placeholder", placeholder);
        if (binding != null) properties.set("binding", binding);
    }
}
