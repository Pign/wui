package wui.ui;

import wui.View;

/**
 * Vertical stack layout. Maps to WinUI StackPanel with Vertical orientation.
 *
 * Usage:
 *   new VStack([
 *       new Text("Top"),
 *       new Text("Bottom")
 *   ]).spacing(8)
 */
class VStack extends View {
    public function new(children:Array<View>, ?spacing:Float) {
        super("StackPanel", children);
        properties.set("orientation", "Vertical");
        if (spacing != null) properties.set("spacing", spacing);
    }
}
