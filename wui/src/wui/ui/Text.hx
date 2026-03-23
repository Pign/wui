package wui.ui;

import wui.View;

/**
 * Displays read-only text. Maps to WinUI TextBlock.
 *
 * Usage:
 *   new Text("Hello World")
 *       .font(TitleLarge)
 *       .foregroundColor(AccentColor)
 */
class Text extends View {
    public function new(content:Dynamic) {
        super("TextBlock");
        properties.set("text", content);
    }
}
