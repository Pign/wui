package wui.ui;

import wui.View;

/**
 * Displays an image. Maps to WinUI Image.
 *
 * Usage:
 *   new Image("assets/logo.png")
 *       .frame(200, 200)
 */
class Image extends View {
    public function new(source:String) {
        super("Image");
        properties.set("source", source);
    }
}
